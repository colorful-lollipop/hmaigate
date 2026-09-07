// proxy_server.cpp —— mongoose 转发代理实现
#include "proxy/proxy_server.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>

#include "mongoose/mongoose.h"
#include "json_scan.h"                    // hmsec::JsonEscape（R2：SSE 错误事件的 JSON 转义）
#include "plugin_manager.h"              // aigate::PluginManager（M4：响应侧钩子探测）
#include "proxy/request_pipeline.h"  // 转发管线：ResolveRoute / SecurityCheckRequest / BuildRequest
#include "proxy/upstream.h"
#include "security/response_scanner.h"   // M4：上游响应流式安全扫描
#include <psa/crypto.h>  // psa_crypto_init（mbedtls 3.6 默认编入 PSA crypto）
#include <hilog/log.h>   // OH_LOG_Print：C++ 事件直打 hilog（诊断转发链路）
#define PROXY_LOG(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "ProxyEv", __VA_ARGS__)

namespace hmsec {

namespace {

inline std::string S(const mg_str& s) {
  return std::string(s.buf, s.len);
}

// 一对连接的上下文：把「本地客户端连接」与「到上游的连接」配对。
struct ConnCtx {
  ProxyServer* self = nullptr;
  mg_connection* server = nullptr;  // 面向 Claude Code 的本地连接
  mg_connection* client = nullptr;  // 连到上游大模型厂商的连接
  std::string reqRaw;               // 待发送给上游的完整请求字节
  bool upstreamTls = false;         // 实际转发目标是否 https（M3：路由命中时≠默认上游）
  std::string upstreamHost;         // 实际转发目标主机名（TLS SNI 用）
  bool relayed = false;             // 是否已回传过响应字节（用于 success 计数）
  bool securityBlocked = false;
  bool hadError = false;            // 是否已收到 MG_EV_ERROR（避免覆盖具体错误信息）
  // M4：响应安全扫描器；为空 = 本连接零拷贝直通（响应检测关闭或无启用的响应侧检测能力）
  std::unique_ptr<ResponseScanner> scanner;
};

// 首次向本地客户端回传响应字节时记一次成功（relayed 保证每条连接只计一次；
// R2：消去 ClientEv 里三处近重复的 relayed+IncSuccess 块，并统一 self 判空）。
void NoteRelayed(ConnCtx* ctx) {
  if (ctx->relayed) return;
  ctx->relayed = true;
  if (ctx->self != nullptr) ctx->self->IncSuccess();
}

// 响应检测命中阻断：给本地连接发一个 SSE 错误事件后按 is_draining 语义优雅关闭。
// 选 SSE 事件形态的理由：Agent 工具（Claude Code 等）的客户端是 SSE 解析器，
// 流内 `data: {"error":...}` 能被按协议解析为错误并展示；直接截断只会让客户端
// 报 2300018 partial file。对非 SSE 响应它也是一段可读尾部文本，优于静默断流。
void BlockResponse(ConnCtx* ctx, mg_connection* upstream, const std::string& reason) {
  ctx->securityBlocked = true;
  if (ctx->self != nullptr) {
    ctx->self->IncBlocked();
    ctx->self->SetLastError("response blocked: " + reason);
  }
  PROXY_LOG("response blocked: %{public}s", reason.c_str());
  if (ctx->server != nullptr) {
    std::string evt = "data: {\"error\":{\"type\":\"security_block\",\"message\":\"" +
                      hmsec::JsonEscape(reason) + "\"}}\n\n";
    mg_send(ctx->server, evt.data(), evt.size());
    // is_draining：先冲完已缓冲字节 + 错误事件再关，避免尾部丢失
    ctx->server->is_draining = true;
  }
  upstream->is_draining = true;  // 上游连接不再继续读
}

void ServerEv(mg_connection* c, int ev, void* ev_data);
void ClientEv(mg_connection* c, int ev, void* ev_data);

void ServerEv(mg_connection* c, int ev, void* ev_data) {
  if (ev == MG_EV_ACCEPT) {
    // 新的本地入站连接：建立配对上下文（此时 c->fn_data 是 ProxyServer*）
    ConnCtx* ctx = new ConnCtx();
    ctx->self = static_cast<ProxyServer*>(c->fn_data);
    ctx->server = c;
    c->fn_data = ctx;
    return;
  }

  // 监听连接自身（is_listening）只负责产生 ACCEPT；其 fn_data 为 ProxyServer*，
  // 不可当作 ConnCtx* 解引用（否则在其 OPEN/CLOSE，以及 mg_mgr_free 关闭时崩溃）。
  if (c->is_listening) return;

  if (ev == MG_EV_HTTP_MSG) {
    ConnCtx* ctx = static_cast<ConnCtx*>(c->fn_data);  // ACCEPT 之后必为 ConnCtx*
    if (ctx == nullptr || ctx->self == nullptr) return;
    mg_http_message* hm = static_cast<mg_http_message*>(ev_data);
    ProxyServer* self = ctx->self;

    // 管线步骤 1：路由解析（CurrentUpstream 在互斥锁下读取，保持既有锁语义；
    // M3 起内部做协议识别 + 规则路由，未命中回退默认上游）
    RouteResult route = ResolveRoute(self->CurrentUpstream(), S(hm->method), S(hm->uri),
                                     S(hm->body));
    if (!route.ok) {
      if (route.error == RouteError::kNoUpstream) {
        mg_http_reply(c, 502, "Content-Type: text/plain\r\n",
                      "no upstream configured");
        self->IncFailed();
        self->SetLastError("no upstream");
      } else {
        mg_http_reply(c, 502, "Content-Type: text/plain\r\n", "bad upstream url");
        self->IncFailed();
        self->SetLastError("bad upstream url");
      }
      return;
    }
    // 命中规则路由：记录规则 id/协议/model 便于排障（绝不打 apiKey）
    if (!route.ruleId.empty()) {
      PROXY_LOG("route hit: rule=%{public}s proto=%{public}s model=%{public}s",
                route.ruleId.c_str(), ProtocolToString(route.protocol),
                route.model.c_str());
    }
    // 记录实际转发目标的 TLS/主机名，供 ClientEv 握手用（路由命中时与默认上游不同）
    ctx->upstreamTls = route.target.tls;
    ctx->upstreamHost = route.target.host;

    // 管线步骤 2：安全检测（只对请求体执行；不检测鉴权头，避免误伤合法 Bearer）
    if (!SecurityCheckRequest(self->IsSecurityEnabled(), S(hm->method), S(hm->uri),
                              S(hm->body))) {
      mg_http_reply(c, 403, "Content-Type: application/json\r\n",
                    "{\"error\":{\"type\":\"blocked_by_gateway\","
                    "\"message\":\"请求被安全网关拦截\"}}");
      ctx->securityBlocked = true;
      self->IncBlocked();
      return;
    }

    // 密码泄露提醒与同步安全策略分离：这里只做受限复制入异步队列，绝不等待扫描
    // 也不改变当前请求结果。请求头从未传入，避免正常鉴权头被误报。
    QueuePasswordLeakAudit(S(hm->body), ProtocolToString(route.protocol), route.model);

    self->IncTotal();

    // 管线步骤 3：构造转发请求。把 mongoose 消息剥离成纯字符串头列表（HeaderList），
    // mongoose 类型不进管线模块（管线需宿主侧可编译、可单测）。
    HeaderList headers;
    for (int i = 0; i < MG_MAX_HTTP_HEADERS; i++) {
      const mg_str& name = hm->headers[i].name;
      if (name.len == 0) break;
      headers.emplace_back(S(name), S(hm->headers[i].value));
    }
    ctx->reqRaw = BuildRequest(S(hm->method), headers, S(hm->body), route.target,
                               route.upstream);

    // 建立到上游的连接（mg_connect 已把 fn_data=ctx 传入）
    std::string addr = route.target.host;
    addr += ':';
    addr += std::to_string(route.target.port != 0 ? route.target.port
                                                  : DefaultPort(route.target.tls));
    mg_connection* client = mg_connect(c->mgr, addr.c_str(), ClientEv, ctx);
    if (client == nullptr) {
      mg_http_reply(c, 502, "Content-Type: text/plain\r\n", "upstream connect failed");
      self->IncFailed();
      self->SetLastError("connect failed: " + addr);
      return;
    }
    ctx->client = client;

    // M4：响应检测开启且有启用的响应侧检测能力时，为本连接挂流式扫描器；
    // 否则 scanner 保持空，MG_EV_READ 走原有零拷贝直通路径。
    if (self->ShouldScanResponse()) {
      ctx->scanner = std::unique_ptr<ResponseScanner>(new ResponseScanner());
    }
    return;
  }

  if (ev == MG_EV_CLOSE) {
    // 幂等清理：先把两侧 fn_data 都置空再 delete，避免对端 CLOSE 时拿到悬垂指针
    ConnCtx* ctx = static_cast<ConnCtx*>(c->fn_data);
    if (ctx == nullptr) return;
    c->fn_data = nullptr;
    mg_connection* peer = ctx->client;
    if (peer != nullptr) peer->fn_data = nullptr;
    ctx->server = nullptr;
    ctx->client = nullptr;
    delete ctx;
    if (peer != nullptr) peer->is_draining = true;  // 先 flush 对端发送缓冲再关（否则末尾字节丢失→partial file）
  }
}

void ClientEv(mg_connection* c, int ev, void* ev_data) {
  // 出站连接自创建（mg_connect）起 fn_data 即为 ConnCtx*
  ConnCtx* ctx = static_cast<ConnCtx*>(c->fn_data);
  if (ctx == nullptr) return;

  if (ev == MG_EV_ERROR) {
    // mongoose 给出的具体错误（DNS/连接/TLS 握手/证书解析等）。保留首个（根因），
    // 后续更外层的笼统错误不覆盖。
    const char* msg = ev_data ? static_cast<const char*>(ev_data) : "(unknown)";
    PROXY_LOG("upstream error: %{public}s", msg);
    if (!ctx->hadError && ctx->self != nullptr) {
      ctx->self->SetLastError(std::string("mg error: ") + msg);
    }
    ctx->hadError = true;
    return;
  }

  if (ev == MG_EV_CONNECT) {
    // 上游连接已建立：按实际转发目标（可能是路由规则上游）按需启用 TLS，然后发送转发请求
    if (ctx->upstreamTls) {
      mg_tls_opts opts{};
      opts.name = mg_str(ctx->upstreamHost.c_str());
      opts.skip_verification = true; // 无系统 CA，跳过校验；mbedtls 仍会完整解析证书
      mg_tls_init(c, &opts);
    }
    mg_send(c, ctx->reqRaw.c_str(), ctx->reqRaw.size());
    return;
  }

  if (ev == MG_EV_READ) {
    // 本构建 mongoose 走 socket：数据在 c->recv（.buf/.len），ev_data 为 &n（字节数）。
    if (c->recv.len > 0 && !ctx->securityBlocked) {
      if (ctx->scanner != nullptr) {
        // M4 响应扫描路径：只转发被扫描器确认放行的字节（SSE 按事件边界放行，
        // 非 SSE 聚合到 Flush/超上限 fail-open），不完整尾部留在扫描器缓冲区。
        ScanOutcome out = ctx->scanner->Feed(reinterpret_cast<const char*>(c->recv.buf),
                                             c->recv.len);
        if (out.overflow) {
          PROXY_LOG("response scanner overflow (>256KB), fail-open passthrough");
        }
        if (!out.release.empty() && ctx->server != nullptr) {
          mg_send(ctx->server, out.release.data(), out.release.size());
          NoteRelayed(ctx);
        }
        if (out.blocked) {
          BlockResponse(ctx, c, out.reason);
        }
      } else if (ctx->server != nullptr) {
        // 零拷贝直通（原路径）：上游响应字节（含流式 SSE 分片）原样回传本地客户端
        mg_send(ctx->server, c->recv.buf, c->recv.len);
        NoteRelayed(ctx);
      }
    }
    mg_iobuf_del(&c->recv, 0, c->recv.len);  // 消费已读字节，否则下次会重复回传
    return;
  }

  if (ev == MG_EV_CLOSE) {
    // M4：扫描器里可能还压着未放行的尾部（非 SSE 聚合 body / SSE 不完整事件），
    // 关闭前 Flush 整体扫描放行——否则客户端会丢尾部报 2300018 partial file。
    if (ctx->scanner != nullptr && !ctx->securityBlocked) {
      ScanOutcome out = ctx->scanner->Flush();
      if (!out.release.empty() && ctx->server != nullptr) {
        mg_send(ctx->server, out.release.data(), out.release.size());
        NoteRelayed(ctx);
      }
      if (out.blocked) {
        BlockResponse(ctx, c, out.reason);
      }
    }
    // 上游未回传任何字节就关闭 → 计失败；若已有 MG_EV_ERROR 的具体信息则不覆盖
    if (!ctx->relayed && !ctx->securityBlocked) {
      if (!ctx->hadError && ctx->self != nullptr) {
        ctx->self->SetLastError("上游连接关闭/未返回响应");
      }
      if (ctx->self != nullptr) ctx->self->IncFailed();
    }
    // 幂等清理（与 ServerEv 对称）
    c->fn_data = nullptr;
    mg_connection* peer = ctx->server;
    if (peer != nullptr) peer->fn_data = nullptr;
    ctx->server = nullptr;
    ctx->client = nullptr;
    delete ctx;
    if (peer != nullptr) peer->is_draining = true;  // 先 flush 对端发送缓冲再关
  }
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

#if defined(MBEDTLS_PSA_CRYPTO_C)
  // mbedtls 3.6 默认编入 PSA crypto；部分 EC/ECDH 操作经 PSA，握手前需初始化（幂等）。
  // 即使某次失败也不致命——legacy 路径仍可用。
  (void) psa_crypto_init();
#endif

  mgr_ = std::unique_ptr<mg_mgr>(new mg_mgr());
  mg_mgr_init(mgr_.get());

  std::string url = "http://" + host + ":" + std::to_string(port);
  listener_ = mg_http_listen(mgr_.get(), url.c_str(), ServerEv, this);
  if (listener_ == nullptr) {
    mg_mgr_free(mgr_.get());
    mgr_.reset();
    SetLastError("listen failed: " + url);
    return false;
  }

  stopFlag_.store(false);
  running_.store(true);
  worker_ = new std::thread([this]() { this->Loop(); });
  return true;
}

void ProxyServer::Stop() {
  if (!running_.exchange(false)) return;
  stopFlag_.store(true);
  if (worker_ != nullptr) {
    if (worker_->joinable()) worker_->join();
    delete worker_;
    worker_ = nullptr;
  }
  if (mgr_) {
    mg_mgr_free(mgr_.get());
    mgr_.reset();
  }
  listener_ = nullptr;
}

void ProxyServer::Loop() {
  while (!stopFlag_.load()) {
    mg_mgr_poll(mgr_.get(), 200);  // 200ms 超时，保证及时响应停止信号
  }
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

}  // namespace hmsec
