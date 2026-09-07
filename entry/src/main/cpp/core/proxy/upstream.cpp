// upstream.cpp —— 上游 URL 纯逻辑实现
#include "proxy/upstream.h"

#include <algorithm>
#include <cctype>

namespace hmsec {

// ToLower 定义已移入 str_util.h（header-only 公共 util），此处不再重复。

std::string Trim(const std::string& s) {
  size_t b = 0;
  size_t e = s.size();
  while (b < e && std::isspace(static_cast<unsigned char>(s[b]))) ++b;
  while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) --e;
  return s.substr(b, e - b);
}

uint16_t DefaultPort(bool tls) {
  return tls ? 443 : 80;
}

ParsedUrl ParseUrl(const std::string& url) {
  ParsedUrl r;
  const std::string u = Trim(url);
  if (u.empty()) return r;

  // scheme://
  size_t pos = u.find("://");
  if (pos == std::string::npos) return r;
  r.scheme = ToLower(u.substr(0, pos));
  if (r.scheme != "http" && r.scheme != "https") return r;
  r.tls = (r.scheme == "https");

  size_t hostStart = pos + 3;
  // authority 一直延续到首个 '/' 或结尾
  size_t pathStart = u.find('/', hostStart);
  std::string authority;
  if (pathStart == std::string::npos) {
    authority = u.substr(hostStart);
    r.path = "/";
  } else {
    authority = u.substr(hostStart, pathStart - hostStart);
    r.path = u.substr(pathStart);
  }
  if (authority.empty()) return r;

  // 处理 userinfo@host:port（仅取 host:port，忽略 userinfo）
  size_t at = authority.find('@');
  if (at != std::string::npos) authority = authority.substr(at + 1);

  // host:port
  // IPv6 形如 [::1]:8080 —— 简化处理：若以 '[' 开头，则到 ']'
  if (!authority.empty() && authority[0] == '[') {
    size_t rb = authority.find(']');
    if (rb == std::string::npos) return r;
    r.host = authority.substr(1, rb - 1);
    if (rb + 1 < authority.size() && authority[rb + 1] == ':') {
      r.port = static_cast<uint16_t>(std::atoi(authority.c_str() + rb + 2));
    }
  } else {
    size_t colon = authority.find(':');
    if (colon == std::string::npos) {
      r.host = authority;
    } else {
      r.host = authority.substr(0, colon);
      r.port = static_cast<uint16_t>(std::atoi(authority.c_str() + colon + 1));
    }
  }
  if (r.host.empty()) return r;
  r.valid = true;
  return r;
}

std::string JoinUrl(const std::string& baseUrl, const std::string& requestPath) {
  const std::string path = Trim(requestPath);
  if (path.empty()) return baseUrl;
  // 规范化：base 去掉末尾 '/'，path 保证以 '/' 开头
  std::string base = baseUrl;
  while (base.size() > 1 && base.back() == '/') base.pop_back();
  std::string p = path;
  if (p.empty() || p[0] != '/') p = "/" + p;
  return base + p;
}

ParsedUrl ResolveTarget(const std::string& baseUrl, const std::string& requestPath) {
  return ParseUrl(JoinUrl(baseUrl, requestPath));
}

bool IsMessagesPath(const std::string& path) {
  std::string p = ToLower(Trim(path));
  if (p.empty()) return false;
  // 去掉 query
  size_t q = p.find('?');
  if (q != std::string::npos) p = p.substr(0, q);
  if (p.back() == '/') p.pop_back();
  return p == "/v1/messages";
}

bool IsAuthHeaderName(const std::string& name) {
  std::string n = ToLower(Trim(name));
  return n == "authorization" || n == "x-api-key" ||
         n == "x-goog-api-key" || n == "proxy-authorization";
}

std::string BuildAuthHeader(const std::string& apiKeyField, const std::string& apiKey) {
  std::string key = Trim(apiKey);
  if (key.empty()) return std::string();  // 未配置 Key：不注入
  std::string field = ToLower(Trim(apiKeyField));
  if (field == "anthropic_api_key") {
    return "x-api-key: " + key + "\r\n";
  }
  if (field == "anthropic_auth_token") {
    return "Authorization: Bearer " + key + "\r\n";
  }
  if (field == "gemini_api_key") {
    return "x-goog-api-key: " + key + "\r\n";
  }
  return std::string();  // 未知字段：不注入
}

}  // namespace hmsec
