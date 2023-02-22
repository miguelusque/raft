/*
 * Copyright (c) 2019-2023, NVIDIA CORPORATION.
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

#if defined RAFT_DISTANCE_COMPILED
#include <raft/distance/specializations.cuh>
#endif

#include "../test_utils.cuh"
#include <gtest/gtest.h>
#include <iostream>
#include <memory>
#include <raft/distance/detail/matrix/matrix.hpp>
#include <raft/distance/distance_types.hpp>
#include <raft/distance/kernels.cuh>
#include <raft/random/rng.cuh>
#include <raft/sparse/convert/dense.cuh>
#include <raft/util/cuda_utils.cuh>
#include <raft/util/cudart_utils.hpp>
#include <rmm/device_uvector.hpp>

namespace raft::distance::kernels {

using namespace raft::distance::matrix::detail;

// Get the offset of element [i,k].
HDI int get_offset(int i, int k, int ld, bool is_row_major)
{
  return is_row_major ? i * ld + k : i + k * ld;
}

enum SparseType { DENSE, MIX, CSR };

struct GramMatrixInputs {
  int n1;      // feature vectors in matrix 1
  int n2;      // featuer vectors in matrix 2
  int n_cols;  // number of elements in a feature vector
  bool is_row_major;
  SparseType sparse_input;
  KernelParams kernel;
  int ld1;
  int ld2;
  int ld_out;
  // We will generate random input using the dimensions given here.
  // The reference output is calculated by a custom kernel.
};

std::ostream& operator<<(std::ostream& os, const GramMatrixInputs& p)
{
  std::vector<std::string> kernel_names{"linear", "poly", "rbf", "tanh"};
  os << "/" << p.n1 << "x" << p.n2 << "x" << p.n_cols << "/"
     << (p.is_row_major ? "RowMajor/" : "ColMajor/")
     << (p.sparse_input == SparseType::DENSE
           ? "DenseDense/"
           : (p.sparse_input == SparseType::MIX ? "CsrDense/" : "CsrCsr/"))
     << kernel_names[p.kernel.kernel] << "/ld_" << p.ld1 << "x" << p.ld2 << "x" << p.ld_out;
  return os;
}

const std::vector<GramMatrixInputs> inputs = {
  {42, 137, 2, false, SparseType::DENSE, {KernelType::LINEAR}},
  {42, 137, 2, true, SparseType::DENSE, {KernelType::LINEAR}},
  {42, 137, 2, false, SparseType::DENSE, {KernelType::LINEAR}, 64, 179, 181},
  {42, 137, 2, true, SparseType::DENSE, {KernelType::LINEAR}, 64, 179, 181},
  {42, 137, 2, false, SparseType::MIX, {KernelType::LINEAR}},
  {42, 137, 2, true, SparseType::MIX, {KernelType::LINEAR}},
  {42, 137, 2, false, SparseType::MIX, {KernelType::LINEAR}, 64, 179, 181},
  {42, 137, 2, true, SparseType::MIX, {KernelType::LINEAR}, 64, 179, 181},
  {42, 137, 2, false, SparseType::CSR, {KernelType::LINEAR}},
  {42, 137, 2, true, SparseType::CSR, {KernelType::LINEAR}},
  // CSR does not support ld_out
  {42, 137, 2, false, SparseType::CSR, {KernelType::LINEAR}, 64, 179, 0},
  {42, 137, 2, true, SparseType::CSR, {KernelType::LINEAR}, 64, 179, 0},
  {137, 42, 2, false, SparseType::DENSE, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}},
  {137, 42, 2, true, SparseType::DENSE, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}},
  {137, 42, 2, false, SparseType::DENSE, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}, 159, 73, 144},
  {137, 42, 2, true, SparseType::DENSE, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}, 159, 73, 144},
  {137, 42, 2, false, SparseType::MIX, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}},
  {137, 42, 2, true, SparseType::MIX, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}},
  {137, 42, 2, false, SparseType::MIX, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}, 159, 73, 144},
  {137, 42, 2, true, SparseType::MIX, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}, 159, 73, 144},
  {137, 42, 2, false, SparseType::CSR, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}},
  {137, 42, 2, true, SparseType::CSR, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}},
  // CSR does not support ld_out
  {137, 42, 2, false, SparseType::CSR, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}, 159, 73, 0},
  {137, 42, 2, true, SparseType::CSR, {KernelType::POLYNOMIAL, 2, 0.5, 2.4}, 159, 73, 0},
  {42, 137, 2, false, SparseType::DENSE, {KernelType::TANH, 0, 0.5, 2.4}},
  {42, 137, 2, true, SparseType::DENSE, {KernelType::TANH, 0, 0.5, 2.4}},
  {42, 137, 2, false, SparseType::DENSE, {KernelType::TANH, 0, 0.5, 2.4}, 64, 155, 49},
  {42, 137, 2, true, SparseType::DENSE, {KernelType::TANH, 0, 0.5, 2.4}, 64, 155, 143},
  {42, 137, 2, false, SparseType::MIX, {KernelType::TANH, 0, 0.5, 2.4}},
  {42, 137, 2, true, SparseType::MIX, {KernelType::TANH, 0, 0.5, 2.4}},
  {42, 137, 2, false, SparseType::MIX, {KernelType::TANH, 0, 0.5, 2.4}, 64, 155, 49},
  {42, 137, 2, true, SparseType::MIX, {KernelType::TANH, 0, 0.5, 2.4}, 64, 155, 143},
  {42, 137, 2, false, SparseType::CSR, {KernelType::TANH, 0, 0.5, 2.4}},
  {42, 137, 2, true, SparseType::CSR, {KernelType::TANH, 0, 0.5, 2.4}},
  // CSR does not support ld_out
  {42, 137, 2, false, SparseType::CSR, {KernelType::TANH, 0, 0.5, 2.4}, 64, 155, 0},
  {42, 137, 2, true, SparseType::CSR, {KernelType::TANH, 0, 0.5, 2.4}, 64, 155, 0},
  {3, 4, 2, false, SparseType::DENSE, {KernelType::RBF, 0, 0.5}},
  {42, 137, 2, false, SparseType::DENSE, {KernelType::RBF, 0, 0.5}},
  {42, 137, 2, true, SparseType::DENSE, {KernelType::RBF, 0, 0.5}},
  {3, 4, 2, false, SparseType::MIX, {KernelType::RBF, 0, 0.5}},
  {42, 137, 2, false, SparseType::MIX, {KernelType::RBF, 0, 0.5}},
  {42, 137, 2, true, SparseType::MIX, {KernelType::RBF, 0, 0.5}},
  {3, 4, 2, false, SparseType::CSR, {KernelType::RBF, 0, 0.5}},
  {42, 137, 2, false, SparseType::CSR, {KernelType::RBF, 0, 0.5}},
  {42, 137, 2, true, SparseType::CSR, {KernelType::RBF, 0, 0.5}},
  // Distance kernel does not support LD parameter yet.
  //{42, 137, 2, false, {KernelType::RBF, 0, 0.5}, 64, 155, 49},
  //{42, 137, 2, true, {KernelType::RBF, 0, 0.5}, 64, 155, 143},
};

template <typename math_t>
class GramMatrixTest : public ::testing::TestWithParam<GramMatrixInputs> {
 protected:
  GramMatrixTest()
    : params(GetParam()),
      stream(0),
      x1(0, stream),
      x2(0, stream),
      x1_csr_indptr(0, stream),
      x1_csr_indices(0, stream),
      x1_csr_data(0, stream),
      x2_csr_indptr(0, stream),
      x2_csr_indices(0, stream),
      x2_csr_data(0, stream),
      gram(0, stream),
      gram_host(0)
  {
    RAFT_CUDA_TRY(cudaStreamCreate(&stream));

    if (params.ld1 == 0) { params.ld1 = params.is_row_major ? params.n_cols : params.n1; }
    if (params.ld2 == 0) { params.ld2 = params.is_row_major ? params.n_cols : params.n2; }
    if (params.ld_out == 0) { params.ld_out = params.is_row_major ? params.n2 : params.n1; }
    // Derive the size of the output from the offset of the last element.
    size_t size = get_offset(params.n1 - 1, params.n_cols - 1, params.ld1, params.is_row_major) + 1;
    x1.resize(size, stream);
    size = get_offset(params.n2 - 1, params.n_cols - 1, params.ld2, params.is_row_major) + 1;
    x2.resize(size, stream);
    size = get_offset(params.n1 - 1, params.n2 - 1, params.ld_out, params.is_row_major) + 1;

    gram.resize(size, stream);
    RAFT_CUDA_TRY(cudaMemsetAsync(gram.data(), 0, gram.size() * sizeof(math_t), stream));
    gram_host.resize(gram.size());
    std::fill(gram_host.begin(), gram_host.end(), 0);

    raft::random::Rng r(42137ULL);
    r.uniform(x1.data(), x1.size(), math_t(0), math_t(1), stream);
    r.uniform(x2.data(), x2.size(), math_t(0), math_t(1), stream);
  }

  ~GramMatrixTest() override { RAFT_CUDA_TRY_NO_THROW(cudaStreamDestroy(stream)); }

  // Calculate the Gram matrix on the host.
  void naiveKernel()
  {
    std::vector<math_t> x1_host(x1.size());
    raft::update_host(x1_host.data(), x1.data(), x1.size(), stream);
    std::vector<math_t> x2_host(x2.size());
    raft::update_host(x2_host.data(), x2.data(), x2.size(), stream);
    handle.sync_stream(stream);

    for (int i = 0; i < params.n1; i++) {
      for (int j = 0; j < params.n2; j++) {
        float d = 0;
        for (int k = 0; k < params.n_cols; k++) {
          if (params.kernel.kernel == KernelType::RBF) {
            math_t diff = x1_host[get_offset(i, k, params.ld1, params.is_row_major)] -
                          x2_host[get_offset(j, k, params.ld2, params.is_row_major)];
            d += diff * diff;
          } else {
            d += x1_host[get_offset(i, k, params.ld1, params.is_row_major)] *
                 x2_host[get_offset(j, k, params.ld2, params.is_row_major)];
          }
        }
        int idx  = get_offset(i, j, params.ld_out, params.is_row_major);
        math_t v = 0;
        switch (params.kernel.kernel) {
          case (KernelType::LINEAR): gram_host[idx] = d; break;
          case (KernelType::POLYNOMIAL):
            v              = params.kernel.gamma * d + params.kernel.coef0;
            gram_host[idx] = std::pow(v, params.kernel.degree);
            break;
          case (KernelType::TANH):
            gram_host[idx] = std::tanh(params.kernel.gamma * d + params.kernel.coef0);
            break;
          case (KernelType::RBF): gram_host[idx] = exp(-params.kernel.gamma * d); break;
        }
      }
    }
  }

  int prepareCsr(math_t* dense, int n_rows, int ld, int* indptr, int* indices, math_t* data)
  {
    int nnz           = 0;
    double eps        = 1e-6;
    int n_cols        = params.n_cols;
    bool is_row_major = params.is_row_major;
    size_t dense_size = get_offset(n_rows - 1, n_cols - 1, ld, is_row_major) + 1;

    std::vector<math_t> dense_host(dense_size);
    raft::update_host(dense_host.data(), dense, dense_size, stream);
    handle.sync_stream(stream);

    std::vector<int> indptr_host(n_rows + 1);
    std::vector<int> indices_host(n_rows * n_cols);
    std::vector<math_t> data_host(n_rows * n_cols);

    // create csr matrix from dense (with threshold)
    for (int i = 0; i < n_rows; ++i) {
      indptr_host[i] = nnz;
      for (int j = 0; j < n_cols; ++j) {
        math_t value = dense_host[get_offset(i, j, ld, is_row_major)];
        if (value > eps) {
          indices_host[nnz] = j;
          data_host[nnz]    = value;
          nnz++;
        }
      }
    }
    indptr_host[n_rows] = nnz;

    // fill back dense matrix from CSR
    std::fill(dense_host.data(), dense_host.data() + dense_size, 0);
    for (int i = 0; i < n_rows; ++i) {
      for (int idx = indptr_host[i]; idx < indptr_host[i + 1]; ++idx) {
        dense_host[get_offset(i, indices_host[idx], ld, is_row_major)] = data_host[idx];
      }
    }

    raft::update_device(dense, dense_host.data(), dense_size, stream);
    raft::update_device(indptr, indptr_host.data(), n_rows + 1, stream);
    raft::update_device(indices, indices_host.data(), nnz, stream);
    raft::update_device(data, data_host.data(), nnz, stream);
    handle.sync_stream(stream);

    return nnz;
  }

  void runTest()
  {
    std::unique_ptr<GramMatrixBase<math_t>> kernel =
      std::unique_ptr<GramMatrixBase<math_t>>(KernelFactory<math_t>::create(params.kernel, handle));

    Matrix<math_t>* x1_matrix = nullptr;
    Matrix<math_t>* x2_matrix = nullptr;

    if (params.sparse_input != SparseType::DENSE) {
      x1_csr_indptr.reserve(params.n1 + 1, stream);
      x1_csr_indices.reserve(params.n1 * params.n_cols, stream);
      x1_csr_data.reserve(params.n1 * params.n_cols, stream);
      int nnz   = prepareCsr(x1.data(),
                           params.n1,
                           params.ld1,
                           x1_csr_indptr.data(),
                           x1_csr_indices.data(),
                           x1_csr_data.data());
      x1_matrix = new CsrMatrix<math_t>(x1_csr_indptr.data(),
                                        x1_csr_indices.data(),
                                        x1_csr_data.data(),
                                        nnz,
                                        params.n1,
                                        params.n_cols);
    } else {
      x1_matrix = new DenseMatrix<math_t>(
        x1.data(), params.n1, params.n_cols, params.is_row_major, params.ld1);
    }

    if (params.sparse_input == SparseType::CSR) {
      x2_csr_indptr.reserve(params.n2 + 1, stream);
      x2_csr_indices.reserve(params.n2 * params.n_cols, stream);
      x2_csr_data.reserve(params.n2 * params.n_cols, stream);
      int nnz   = prepareCsr(x2.data(),
                           params.n2,
                           params.ld2,
                           x2_csr_indptr.data(),
                           x2_csr_indices.data(),
                           x2_csr_data.data());
      x2_matrix = new CsrMatrix<math_t>(x2_csr_indptr.data(),
                                        x2_csr_indices.data(),
                                        x2_csr_data.data(),
                                        nnz,
                                        params.n2,
                                        params.n_cols);
    } else {
      x2_matrix = new DenseMatrix<math_t>(
        x2.data(), params.n2, params.n_cols, params.is_row_major, params.ld2);
    }

    DenseMatrix<math_t> gram_dense(
      gram.data(), params.n1, params.n2, params.is_row_major, params.ld_out);

    naiveKernel();

    (*kernel)(*x1_matrix, *x2_matrix, gram_dense, stream);
    handle.sync_stream(stream);

    ASSERT_TRUE(raft::devArrMatchHost(
      gram_host.data(), gram.data(), gram.size(), raft::CompareApprox<math_t>(1e-6f)));

    delete x1_matrix;
    delete x2_matrix;
  }

  raft::device_resources handle;
  cudaStream_t stream = 0;
  GramMatrixInputs params;

  rmm::device_uvector<math_t> x1;
  rmm::device_uvector<math_t> x2;

  rmm::device_uvector<int> x1_csr_indptr;
  rmm::device_uvector<int> x1_csr_indices;
  rmm::device_uvector<math_t> x1_csr_data;
  rmm::device_uvector<int> x2_csr_indptr;
  rmm::device_uvector<int> x2_csr_indices;
  rmm::device_uvector<math_t> x2_csr_data;

  rmm::device_uvector<math_t> gram;
  std::vector<math_t> gram_host;
};

typedef GramMatrixTest<float> GramMatrixTestFloat;
typedef GramMatrixTest<double> GramMatrixTestDouble;

TEST_P(GramMatrixTestFloat, Gram) { runTest(); }

INSTANTIATE_TEST_SUITE_P(GramMatrixTests, GramMatrixTestFloat, ::testing::ValuesIn(inputs));
};  // end namespace raft::distance::kernels