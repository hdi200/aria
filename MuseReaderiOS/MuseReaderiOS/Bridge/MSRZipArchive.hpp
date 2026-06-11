//
//  MSRZipArchive.hpp
//  MuseReaderiOS
//
//  Created by Codex on 4/13/26.
//

#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace msr {

struct ZipEntry {
    std::string path;
    std::uint16_t compressionMethod = 0;
    std::uint32_t compressedSize = 0;
    std::uint32_t uncompressedSize = 0;
    std::uint32_t localHeaderOffset = 0;
};

class ZipArchive {
public:
    bool open(std::vector<std::uint8_t> data, std::string& errorMessage);
    bool extract(std::string_view path, std::vector<std::uint8_t>& output, std::string& errorMessage) const;
    std::vector<std::string> entryNames() const;

private:
    bool parse(std::string& errorMessage);
    const ZipEntry* findEntry(std::string_view path) const;
    std::size_t findEndOfCentralDirectory() const;

    std::vector<std::uint8_t> archiveData_;
    std::vector<ZipEntry> entries_;
};

} // namespace msr
