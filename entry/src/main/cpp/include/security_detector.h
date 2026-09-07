#ifndef AIGATE_SECURITY_DETECTOR_H
#define AIGATE_SECURITY_DETECTOR_H

#include <string>
#include <vector>
#include <memory>
#include <atomic>
#include <mutex>
#include <unordered_map>
#include <unordered_set>
#include "proxy_engine.h"

namespace aigate {

// 检测级别
enum class DetectionLevel {
    INFO,       // 信息级别，仅记录
    WARNING,    // 警告级别，需要关注
    CRITICAL,   // 严重级别，建议阻断
    BLOCK       // 阻断级别，必须阻断
};

// 检测动作
enum class DetectionAction {
    ALLOW,      // 放行
    WARN,       // 警告后放行
    BLOCK       // 阻断
};

// 检测结果
struct DetectionResult {
    bool isSafe;
    DetectionLevel level;
    std::string message;
    std::string ruleId;
    size_t matchedPosition;

    DetectionResult() : isSafe(true), level(DetectionLevel::INFO),
                       matchedPosition(0) {}
};

// 检测规则接口
class DetectionRule {
public:
    virtual ~DetectionRule() = default;

    // 获取规则ID
    virtual const char* GetId() const = 0;

    // 获取规则名称
    virtual const char* GetName() const = 0;

    // 获取默认检测级别
    virtual DetectionLevel GetDefaultLevel() const = 0;

    // 检测请求
    virtual DetectionResult DetectRequest(const HttpRequest& request) = 0;

    // 检测响应
    virtual DetectionResult DetectResponse(const HttpResponse& response) = 0;

    // ---- M4：用户自定义词条（经 SecurityDetector::UpdateRuleConfig 增删） ----
    // 关键词 = 大小写不敏感子串；正则 = std::regex_search（无效正则静默忽略）。
    // 在规则内置词表之外追加，各规则的检测路径在内置检查之后统一兜底调用 MatchCustom。
    // 内部互斥锁保护：NAPI 线程增删与转发工作线程检测可并发。
    void AddCustomKeyword(const std::string& keyword);
    void RemoveCustomKeyword(const std::string& keyword);
    void AddCustomPattern(const std::string& pattern);
    void RemoveCustomPattern(const std::string& pattern);
    std::vector<std::string> GetCustomKeywords() const;
    std::vector<std::string> GetCustomPatterns() const;

    // M4：命中计数（规则每次给出非安全结果时 +1，原子计数；供 UI 展示规则是否在工作）
    void IncHit() { hitCount_.fetch_add(1); }
    uint32_t GetHitCount() const { return hitCount_.load(); }

protected:
    // 自定义词条匹配：命中返回 true 并给出命中的词条（供规则构造 message）。
    // 锁内拷贝词条快照、锁外匹配，避免持锁跑正则。
    bool MatchCustom(const std::string& text, std::string& matched) const;

    // 构造一条命中结果（R2：消去各规则里重复的五字段填充块）：
    // isSafe=false、级别取 GetDefaultLevel()、ruleId 取 GetId()。
    DetectionResult MakeHit(const std::string& message, size_t pos = 0) const {
        DetectionResult result;
        result.isSafe = false;
        result.level = GetDefaultLevel();
        result.message = message;
        result.ruleId = GetId();
        result.matchedPosition = pos;
        return result;
    }

private:
    mutable std::mutex customMutex_;
    std::unordered_set<std::string> customKeywords_;
    std::vector<std::string> customPatterns_;
    std::atomic<uint32_t> hitCount_{0};
};

// 密码泄露检测规则
class PasswordLeakRule : public DetectionRule {
public:
    PasswordLeakRule();

    const char* GetId() const override { return "password_leak"; }
    const char* GetName() const override { return "密码泄露检测"; }
    // M4 起管线尊重「级别→动作」映射。历史上管线对任何非安全结果一律阻断，
    // 本规则一直实际阻断，故级别由 CRITICAL 提升为 BLOCK 以如实表达既有行为。
    DetectionLevel GetDefaultLevel() const override { return DetectionLevel::BLOCK; }

    DetectionResult DetectRequest(const HttpRequest& request) override;
    DetectionResult DetectResponse(const HttpResponse& response) override;

    // 添加敏感关键词
    void AddKeyword(const std::string& keyword);

    // 添加正则表达式模式
    void AddPattern(const std::string& pattern);

private:
    std::unordered_set<std::string> keywords_;
    std::vector<std::string> patterns_;

    // 检测文本中是否包含密码泄露
    DetectionResult DetectText(const std::string& text);
};

// 恶意Tool Use检测规则
class MaliciousToolUseRule : public DetectionRule {
public:
    MaliciousToolUseRule();

    const char* GetId() const override { return "malicious_tool_use"; }
    const char* GetName() const override { return "恶意工具调用检测"; }
    DetectionLevel GetDefaultLevel() const override { return DetectionLevel::BLOCK; }

    DetectionResult DetectRequest(const HttpRequest& request) override;
    DetectionResult DetectResponse(const HttpResponse& response) override;

    // 添加危险工具名称
    void AddDangerousTool(const std::string& toolName);

    // 设置工具白名单
    void SetWhitelist(const std::vector<std::string>& whitelist);

private:
    std::unordered_set<std::string> dangerousTools_;
    std::unordered_set<std::string> whitelist_;

    DetectionResult DetectToolUse(const std::string& content);
};

// 提示注入检测规则
class PromptInjectionRule : public DetectionRule {
public:
    PromptInjectionRule();

    const char* GetId() const override { return "prompt_injection"; }
    const char* GetName() const override { return "提示注入检测"; }
    // 同 password_leak：M4 起管线尊重动作映射，级别提升为 BLOCK 以保持既有阻断行为。
    DetectionLevel GetDefaultLevel() const override { return DetectionLevel::BLOCK; }

    DetectionResult DetectRequest(const HttpRequest& request) override;
    DetectionResult DetectResponse(const HttpResponse& response) override;

private:
    std::vector<std::string> injectionPatterns_;

    DetectionResult DetectInjection(const std::string& text);
};

// M4：上下文注入检测（伪装系统指令/越权操纵，中英文兼有）
//
// 保守取向，宁漏勿错杀：默认级别 CRITICAL，经默认动作映射（CRITICAL→WARN）
// 只记录不阻断——命中会进规则 hitCount，但不拦请求。模型系统提示、工具结果等
// 合法内容里完全可能讨论「系统提示词」这类话题，误阻断的代价比漏报高。
// 需要强阻断的用户可经 SetDetectionAction 把 CRITICAL 提升为 BLOCK。
class ContextInjectionRule : public DetectionRule {
public:
    ContextInjectionRule();

    const char* GetId() const override { return "context_injection"; }
    const char* GetName() const override { return "上下文注入检测"; }
    DetectionLevel GetDefaultLevel() const override { return DetectionLevel::CRITICAL; }

    DetectionResult DetectRequest(const HttpRequest& request) override;
    DetectionResult DetectResponse(const HttpResponse&) override {
        // 响应不检测上下文注入（模型输出里讨论这些话题是正常内容）
        return DetectionResult();
    }

private:
    std::vector<std::string> substrPatterns_;  // 子串模式（英文大小写不敏感 + 中文）
    std::vector<std::string> regexPatterns_;   // 正则模式（中文变体：忽略/无视 + 指令）

    DetectionResult DetectInjection(const std::string& text);
};

// M4：规则列表 JSON 的单条信息（NAPI getSecurityRules 返回形态）
struct RuleInfo {
    std::string id;
    std::string name;
    bool enabled;
    uint32_t hitCount;
    std::vector<std::string> customKeywords;
    std::vector<std::string> customPatterns;
};

// 安全检测器
class SecurityDetector {
public:
    // 获取单例实例
    static SecurityDetector& GetInstance();

    SecurityDetector();
    ~SecurityDetector() = default;

    // 注册检测规则
    void RegisterRule(std::unique_ptr<DetectionRule> rule);

    // 移除检测规则
    void UnregisterRule(const std::string& ruleId);

    // 检测请求
    DetectionResult DetectRequest(const HttpRequest& request);

    // 检测响应
    DetectionResult DetectResponse(const HttpResponse& response);

    // 设置检测动作映射
    void SetDetectionAction(DetectionLevel level, DetectionAction action);

    // 获取检测动作
    DetectionAction GetDetectionAction(DetectionLevel level) const;

    // 该命中按当前「级别→动作」映射是否应阻断（R2：收敛管线/响应扫描器/
    // 内置适配器三处重复的 "!isSafe && GetDetectionAction(level)==BLOCK" 判断）。
    bool IsBlocking(const DetectionResult& result) const {
        return !result.isSafe && GetDetectionAction(result.level) == DetectionAction::BLOCK;
    }

    // 启用/禁用规则
    void EnableRule(const std::string& ruleId, bool enable = true);

    // 获取所有规则ID
    std::vector<std::string> GetRuleIds() const;

    // ---- M4：自定义词条与规则信息 ----

    // 增删指定规则的用户自定义词条（先删后增）。未知 ruleId 返回 false，不动任何词条。
    bool UpdateRuleConfig(const std::string& ruleId,
                          const std::vector<std::string>& addKeywords,
                          const std::vector<std::string>& removeKeywords,
                          const std::vector<std::string>& addPatterns,
                          const std::vector<std::string>& removePatterns);

    // NAPI 入口用的 JSON 形态：configJson 为
    // {"addKeywords":[],"addPatterns":[],"removeKeywords":[],"removePatterns":[]}
    //（四个键均可选）。未知 ruleId 或非法 JSON 返回 false。
    bool UpdateRuleConfigFromJson(const std::string& ruleId, const std::string& configJson);

    // 全量规则信息（id/name/enabled/hitCount/自定义词条），供 NAPI 拼规则列表 JSON
    std::vector<RuleInfo> GetRuleInfos();

private:
    std::vector<std::unique_ptr<DetectionRule>> rules_;
    std::unordered_map<DetectionLevel, DetectionAction> actionMap_;
    std::unordered_map<std::string, bool> ruleEnabled_;

    // 初始化默认规则
    void InitializeDefaultRules();
};

} // namespace aigate

#endif // AIGATE_SECURITY_DETECTOR_H
