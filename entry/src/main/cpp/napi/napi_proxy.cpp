#include "napi/native_api.h"
#include "include/proxy_engine.h"
#include "include/security_detector.h"
#include "include/plugin_manager.h"
#include "security/password_leak_audit.h"
#include "proxy/router.h"  // hmsec::Router（M3：setRouteRules）
#include "json_scan.h"     // hmsec::JsonEscape（R2：JSON 字符串转义的公共实现）
#include <memory>
#include <cstring>
#include <cstdio>
#include <vector>

using namespace aigate;

// 从 napi 对象读取字符串属性（缺失返回空串）
static std::string GetStringProp(napi_env env, napi_value obj, const char* name) {
    napi_value v;
    napi_valuetype vt = napi_undefined;
    if (napi_get_named_property(env, obj, name, &v) == napi_ok) {
        napi_typeof(env, v, &vt);
    }
    if (vt != napi_string) return std::string();
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    std::string out(len, '\0');
    napi_get_value_string_utf8(env, v, &out[0], len + 1, &len);
    return out;
}

// 读一个字符串入参（两段式：先取长度再分配），返回空串表示缺失/非字符串。
// R2 起所有字符串入参统一走这里，不再用定长 char 缓冲（避免截断与两段式散落）。
static std::string GetStringArg(napi_env env, napi_value arg) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, arg, nullptr, 0, &len) != napi_ok) return std::string();
    std::string out(len, '\0');
    napi_get_value_string_utf8(env, arg, &out[0], len + 1, &len);
    return out;
}

// ========== Proxy Engine NAPI绑定 ==========

static napi_value StartProxy(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 解析配置参数
    ProxyConfig config;

    if (argc > 0) {
        // host：空串（缺失/空）保持默认 127.0.0.1
        std::string host = GetStringProp(env, args[0], "host");
        if (!host.empty()) {
            config.host = host;
        }

        // port
        napi_value portValue;
        napi_get_named_property(env, args[0], "port", &portValue);
        int32_t port;
        napi_get_value_int32(env, portValue, &port);
        config.port = static_cast<uint16_t>(port);
    }

    // 启动代理
    auto& engine = ProxyEngine::GetInstance();
    bool result = engine.Start(config);

    napi_value returnResult;
    napi_get_boolean(env, result, &returnResult);
    return returnResult;
}

static napi_value StopProxy(napi_env env, napi_callback_info info) {
    auto& engine = ProxyEngine::GetInstance();
    engine.Stop();

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value GetProxyStatus(napi_env env, napi_callback_info info) {
    auto& engine = ProxyEngine::GetInstance();
    ProxyStatus status = engine.GetStatus();

    // 创建返回对象
    napi_value result;
    napi_create_object(env, &result);

    // 设置isRunning
    napi_value isRunningValue;
    napi_get_boolean(env, status.isRunning, &isRunningValue);
    napi_set_named_property(env, result, "isRunning", isRunningValue);

    // 设置host
    napi_value hostValue;
    napi_create_string_utf8(env, status.host.c_str(), status.host.length(), &hostValue);
    napi_set_named_property(env, result, "host", hostValue);

    // 设置port
    napi_value portValue;
    napi_create_uint32(env, status.port, &portValue);
    napi_set_named_property(env, result, "port", portValue);

    // 设置totalRequests
    napi_value totalRequestsValue;
    napi_create_uint32(env, status.totalRequests, &totalRequestsValue);
    napi_set_named_property(env, result, "totalRequests", totalRequestsValue);

    // 设置blockedRequests
    napi_value blockedRequestsValue;
    napi_create_uint32(env, status.blockedRequests, &blockedRequestsValue);
    napi_set_named_property(env, result, "blockedRequests", blockedRequestsValue);

    // successRequests / failedRequests / lastError（便于诊断上游/TLS 问题）
    napi_value successRequestsValue;
    napi_create_uint32(env, status.successRequests, &successRequestsValue);
    napi_set_named_property(env, result, "successRequests", successRequestsValue);

    napi_value failedRequestsValue;
    napi_create_uint32(env, status.failedRequests, &failedRequestsValue);
    napi_set_named_property(env, result, "failedRequests", failedRequestsValue);

    napi_value lastErrorValue;
    napi_create_string_utf8(env, status.lastError.c_str(), status.lastError.length(), &lastErrorValue);
    napi_set_named_property(env, result, "lastError", lastErrorValue);

    napi_value securityValue;
    napi_get_boolean(env, status.securityEnabled, &securityValue);
    napi_set_named_property(env, result, "securityEnabled", securityValue);

    // M4：响应侧安全检测开关状态
    napi_value respSecValue;
    napi_get_boolean(env, status.responseSecurityEnabled, &respSecValue);
    napi_set_named_property(env, result, "responseSecurityEnabled", respSecValue);

    return result;
}

static napi_value SetUpstream(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string baseUrl, apiKey, apiKeyField, model;
    if (argc > 0) {
        baseUrl = GetStringProp(env, args[0], "baseUrl");
        apiKey = GetStringProp(env, args[0], "apiKey");
        apiKeyField = GetStringProp(env, args[0], "apiKeyField");
        model = GetStringProp(env, args[0], "model");
    }

    auto& engine = ProxyEngine::GetInstance();
    engine.SetUpstream(baseUrl, apiKey, apiKeyField, model);

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ========== Security Detector NAPI绑定 ==========

// getSecurityRules()：规则列表 JSON 字符串（M4 起由 string[] 改为 JSON，
// 元素形态见 Types.d.ts 的 NativeSecurityRule：
// id/name/enabled/hitCount/customKeywords/customPatterns）。
static napi_value GetSecurityRules(napi_env env, napi_callback_info info) {
    auto& detector = SecurityDetector::GetInstance();
    std::vector<RuleInfo> rules = detector.GetRuleInfos();

    std::string json = "[";
    for (size_t i = 0; i < rules.size(); ++i) {
        const RuleInfo& r = rules[i];
        if (i > 0) json += ',';
        json += "{\"id\":\"" + hmsec::JsonEscape(r.id) + "\"";
        json += ",\"name\":\"" + hmsec::JsonEscape(r.name) + "\"";
        json += ",\"enabled\":";
        json += r.enabled ? "true" : "false";
        json += ",\"hitCount\":" + std::to_string(r.hitCount);
        json += ",\"customKeywords\":[";
        for (size_t j = 0; j < r.customKeywords.size(); ++j) {
            if (j > 0) json += ',';
            json += "\"" + hmsec::JsonEscape(r.customKeywords[j]) + "\"";
        }
        json += "],\"customPatterns\":[";
        for (size_t j = 0; j < r.customPatterns.size(); ++j) {
            if (j > 0) json += ',';
            json += "\"" + hmsec::JsonEscape(r.customPatterns[j]) + "\"";
        }
        json += "]}";
    }
    json += "]";

    napi_value result;
    napi_create_string_utf8(env, json.c_str(), json.length(), &result);
    return result;
}

// updateRuleConfig(ruleId, configJson)：增删规则的用户自定义词条（M4）。
// configJson 形态 {"addKeywords":[],"addPatterns":[],"removeKeywords":[],"removePatterns":[]}
//（四键均可选）；未知 ruleId 或非法 JSON 返回 false。解析在 SecurityDetector 内
//（手写最小 JSON 扫描，与 M3 router 共用 json_scan.h），宿主单测可直接覆盖。
static napi_value UpdateRuleConfig(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    bool ok = false;
    if (argc >= 2) {
        std::string ruleId = GetStringArg(env, args[0]);
        std::string configJson = GetStringArg(env, args[1]);
        ok = SecurityDetector::GetInstance().UpdateRuleConfigFromJson(ruleId, configJson);
    }

    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

// setResponseSecurityEnabled(enabled)：M4 响应侧安全检测开关
static napi_value SetResponseSecurityEnabled(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    bool enabled = true;
    if (argc > 0) {
        napi_get_value_bool(env, args[0], &enabled);
    }
    ProxyEngine::GetInstance().SetResponseSecurityEnabled(enabled);

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// setSecurityEnabled(enabled)：请求侧安全检测开关（可在运行中热更新）
static napi_value SetSecurityEnabled(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    bool enabled = true;
    if (argc > 0) {
        napi_get_value_bool(env, args[0], &enabled);
    }
    ProxyEngine::GetInstance().SetSecurityEnabled(enabled);

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value SetRuleEnabled(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_value undefined;
        napi_get_undefined(env, &undefined);
        return undefined;
    }

    std::string ruleId = GetStringArg(env, args[0]);

    bool enabled;
    napi_get_value_bool(env, args[1], &enabled);

    auto& detector = SecurityDetector::GetInstance();
    detector.EnableRule(ruleId, enabled);

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ========== Plugin Manager NAPI绑定（M2：动态库插件） ==========

static const char* PluginTypeStr(AigatePluginType t) {
    switch (t) {
        case AIGATE_PLUGIN_SECURITY: return "security";
        case AIGATE_PLUGIN_TRANSFORM: return "transform";
        default: return "other";
    }
}

// loadPlugins(dir)：扫描目录加载全部动态库插件，返回成功加载数。
// 同步完成后立即 resolve——返回 Promise 是为了让 ArkTS 侧统一 await 形态
//（目录扫描/插件初始化将来变慢时无需改签名）。
static napi_value LoadPlugins(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string dir;
    if (argc > 0) dir = GetStringArg(env, args[0]);

    int count = 0;
    if (!dir.empty()) {
        count = PluginManager::GetInstance().LoadPluginsFromDir(dir);
    }

    napi_deferred deferred;
    napi_value promise;
    napi_create_promise(env, &deferred, &promise);
    napi_value countValue;
    napi_create_int32(env, count, &countValue);
    napi_resolve_deferred(env, deferred, countValue);
    return promise;
}

// listPlugins()：统一插件表（内置 + 文件）的 JSON 字符串，
// 字段：id/name/version/description/author/type/enabled/source/error。
static napi_value ListPlugins(napi_env env, napi_callback_info info) {
    std::vector<PluginRecord> plugins = PluginManager::GetInstance().GetPlugins();

    std::string json = "[";
    for (size_t i = 0; i < plugins.size(); ++i) {
        const PluginRecord& p = plugins[i];
        if (i > 0) json += ',';
        json += "{\"id\":\"" + hmsec::JsonEscape(p.id) + "\"";
        json += ",\"name\":\"" + hmsec::JsonEscape(p.name) + "\"";
        json += ",\"version\":\"" + hmsec::JsonEscape(p.version) + "\"";
        json += ",\"description\":\"" + hmsec::JsonEscape(p.description) + "\"";
        json += ",\"author\":\"" + hmsec::JsonEscape(p.author) + "\"";
        json += ",\"type\":\"";
        json += PluginTypeStr(p.type);
        json += "\"";
        json += ",\"enabled\":";
        json += p.enabled ? "true" : "false";
        json += ",\"source\":\"";
        json += (p.source == PluginSource::BUILTIN) ? "builtin" : "file";
        json += "\"";
        json += ",\"error\":\"" + hmsec::JsonEscape(p.error) + "\"";
        json += "}";
    }
    json += "]";

    napi_value result;
    napi_create_string_utf8(env, json.c_str(), json.length(), &result);
    return result;
}

// setPluginEnabled(id, enabled)：启用/禁用插件（含内置适配器），id 不存在返回 false
static napi_value SetPluginEnabled(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    bool ok = false;
    if (argc >= 2) {
        std::string id = GetStringArg(env, args[0]);
        bool enabled = false;
        napi_get_value_bool(env, args[1], &enabled);
        ok = PluginManager::GetInstance().SetPluginEnabled(id, enabled);
    }

    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

// ========== Password Leak Audit NAPI绑定 ==========
// 该模块的所有输出都只含脱敏告警元数据；请求正文和命中片段绝不离开原生审计线程。

static napi_value SetPasswordLeakAuditEnabled(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    bool enabled = true;
    bool ok = false;
    if (argc > 0 && napi_get_value_bool(env, args[0], &enabled) == napi_ok) {
        ok = PluginManager::GetInstance().SetPluginEnabled(kPasswordLeakAuditPluginId, enabled);
    }
    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

static napi_value GetPasswordLeakAuditStatus(napi_env env, napi_callback_info info) {
    PasswordLeakAuditStatus status = PasswordLeakAudit::GetInstance().GetStatus();
    const bool enabled = PluginManager::GetInstance().IsPluginEnabled(kPasswordLeakAuditPluginId) &&
                         PasswordLeakAudit::GetInstance().IsEnabled();
    std::string json = "{\"enabled\":";
    json += enabled ? "true" : "false";
    json += ",\"unreadCount\":" + std::to_string(status.unreadCount);
    json += ",\"todayCount\":" + std::to_string(status.todayCount);
    json += ",\"lastAlertTimeMs\":" + std::to_string(status.lastAlertTimeMs);
    json += ",\"droppedTasks\":" + std::to_string(status.droppedTasks);
    json += ",\"truncatedTasks\":" + std::to_string(status.truncatedTasks);
    json += ",\"failedTasks\":" + std::to_string(status.failedTasks) + "}";
    napi_value result;
    napi_create_string_utf8(env, json.c_str(), json.length(), &result);
    return result;
}

static napi_value GetPasswordLeakAlerts(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    uint32_t offset = 0;
    uint32_t limit = 50;
    if (argc > 0) napi_get_value_uint32(env, args[0], &offset);
    if (argc > 1) napi_get_value_uint32(env, args[1], &limit);

    PasswordLeakAlertPage page = PasswordLeakAudit::GetInstance().GetAlerts(offset, limit);
    std::string json = "{\"alerts\":[";
    for (size_t i = 0; i < page.alerts.size(); ++i) {
        const PasswordLeakAlert& alert = page.alerts[i];
        if (i > 0) json += ',';
        json += "{\"id\":\"" + hmsec::JsonEscape(alert.id) + "\"";
        json += ",\"timeMs\":" + std::to_string(alert.timeMs);
        json += ",\"severity\":\"" + hmsec::JsonEscape(alert.severity) + "\"";
        json += ",\"secretType\":\"" + hmsec::JsonEscape(alert.secretType) + "\"";
        json += ",\"location\":\"" + hmsec::JsonEscape(alert.location) + "\"";
        json += ",\"protocol\":\"" + hmsec::JsonEscape(alert.protocol) + "\"";
        json += ",\"model\":\"" + hmsec::JsonEscape(alert.model) + "\"";
        json += ",\"status\":\"" + hmsec::JsonEscape(alert.status) + "\"}";
    }
    json += "],\"total\":" + std::to_string(page.total) + "}";
    napi_value result;
    napi_create_string_utf8(env, json.c_str(), json.length(), &result);
    return result;
}

static napi_value MarkPasswordLeakAlertsRead(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    uint32_t changed = 0;
    if (argc > 0) {
        const std::string rawIds = GetStringArg(env, args[0]);
        hmsec::JsonCursor cursor{rawIds.c_str(), rawIds.size()};
        std::vector<std::string> ids;
        if (cursor.ParseStringArray(ids) && cursor.Eof() && ids.size() <= 200) {
            changed = PasswordLeakAudit::GetInstance().MarkRead(ids);
        }
    }
    napi_value result;
    napi_create_uint32(env, changed, &result);
    return result;
}

static napi_value ClearPasswordLeakAlerts(napi_env env, napi_callback_info info) {
    PasswordLeakAudit::GetInstance().ClearAlerts();
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ========== Router NAPI绑定（M3：多协议智能路由） ==========

// setRouteRules(rulesJson)：原子替换整张路由表。
// rulesJson 为规则数组 JSON（schema 见 Types.d.ts 的 NativeRouteRule）；
// 非法 JSON 返回 false 且不动旧表；空数组 "[]" 合法 = 关闭规则路由（回退单一上游）。
// 同步函数：解析与 swap 都是内存操作，无需 Promise。
static napi_value SetRouteRules(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    bool ok = false;
    if (argc > 0) {
        std::string json = GetStringArg(env, args[0]);
        ok = hmsec::Router::Instance().SetRulesFromJson(json);
    }

    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

// ========== 初始化函数 ==========

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        // Proxy Engine
        {"startProxy", nullptr, StartProxy, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopProxy", nullptr, StopProxy, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getProxyStatus", nullptr, GetProxyStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setUpstream", nullptr, SetUpstream, nullptr, nullptr, nullptr, napi_default, nullptr},

        // Security Detector
        {"getSecurityRules", nullptr, GetSecurityRules, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setRuleEnabled", nullptr, SetRuleEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},
        // M4：规则自定义词条增删 + 响应侧安全检测开关
        {"updateRuleConfig", nullptr, UpdateRuleConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSecurityEnabled", nullptr, SetSecurityEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setResponseSecurityEnabled", nullptr, SetResponseSecurityEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},

        // Plugin Manager（M2：动态库插件）
        {"loadPlugins", nullptr, LoadPlugins, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"listPlugins", nullptr, ListPlugins, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setPluginEnabled", nullptr, SetPluginEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},

        // Password Leak Audit（异步、脱敏、只提醒）
        {"setPasswordLeakAuditEnabled", nullptr, SetPasswordLeakAuditEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getPasswordLeakAuditStatus", nullptr, GetPasswordLeakAuditStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getPasswordLeakAlerts", nullptr, GetPasswordLeakAlerts, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"markPasswordLeakAlertsRead", nullptr, MarkPasswordLeakAlertsRead, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"clearPasswordLeakAlerts", nullptr, ClearPasswordLeakAlerts, nullptr, nullptr, nullptr, napi_default, nullptr},

        // Router（M3：多协议智能路由）
        {"setRouteRules", nullptr, SetRouteRules, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
