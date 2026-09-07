// Copyright (c) 2026 鸿蒙安全网关
// upstream.h —— 上游 URL / 转发目标的纯函数（无网络依赖，便于单元测试）
//
// 代理收到 Claude Code 的请求后，需要把「请求路径」拼到「上游 BaseURL」上，
// 并解析出 host/port/TLS 以便代理核心建立到上游的连接。本模块封装这些纯逻辑。
#pragma once

#include <cstdint>
#include <string>

#include "str_util.h"  // hmsec::ToLower（R2 起收敛为公共 header-only util）

namespace hmsec {

// 解析后的绝对 URL。
struct ParsedUrl {
  bool valid = false;     // 是否解析成功
  bool tls = false;       // https => true
  std::string scheme;     // "http" / "https"
  std::string host;       // 不含端口，例如 "api.example.com"
  uint16_t port = 0;      // 显式端口；未指定时为 0（调用方用 DefaultPort 补全）
  std::string path;       // 以 '/' 开头；根路径为 "/"
};

// 解析绝对 URL，例如 "https://open.bigmodel.cn:8443/api/anthropic"。
ParsedUrl ParseUrl(const std::string& url);

// 按协议返回默认端口（https=443, http=80）。
uint16_t DefaultPort(bool tls);

// 将「上游 BaseURL」与「请求路径」拼接为完整转发 URL。
// 例：JoinUrl("https://open.bigmodel.cn/api/anthropic", "/v1/messages")
//   => "https://open.bigmodel.cn/api/anthropic/v1/messages"
// 规则：requestPath 为空时返回 base；保证 base 与 path 之间恰好一个 '/'。
std::string JoinUrl(const std::string& baseUrl, const std::string& requestPath);

// 计算 Claude Code 请求应转发到的目标（解析 JoinUrl 的结果）。
ParsedUrl ResolveTarget(const std::string& baseUrl, const std::string& requestPath);

// ToLower 已移到 str_util.h（R2：与 security_detector 的小写化合并为公共 util）。

// 去除首尾空白。
std::string Trim(const std::string& s);

// 判断路径是否为 Anthropic Messages 端点（/v1/messages）。
bool IsMessagesPath(const std::string& path);

// 判断请求头名称是否为「鉴权头」——转发时需剔除客户端自带的此类头，
// 改用网关配置的上游 Key 注入。大小写不敏感：
//   authorization / x-api-key / x-goog-api-key / proxy-authorization
bool IsAuthHeaderName(const std::string& name);

// 依据 apiKeyField 构造注入到上游请求的鉴权头行（含末尾 CRLF）；
// 无 Key 或未知字段时返回空串。
//   ANTHROPIC_API_KEY    => "x-api-key: <apiKey>\r\n"
//   ANTHROPIC_AUTH_TOKEN => "Authorization: Bearer <apiKey>\r\n"
//   GEMINI_API_KEY       => "x-goog-api-key: <apiKey>\r\n"
std::string BuildAuthHeader(const std::string& apiKeyField, const std::string& apiKey);

}  // namespace hmsec
