/*
 * Copyright (c) 2022-2023, NVIDIA CORPORATION.
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

#include <cstdint>                                // uintX_t
#include <raft/neighbors/ivf_flat_types.hpp>      // index
#include <raft/spatial/knn/detail/ann_utils.cuh>  // TODO: consider remove
#include <raft/util/raft_explicit.hpp>            // RAFT_EXPLICIT
#include <rmm/cuda_stream_view.hpp>               // rmm:cuda_stream_view

#ifdef RAFT_EXPLICIT_INSTANTIATE_ONLY

namespace raft::neighbors::ivf_flat::detail {

template <typename T, typename IdxT>
void search(raft::device_resources const& handle,
            const search_params& params,
            const raft::neighbors::ivf_flat::index<T, IdxT>& index,
            const T* queries,
            uint32_t n_queries,
            uint32_t k,
            IdxT* neighbors,
            float* distances,
            rmm::mr::device_memory_resource* mr = nullptr);

}  // namespace raft::neighbors::ivf_flat::detail

#endif  // RAFT_EXPLICIT_INSTANTIATE_ONLY

#define instantiate_raft_neighbors_ivf_flat_detail_search(T, IdxT)         \
  extern template void raft::neighbors::ivf_flat::detail::search<T, IdxT>( \
    raft::device_resources const& handle,                                  \
    const search_params& params,                                           \
    const raft::neighbors::ivf_flat::index<T, IdxT>& index,                \
    const T* queries,                                                      \
    uint32_t n_queries,                                                    \
    uint32_t k,                                                            \
    IdxT* neighbors,                                                       \
    float* distances,                                                      \
    rmm::mr::device_memory_resource* mr)

instantiate_raft_neighbors_ivf_flat_detail_search(float, int64_t);
instantiate_raft_neighbors_ivf_flat_detail_search(int8_t, int64_t);
instantiate_raft_neighbors_ivf_flat_detail_search(uint8_t, int64_t);

#undef instantiate_raft_neighbors_ivf_flat_detail_search
