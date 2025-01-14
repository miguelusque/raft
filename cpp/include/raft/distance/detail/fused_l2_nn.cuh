/*
 * Copyright (c) 2021-2023, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <cstddef>                                          // size_t
#include <limits>                                           // std::numeric_limits
#include <raft/core/kvp.hpp>                                // raft::KeyValuePair
#include <raft/core/operators.hpp>                          // raft::identity_op
#include <raft/distance/detail/distance_ops/l2_exp.cuh>     // ops::l2_exp_distance_op
#include <raft/distance/detail/pairwise_distance_base.cuh>  // PairwiseDistances
#include <raft/linalg/contractions.cuh>                     // Policy
#include <raft/util/cuda_utils.cuh>                         // raft::ceildiv, raft::shfl

namespace raft {
namespace distance {

namespace detail {

template <typename LabelT, typename DataT>
struct KVPMinReduceImpl {
  typedef raft::KeyValuePair<LabelT, DataT> KVP;
  DI KVP operator()(LabelT rit, const KVP& a, const KVP& b) { return b.value < a.value ? b : a; }
  DI KVP operator()(const KVP& a, const KVP& b) { return b.value < a.value ? b : a; }

};  // KVPMinReduce

template <typename LabelT, typename DataT>
struct MinAndDistanceReduceOpImpl {
  typedef typename raft::KeyValuePair<LabelT, DataT> KVP;
  DI void operator()(LabelT rid, KVP* out, const KVP& other)
  {
    if (other.value < out->value) {
      out->key   = other.key;
      out->value = other.value;
    }
  }

  DI void operator()(LabelT rid, DataT* out, const KVP& other)
  {
    if (other.value < *out) { *out = other.value; }
  }

  DI void init(DataT* out, DataT maxVal) { *out = maxVal; }
  DI void init(KVP* out, DataT maxVal)
  {
    out->key   = 0;
    out->value = maxVal;
  }
};

template <typename LabelT, typename DataT>
struct MinReduceOpImpl {
  typedef typename raft::KeyValuePair<LabelT, DataT> KVP;
  DI void operator()(LabelT rid, DataT* out, const KVP& other)
  {
    if (other.value < *out) { *out = other.value; }
  }

  DI void init(DataT* out, DataT maxVal) { *out = maxVal; }
};

template <typename DataT, typename OutT, typename IdxT, typename ReduceOpT>
__global__ void initKernel(OutT* min, IdxT m, DataT maxVal, ReduceOpT redOp)
{
  auto tid = IdxT(blockIdx.x) * blockDim.x + threadIdx.x;
  if (tid < m) { redOp.init(min + tid, maxVal); }
}

template <typename DataT, typename OutT, typename IdxT, typename ReduceOpT>
void initialize(OutT* min, IdxT m, DataT maxVal, ReduceOpT redOp, cudaStream_t stream)
{
  auto blks = raft::ceildiv(m, 256);
  initKernel<DataT, OutT, IdxT><<<blks, 256, 0, stream>>>(min, m, maxVal, redOp);
}

// TODO: specialize this function for MinAndDistanceReduceOp<int, float>
// with atomicCAS of 64 bit which will eliminate mutex and shfls
template <typename P, typename OutT, typename IdxT, typename KVPair, typename ReduceOpT>
DI void updateReducedVal(
  int* mutex, OutT* min, KVPair* val, ReduceOpT red_op, IdxT m, IdxT gridStrideY)
{
  const auto lid      = threadIdx.x % raft::WarpSize;
  const auto accrowid = threadIdx.x / P::AccThCols;

  // Update each output row in order within a warp. This will resolve hang
  // issues with pre-Volta architectures
#pragma unroll
  for (int j = 0; j < (raft::WarpSize / P::AccThCols); j++) {
    if (lid == j * P::AccThCols) {
#pragma unroll
      for (int i = 0; i < P::AccRowsPerTh; ++i) {
        auto rid = gridStrideY + accrowid + i * P::AccThRows;
        if (rid < m) {
          auto value = val[i];
          while (atomicCAS(mutex + rid, 0, 1) == 1)
            ;
          __threadfence();
          red_op(rid, min + rid, value);
          __threadfence();
          atomicCAS(mutex + rid, 1, 0);
        }
      }
    }
  }
}

template <typename DataT,
          typename OutT,
          typename IdxT,
          typename P,
          typename ReduceOpT,
          typename KVPReduceOpT,
          typename OpT,
          typename FinalLambda>
__global__ __launch_bounds__(P::Nthreads, 2) void fusedL2NNkernel(OutT* min,
                                                                  const DataT* x,
                                                                  const DataT* y,
                                                                  const DataT* xn,
                                                                  const DataT* yn,
                                                                  IdxT m,
                                                                  IdxT n,
                                                                  IdxT k,
                                                                  DataT maxVal,
                                                                  int* mutex,
                                                                  ReduceOpT redOp,
                                                                  KVPReduceOpT pairRedOp,
                                                                  OpT distance_op,
                                                                  FinalLambda fin_op)
{
  extern __shared__ char smem[];

  typedef KeyValuePair<IdxT, DataT> KVPair;
  KVPair val[P::AccRowsPerTh];
#pragma unroll
  for (int i = 0; i < P::AccRowsPerTh; ++i) {
    val[i] = {0, maxVal};
  }

  // epilogue operation lambda for final value calculation
  auto epilog_lambda = [n, pairRedOp, &val, maxVal] __device__(
                         DataT acc[P::AccRowsPerTh][P::AccColsPerTh],
                         DataT * regxn,
                         DataT * regyn,
                         IdxT gridStrideX,
                         IdxT gridStrideY) {
    KVPReduceOpT pairRed_op(pairRedOp);

    // intra thread reduce
    const auto acccolid = threadIdx.x % P::AccThCols;
    const auto accrowid = threadIdx.x / P::AccThCols;
#pragma unroll
    for (int i = 0; i < P::AccRowsPerTh; ++i) {
#pragma unroll
      for (int j = 0; j < P::AccColsPerTh; ++j) {
        auto tmpkey = acccolid + j * P::AccThCols + gridStrideX;
        KVPair tmp  = {tmpkey, acc[i][j]};
        if (tmpkey < n) {
          val[i] = pairRed_op(accrowid + i * P::AccThRows + gridStrideY, tmp, val[i]);
        }
      }
    }
  };

  auto rowEpilog_lambda =
    [m, mutex, min, pairRedOp, redOp, &val, maxVal] __device__(IdxT gridStrideY) {
      KVPReduceOpT pairRed_op(pairRedOp);
      ReduceOpT red_op(redOp);

      const auto accrowid = threadIdx.x / P::AccThCols;
      const auto lid      = raft::laneId();

    // reduce
#pragma unroll
      for (int i = 0; i < P::AccRowsPerTh; ++i) {
#pragma unroll
        for (int j = P::AccThCols / 2; j > 0; j >>= 1) {
          // Actually, the srcLane (lid +j) should be (lid +j) % P:AccThCols,
          // but the shfl op applies the modulo internally.
          auto tmpkey   = raft::shfl(val[i].key, lid + j, P::AccThCols);
          auto tmpvalue = raft::shfl(val[i].value, lid + j, P::AccThCols);
          KVPair tmp    = {tmpkey, tmpvalue};
          val[i]        = pairRed_op(accrowid + i * P::AccThRows + gridStrideY, tmp, val[i]);
        }
      }

      updateReducedVal<P, OutT, IdxT, KVPair, ReduceOpT>(mutex, min, val, red_op, m, gridStrideY);

    // reset the val array.
#pragma unroll
      for (int i = 0; i < P::AccRowsPerTh; ++i) {
        val[i] = {0, maxVal};
      }
    };

  IdxT lda = k, ldb = k, ldd = n;
  constexpr bool row_major = true;
  constexpr bool write_out = false;
  PairwiseDistances<DataT,
                    DataT,  // OutT (unused in PairwiseDistances)
                    IdxT,
                    P,
                    decltype(distance_op),
                    decltype(epilog_lambda),
                    FinalLambda,
                    decltype(rowEpilog_lambda),
                    row_major,
                    write_out>
    obj(x,
        y,
        m,
        n,
        k,
        lda,
        ldb,
        ldd,
        xn,
        yn,
        nullptr,  // Output pointer
        smem,
        distance_op,
        epilog_lambda,
        fin_op,
        rowEpilog_lambda);
  obj.run();
}

template <typename DataT,
          typename OutT,
          typename IdxT,
          typename Policy,
          typename ReduceOpT,
          typename KVPReduceOpT>
void fusedL2NNImpl(OutT* min,
                   const DataT* x,
                   const DataT* y,
                   const DataT* xn,
                   const DataT* yn,
                   IdxT m,
                   IdxT n,
                   IdxT k,
                   int* workspace,
                   ReduceOpT redOp,
                   KVPReduceOpT pairRedOp,
                   bool sqrt,
                   bool initOutBuffer,
                   cudaStream_t stream)
{
  // The kernel policy is determined by fusedL2NN.
  typedef Policy P;

  dim3 blk(P::Nthreads);
  auto nblks            = raft::ceildiv<int>(m, P::Nthreads);
  constexpr auto maxVal = std::numeric_limits<DataT>::max();
  typedef KeyValuePair<IdxT, DataT> KVPair;

  RAFT_CUDA_TRY(cudaMemsetAsync(workspace, 0, sizeof(int) * m, stream));
  if (initOutBuffer) {
    initKernel<DataT, OutT, IdxT, ReduceOpT>
      <<<nblks, P::Nthreads, 0, stream>>>(min, m, maxVal, redOp);
    RAFT_CUDA_TRY(cudaGetLastError());
  }

  constexpr size_t shmemSize = P::SmemSize + ((P::Mblk + P::Nblk) * sizeof(DataT));

  using AccT = DataT;
  ops::l2_exp_distance_op<DataT, AccT, IdxT> distance_op{sqrt};

  raft::identity_op fin_op{};

  auto kernel = fusedL2NNkernel<DataT,
                                OutT,
                                IdxT,
                                P,
                                ReduceOpT,
                                KVPReduceOpT,
                                decltype(distance_op),
                                decltype(fin_op)>;

  dim3 grid = launchConfigGenerator<P>(m, n, shmemSize, kernel);

  kernel<<<grid, blk, shmemSize, stream>>>(
    min, x, y, xn, yn, m, n, k, maxVal, workspace, redOp, pairRedOp, distance_op, fin_op);
  RAFT_CUDA_TRY(cudaGetLastError());
}

}  // namespace detail
}  // namespace distance
}  // namespace raft
