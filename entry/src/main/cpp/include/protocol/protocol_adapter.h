// protocol_adapter.h —— 多 LLM 协议识别与请求元数据提取（M3）
//
// 纯逻辑、零依赖（不引 mongoose / JSON 库），宿主侧（MinGW g++）可直接编译单测。
// 识别结果供 Router 做规则匹配（protocol 字段），也供日志诊断使用。
#pragma once

#include <string>

namespace hmsec {

// 上游 LLM API 的协议形态。
enum class LlmProtocol {
  kAnthropic,  // /v1/messages（Claude / 智谱 anthropic 兼容端点等）
  kOpenAI,     // /v1/chat/completions、/v1/responses
  kGemini,     // /v1beta/models/<model>:generateContent | :streamGenerateContent
  kUnknown     // 形态与 body 签名都不命中
};

// 协议枚举 → 路由规则/日志用的字符串（"anthropic"/"openai"/"gemini"/"unknown"）。
const char* ProtocolToString(LlmProtocol proto);

// 按请求形态识别协议：
//   1. 先按 URI 路径特征判定（/v1/messages、/v1/chat/completions|/v1/responses、:generateContent）
//   2. 都不中再嗅探 body 字段签名（anthropic="max_tokens"+"messages"、gemini="contents"、openai="messages"）
//   3. 仍不中返回 kUnknown
// method 目前不参与判定（保留入参：未来可仅对 POST 类方法嗅探 body）。
LlmProtocol DetectProtocol(const std::string& method, const std::string& uri,
                           const std::string& body);

// 从请求中提取的元数据（路由匹配 + 日志用）。
struct RequestMetadata {
  std::string model;  // 模型名（提取不到为空串）
  bool stream = false;
};

// 提取 model / stream。三种协议的 model 字段同名（"model"），统一从 body 提取；
// Gemini 的 model 在 URI 里（/models/<model>:generateContent），body 提取不到时从 URI 兜底。
//
// 为何手写字符串扫描而非 JSON 库：请求体可达数百 KB（长上下文），这里只需要两个顶层字段，
// 完整 JSON 解析既浪费性能又引入依赖；扫描只做 find + 局部读取，复杂度与结果字段位置相关。
RequestMetadata ExtractMetadata(LlmProtocol proto, const std::string& uri,
                                const std::string& body);

}  // namespace hmsec
