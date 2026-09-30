#include "ir.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <iostream>
#include <random>
#include <system_error>
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/stat.h>
#include <unistd.h>
#endif
using namespace hdm;
using namespace hdm::prototype;
namespace {
bool Exists(const std::string& path) {
#ifdef _WIN32
    return GetFileAttributesA(path.c_str()) != INVALID_FILE_ATTRIBUTES;
#else
    struct stat info{}; return stat(path.c_str(),&info) == 0;
#endif
}
void CreateOnlyLink(const std::string& source, const std::string& destination) {
#ifdef _WIN32
    if (!CreateHardLinkA(destination.c_str(),source.c_str(),nullptr))
#else
    if (link(source.c_str(),destination.c_str()) != 0)
#endif
        throw BridgeProblem(ErrorCode::IoError, "PROTOTYPE_COMMIT_FAILED");
}
struct OwnedPaths {
    std::string spool, candidate;
    bool spoolCreated{}, candidateCreated{};
    ~OwnedPaths() {
        if (spoolCreated) std::remove(spool.c_str());
        if (candidateCreated) std::remove(candidate.c_str());
    }
};
std::uint64_t Unsigned(const std::string& value) {
    if (value.empty() || value[0] == '-') throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_OPTION_RANGE");
    std::size_t used{}; std::uint64_t result{};
    try { result = std::stoull(value, &used); }
    catch (...) { throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_OPTION_RANGE"); }
    if (used != value.size()) throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_OPTION_RANGE");
    return result;
}
ResourceBudget DefaultBudget() {
    ResourceBudget budget{};
    budget.maxInputBytes = 104857600; budget.maxBatchBytes = 314572800;
    budget.maxNativeBytes = 201326592; budget.maxTempBytes = 536870912;
    budget.maxPages = 300; budget.maxPixels = 16000000; budget.maxThreads = 2; budget.timeoutMs = 180000;
    return budget;
}
int Run(int argc, char** argv) {
    if (argc < 3) throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_ARGUMENTS");
    const std::string inputPath(argv[1]), outputPath(argv[2]);
    if (Exists(outputPath)) throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_OUTPUT_EXISTS");
    auto budget = DefaultBudget(); bool cancel = false;
    for (int i = 3; i < argc; ++i) {
        const std::string option(argv[i]);
        if (option == "--cancel") { cancel = true; continue; }
        if (i + 1 >= argc) throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_ARGUMENTS");
        const auto value = Unsigned(argv[++i]);
        if (option == "--max-native-bytes") budget.maxNativeBytes = value;
        else if (option == "--max-input-bytes") budget.maxInputBytes = value;
        else if (option == "--max-temp-bytes") budget.maxTempBytes = value;
        else if (option == "--max-pixels" && value <= UINT32_MAX) budget.maxPixels = static_cast<std::uint32_t>(value);
        else if (option == "--timeout-ms" && value <= UINT32_MAX) budget.timeoutMs = static_cast<std::uint32_t>(value);
        else throw BridgeProblem(ErrorCode::InvalidRequest, "PROTOTYPE_OPTION_UNKNOWN");
    }
    std::random_device random;
    const auto suffix = ".hdm-" + std::to_string(random()) + "-" + std::to_string(random());
    OwnedPaths paths{outputPath+suffix+".jpg", outputPath+suffix+".pdf"};
    const auto began = std::chrono::steady_clock::now();
    Control control = [began, cancel, timeout=budget.timeoutMs] {
        if (cancel) return ErrorCode::ConversionCancelled;
        if (std::chrono::steady_clock::now() - began > std::chrono::milliseconds(timeout)) return ErrorCode::ConversionTimeout;
        return ErrorCode::Ok;
    };
    PrototypeResult result;
    {
        HostFile input(inputPath, false);
        HostFile spool(paths.spool, true); paths.spoolCreated = true;
        HostFile pdf(paths.candidate, true); paths.candidateCreated = true;
        result = Convert(input, spool, pdf, budget, control);
    }
    // A same-directory hard link creates the final name only if it is absent;
    // unlike rename, it never replaces another file that raced our creation.
    CreateOnlyLink(paths.candidate, outputPath);
    const auto& image = result.document.pages[0].images[0];
    std::cout << "{\"state\":\"prototype_candidate\",\"format\":\"pdf\",\"profile\":\"image_pdf\",\"pages\":1,"
              << "\"widthPx\":" << image.widthPx << ",\"heightPx\":" << image.heightPx
              << ",\"sourceBytes\":" << image.byteSize << ",\"pdfBytes\":" << result.candidate.bytes
              << ",\"embeddedJpegIdentical\":" << (result.candidate.payloadIdentical ? "true" : "false")
              << ",\"trackedAllocationPeak\":" << result.candidate.trackedAllocationPeak
              << ",\"tempPeak\":" << result.candidate.tempPeak << "}\n";
    return 0;
}
}
int main(int argc, char** argv) {
    try { return Run(argc, argv); }
    catch (const BridgeProblem& error) {
        std::cerr << "{\"code\":\"" << ErrorCodeName(error.code) << "\",\"reason\":\"" << error.what() << "\"}\n";
    } catch (const std::bad_alloc&) {
        std::cerr << "{\"code\":\"RESOURCE_LIMIT_EXCEEDED\",\"reason\":\"PROTOTYPE_ALLOCATION\"}\n";
    } catch (const std::exception&) {
        std::cerr << "{\"code\":\"IO_ERROR\",\"reason\":\"PROTOTYPE_HOST_IO\"}\n";
    }
    return 1;
}
