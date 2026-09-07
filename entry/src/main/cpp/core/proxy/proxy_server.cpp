// proxy_server.cpp —— cpp-httplib 转发代理实现
//
// 每条请求一条转发链：
//   httplib 线程池 handler（已收完整请求 body）
//     → 管线：ResolveRoute / SecurityCheckRequest / 密码泄露异步审计
//     → 启动 pump 线程向上游 send()：响应头经 req.response_handler 回调
//       提前发布（send 会阻塞到 body 读完，不能等 send 返回才取头），
//       body 字节经 req.content_receiver 压入有界字节队列。
//       选缓冲式 send 而非 open_stream 的原因：open_stream 把 socket 所有权
//       移交给 StreamHandle（私有字段），外部无法主动中断，Stop() 最坏要等
//       上游读超时；缓冲路径下 Client::stop() 在请求进行中会 shutdown
//       socket，pump 立即解阻塞（ClientImpl::stop 语义）。
//     → handler 等到头后回写状态码/响应头，并以 set_chunked_content_provider
//       从队列排空回传本地客户端；挂了 ResponseScanner 时在泵线程逐块 Feed、
//       只把确认安全的字节入队，命中阻断则发 SSE 错误事件后 done() 收尾。
//   生命周期：pump 线程 detach，ctx/Client 全程 shared_ptr 持有；provider 的
//   资源释放器（Response 析构必调）负责注销在途表 + stop 上游 Client 保证
//   pump 及时退出。停止有界：Stop() 关监听 socket → 解阻塞全部在途转发 →
//   join，绝不等待上游超时。
#include "proxy/proxy_server.h"

#include <atomic>
#include <chrono>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "httplib/httplib.h"
#include "json_scan.h"                    // hmsec::JsonEscape（SSE 错误事件的 JSON 转义）
#include "plugin_manager.h"               // aigate::PluginManager（响应侧钩子探测）
#include "proxy/request_pipeline.h"       // 转发管线：ResolveRoute / SecurityCheckRequest / ...
#include "proxy/upstream.h"
#include "security/response_scanner.h"    // 响应流式安全扫描
#include "str_util.h"                     // hmsec::ToLower
#include <hilog/log.h>                    // OH_LOG_Print：C++ 事件直打 hilog（诊断转发链路）
#if defined(MBEDTLS_PSA_CRYPTO_C)
#include <psa/crypto.h>  // psa_crypto_init（mbedtls 3.6 部分 EC/ECDH 走 PSA，握手前需初始化）
#endif
#define PROXY_LOG(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "ProxyEv", __VA_ARGS__)

namespace hmsec {
namespace detail {

using httplib::Client;
using httplib::Headers;
using httplib::Request;
using httplib::Response;

// 有界字节队列：pump 线程（上游 → 队列）与 provider（队列 → 本地客户端）解耦。
// 容量即背压，与「socket 直通天然背压」等价，防止大响应撑爆内存。
class BoundedByteQueue {
 public:
  explicit BoundedByteQueue(size_t capacityBytes) : capacity_(capacityBytes) {}

  // 阻塞入队。返回 false = 队列已关闭（泵线程随即放弃剩余转发）。
  bool Push(std::string&& chunk) {
    std::unique_lock<std::mutex> lk(m_);
    cvFull_.wait(lk, [&] { return closed_ || bytes_ + chunk.size() <= capacity_; });
    if (closed_) return false;
    bytes_ += chunk.size();
    chunks_.push_back(std::move(chunk));
    cvEmpty_.notify_one();
    return true;
  }

  // 阻塞出队。返回 false = 队列已关闭且已排空，消费方据此收尾。
  bool Pop(std::string& out) {
    std::unique_lock<std::mutex> lk(m_);
    cvEmpty_.wait(lk, [&] { return closed_ || !chunks_.empty(); });
    if (chunks_.empty()) return false;  // closed_ 且排空
    bytes_ -= chunks_.front().size();
    out = std::move(chunks_.front());
    chunks_.pop_front();
    cvFull_.notify_one();
    return true;
  }

  // 关闭队列：已缓冲数据仍可 Pop 出来（排空语义），之后两端都不再阻塞。
  void Close() {
    std::lock_guard<std::mutex> lk(m_);
    closed_ = true;
    cvEmpty_.notify_all();
    cvFull_.notify_all();
  }

  // 丢弃积压并关闭（阻断/失败/停机路径：让两端尽快取到终止信号）。
  void CloseAndDrop() {
    std::lock_guard<std::mutex> lk(m_);
    chunks_.clear();
    bytes_ = 0;
    closed_ = true;
    cvEmpty_.notify_all();
    cvFull_.notify_all();
  }

 private:
  size_t capacity_;
  std::mutex m_;
  std::condition_variable cvFull_;
  std::condition_variable cvEmpty_;
  std::deque<std::string> chunks_;
  size_t bytes_ = 0;
  bool closed_ = false;
};

// 一次转发的共享上下文：pump 线程、handler/provider（监听线程池线程）与
// Stop() 三方共享。生命周期由 shared_ptr 保证：handler 的 provider lambda、
// 泵线程 lambda、ProxyServer 在途表各持一份；任一使用方访问期间必然存活。
struct RelayContext {
  explicit RelayContext(size_t queueCapBytes) : queue(queueCapBytes) {}

  BoundedByteQueue queue;
  std::shared_ptr<Client> cli;  // 泵线程在用；释放器 stop() 它以解阻塞泵
  std::unique_ptr<ResponseScanner> scanner;  // 为空 = 直通路径

  // 上游响应头：pump 的 response_handler 回调发布（body 之前），handler 线程
  // 在 headReady 置位后读取（seq_cst 建立先行关系）。
  std::atomic<bool> headReady{false};
  int upstreamStatus = -1;
  Headers upstreamHeaders;

  bool relayed = false;          // 是否已回传过响应字节（success 计数，只计一次）
  bool securityBlocked = false;  // ResponseScanner 命中阻断（泵线程写）
  bool failedNoted = false;      // 失败记账只做一次
  bool overflowReported = false; // 扫描器 fail-open 只告警一次
};

}  // namespace detail

namespace {

using detail::BoundedByteQueue;
using detail::RelayContext;
using httplib::Client;
using httplib::Headers;
using httplib::Request;
using httplib::Response;

// 响应回传本地客户端时剥掉的响应头：逐跳头 + 框架自动生成的头。
// Content-Length 必须剥：chunked provider 场景 httplib 自动改用
// Transfer-Encoding: chunked（apply_ranges），保留旧值会与分块帧冲突。
// Content-Type 单独处理（set_chunked_content_provider 会写入它，这里跳过防重复）。
bool IsSkippedResponseHeader(const std::string& lowerName) {
  return lowerName == "connection" || lowerName == "keep-alive" ||
         lowerName == "transfer-encoding" || lowerName == "content-length" ||
         lowerName == "trailer" || lowerName == "proxy-connection" ||
         lowerName == "upgrade" || lowerName == "content-type";
}

// 转发请求头时剥掉的头：逐跳头 + 框架按 req.body 重算的头 + Accept-Encoding +
// 客户端自带鉴权头（换网关持有的真实 Key）。
// Accept-Encoding 必须剥：本构建未编 zlib，若放行上游 gzip 响应，泵线程会因
// UnsupportedContentEncoding 直接失败；剥掉即「只收未压缩响应」。
bool IsSkippedRequestHeader(const std::string& lowerName) {
  return lowerName == "host" || lowerName == "content-length" ||
         lowerName == "connection" || lowerName == "accept-encoding" ||
         lowerName == "keep-alive" || lowerName == "transfer-encoding" ||
         lowerName == "expect" || lowerName == "proxy-connection" ||
         lowerName == "upgrade" || IsAuthHeaderName(lowerName);
}

// 构造上游 Client（通用构造按 scheme 自动选 ClientImpl/SSLClient）。
// 证书校验关闭：本地无系统 CA 可用，与旧版 skip_verification 一致
//（本地可信网关场景；mbedtls 仍完整解析证书链）。
std::shared_ptr<Client> MakeUpstreamClient(const ParsedUrl& target) {
  const int port = (target.port != 0) ? target.port : DefaultPort(target.tls);
  auto cli = std::make_shared<Client>((target.tls ? "https://" : "http://") +
                                      target.host + ":" + std::to_string(port));
  if (!cli->is_valid()) return cli;
  // 路径已由 ResolveTarget/JoinUrl 拼好（含 query），httplib 的默认编码会
  // 二次编码 `%xx`——关闭，原样上送字节。
  cli->set_path_encode(false);
  // 对齐旧 BuildRequest 的 Connection: close：不复用连接，响应读完即断。
  cli->set_keep_alive(false);
  cli->set_connection_timeout(10);
  cli->set_read_timeout(300);   // SSE 长流空闲容忍
  cli->set_write_timeout(30);
  return cli;
}

// 把下游请求头复制给上游（跳过 IsSkippedRequestHeader 命中的头），再按上游
// 配置注入网关侧鉴权头（BuildAuthHeader 的 "Name: value\r\n" 形态解析回键值对）。
Headers BuildUpstreamHeaders(const HeaderList& in, const UpstreamConfig& up) {
  Headers out;
  for (const auto& h : in) {
    if (IsSkippedRequestHeader(ToLower(h.first))) continue;
    out.emplace(h.first, h.second);
  }
  const std::string raw = BuildAuthHeader(up.apiKeyField, up.apiKey);
  if (!raw.empty()) {
    const size_t colon = raw.find(": ");
    if (colon != std::string::npos) {
      std::string name = raw.substr(0, colon);
      std::string value = raw.substr(colon + 2);
      while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) {
        value.pop_back();
      }
      out.emplace(std::move(name), std::move(value));
    }
  }
  return out;
}

// 首次向本地客户端回传响应字节时记一次成功（每条转发只计一次）。
void NoteRelayed(RelayContext* ctx, ProxyServer* self) {
  if (ctx->relayed) return;
  ctx->relayed = true;
  if (self != nullptr) self->IncSuccess();
}

// 记失败（幂等）。
void NoteFailed(RelayContext* ctx, ProxyServer* self, const std::string& msg) {
  if (ctx->failedNoted) return;
  ctx->failedNoted = true;
  if (self != nullptr) {
    self->IncFailed();
    if (!msg.empty()) self->SetLastError(msg);
  }
}

// 阻断事件的 SSE 形态。选 SSE 事件的理由与旧版一致：Agent 客户端是 SSE
// 解析器，流内 data: {"error":...} 能被按协议解析展示；对非 SSE 响应也是可读尾部。
std::string MakeBlockEvent(const std::string& reason) {
  return "data: {\"error\":{\"type\":\"security_block\",\"message\":\"" +
         JsonEscape(reason) + "\"}}\n\n";
}

// 泵线程主体：向上游发请求。响应头经 response_handler 提前发布；响应体经
// content_receiver 压入有界队列（ResponseScanner 在泵线程逐块 Feed，只有
// 确认安全的字节入队）。send 返回后兜底发布响应头（HEAD/204 无回调）并收尾。
void PumpUpstream(const std::shared_ptr<RelayContext>& ctx, ProxyServer* self,
                  const std::shared_ptr<Client>& cli, const std::string& method,
                  const std::string& pathWithQuery, const Headers& headers,
                  const std::string& body) {
  Request req;
  req.method = method;
  req.path = pathWithQuery;
  req.headers = headers;
  req.body = body;

  // 响应头发布（读 body 前回调）。返回 false 会让 send 以 Canceled 放弃——
  // 头总是放行，阻断发生在 body 阶段。
  req.response_handler = [ctx](const Response& rs) {
    ctx->upstreamStatus = rs.status;
    Headers picked;
    for (const auto& h : rs.headers) {
      if (!IsSkippedResponseHeader(ToLower(h.first))) {
        picked.emplace(h.first, h.second);
      }
    }
    ctx->upstreamHeaders = std::move(picked);
    ctx->headReady.store(true);
    return true;
  };

  // 响应体泵入口。返回 false 会让 send 以 Canceled 放弃本次请求。
  req.content_receiver = [ctx, self](const char* data, size_t n, size_t, size_t) {
    if (ctx->securityBlocked || ctx->failedNoted) return false;
    if (ctx->scanner != nullptr) {
      ScanOutcome out = ctx->scanner->Feed(data, n);
      if (out.overflow && !ctx->overflowReported) {
        ctx->overflowReported = true;
        PROXY_LOG("response scanner overflow (>256KB), fail-open passthrough");
      }
      if (!out.release.empty()) {
        if (!ctx->queue.Push(std::move(out.release))) return false;
        NoteRelayed(ctx.get(), self);
      }
      if (out.blocked) {
        ctx->securityBlocked = true;
        if (self != nullptr) {
          self->IncBlocked();
          self->SetLastError("response blocked: " + out.reason);
        }
        PROXY_LOG("response blocked: %{public}s", out.reason.c_str());
        ctx->queue.Push(MakeBlockEvent(out.reason));  // 客户端可解析的终止事件
        ctx->queue.Close();
        return false;
      }
      return true;
    }
    // 直通路径：字节原样入队
    std::string chunk(data, n);
    if (!ctx->queue.Push(std::move(chunk))) return false;
    NoteRelayed(ctx.get(), self);
    return true;
  };

  httplib::Error err = httplib::Error::Success;
  Response res;
  const bool ok = cli->send(req, res, err);

  // 兜底发布：HEAD/204 等不触发 response_handler 的场景，send 返回后 res
  // 已含最终状态/头。
  if (!ctx->headReady.load()) {
    ctx->upstreamStatus = ok ? res.status : -1;
    Headers picked;
    for (const auto& h : res.headers) {
      if (!IsSkippedResponseHeader(ToLower(h.first))) {
        picked.emplace(h.first, h.second);
      }
    }
    ctx->upstreamHeaders = std::move(picked);
    ctx->headReady.store(true);
  }

  // 失败记账：与旧版语义对齐——上游没回传任何字节才算失败（已回传过的不补计）。
  if ((!ok || err != httplib::Error::Success) && !ctx->relayed &&
      !ctx->securityBlocked) {
    NoteFailed(ctx.get(), self,
               "upstream error: " + std::string(httplib::to_string(err)));
    PROXY_LOG("upstream error: %{public}s", httplib::to_string(err).c_str());
  }
  ctx->queue.Close();  // 无论成败，泵到此为止；provider 端排空后自然结束
}

// 处理一条已收完 body 的代理请求（catch-all 路由的共用 handler）。
void HandleProxyRequest(ProxyServer* self, const Request& req, Response& res) {
  // ---- 管线步骤 1：路由解析（CurrentUpstream 在互斥锁下读取，保持锁语义）----
  RouteResult route =
      ResolveRoute(self->CurrentUpstream(), req.method, req.target, req.body);
  if (!route.ok) {
    res.status = 502;
    res.set_header("Content-Type", "text/plain");
    if (route.error == RouteError::kNoUpstream) {
      res.body = "no upstream configured";
      self->SetLastError("no upstream");
    } else {
      res.body = "bad upstream url";
      self->SetLastError("bad upstream url");
    }
    self->IncFailed();
    return;
  }
  if (!route.ruleId.empty()) {
    PROXY_LOG("route hit: rule=%{public}s proto=%{public}s model=%{public}s",
              route.ruleId.c_str(), ProtocolToString(route.protocol),
              route.model.c_str());
  }

  // ---- 管线步骤 2：请求体安全检测（只查 body，不查鉴权头）----
  if (!SecurityCheckRequest(self->IsSecurityEnabled(), req.method, req.target,
                            req.body)) {
    res.status = 403;
    res.set_header("Content-Type", "application/json");
    res.body =
        "{\"error\":{\"type\":\"blocked_by_gateway\","
        "\"message\":\"请求被安全网关拦截\"}}";
    self->IncBlocked();
    return;
  }

  // 密码泄露提醒与同步安全策略分离：只做受限复制入异步队列，绝不等待扫描。
  QueuePasswordLeakAudit(req.body, ProtocolToString(route.protocol), route.model);

  self->IncTotal();

  // ---- 泵线程 + 队列 + 扫描器 ----
  auto ctx = std::make_shared<RelayContext>(detail::kQueueCapacityBytes);
  if (self->ShouldScanResponse()) {
    ctx->scanner = std::unique_ptr<ResponseScanner>(new ResponseScanner());
  }

  auto cli = MakeUpstreamClient(route.target);
  if (!cli->is_valid()) {
    res.status = 502;
    res.set_header("Content-Type", "text/plain");
    res.body = "upstream connect failed";
    self->IncFailed();
    self->SetLastError("invalid upstream: " + route.target.host);
    return;
  }
  ctx->cli = cli;

  Headers upHeaders =
      BuildUpstreamHeaders(HeaderList(req.headers.begin(), req.headers.end()),
                           route.upstream);

  // 注册在途表（Stop 据此解阻塞）；provider 释放器里注销。
  self->RegisterRelay(ctx, cli);

  // 转发目标路径 = baseUrl 路径 + 请求 target（ParseUrl.path 从首个 '/' 起
  // 到结尾，天然包含 query；透传原样字节，配合 set_path_encode(false)）。
  const std::string pathWithQuery = route.target.path;

  std::thread pump([ctx, self, cli, method = req.method, pathWithQuery,
                    upHeaders, body = req.body]() {
    PumpUpstream(ctx, self, cli, method, pathWithQuery, upHeaders, body);
  });
  pump.detach();  // 生命周期由 shared_ptr 保证；收尾同步见 provider 释放器

  // ---- 等上游响应头（有界：受 client 连接 10s / 读 300s 超时约束；
  // Stop() 会 stop 上游 Client 使 send 立即失败并发布头）----
  while (!ctx->headReady.load()) {
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
  }
  if (ctx->upstreamStatus == -1) {
    // 泵失败且无响应头（连接/TLS 失败等）：失败记账已由泵完成。
    self->UnregisterRelay(ctx.get());
    res.status = 502;
    res.set_header("Content-Type", "text/plain");
    res.body = "upstream connect failed";
    return;
  }

  // ---- 构造本地响应 ----
  res.status = ctx->upstreamStatus;
  for (const auto& h : ctx->upstreamHeaders) {
    res.headers.emplace(h.first, h.second);
  }
  // Content-Type 未随头复制（防 set_chunked_content_provider 重复写入），
  // 此处显式传入；缺失时给通用兜底。
  std::string contentType = "application/octet-stream";
  if (ctx->upstreamHeaders.find("Content-Type") != ctx->upstreamHeaders.end()) {
    contentType = ctx->upstreamHeaders.find("Content-Type")->second;
  }

  // chunked provider：从队列排空回传。std::function 要求可拷贝 → ctx 经
  // shared_ptr 值捕获；self 是静态单例，裸指针捕获安全。
  res.set_chunked_content_provider(
      contentType,
      [ctx, self](size_t, httplib::DataSink& sink) -> bool {
        RelayContext* c = ctx.get();
        std::string chunk;
        if (!c->queue.Pop(chunk)) {
          // 队列已关闭且排空：正常收尾（阻断事件已由泵线程入队并写出）。
          if (!c->failedNoted && !c->securityBlocked) NoteRelayed(c, self);
          sink.done();
          return true;
        }
        if (chunk.empty()) return true;
        if (!sink.write(chunk.data(), chunk.size())) {
          // 本地客户端断开：关队列 + stop 上游，让泵线程尽快退出。
          c->queue.CloseAndDrop();
          if (c->cli != nullptr) c->cli->stop();
          return false;  // httplib 以 Canceled 终止；释放器随后收尾
        }
        return true;
      },
      [ctx, self](bool success) {
        // Response 析构时回调：provider 结束（成功/失败/客户端断开/停机）。
        RelayContext* c = ctx.get();
        if (!success && !c->relayed && !c->securityBlocked &&
            !c->failedNoted) {
          NoteFailed(c, self, "relay aborted");
        }
        c->queue.CloseAndDrop();     // 唤醒可能仍在等待的泵线程
        if (c->cli != nullptr) c->cli->stop();  // 保证泵及时退出（幂等）
        self->UnregisterRelay(c);
      });
}

}  // namespace

ProxyServer& ProxyServer::Instance() {
  static ProxyServer inst;
  return inst;
}

ProxyServer::ProxyServer() = default;
ProxyServer::~ProxyServer() { Stop(); }

bool ProxyServer::Start(const std::string& host, uint16_t port) {
  if (running_.load()) return false;

  svr_ = std::unique_ptr<httplib::Server>(new httplib::Server());
  // catch-all：Agent 场景以 POST /v1/messages 为主，其余方法是 models 列表/
  // 健康检查等，同一 handler 全部兼容；HEAD 由 httplib 在写响应阶段去 body。
  auto handler = [this](const Request& req, Response& res) {
    HandleProxyRequest(this, req, res);
  };
  svr_->Get(".*", handler);
  svr_->Post(".*", handler);
  svr_->Put(".*", handler);
  svr_->Patch(".*", handler);
  svr_->Delete(".*", handler);
  svr_->Options(".*", handler);

#if defined(MBEDTLS_PSA_CRYPTO_C)
  // mbedtls 3.6 部分 EC/ECDH 操作经 PSA；握手前初始化（幂等）。失败不致命——
  // legacy 路径仍可用。
  (void)psa_crypto_init();
#endif

  // listen() 阻塞（bind + accept 循环 + 线程池 shutdown 全在调用线程内），
  // 必须放到 worker 线程；Start 用 wait_until_ready 等待 bind 结果。
  worker_ = new std::thread([this, host, port]() {
    const bool ok = svr_->listen(host, static_cast<int>(port));
    if (!ok) running_.store(false);
  });
  svr_->wait_until_ready();

  if (!svr_->is_running()) {
    // bind 失败：worker 即将自行退出，收尾并报错。
    if (worker_ != nullptr) {
      if (worker_->joinable()) worker_->join();
      delete worker_;
      worker_ = nullptr;
    }
    svr_.reset();
    running_.store(false);
    SetLastError("listen failed: " + host + ":" + std::to_string(port));
    return false;
  }
  return true;
}

void ProxyServer::Stop() {
  if (!running_.exchange(false)) return;
  stopFlag_.store(true);

  // 1) 关监听 socket：accept 循环退出（is_shutting_down 置位也会中止
  //    进行中的 chunked 写出）。stop() 本身不 join，立即返回。
  if (svr_) svr_->stop();

  // 2) 解阻塞所有在途转发：丢积压 + 关队列（provider/pump 两端立即收尾），
  //    再对上游 Client 逐个 stop()——进行中的请求会 shutdown socket，
  //    泵的阻塞读/写立即报错返回（有界，绝不等待上游超时）。
  {
    std::lock_guard<std::mutex> lk(relayMutex_);
    for (auto& entry : relays_) {
      entry.first->queue.CloseAndDrop();
      if (entry.second != nullptr) entry.second->stop();
    }
  }

  // 3) join worker：listen 内部的 ThreadPool::shutdown 会 join 全部 handler
  //    （在途转发已在步骤 2 被解阻塞，provider 很快返回）。
  if (worker_ != nullptr) {
    if (worker_->joinable()) worker_->join();
    delete worker_;
    worker_ = nullptr;
  }
  svr_.reset();
}

void ProxyServer::SetUpstream(const UpstreamConfig& u) {
  std::lock_guard<std::mutex> lk(upstream_mutex_);
  upstream_ = u;
}

UpstreamConfig ProxyServer::CurrentUpstream() {
  std::lock_guard<std::mutex> lk(upstream_mutex_);
  return upstream_;
}

bool ProxyServer::ShouldScanResponse() {
  if (!response_security_enabled_.load()) return false;
  auto& pm = aigate::PluginManager::GetInstance();
  // 有启用的内置检测器（响应侧规则：password_leak / malicious_tool_use）
  // 或至少一个响应插件钩子时，才值得挂扫描器
  return pm.IsPluginEnabled(aigate::kBuiltinSecurityPluginId) ||
         !pm.GetEnabledResponseHooks().empty();
}

ProxySnapshot ProxyServer::Snapshot() const {
  ProxySnapshot s;
  s.running = running_.load();
  s.securityEnabled = security_enabled_.load();
  s.responseSecurityEnabled = response_security_enabled_.load();
  std::lock_guard<std::mutex> lk(stats_mutex_);
  s.totalRequests = total_;
  s.successRequests = success_;
  s.blockedRequests = blocked_;
  s.failedRequests = failed_;
  s.lastError = lastError_;
  return s;
}

void ProxyServer::IncTotal() {
  std::lock_guard<std::mutex> lk(stats_mutex_);
  ++total_;
}
void ProxyServer::IncSuccess() {
  std::lock_guard<std::mutex> lk(stats_mutex_);
  ++success_;
}
void ProxyServer::IncBlocked() {
  std::lock_guard<std::mutex> lk(stats_mutex_);
  ++blocked_;
}
void ProxyServer::IncFailed() {
  std::lock_guard<std::mutex> lk(stats_mutex_);
  ++failed_;
}
void ProxyServer::SetLastError(const std::string& msg) {
  std::lock_guard<std::mutex> lk(stats_mutex_);
  lastError_ = msg;
}

void ProxyServer::RegisterRelay(
    const std::shared_ptr<detail::RelayContext>& ctx,
    const std::shared_ptr<Client>& cli) {
  std::lock_guard<std::mutex> lk(relayMutex_);
  relays_.emplace_back(ctx, cli);
}

void ProxyServer::UnregisterRelay(detail::RelayContext* ctx) {
  std::lock_guard<std::mutex> lk(relayMutex_);
  for (auto it = relays_.begin(); it != relays_.end(); ++it) {
    if (it->first.get() == ctx) {
      relays_.erase(it);
      return;
    }
  }
}

}  // namespace hmsec
