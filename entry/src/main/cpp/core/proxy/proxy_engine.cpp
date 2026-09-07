#include "include/proxy_engine.h"

#include "proxy/proxy_server.h"

namespace aigate {

// ProxyEngine 实现：薄外壳，委托给 hmsec::ProxyServer（mongoose 转发核心）。
// 保留这层门面的真实价值：Impl 记住 Start 时的 host/port，回填进 GetStatus
//（ProxyServer 自己不存监听地址，快照里只有计数器与运行标志）。
class ProxyEngine::Impl {
public:
    bool Start(const ProxyConfig& config) {
        config_ = config;
        return hmsec::ProxyServer::Instance().Start(config.host, config.port);
    }

    void Stop() {
        hmsec::ProxyServer::Instance().Stop();
    }

    ProxyStatus GetStatus() const {
        hmsec::ProxySnapshot s = hmsec::ProxyServer::Instance().Snapshot();
        ProxyStatus st{};
        st.isRunning = s.running;
        st.host = config_.host;
        st.port = config_.port;
        st.totalRequests = s.totalRequests;
        st.blockedRequests = s.blockedRequests;
        st.successRequests = s.successRequests;
        st.failedRequests = s.failedRequests;
        st.lastError = s.lastError;
        st.securityEnabled = s.securityEnabled;
        st.responseSecurityEnabled = s.responseSecurityEnabled;
        return st;
    }

    void SetUpstream(const std::string& baseUrl, const std::string& apiKey,
                     const std::string& apiKeyField, const std::string& model) {
        hmsec::UpstreamConfig u;
        u.set = !baseUrl.empty();
        u.baseUrl = baseUrl;
        u.apiKey = apiKey;
        u.apiKeyField = apiKeyField;
        u.model = model;
        hmsec::ProxyServer::Instance().SetUpstream(u);
    }

    void SetResponseSecurityEnabled(bool enabled) {
        hmsec::ProxyServer::Instance().SetResponseSecurityEnabled(enabled);
    }

    void SetSecurityEnabled(bool enabled) {
        hmsec::ProxyServer::Instance().SetSecurityEnabled(enabled);
    }

    ProxyConfig config_;
};

ProxyEngine& ProxyEngine::GetInstance() {
    static ProxyEngine instance;
    return instance;
}

ProxyEngine::ProxyEngine() : impl_(std::make_unique<Impl>()) {}
ProxyEngine::~ProxyEngine() = default;

bool ProxyEngine::Start(const ProxyConfig& config) { return impl_->Start(config); }
void ProxyEngine::Stop() { impl_->Stop(); }
ProxyStatus ProxyEngine::GetStatus() const { return impl_->GetStatus(); }
void ProxyEngine::SetUpstream(const std::string& baseUrl, const std::string& apiKey,
                              const std::string& apiKeyField, const std::string& model) {
    impl_->SetUpstream(baseUrl, apiKey, apiKeyField, model);
}
void ProxyEngine::SetResponseSecurityEnabled(bool enabled) {
    impl_->SetResponseSecurityEnabled(enabled);
}
void ProxyEngine::SetSecurityEnabled(bool enabled) {
    impl_->SetSecurityEnabled(enabled);
}

} // namespace aigate
