// password_leak_audit.cpp —— 密码泄露提醒的受限异步审计实现
#include "security/password_leak_audit.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <unordered_set>
#include <utility>

#include "str_util.h"

namespace aigate {

// BiSheng 的部分目标仍按 C++14 的 ODR 规则处理类内 constexpr；为避免设备侧链接器
// 对被取址的容量常量报 undefined symbol，这里提供显式定义（值仍以头文件为准）。
constexpr size_t PasswordLeakAudit::kMaxBodyBytes;
constexpr size_t PasswordLeakAudit::kMaxQueueTasks;
constexpr size_t PasswordLeakAudit::kMaxAlerts;
constexpr uint64_t PasswordLeakAudit::kRetentionMs;

namespace {

using Clock = std::chrono::system_clock;

uint64_t NowMs() {
  return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
      Clock::now().time_since_epoch()).count());
}

void SecureClear(std::string& value) {
  std::fill(value.begin(), value.end(), '\0');
  value.clear();
}

bool IsWordChar(char c) {
  const unsigned char uc = static_cast<unsigned char>(c);
  return std::isalnum(uc);
}

std::string Trim(const std::string& value) {
  size_t begin = 0;
  size_t end = value.size();
  while (begin < end && std::isspace(static_cast<unsigned char>(value[begin]))) ++begin;
  while (end > begin && std::isspace(static_cast<unsigned char>(value[end - 1]))) --end;
  return value.substr(begin, end - begin);
}

bool IsPlaceholder(const std::string& rawValue) {
  const std::string value = hmsec::ToLower(Trim(rawValue));
  if (value.empty() || value == "null" || value == "undefined" || value == "none") return true;
  if (value == "***" || value == "redacted" || value == "[redacted]") return true;
  if ((value.front() == '<' && value.back() == '>') ||
      (value.size() >= 3 && value[0] == '$' && value[1] == '{' && value.back() == '}')) {
    return true;
  }
  return value.find("your_") != std::string::npos ||
         value.find("your-") != std::string::npos ||
         value.find("example") != std::string::npos ||
         value.find("placeholder") != std::string::npos ||
         value.find("replace_me") != std::string::npos ||
         value.find("changeme") != std::string::npos;
}

struct Finding {
  const char* severity;
  const char* secretType;
  const char* location;
  size_t position;
};

void AddFinding(std::vector<Finding>& findings, const Finding& finding) {
  // 一段文本可能同时匹配字段和值格式；同一位置只保留风险更高的已知格式结论。
  for (const Finding& previous : findings) {
    if (previous.position == finding.position) return;
  }
  if (findings.size() < 16) findings.push_back(finding);
}

const char* FieldSecretType(const std::string& key) {
  if (key.find("private") != std::string::npos) return "private_key";
  if (key.find("password") != std::string::npos || key == "passwd" || key == "pwd") {
    return "password";
  }
  if (key.find("api") != std::string::npos || key.find("access") != std::string::npos) {
    return "api_key";
  }
  if (key.find("token") != std::string::npos) return "token";
  return "credential";
}

const char* FieldSeverity(const std::string& key) {
  return (key.find("private") != std::string::npos || key.find("api") != std::string::npos ||
          key.find("access") != std::string::npos)
             ? "high"
             : "medium";
}

void FindSensitiveAssignments(const std::string& text, std::vector<Finding>& findings) {
  static const char* kKeys[] = {
      "password", "passwd", "pwd", "secret", "token", "api_key", "api-key", "apikey",
      "access_key", "access-key", "secret_key", "secret-key", "private_key", "private-key",
      "auth_token", "auth-token", "credential", "credentials"};
  const std::string lower = hmsec::ToLower(text);

  for (const char* keyLiteral : kKeys) {
    const std::string key(keyLiteral);
    size_t search = 0;
    while (search < lower.size()) {
      const size_t pos = lower.find(key, search);
      if (pos == std::string::npos) break;
      search = pos + key.size();
      // 下划线和连字符是环境变量/配置键的常见分段符，例如 OPENAI_API_KEY、
      // AWS_SECRET_ACCESS_KEY。允许在这些复合键的末段命中，但不匹配普通单词内部。
      if ((pos > 0 && IsWordChar(lower[pos - 1])) ||
          (search < lower.size() && IsWordChar(lower[search]))) {
        continue;
      }

      size_t cursor = search;
      // JSON 的字段名末尾可有引号；YAML/.env/Shell 则直接接空白和 :/=
      if (cursor < text.size() && (text[cursor] == '\'' || text[cursor] == '"')) ++cursor;
      while (cursor < text.size() && std::isspace(static_cast<unsigned char>(text[cursor]))) ++cursor;
      if (cursor >= text.size() || (text[cursor] != ':' && text[cursor] != '=')) continue;
      const char delimiter = text[cursor++];
      while (cursor < text.size() && std::isspace(static_cast<unsigned char>(text[cursor]))) ++cursor;
      if (cursor >= text.size()) continue;

      const size_t valueStart = cursor;
      std::string value;
      if (text[cursor] == '\'' || text[cursor] == '"') {
        const char quote = text[cursor++];
        const size_t contentStart = cursor;
        while (cursor < text.size()) {
          if (text[cursor] == '\\' && cursor + 1 < text.size()) {
            cursor += 2;
            continue;
          }
          if (text[cursor] == quote) break;
          ++cursor;
        }
        value = text.substr(contentStart, cursor - contentStart);
      } else {
        while (cursor < text.size() && !std::isspace(static_cast<unsigned char>(text[cursor])) &&
               text[cursor] != ',' && text[cursor] != ';' && text[cursor] != '}' &&
               text[cursor] != ']') {
          ++cursor;
        }
        value = text.substr(valueStart, cursor - valueStart);
      }
      if (IsPlaceholder(value)) continue;
      const char* location = delimiter == ':' ? "json_field" : "env_assignment";
      AddFinding(findings, {FieldSeverity(key), FieldSecretType(key), location, pos});
      SecureClear(value);
    }
  }
}

// 已知格式只记录格式分类，永远不把匹配内容带到 Finding/Alert 或日志中。
bool IsAsciiAlphaNumUnderscoreHyphen(char c) {
  const unsigned char uc = static_cast<unsigned char>(c);
  return std::isalnum(uc) || c == '_' || c == '-';
}

size_t TokenRunEnd(const std::string& text, size_t start) {
  size_t end = start;
  while (end < text.size() && IsAsciiAlphaNumUnderscoreHyphen(text[end])) ++end;
  return end;
}

void FindKnownPatterns(const std::string& text, std::vector<Finding>& findings) {
  // PEM 私钥有稳定的公开头，不需要保留后续内容即可发出高风险告警。
  static const char* kPemHeaders[] = {
      "-----BEGIN PRIVATE KEY-----", "-----BEGIN RSA PRIVATE KEY-----",
      "-----BEGIN EC PRIVATE KEY-----", "-----BEGIN OPENSSH PRIVATE KEY-----",
      "-----BEGIN DSA PRIVATE KEY-----"};
  for (const char* header : kPemHeaders) {
    const size_t pos = text.find(header);
    if (pos != std::string::npos) AddFinding(findings, {"high", "private_key", "known_pattern", pos});
  }

  const std::string lower = hmsec::ToLower(text);
  const struct PrefixSpec {
    const char* prefix;
    size_t minLength;
    const char* type;
  } prefixes[] = {
      {"sk-ant-", 24, "api_key"}, {"sk-", 24, "api_key"},
      {"ghp_", 24, "token"}, {"gho_", 24, "token"}, {"ghu_", 24, "token"},
      {"ghs_", 24, "token"}, {"ghr_", 24, "token"}, {"glpat-", 24, "token"},
      {"xoxb-", 18, "token"}, {"xoxp-", 18, "token"}, {"xoxa-", 18, "token"},
      {"xoxr-", 18, "token"}, {"akia", 20, "credential"}, {"asia", 20, "credential"}};
  for (const PrefixSpec& spec : prefixes) {
    size_t search = 0;
    while (search < lower.size()) {
      const size_t pos = lower.find(spec.prefix, search);
      if (pos == std::string::npos) break;
      search = pos + 1;
      const size_t end = TokenRunEnd(text, pos);
      if (end - pos >= spec.minLength) {
        AddFinding(findings, {"high", spec.type, "known_pattern", pos});
      }
    }
  }

  // JWT 三段均至少 10 个 URL-safe 字符；不提取或保存 token 本身。
  size_t search = 0;
  while (search < text.size()) {
    const size_t pos = text.find("eyJ", search);
    if (pos == std::string::npos) break;
    search = pos + 3;
    const size_t firstEnd = TokenRunEnd(text, pos);
    if (firstEnd - pos < 13 || firstEnd >= text.size() || text[firstEnd] != '.') continue;
    const size_t secondEnd = TokenRunEnd(text, firstEnd + 1);
    if (secondEnd - firstEnd - 1 < 10 || secondEnd >= text.size() || text[secondEnd] != '.') continue;
    const size_t thirdEnd = TokenRunEnd(text, secondEnd + 1);
    if (thirdEnd - secondEnd - 1 >= 10) {
      AddFinding(findings, {"high", "token", "known_pattern", pos});
    }
  }
}

std::vector<Finding> DetectFindings(const std::string& text) {
  std::vector<Finding> findings;
  FindKnownPatterns(text, findings);
  FindSensitiveAssignments(text, findings);
  return findings;
}

}  // namespace

PasswordLeakAudit& PasswordLeakAudit::GetInstance() {
  static PasswordLeakAudit instance;
  return instance;
}

PasswordLeakAudit::~PasswordLeakAudit() {
  {
    std::lock_guard<std::mutex> lock(queueMutex_);
    stop_.store(true);
    for (AuditTask& task : queue_) SecureClear(task.body);
    queue_.clear();
  }
  queueCv_.notify_all();
  if (worker_.joinable()) worker_.join();
}

void PasswordLeakAudit::EnsureWorkerLocked() {
  if (worker_.joinable()) return;
  worker_ = std::thread([this]() { WorkerLoop(); });
}

void PasswordLeakAudit::SetEnabled(bool enabled) {
  enabled_.store(enabled);
  if (enabled) return;
  std::lock_guard<std::mutex> lock(queueMutex_);
  for (AuditTask& task : queue_) SecureClear(task.body);
  queue_.clear();
  idleCv_.notify_all();
}

void PasswordLeakAudit::Enqueue(const std::string& body, const std::string& protocol,
                                const std::string& model) {
  if (!enabled_.load() || body.empty()) return;
  std::unique_lock<std::mutex> lock(queueMutex_, std::try_to_lock);
  if (!lock.owns_lock() || queue_.size() >= kMaxQueueTasks) {
    droppedTasks_.fetch_add(1);
    return;
  }

  AuditTask task;
  const size_t copied = std::min(body.size(), kMaxBodyBytes);
  task.body.assign(body.data(), copied);
  task.protocol = protocol;
  task.model = model;
  task.truncated = body.size() > copied;
  if (task.truncated) truncatedTasks_.fetch_add(1);
  queue_.push_back(std::move(task));
  EnsureWorkerLocked();
  lock.unlock();
  queueCv_.notify_one();
}

void PasswordLeakAudit::WorkerLoop() {
  while (true) {
    AuditTask task;
    {
      std::unique_lock<std::mutex> lock(queueMutex_);
      queueCv_.wait(lock, [this]() { return stop_.load() || !queue_.empty(); });
      if (stop_.load() && queue_.empty()) return;
      task = std::move(queue_.front());
      queue_.pop_front();
      processing_ = true;
    }
    try {
      if (enabled_.load()) ProcessTask(task);
    } catch (...) {
      // 审计失败必须被隔离，不能传到转发线程或写出正文/异常上下文。
      failedTasks_.fetch_add(1);
    }
    SecureClear(task.body);
    SecureClear(task.protocol);
    SecureClear(task.model);
    {
      std::lock_guard<std::mutex> lock(queueMutex_);
      processing_ = false;
      if (queue_.empty()) idleCv_.notify_all();
    }
  }
}

void PasswordLeakAudit::ProcessTask(const AuditTask& task) {
  const std::vector<Finding> findings = DetectFindings(task.body);
  if (findings.empty()) return;

  // 模型名通常是普通标识符，但它来自请求体。若攻击者把凭据伪装成 model 值，不能让
  // 告警历史反过来成为泄露载体；这种极端情况只保留脱敏占位。
  std::string safeModel = task.model.substr(0, 128);
  if (!DetectFindings(safeModel).empty()) safeModel = "[redacted]";

  const uint64_t now = NowMs();
  std::lock_guard<std::mutex> lock(alertMutex_);
  PurgeExpiredLocked(now);
  for (const Finding& finding : findings) {
    while (alerts_.size() >= kMaxAlerts) alerts_.pop_front();
    PasswordLeakAlert alert;
    alert.id = std::to_string(now) + "-" + std::to_string(nextId_++);
    alert.timeMs = now;
    alert.severity = finding.severity;
    alert.secretType = finding.secretType;
    alert.location = finding.location;
    alert.protocol = task.protocol;
    alert.model = safeModel;
    alert.status = "new";
    alerts_.push_back(std::move(alert));
  }
}

void PasswordLeakAudit::PurgeExpiredLocked(uint64_t nowMs) {
  while (!alerts_.empty() && nowMs > alerts_.front().timeMs &&
         nowMs - alerts_.front().timeMs > kRetentionMs) {
    alerts_.pop_front();
  }
}

PasswordLeakAuditStatus PasswordLeakAudit::GetStatus() {
  PasswordLeakAuditStatus status;
  const uint64_t now = NowMs();
  std::lock_guard<std::mutex> lock(alertMutex_);
  PurgeExpiredLocked(now);
  const uint64_t dayStart = now - (now % (24ULL * 60ULL * 60ULL * 1000ULL));
  for (const PasswordLeakAlert& alert : alerts_) {
    if (alert.status == "new") ++status.unreadCount;
    if (alert.timeMs >= dayStart) ++status.todayCount;
    status.lastAlertTimeMs = std::max(status.lastAlertTimeMs, alert.timeMs);
  }
  status.droppedTasks = droppedTasks_.load();
  status.truncatedTasks = truncatedTasks_.load();
  status.failedTasks = failedTasks_.load();
  return status;
}

PasswordLeakAlertPage PasswordLeakAudit::GetAlerts(uint32_t offset, uint32_t limit) {
  PasswordLeakAlertPage page;
  const uint64_t now = NowMs();
  std::lock_guard<std::mutex> lock(alertMutex_);
  PurgeExpiredLocked(now);
  page.total = static_cast<uint32_t>(alerts_.size());
  if (limit == 0) return page;
  const size_t begin = std::min(static_cast<size_t>(offset), alerts_.size());
  const size_t end = std::min(alerts_.size(), begin + std::min<size_t>(limit, 100));
  page.alerts.reserve(end - begin);
  // 历史列表按最新优先；offset 也据此计数。
  for (size_t index = begin; index < end; ++index) {
    page.alerts.push_back(alerts_[alerts_.size() - 1 - index]);
  }
  return page;
}

uint32_t PasswordLeakAudit::MarkRead(const std::vector<std::string>& ids) {
  if (ids.empty()) return 0;
  const std::unordered_set<std::string> idSet(ids.begin(), ids.end());
  uint32_t changed = 0;
  std::lock_guard<std::mutex> lock(alertMutex_);
  PurgeExpiredLocked(NowMs());
  for (PasswordLeakAlert& alert : alerts_) {
    if (alert.status == "new" && idSet.find(alert.id) != idSet.end()) {
      alert.status = "read";
      ++changed;
    }
  }
  return changed;
}

void PasswordLeakAudit::ClearAlerts() {
  std::lock_guard<std::mutex> lock(alertMutex_);
  alerts_.clear();
}

bool PasswordLeakAudit::WaitForIdleForTest(uint32_t timeoutMs) {
  std::unique_lock<std::mutex> lock(queueMutex_);
  return idleCv_.wait_for(lock, std::chrono::milliseconds(timeoutMs), [this]() {
    return queue_.empty() && !processing_;
  });
}

}  // namespace aigate
