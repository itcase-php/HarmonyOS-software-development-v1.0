#include "stream.h"
#include <algorithm>
#include <array>
#include <cerrno>
#include <climits>
#include <fcntl.h>
#include <limits>
#ifdef _WIN32
#include <io.h>
#define HDM_OPEN _open
#define HDM_CLOSE _close
#define HDM_FDOPEN _fdopen
#define HDM_SEEK _fseeki64
#define HDM_TELL _ftelli64
#else
#include <unistd.h>
#define HDM_OPEN open
#define HDM_CLOSE close
#define HDM_FDOPEN fdopen
#define HDM_SEEK fseeko
#define HDM_TELL ftello
#endif
namespace hdm::prototype {
void CheckControl(const Control& control) {
    const auto code = control ? control() : ErrorCode::Ok;
    if (code != ErrorCode::Ok) throw BridgeProblem(code, code == ErrorCode::ConversionCancelled ? "PROTOTYPE_CANCELLED" : "PROTOTYPE_CONTROL_STOPPED");
}
void WriteAll(ISink& output, const void* data, std::size_t size, const Control& control,
    std::uint64_t& written, std::uint64_t maximum) {
    const auto* bytes = static_cast<const unsigned char*>(data);
    if (written > maximum || size > maximum - written) throw BridgeProblem(ErrorCode::ResourceLimitExceeded, "PROTOTYPE_TEMP_LIMIT");
    while (size) {
        CheckControl(control); const auto count = output.Write(bytes, size);
        if (!count || count > size) throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_SHORT_WRITE");
        written += count; bytes += count; size -= count;
    }
}
void CopyChunks(IStream& input, ISink& output, std::uint64_t size, const Control& control,
    std::uint64_t& written, std::uint64_t maximum, std::uint64_t nativeBudget) {
    if (nativeBudget < kChunkBytes) throw BridgeProblem(ErrorCode::ResourceLimitExceeded, "PROTOTYPE_COPY_MEMORY_LIMIT");
    std::array<unsigned char, kChunkBytes> buffer{};
    while (size) {
        CheckControl(control); const auto request = static_cast<std::size_t>(std::min<std::uint64_t>(size, buffer.size()));
        const auto count = input.Read(buffer.data(), request);
        if (!count || count > request) throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_SHORT_READ");
        WriteAll(output, buffer.data(), count, control, written, maximum); size -= count;
    }
}
HostFile::HostFile(const std::string& path, bool createExclusive) {
    int flags = createExclusive ? O_RDWR | O_CREAT | O_EXCL : O_RDONLY;
#ifdef _WIN32
    flags |= O_BINARY;
#endif
    const int fd = HDM_OPEN(path.c_str(), flags, 0600);
    if (fd < 0) throw BridgeProblem(createExclusive ? ErrorCode::IoError : ErrorCode::InputNotFound, "PROTOTYPE_FILE_OPEN");
    file_ = HDM_FDOPEN(fd, createExclusive ? "w+b" : "rb");
    if (!file_) { HDM_CLOSE(fd); throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_FILE_STREAM"); }
    if (setvbuf(file_, nullptr, _IONBF, 0) != 0) { fclose(file_); file_ = nullptr; throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_FILE_BUFFER"); }
}
HostFile::~HostFile() { if (file_) fclose(file_); }
std::size_t HostFile::Read(void* data, std::size_t capacity) {
    const auto count = fread(data, 1, capacity, file_);
    if (ferror(file_)) throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_FILE_READ");
    return count;
}
void HostFile::Seek(std::uint64_t position) {
    if (position > static_cast<std::uint64_t>(std::numeric_limits<long long>::max()) || HDM_SEEK(file_, static_cast<long long>(position), SEEK_SET) != 0)
        throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_FILE_SEEK");
    clearerr(file_);
}
std::uint64_t HostFile::Size() {
    const auto old = HDM_TELL(file_);
    if (old < 0 || HDM_SEEK(file_, 0, SEEK_END) != 0) throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_FILE_SIZE");
    const auto size = HDM_TELL(file_);
    if (size < 0 || HDM_SEEK(file_, old, SEEK_SET) != 0) throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_FILE_SIZE");
    return static_cast<std::uint64_t>(size);
}
std::size_t HostFile::Write(const void* data, std::size_t size) {
    const auto count = fwrite(data, 1, size, file_);
    if (ferror(file_)) throw BridgeProblem(errno == ENOSPC ? ErrorCode::StorageFull : ErrorCode::IoError, "PROTOTYPE_FILE_WRITE");
    return count;
}
void HostFile::Flush() { if (fflush(file_) != 0) throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_FILE_FLUSH"); }
}
