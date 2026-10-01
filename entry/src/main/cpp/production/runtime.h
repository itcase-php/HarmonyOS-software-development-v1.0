#pragma once
#include "../core/converter.h"
#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

namespace hdm::production {
struct Grant {
    std::string sessionId, taskId, attemptId, workspaceRef;
    std::filesystem::path directory;
    std::shared_ptr<std::atomic<bool>> cancelled;
};
struct ProbeResult {
    std::vector<InputProbe> inputs;
};
class Runtime final {
public:
    std::string Initialize(const SessionInit& init);
    std::string Register(const WorkspaceGrant& grant);
    ProbeResult Probe(const ProbeRequest& request);
    ConvertResult Execute(const ConvertRequest& request);
    ControlAck Control(const std::string& taskId, const std::string& attemptId, const char* action);
    void ReleaseTask(const std::string& taskId, const std::string& attemptId);
    void ReleaseArtifact(const std::string& ref);
    void Shutdown();
    bool HasSession(const std::string& sessionId) const;
private:
    struct Session { std::filesystem::path root; std::unordered_map<std::string, Grant> grants; };
    struct ArtifactState { std::filesystem::path path; std::string taskId, attemptId; };
    Grant GetGrant(const std::string& sessionId, const std::string& workspaceRef) const;
    mutable std::mutex mutex_;
    std::unordered_map<std::string, Session> sessions_;
    std::unordered_map<std::string, ArtifactState> artifacts_;
};
Runtime& SharedRuntime();
} // namespace hdm::production
