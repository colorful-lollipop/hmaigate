// protocol_adapter.cpp —— 多 LLM 协议识别与请求元数据提取实现（M3）
#include "protocol/protocol_adapter.h"

#include <cctype>

namespace hmsec {

namespace {

// 在 body 中提取 "key" 字段的字符串值（手写最小扫描，理由见头文件注释）。
// 注意是启发式：find 命中的可能是嵌套对象/字符串值里的同名片段——
// 对本场景（顶层 model/stream 字段）足够，误判代价仅是路由 metadata 偏差。
bool FindJsonStringField(const std::string& body, const char* key, std::string& out) {
  const std::string pat = std::string("\"") + key + "\"";
  size_t pos = body.find(pat);
  if (pos == std::string::npos) return false;
  size_t colon = body.find(':', pos + pat.size());
  if (colon == std::string::npos) return false;
  size_t i = colon + 1;
  while (i < body.size() &&
         std::isspace(static_cast<unsigned char>(body[i]))) {
    ++i;
  }
  if (i >= body.size() || body[i] != '"') return false;  // 字段存在但不是字符串
  ++i;
  std::string v;
  while (i < body.size()) {
    char c = body[i];
    if (c == '\\' && i + 1 < body.size()) {  // 转义：如实保留被转义字符
      v += body[i + 1];
      i += 2;
      continue;
    }
    if (c == '"') {
      out = v;
      return true;
    }
    v += c;
    ++i;
  }
  return false;  // 未闭合
}

// 在 body 中提取 "key" 字段的布尔值。带引号的精确 key 匹配，
// 因此 openai 的 "stream_options" 不会被误认作 "stream"。
bool FindJsonBoolField(const std::string& body, const char* key, bool& out) {
  const std::string pat = std::string("\"") + key + "\"";
  size_t pos = body.find(pat);
  if (pos == std::string::npos) return false;
  size_t colon = body.find(':', pos + pat.size());
  if (colon == std::string::npos) return false;
  size_t i = colon + 1;
  while (i < body.size() &&
         std::isspace(static_cast<unsigned char>(body[i]))) {
    ++i;
  }
  if (body.compare(i, 4, "true") == 0) {
    out = true;
    return true;
  }
  if (body.compare(i, 5, "false") == 0) {
    out = false;
    return true;
  }
  return false;
}

// 从 Gemini URI 提取模型名：
//   /v1beta/models/gemini-2.5-pro:generateContent → gemini-2.5-pro
std::string ModelFromGeminiUri(const std::string& uri) {
  const std::string marker = "/models/";
  size_t b = uri.find(marker);
  if (b == std::string::npos) return std::string();
  b += marker.size();
  size_t e = uri.find_first_of(":?", b);  // 到 ':generateContent' 或 query 为止
  if (e == std::string::npos) e = uri.size();
  return uri.substr(b, e - b);
}

}  // namespace

const char* ProtocolToString(LlmProtocol proto) {
  switch (proto) {
    case LlmProtocol::kAnthropic: return "anthropic";
    case LlmProtocol::kOpenAI: return "openai";
    case LlmProtocol::kGemini: return "gemini";
    default: return "unknown";
  }
}

LlmProtocol DetectProtocol(const std::string& method, const std::string& uri,
                           const std::string& body) {
  (void)method;  // 暂不参与判定（保留入参：未来可仅对 POST 类方法嗅探 body）

  // 1. URI 路径特征（先剥掉 query）
  std::string path = uri;
  size_t q = path.find('?');
  if (q != std::string::npos) path = path.substr(0, q);

  if (path.find("/v1/messages") != std::string::npos) return LlmProtocol::kAnthropic;
  if (path.find("/v1/chat/completions") != std::string::npos ||
      path.find("/v1/responses") != std::string::npos) {
    return LlmProtocol::kOpenAI;
  }
  if (path.find(":generateContent") != std::string::npos ||
      path.find(":streamGenerateContent") != std::string::npos) {
    return LlmProtocol::kGemini;
  }

  // 2. body 字段签名兜底（自定义/反代路径时靠它）。判定顺序即协议特异度：
  //    anthropic 的 max_tokens+messages 组合最强；gemini 的 contents 独有；
  //    只有 messages 时按 openai（anthropic 请求必有 max_tokens）。
  if (!body.empty()) {
    const bool hasMessages = body.find("\"messages\"") != std::string::npos;
    const bool hasMaxTokens = body.find("\"max_tokens\"") != std::string::npos;
    const bool hasContents = body.find("\"contents\"") != std::string::npos;
    if (hasMessages && hasMaxTokens) return LlmProtocol::kAnthropic;
    if (hasContents) return LlmProtocol::kGemini;
    if (hasMessages) return LlmProtocol::kOpenAI;
  }
  return LlmProtocol::kUnknown;
}

RequestMetadata ExtractMetadata(LlmProtocol proto, const std::string& uri,
                                const std::string& body) {
  RequestMetadata meta;
  FindJsonStringField(body, "model", meta.model);
  bool stream = false;
  if (FindJsonBoolField(body, "stream", stream)) meta.stream = stream;

  // Gemini 的 model 在 URI 路径里，body 没有 "model" 字段——URI 兜底
  if (meta.model.empty() && proto == LlmProtocol::kGemini) {
    meta.model = ModelFromGeminiUri(uri);
  }
  return meta;
}

}  // namespace hmsec
