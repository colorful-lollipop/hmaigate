// password_leak_audit.h —— 请求侧密码泄露提醒审计（异步、只保留脱敏元数据）
//
// 这个组件故意不复用同步 SecurityDetector 的 BLOCK 结论：用户把可能的密码或
// Key 发给 Agent 时，网关仍应立即转发；审计线程仅在后台生成不含原文的提醒记录。
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace aigate {

struct PasswordLeakAlert {
  std::string id;
  uint64_t timeMs = 0;
  std::string severity;    // "high" | "medium"
  std::string secretType;  // "api_key" | "password" | "token" | "private_key" | "credential"
  std::string location;    // "json_field" | "env_assignment" | "code_text" | "known_pattern"
  std::string protocol;
  std::string model;
  std::string status;      // "new" | "read"
};

struct PasswordLeakAuditStatus {
  uint32_t unreadCount = 0;
  uint32_t todayCount = 0;
  uint64_t lastAlertTimeMs = 0;
  uint32_t droppedTasks = 0;
  uint32_t truncatedTasks = 0;
  uint32_t failedTasks = 0;
};

struct PasswordLeakAlertPage {
  std::vector<PasswordLeakAlert> alerts;
  uint32_t total = 0;
};

class PasswordLeakAudit {
 public:
  static PasswordLeakAudit& GetInstance();

  // 仅复制前 256KB 入有界队列。队列锁使用 try_lock：队列繁忙或已满时直接丢弃审计
  // 任务，绝不等待或阻塞代理请求；请求正文不会保存在告警历史中。
  void Enqueue(const std::string& body, const std::string& protocol,
               const std::string& model);

  // 关闭时清理尚未处理的正文，防止已禁用后继续产生新告警。
  void SetEnabled(bool enabled);
  bool IsEnabled() const { return enabled_.load(); }

  PasswordLeakAuditStatus GetStatus();
  PasswordLeakAlertPage GetAlerts(uint32_t offset, uint32_t limit);
  uint32_t MarkRead(const std::vector<std::string>& ids);
  void ClearAlerts();

  // 宿主单测用：等待队列清空和当前扫描结束，不暴露给 NAPI。
  bool WaitForIdleForTest(uint32_t timeoutMs);

 private:
  PasswordLeakAudit() = default;
  ~PasswordLeakAudit();
  PasswordLeakAudit(const PasswordLeakAudit&) = delete;
  PasswordLeakAudit& operator=(const PasswordLeakAudit&) = delete;

  struct AuditTask {
    std::string body;
    std::string protocol;
    std::string model;
    bool truncated = false;
  };

  void EnsureWorkerLocked();
  void WorkerLoop();
  void ProcessTask(const AuditTask& task);
  void PurgeExpiredLocked(uint64_t nowMs);

  static constexpr size_t kMaxBodyBytes = 256 * 1024;
  static constexpr size_t kMaxQueueTasks = 64;
  static constexpr size_t kMaxAlerts = 200;
  static constexpr uint64_t kRetentionMs = 30ULL * 24ULL * 60ULL * 60ULL * 1000ULL;

  std::atomic<bool> enabled_{true};
  std::atomic<bool> stop_{false};
  std::atomic<uint32_t> droppedTasks_{0};
  std::atomic<uint32_t> truncatedTasks_{0};
  std::atomic<uint32_t> failedTasks_{0};

  std::mutex queueMutex_;
  std::condition_variable queueCv_;
  std::condition_variable idleCv_;
  std::deque<AuditTask> queue_;
  bool processing_ = false;
  std::thread worker_;

  std::mutex alertMutex_;
  std::deque<PasswordLeakAlert> alerts_;
  uint64_t nextId_ = 1;
};

}  // namespace aigate
