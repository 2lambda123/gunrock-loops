/**
 * @file filepath.hxx
 * @author Muhammad Osama (mosama@ucdavis.edu)
 * @brief Utilities for filepaths.
 * @version 0.1
 * @date 2022-02-03
 *
 * @copyright Copyright (c) 2022
 *
 */

#pragma once

#include <string>

namespace loops {

std::string extract_filename(std::string path, std::string delim = "/") {
  size_t lastSlashIndex = path.find_last_of("/");
  return path.substr(lastSlashIndex + 1);
}

std::string extract_dataset(std::string filename) {
  size_t lastindex = filename.find_last_of(".");
  return filename.substr(0, lastindex);
}

bool is_market(std::string filename) {
  return ((filename.substr(filename.size() - 4) == ".mtx") ||
          (filename.substr(filename.size() - 5) == ".mmio"));
}

bool is_binary_csr(std::string filename) {
  return filename.substr(filename.size() - 4) == ".csr";
}

}  // namespace loops