#ifndef AIGATE_PROXY_ENGINE_H
#define AIGATE_PROXY_ENGINE_H

#include <string>
#include <memory>
#include <unordered_map>

namespace aigate {

// HTTP请求方法枚举
enum class HttpMethod {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
    CONNECT
};

// HTTP请求结构（SecurityDetector 的检测入参在用）
struct HttpRequest {
    HttpMethod method;
    std::string url;
    std::unordered_map<std::string, std::string> headers;
    std::string body;
};

// HTTP响应结构（SecurityDetector 的检测入参在用）
struct HttpResponse {
    int statusCode;
    std::string statusMessage;
    std::unordered_map<std::string, std::string> headers;
    std::string body;
};

// 代理状态
struct ProxyStatus {
    bool isRunning;
    std::string host;
    uint16_t port;
    uint32_t totalRequests;
    uint32_t blockedRequests;
    uint32_t successRequests;
    uint32_t failedRequests;
    std::string lastError;
    bool securityEnabled = true;          // 请求侧安全检测开关状态
    bool responseSecurityEnabled = true;  // M4：响应侧安全检测开关状态
};

// 代理配置（上游代理字段已随 R1 删除：从未接线，零调用方）
struct ProxyConfig {
    std::string host = "127.0.0.1";
    uint16_t port = 8080;
};

// HTTP代理引擎
class ProxyEngine {
public:
    // 获取单例实例
    static ProxyEngine& GetInstance();

    // 启动代理服务器
    bool Start(const ProxyConfig& config);

    // 停止代理服务器
    void Stop();

    // 获取代理状态
    ProxyStatus GetStatus() const;

    // 设置上游大模型厂商（base URL / api key / 字段名 / 默认模型）
    void SetUpstream(const std::string& baseUrl, const std::string& apiKey,
                     const std::string& apiKeyField, const std::string& model);

    // M4：响应侧安全检测开关（默认开启）
    void SetResponseSecurityEnabled(bool enabled);

    // 请求侧安全检测开关（NAPI 线程写，转发工作线程原子读取）
    void SetSecurityEnabled(bool enabled);

private:
    ProxyEngine();
    ~ProxyEngine();

    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace aigate

#endif // AIGATE_PROXY_ENGINE_H
