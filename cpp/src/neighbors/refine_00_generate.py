#!/usr/bin/env python3

header = """
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

#include <raft/neighbors/refine-inl.cuh>

#define instantiate_raft_neighbors_refine(idx_t, data_t, distance_t, matrix_idx)       \\
  template void raft::neighbors::refine<idx_t, data_t, distance_t, matrix_idx>(        \\
    raft::device_resources const& handle,                                              \\
    raft::device_matrix_view<const data_t, matrix_idx, row_major> dataset,             \\
    raft::device_matrix_view<const data_t, matrix_idx, row_major> queries,             \\
    raft::device_matrix_view<const idx_t, matrix_idx, row_major> neighbor_candidates,  \\
    raft::device_matrix_view<idx_t, matrix_idx, row_major> indices,                    \\
    raft::device_matrix_view<distance_t, matrix_idx, row_major> distances,             \\
    raft::distance::DistanceType metric);                                              \\
                                                                                       \\
  template void raft::neighbors::refine<idx_t, data_t, distance_t, matrix_idx>(        \\
    raft::device_resources const& handle,                                              \\
    raft::host_matrix_view<const data_t, matrix_idx, row_major> dataset,               \\
    raft::host_matrix_view<const data_t, matrix_idx, row_major> queries,               \\
    raft::host_matrix_view<const idx_t, matrix_idx, row_major> neighbor_candidates,    \\
    raft::host_matrix_view<idx_t, matrix_idx, row_major> indices,                      \\
    raft::host_matrix_view<distance_t, matrix_idx, row_major> distances,               \\
    raft::distance::DistanceType metric);

"""

types = dict(
    float_float= ("float", "float"),
    int8_t_float=("int8_t", "float"),
    uint8_t_float=("uint8_t", "float"),
)

for type_path, (data_t, distance_t) in types.items():
    path = f"refine_{type_path}.cu"
    with open(path, "w") as f:
        f.write(header)
        f.write(f"instantiate_raft_neighbors_refine(int64_t, {data_t}, {distance_t}, int64_t);\n\n")
        f.write(f"#undef instantiate_raft_neighbors_refine\n")

    # for pasting into CMakeLists.txt
    print(f"src/neighbors/{path}")
