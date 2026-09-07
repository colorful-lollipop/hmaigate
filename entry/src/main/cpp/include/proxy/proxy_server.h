// proxy_server.h —— 基于 mongoose 的高性能 HTTP 转发代理（核心）
//
// 职责：在本地端口监听 HTTP，把 Claude Code 的请求转发到上游大模型厂商，
// 原样回传响应（支持 SSE 流式）；转发前可选进行安全检测（拦截密码泄露/提示注入）。
// 事件循环运行在独立线程，与 NAPI 调用线程隔离。
#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "proxy/upstream.h"

// 前向声明 mongoose 管理器，避免在头文件中暴露 mongoose.h
struct mg_mgr;
struct mg_connection;

namespace hmsec {

// 上游配置（由 ArkTS 通过 NAPI 注入）。
struct UpstreamConfig {
  bool set = false;
  std::string baseUrl;        // 例：https://open.bigmodel.cn/api/anthropic
  std::string apiKey;         // API Key（透传或注入鉴权头）
  std::string apiKeyField;    // "ANTHROPIC_AUTH_TOKEN" | "ANTHROPIC_API_KEY" | "GEMINI_API_KEY"
  std::string model;          // 默认模型（可选，覆盖 ANTHROPIC_MODEL）
};

// 代理运行状态快照。
struct ProxySnapshot {
  bool running = false;
  std::string host;
  uint16_t port = 0;
  uint32_t totalRequests = 0;
  uint32_t successRequests = 0;
  uint32_t blockedRequests = 0;
  uint32_t failedRequests = 0;
  std::string lastError;
  bool securityEnabled = true;          // 请求侧安全检测开关（云端策略可热更新）
  bool responseSecurityEnabled = true;  // M4：响应侧安全检测开关（随 getStatus 上送 UI）
};

class ProxyServer {
 public:
  static ProxyServer& Instance();

  // 启动监听（host:port）。返回是否成功。重复 Start 直接返回 false。
  bool Start(const std::string& host, uint16_t port);
  void Stop();
  bool IsRunning() const { return running_.load(); }

  // 设置/更新上游（可在运行中热更新；切换供应商时调用）。
  void SetUpstream(const UpstreamConfig& u);
  UpstreamConfig CurrentUpstream();

  // 安全检测开关。
  void SetSecurityEnabled(bool e) { security_enabled_ = e; }
  bool IsSecurityEnabled() const { return security_enabled_.load(); }

  // M4：响应侧安全检测开关（默认 true；atomic 提供跨线程可见性，与
  // security_enabled_ 同一处理方式——NAPI 线程写、转发工作线程读）。
  void SetResponseSecurityEnabled(bool e) { response_security_enabled_ = e; }
  bool IsResponseSecurityEnabled() const { return response_security_enabled_.load(); }

  // 本连接是否需要走 ResponseScanner（响应检测开启 且 有启用的响应侧检测能力：
  // 内置检测器或至少一个响应插件钩子）。两个条件都不满足时保持零拷贝直通。
  bool ShouldScanResponse();

  ProxySnapshot Snapshot() const;

  // —— 以下为事件处理器（在同文件 .cpp 的自由函数中调用）所需的内部接口 ——
  // （安全检测/路由/请求构造已抽至 proxy/request_pipeline.h 的管线步骤函数）
  void IncTotal();
  void IncSuccess();
  void IncBlocked();
  void IncFailed();
  void SetLastError(const std::string& msg);

 private:
  ProxyServer();
  ~ProxyServer();
  ProxyServer(const ProxyServer&) = delete;
  ProxyServer& operator=(const ProxyServer&) = delete;

  void Loop();  // 工作线程：mg_mgr_poll 循环

  std::unique_ptr<mg_mgr> mgr_;
  mg_connection* listener_ = nullptr;
  std::thread* worker_ = nullptr;
  std::atomic<bool> running_{false};
  std::atomic<bool> stopFlag_{false};
  std::atomic<bool> security_enabled_{true};
  std::atomic<bool> response_security_enabled_{true};  // M4：响应侧检测默认开启

  mutable std::mutex upstream_mutex_;
  UpstreamConfig upstream_;

  mutable std::mutex stats_mutex_;
  uint32_t total_ = 0;
  uint32_t success_ = 0;
  uint32_t blocked_ = 0;
  uint32_t failed_ = 0;
  std::string lastError_;
};

}  // namespace hmsec
