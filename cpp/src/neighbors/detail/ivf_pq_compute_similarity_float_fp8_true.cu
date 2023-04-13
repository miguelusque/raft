
/*
 * Copyright (c) 2023, NVIDIA CORPORATION.
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

#include <raft/neighbors/detail/ivf_pq_compute_similarity-inl.cuh>
#include <raft/neighbors/detail/ivf_pq_fp_8bit.cuh>

#define instantiate_raft_neighbors_ivf_pq_detail_compute_similarity_select(OutT, LutT)  \
  template auto raft::neighbors::ivf_pq::detail::compute_similarity_select<OutT, LutT>( \
    const cudaDeviceProp& dev_props,                                                    \
    bool manage_local_topk,                                                             \
    int locality_hint,                                                                  \
    double preferred_shmem_carveout,                                                    \
    uint32_t pq_bits,                                                                   \
    uint32_t pq_dim,                                                                    \
    uint32_t precomp_data_count,                                                        \
    uint32_t n_queries,                                                                 \
    uint32_t n_probes,                                                                  \
    uint32_t topk)                                                                      \
    ->raft::neighbors::ivf_pq::detail::selected<OutT, LutT>;                            \
                                                                                        \
  template void raft::neighbors::ivf_pq::detail::compute_similarity_run<OutT, LutT>(    \
    raft::neighbors::ivf_pq::detail::selected<OutT, LutT> s,                            \
    rmm::cuda_stream_view stream,                                                       \
    uint32_t n_rows,                                                                    \
    uint32_t dim,                                                                       \
    uint32_t n_probes,                                                                  \
    uint32_t pq_dim,                                                                    \
    uint32_t n_queries,                                                                 \
    raft::distance::DistanceType metric,                                                \
    raft::neighbors::ivf_pq::codebook_gen codebook_kind,                                \
    uint32_t topk,                                                                      \
    uint32_t max_samples,                                                               \
    const float* cluster_centers,                                                       \
    const float* pq_centers,                                                            \
    const uint8_t* const* pq_dataset,                                                   \
    const uint32_t* cluster_labels,                                                     \
    const uint32_t* _chunk_indices,                                                     \
    const float* queries,                                                               \
    const uint32_t* index_list,                                                         \
    float* query_kths,                                                                  \
    LutT* lut_scores,                                                                   \
    OutT* _out_scores,                                                                  \
    uint32_t* _out_indices);

#define COMMA ,
instantiate_raft_neighbors_ivf_pq_detail_compute_similarity_select(
  float, raft::neighbors::ivf_pq::detail::fp_8bit<5u COMMA true>);

#undef COMMA

#undef instantiate_raft_neighbors_ivf_pq_detail_compute_similarity_select
