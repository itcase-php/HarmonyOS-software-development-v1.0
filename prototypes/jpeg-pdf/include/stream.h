#pragma once
#include "../../../entry/src/main/cpp/napi/bridge_problem.h"
#include <cstdio>
#include <functional>

namespace hdm::prototype {
inline constexpr std::size_t kChunkBytes = 64 * 1024;
struct IStream {
    virtual ~IStream() = default;
    virtual std::size_t Read(void* buffer, std::size_t capacity) = 0;
    virtual void Seek(std::uint64_t position) = 0;
    virtual std::uint64_t Size() = 0;
};
struct ISink {
    virtual ~ISink() = default;
    virtual std::size_t Write(const void* buffer, std::size_t size) = 0;
};
struct IFile : IStream, ISink { virtual void Flush() = 0; };
using Control = std::function<ErrorCode()>;
void CheckControl(const Control& control);
void WriteAll(ISink& output, const void* data, std::size_t size, const Control& control,
    std::uint64_t& written, std::uint64_t maximum);
void CopyChunks(IStream& input, ISink& output, std::uint64_t size, const Control& control,
    std::uint64_t& written, std::uint64_t maximum, std::uint64_t nativeBudget);
// Explicitly host file I/O, never a Native workspace grant or URI authorization.
class HostFile final : public IFile {
    FILE* file_{};
public:
    HostFile(const std::string& path, bool createExclusive);
    ~HostFile() override;
    HostFile(const HostFile&) = delete;
    HostFile& operator=(const HostFile&) = delete;
    std::size_t Read(void*, std::size_t) override;
    void Seek(std::uint64_t) override;
    std::uint64_t Size() override;
    std::size_t Write(const void*, std::size_t) override;
    void Flush() override;
};
}
