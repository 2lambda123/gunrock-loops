/**
 * @file work_oriented.cuh
 * @author Muhammad Osama (mosama@ucdavis.edu)
 * @brief Sparse Matrix-Vector Multiplication example.
 * @version 0.1
 * @date 2022-02-03
 *
 * @copyright Copyright (c) 2022
 *
 */

#pragma once

#include <loops/schedule.hxx>
#include <loops/util/math.hxx>
#include <loops/container/formats.hxx>
#include <loops/container/vector.hxx>
#include <loops/util/launch.hxx>
#include <loops/util/device.hxx>
#include <loops/memory.hxx>
#include <iostream>

#include <cub/block/block_scan.cuh>

namespace loops {
namespace algorithms {
namespace spmv {

/**
 * @brief Flat Merge-Path SpMV kernel.
 *
 * @tparam threads_per_block Number of threads per block.
 * @tparam items_per_thread Number of items per thread to process.
 * @tparam index_t Type of column indices.
 * @tparam offset_t Type of row offsets.
 * @tparam type_t Type of values.
 */
template <std::size_t threads_per_block,
          std::size_t items_per_thread,
          typename meta_t,
          typename index_t,
          typename offset_t,
          typename type_t>
__global__ void __launch_bounds__(int(threads_per_block))
    __merge_path_flat(meta_t meta,
                      std::size_t rows,
                      std::size_t cols,
                      std::size_t nnz,
                      offset_t* offsets,
                      index_t* indices,
                      const type_t* values,
                      const type_t* x,
                      type_t* y) {
  using setup_t = schedule::setup<schedule::algorithms_t::merge_path_flat,
                                  threads_per_block, items_per_thread, index_t,
                                  offset_t, std::size_t, std::size_t>;

  /// Allocate temporary storage for the schedule.
  using storage_t = typename setup_t::storage_t;
  __shared__ storage_t temporary_storage;

  /// Construct the schedule.
  setup_t config(meta, temporary_storage, offsets, rows, nnz);
  auto map = config.init();

  if (!config.is_valid_accessor(map))
    return;

/// Flat Merge-Path loop from 0..items_per_thread.
#pragma unroll
  for (auto item : config.virtual_idx()) {
    auto nz = config.atom_idx(item, map);
    auto row = config.tile_idx(map);
    type_t nonzero = values[nz] * x[indices[nz]];
    if (config.atoms_counting_it[map.y] <
        temporary_storage.tile_end_offset[map.x]) {
      atomicAdd(&(y[row]), nonzero);
      map.y++;
    } else {
      map.x++;
    }
  }
}

/**
 * @brief Sparse-Matrix Vector Multiplication API.
 *
 * @tparam index_t Type of column indices.
 * @tparam offset_t Type of row offsets.
 * @tparam type_t Type of values.
 * @param csr CSR matrix (GPU).
 * @param x Input vector x (GPU).
 * @param y Output vector y (GPU).
 * @param stream CUDA stream.
 */
template <typename index_t, typename offset_t, typename type_t>
util::timer_t merge_path_flat(csr_t<index_t, offset_t, type_t>& csr,
                              vector_t<type_t>& x,
                              vector_t<type_t>& y,
                              cudaStream_t stream = 0) {
  // Create a schedule.
  constexpr std::size_t block_size = sizeof(type_t) > 4 ? 64 : 128;
  constexpr std::size_t items_per_thread = sizeof(type_t) > 4 ? 3 : 5;

  using preprocessor_t =
      schedule::merge_path::preprocess_t<block_size, items_per_thread, index_t,
                                         offset_t, std::size_t, std::size_t>;

  /// Light-weight preprocess that does not modify the data, just creates an
  /// array with pre-calculated per block coordinates to reduce the work in the
  /// actual kernel.
  preprocessor_t meta(csr.offsets.data().get(), csr.rows, csr.nnzs, stream);

  /// Set-up kernel launch parameters and run the kernel.
  int max_dim_x;
  int num_merge_tiles =
      math::ceil_div(csr.rows + csr.nnzs, block_size * items_per_thread);
  int device_ordinal = device::get();
  cudaDeviceGetAttribute(&max_dim_x, cudaDevAttrMaxGridDimX, device_ordinal);

  util::timer_t timer;
  timer.start();

  // Launch main kernel that uses merge-path schedule.
  int within_bounds = min(num_merge_tiles, max_dim_x);
  int overflow = math::ceil_div(num_merge_tiles, max_dim_x);
  dim3 grid_size(within_bounds, overflow, 1);
  launch::non_cooperative(
      stream,
      __merge_path_flat<block_size, items_per_thread, preprocessor_t, index_t,
                        offset_t, type_t>,
      grid_size, block_size, meta, csr.rows, csr.cols, csr.nnzs,
      csr.offsets.data().get(), csr.indices.data().get(),
      csr.values.data().get(), x.data().get(), y.data().get());
  cudaStreamSynchronize(stream);
  timer.stop();

  return timer;
}

}  // namespace spmv
}  // namespace algorithms
}  // namespace loops