//
//  MSRZipArchive.cpp
//  MuseReaderiOS
//
//  Created by Codex on 4/13/26.
//

#include "MSRZipArchive.hpp"

#include <limits>
#include <utility>

#include <zlib.h>

namespace {

constexpr std::uint32_t kEndOfCentralDirectorySignature = 0x06054b50;
constexpr std::uint32_t kCentralDirectoryEntrySignature = 0x02014b50;
constexpr std::uint32_t kLocalFileHeaderSignature = 0x04034b50;

std::uint16_t readUInt16(const std::vector<std::uint8_t>& data, std::size_t offset)
{
    return static_cast<std::uint16_t>(data[offset])
           | (static_cast<std::uint16_t>(data[offset + 1]) << 8);
}

std::uint32_t readUInt32(const std::vector<std::uint8_t>& data, std::size_t offset)
{
    return static_cast<std::uint32_t>(data[offset])
           | (static_cast<std::uint32_t>(data[offset + 1]) << 8)
           | (static_cast<std::uint32_t>(data[offset + 2]) << 16)
           | (static_cast<std::uint32_t>(data[offset + 3]) << 24);
}

bool inflateRaw(const std::uint8_t* source, std::size_t sourceLength, std::vector<std::uint8_t>& destination, std::string& errorMessage)
{
    if (sourceLength > std::numeric_limits<uInt>::max() || destination.size() > std::numeric_limits<uInt>::max()) {
        errorMessage = "Archive entry is too large to inflate.";
        return false;
    }

    z_stream stream {};
    stream.next_in = const_cast<Bytef*>(reinterpret_cast<const Bytef*>(source));
    stream.avail_in = static_cast<uInt>(sourceLength);
    stream.next_out = reinterpret_cast<Bytef*>(destination.data());
    stream.avail_out = static_cast<uInt>(destination.size());

    int result = inflateInit2(&stream, -MAX_WBITS);
    if (result != Z_OK) {
        errorMessage = "Failed to initialize ZIP inflation.";
        return false;
    }

    result = inflate(&stream, Z_FINISH);
    if (result != Z_STREAM_END) {
        inflateEnd(&stream);
        errorMessage = "Failed to inflate ZIP entry.";
        return false;
    }

    destination.resize(stream.total_out);
    inflateEnd(&stream);
    return true;
}

} // namespace

namespace msr {

bool ZipArchive::open(std::vector<std::uint8_t> data, std::string& errorMessage)
{
    archiveData_ = std::move(data);
    entries_.clear();
    return parse(errorMessage);
}

bool ZipArchive::extract(std::string_view path, std::vector<std::uint8_t>& output, std::string& errorMessage) const
{
    const ZipEntry* entry = findEntry(path);
    if (!entry) {
        errorMessage = "Archive entry not found.";
        return false;
    }

    const std::size_t localHeaderOffset = entry->localHeaderOffset;
    if (localHeaderOffset + 30 > archiveData_.size()) {
        errorMessage = "Local ZIP header is truncated.";
        return false;
    }

    if (readUInt32(archiveData_, localHeaderOffset) != kLocalFileHeaderSignature) {
        errorMessage = "Local ZIP header signature is invalid.";
        return false;
    }

    const std::size_t fileNameLength = readUInt16(archiveData_, localHeaderOffset + 26);
    const std::size_t extraFieldLength = readUInt16(archiveData_, localHeaderOffset + 28);
    const std::size_t dataOffset = localHeaderOffset + 30 + fileNameLength + extraFieldLength;

    if (dataOffset + entry->compressedSize > archiveData_.size()) {
        errorMessage = "ZIP entry data is truncated.";
        return false;
    }

    const std::uint8_t* source = archiveData_.data() + dataOffset;

    if (entry->compressionMethod == 0) {
        output.assign(source, source + entry->compressedSize);
        return true;
    }

    if (entry->compressionMethod != 8) {
        errorMessage = "Unsupported ZIP compression method.";
        return false;
    }

    output.assign(entry->uncompressedSize, 0);
    return inflateRaw(source, entry->compressedSize, output, errorMessage);
}

std::vector<std::string> ZipArchive::entryNames() const
{
    std::vector<std::string> names;
    names.reserve(entries_.size());

    for (const ZipEntry& entry : entries_) {
        names.push_back(entry.path);
    }

    return names;
}

bool ZipArchive::parse(std::string& errorMessage)
{
    if (archiveData_.size() < 22) {
        errorMessage = "ZIP archive is too small.";
        return false;
    }

    const std::size_t endOfCentralDirectoryOffset = findEndOfCentralDirectory();
    if (endOfCentralDirectoryOffset == std::string::npos) {
        errorMessage = "End of central directory was not found.";
        return false;
    }

    const std::uint16_t entryCount = readUInt16(archiveData_, endOfCentralDirectoryOffset + 10);
    const std::uint32_t centralDirectorySize = readUInt32(archiveData_, endOfCentralDirectoryOffset + 12);
    const std::uint32_t centralDirectoryOffset = readUInt32(archiveData_, endOfCentralDirectoryOffset + 16);

    if (static_cast<std::size_t>(centralDirectoryOffset) + centralDirectorySize > archiveData_.size()) {
        errorMessage = "Central directory is truncated.";
        return false;
    }

    std::size_t offset = centralDirectoryOffset;
    for (std::uint16_t index = 0; index < entryCount; ++index) {
        if (offset + 46 > archiveData_.size()) {
            errorMessage = "Central directory entry is truncated.";
            return false;
        }

        if (readUInt32(archiveData_, offset) != kCentralDirectoryEntrySignature) {
            errorMessage = "Central directory signature is invalid.";
            return false;
        }

        const std::uint16_t compressionMethod = readUInt16(archiveData_, offset + 10);
        const std::uint32_t compressedSize = readUInt32(archiveData_, offset + 20);
        const std::uint32_t uncompressedSize = readUInt32(archiveData_, offset + 24);
        const std::uint16_t fileNameLength = readUInt16(archiveData_, offset + 28);
        const std::uint16_t extraFieldLength = readUInt16(archiveData_, offset + 30);
        const std::uint16_t commentLength = readUInt16(archiveData_, offset + 32);
        const std::uint32_t localHeaderOffset = readUInt32(archiveData_, offset + 42);

        const std::size_t pathOffset = offset + 46;
        const std::size_t nextOffset = pathOffset + fileNameLength + extraFieldLength + commentLength;
        if (nextOffset > archiveData_.size()) {
            errorMessage = "Central directory entry data is truncated.";
            return false;
        }

        std::string path(
            reinterpret_cast<const char*>(archiveData_.data() + pathOffset),
            fileNameLength
        );

        entries_.push_back({
            std::move(path),
            compressionMethod,
            compressedSize,
            uncompressedSize,
            localHeaderOffset
        });

        offset = nextOffset;
    }

    return true;
}

const ZipEntry* ZipArchive::findEntry(std::string_view path) const
{
    for (const ZipEntry& entry : entries_) {
        if (entry.path == path) {
            return &entry;
        }
    }

    return nullptr;
}

std::size_t ZipArchive::findEndOfCentralDirectory() const
{
    const std::size_t minimumOffset = archiveData_.size() > (0xFFFF + 22)
        ? archiveData_.size() - (0xFFFF + 22)
        : 0;

    for (std::size_t offset = archiveData_.size() - 22;; --offset) {
        if (readUInt32(archiveData_, offset) == kEndOfCentralDirectorySignature) {
            return offset;
        }

        if (offset == minimumOffset) {
            break;
        }
    }

    return std::string::npos;
}

} // namespace msr
