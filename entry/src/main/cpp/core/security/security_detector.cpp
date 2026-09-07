#include "include/security_detector.h"
#include "json_scan.h"   // hmsec::JsonCursor（R2：UpdateRuleConfigFromJson 的公共 JSON 扫描）
#include "str_util.h"    // hmsec::ToLower（R2：大小写不敏感匹配的公共实现）
#include <regex>
#include <sstream>
#include <algorithm>
#include <cctype>

namespace aigate {

using hmsec::ToLower;

// ========== DetectionRule 基类：自定义词条 + 命中计数（M4） ==========

void DetectionRule::AddCustomKeyword(const std::string& keyword) {
    if (keyword.empty()) return;
    std::lock_guard<std::mutex> lk(customMutex_);
    customKeywords_.insert(keyword);
}

void DetectionRule::RemoveCustomKeyword(const std::string& keyword) {
    std::lock_guard<std::mutex> lk(customMutex_);
    customKeywords_.erase(keyword);
}

void DetectionRule::AddCustomPattern(const std::string& pattern) {
    if (pattern.empty()) return;
    std::lock_guard<std::mutex> lk(customMutex_);
    customPatterns_.push_back(pattern);
}

void DetectionRule::RemoveCustomPattern(const std::string& pattern) {
    std::lock_guard<std::mutex> lk(customMutex_);
    auto it = std::remove(customPatterns_.begin(), customPatterns_.end(), pattern);
    customPatterns_.erase(it, customPatterns_.end());
}

std::vector<std::string> DetectionRule::GetCustomKeywords() const {
    std::lock_guard<std::mutex> lk(customMutex_);
    return std::vector<std::string>(customKeywords_.begin(), customKeywords_.end());
}

std::vector<std::string> DetectionRule::GetCustomPatterns() const {
    std::lock_guard<std::mutex> lk(customMutex_);
    return customPatterns_;
}

bool DetectionRule::MatchCustom(const std::string& text, std::string& matched) const {
    // 锁内拷贝快照、锁外匹配：正则可能耗时，不能持锁跑
    std::vector<std::string> keywords;
    std::vector<std::string> patterns;
    {
        std::lock_guard<std::mutex> lk(customMutex_);
        keywords.assign(customKeywords_.begin(), customKeywords_.end());
        patterns = customPatterns_;
    }
    if (keywords.empty() && patterns.empty()) return false;

    std::string lowerText = ToLower(text);

    for (const auto& kw : keywords) {
        if (lowerText.find(ToLower(kw)) != std::string::npos) {
            matched = kw;
            return true;
        }
    }
    for (const auto& p : patterns) {
        try {
            if (std::regex_search(text, std::regex(p))) {
                matched = p;
                return true;
            }
        } catch (const std::regex_error&) {
            // 用户给的无效正则静默忽略（与内置 patterns_ 的既有处理一致）
        }
    }
    return false;
}

// ========== PasswordLeakRule 实现 ==========

PasswordLeakRule::PasswordLeakRule() {
    // 默认敏感关键词
    keywords_ = {
        "password", "passwd", "pwd",
        "secret", "token", "api_key",
        "apikey", "access_key", "secret_key",
        "private_key", "auth_token"
    };

    // 默认正则模式 - 检测可能的密码格式
    patterns_ = {
        R"(password\s*[:=]\s*[^\s]+)",           // password: xxx
        R"(token\s*[:=]\s*[^\s]+)",              // token: xxx
        R"(api[_-]?key\s*[:=]\s*[^\s]+)",        // api_key: xxx
        R"(secret[_-]?key\s*[:=]\s*[^\s]+)",     // secret_key: xxx
        R"(Bearer\s+[^\s]+)",                    // Bearer token
        R"(sk-[a-zA-Z0-9]{32,})",                // OpenAI API key格式
        R"(sk-ant-[a-zA-Z0-9_-]{40,})",         // Anthropic API key格式
    };
}

void PasswordLeakRule::AddKeyword(const std::string& keyword) {
    keywords_.insert(keyword);
}

void PasswordLeakRule::AddPattern(const std::string& pattern) {
    patterns_.push_back(pattern);
}

DetectionResult PasswordLeakRule::DetectText(const std::string& text) {
    std::string lowerText = ToLower(text);

    // 检查关键词
    for (const auto& keyword : keywords_) {
        size_t pos = lowerText.find(keyword);
        if (pos != std::string::npos) {
            // 进一步检查是否有实际的值
            size_t valueStart = pos + keyword.length();
            while (valueStart < text.length() && std::isspace(text[valueStart])) {
                valueStart++;
            }
            if (valueStart < text.length() &&
                (text[valueStart] == ':' || text[valueStart] == '=')) {
                return MakeHit("检测到可能的密码泄露: " + keyword, pos);
            }
        }
    }

    // 检查正则模式
    for (const auto& pattern : patterns_) {
        try {
            std::regex re(pattern);
            std::smatch match;
            if (std::regex_search(text, match, re)) {
                return MakeHit("检测到可能的密码泄露模式", match.position());
            }
        } catch (const std::regex_error&) {
            // 忽略无效的正则表达式
        }
    }

    // M4：用户自定义词条兜底（内置词表之外追加的敏感词/正则）
    std::string matched;
    if (MatchCustom(text, matched)) {
        return MakeHit("命中自定义敏感词条: " + matched, lowerText.find(matched));
    }

    return DetectionResult(); // 安全
}

DetectionResult PasswordLeakRule::DetectRequest(const HttpRequest& request) {
    // 检查URL
    auto result = DetectText(request.url);
    if (!result.isSafe) return result;

    // 检查headers
    for (auto it = request.headers.begin(); it != request.headers.end(); ++it) {
        result = DetectText(it->first + ": " + it->second);
        if (!result.isSafe) return result;
    }

    // 检查body
    if (!request.body.empty()) {
        return DetectText(request.body);
    }

    return DetectionResult();
}

DetectionResult PasswordLeakRule::DetectResponse(const HttpResponse& response) {
    // 主要是检查响应体
    if (!response.body.empty()) {
        return DetectText(response.body);
    }
    return DetectionResult();
}

// ========== MaliciousToolUseRule 实现 ==========

MaliciousToolUseRule::MaliciousToolUseRule() {
    // 默认危险工具列表
    dangerousTools_ = {
        "bash", "shell", "cmd", "powershell",
        "execute", "eval", "compile", "run_code",
        "file_delete", "file_remove", "delete_file",
        "system", "subprocess", "os.system",
        "exec", "spawn", "fork"
    };

    // 默认白名单（Claude Code的安全工具）
    whitelist_ = {
        "read_file", "write_file", "list_files",
        "search_files", "grep", "glob",
        "web_search", "ask_user"
    };
}

void MaliciousToolUseRule::AddDangerousTool(const std::string& toolName) {
    dangerousTools_.insert(toolName);
}

void MaliciousToolUseRule::SetWhitelist(const std::vector<std::string>& whitelist) {
    whitelist_.clear();
    for (const auto& item : whitelist) {
        whitelist_.insert(item);
    }
}

DetectionResult MaliciousToolUseRule::DetectToolUse(const std::string& content) {
    // 检测工具调用模式，例如 {"name": "tool_name", ...}
    // M4 分片输入核对（ResponseScanner 按 SSE 事件边界喂入）：半个 JSON 不会误判——
    // 正则要求完整引号对（"name":"x"）才匹配，跨边界的截断 JSON 只会漏报不会误报；
    // 而完整 SSE 事件（data: {...}）内的 tool_use 名称完整出现，检测不受影响。
    std::regex toolPattern(R"([\"']name[\"']\s*:\s*[\"']([^\"']+)[\"'])");
    std::smatch match;

    std::string::const_iterator searchStart = content.begin();
    while (std::regex_search(searchStart, content.end(), match, toolPattern)) {
        std::string toolName = match[1].str();

        // 检查是否在白名单中
        if (whitelist_.find(toolName) != whitelist_.end()) {
            searchStart = match[0].second;
            continue;
        }

        // 检查是否是危险工具
        for (const auto& dangerous : dangerousTools_) {
            if (toolName.find(dangerous) != std::string::npos) {
                return MakeHit("检测到恶意工具调用: " + toolName, match.position());
            }
        }

        searchStart = match[0].second;
    }

    // M4：用户自定义词条兜底（如对特定内部工具名的追加封禁）
    std::string matched;
    if (MatchCustom(content, matched)) {
        return MakeHit("命中自定义危险工具词条: " + matched);
    }

    return DetectionResult();
}

DetectionResult MaliciousToolUseRule::DetectRequest(const HttpRequest&) {
    // 请求不检测tool use
    return DetectionResult();
}

DetectionResult MaliciousToolUseRule::DetectResponse(const HttpResponse& response) {
    if (!response.body.empty()) {
        return DetectToolUse(response.body);
    }
    return DetectionResult();
}

// ========== PromptInjectionRule 实现 ==========

PromptInjectionRule::PromptInjectionRule() {
    injectionPatterns_ = {
        "ignore all previous instructions",
        "disregard all instructions",
        "forget everything",
        "override security",
        "bypass restrictions",
        "jailbreak",
        "developer mode",
        "dan mode",
        "admin mode",
        "ignore the above",
        "pretend to be",
        "act as",
        "roleplay as",
        // M4 中文模式（保守选词：只收高指向性的对抗句式，避免误杀正常讨论）
        "无视所有安全限制",
        "绕过内容过滤",
        "忽略先前的所有指令",
        "无视你之前的指令"
    };
}

DetectionResult PromptInjectionRule::DetectInjection(const std::string& text) {
    std::string lowerText = ToLower(text);

    for (const auto& pattern : injectionPatterns_) {
        size_t pos = lowerText.find(ToLower(pattern));
        if (pos != std::string::npos) {
            return MakeHit("检测到可能的提示注入: " + pattern, pos);
        }
    }

    // M4：用户自定义词条兜底
    std::string matched;
    if (MatchCustom(text, matched)) {
        return MakeHit("命中自定义提示注入词条: " + matched);
    }

    return DetectionResult();
}

DetectionResult PromptInjectionRule::DetectRequest(const HttpRequest& request) {
    // 检查请求内容
    std::string content = request.url;
    content += " " + request.body;

    for (auto it = request.headers.begin(); it != request.headers.end(); ++it) {
        content += " " + it->first + ": " + it->second;
    }

    return DetectInjection(content);
}

DetectionResult PromptInjectionRule::DetectResponse(const HttpResponse&) {
    // 响应不检测提示注入
    return DetectionResult();
}

// ========== ContextInjectionRule 实现（M4） ==========

ContextInjectionRule::ContextInjectionRule() {
    // 子串模式（英文大小写不敏感；中文原样）。选词保守：只收明确的越权/伪装句式。
    substrPatterns_ = {
        "you are now",       // "you are now DAN / an unrestricted AI"
        "system prompt",     // 索取/伪造系统提示
        "new instructions:", // 伪指令注入
        "from now on you",
        "你现在是一个",
        "进入开发者模式"
    };
    // 正则模式：中文「忽略/无视 + （以上|之前|先前） + 指令」的各种变体。
    // 注意：std::regex 按字节匹配，量词只作用于多字节字符的最后一个字节——
    // 可选的中文必须包成分组（如 (的)?），写 的? 会让前两字节变成必需而永不匹配。
    regexPatterns_ = {
        R"(忽略(以上|之前|先前|上面)(的)?(所有|全部)?(指令|指示|命令))",
        R"(无视(以上|之前|先前|上面)(的)?(所有|全部)?(指令|指示|限制))"
    };
}

DetectionResult ContextInjectionRule::DetectInjection(const std::string& text) {
    std::string lowerText = ToLower(text);

    for (const auto& pattern : substrPatterns_) {
        size_t pos = lowerText.find(ToLower(pattern));
        if (pos != std::string::npos) {
            // CRITICAL → 默认映射 WARN，只记录不阻断
            return MakeHit("检测到可能的上下文注入: " + pattern, pos);
        }
    }

    for (const auto& pattern : regexPatterns_) {
        try {
            std::smatch m;
            if (std::regex_search(text, m, std::regex(pattern))) {
                return MakeHit("检测到可能的上下文注入模式", m.position());
            }
        } catch (const std::regex_error&) {
            // 内置正则不应无效；防御性忽略
        }
    }

    // 用户自定义词条兜底
    std::string matched;
    if (MatchCustom(text, matched)) {
        return MakeHit("命中自定义上下文注入词条: " + matched);
    }

    return DetectionResult();
}

DetectionResult ContextInjectionRule::DetectRequest(const HttpRequest& request) {
    // 与 PromptInjectionRule 同范围：url + body + 头（管线传入的是脱敏请求——只有 body，
    // 头部注入的拦截由管线语义保证不在这里发生）
    std::string content = request.url;
    content += " " + request.body;
    for (auto it = request.headers.begin(); it != request.headers.end(); ++it) {
        content += " " + it->first + ": " + it->second;
    }
    return DetectInjection(content);
}

// ========== SecurityDetector 实现 ==========

SecurityDetector& SecurityDetector::GetInstance() {
    static SecurityDetector instance;
    return instance;
}

SecurityDetector::SecurityDetector() {
    // 设置默认动作映射
    actionMap_[DetectionLevel::INFO] = DetectionAction::ALLOW;
    actionMap_[DetectionLevel::WARNING] = DetectionAction::WARN;
    actionMap_[DetectionLevel::CRITICAL] = DetectionAction::WARN;
    actionMap_[DetectionLevel::BLOCK] = DetectionAction::BLOCK;

    InitializeDefaultRules();
}

void SecurityDetector::InitializeDefaultRules() {
    // 注册默认规则
    rules_.push_back(std::make_unique<PasswordLeakRule>());
    rules_.push_back(std::make_unique<MaliciousToolUseRule>());
    rules_.push_back(std::make_unique<PromptInjectionRule>());
    rules_.push_back(std::make_unique<ContextInjectionRule>());  // M4：CRITICAL→WARN，只记录不阻断

    // 默认启用所有规则
    for (const auto& rule : rules_) {
        ruleEnabled_[rule->GetId()] = true;
    }
}

void SecurityDetector::RegisterRule(std::unique_ptr<DetectionRule> rule) {
    rules_.push_back(std::move(rule));
}

void SecurityDetector::UnregisterRule(const std::string& ruleId) {
    auto it = std::remove_if(rules_.begin(), rules_.end(),
        [&ruleId](const std::unique_ptr<DetectionRule>& rule) {
            return ruleId == rule->GetId();
        });
    rules_.erase(it, rules_.end());
    ruleEnabled_.erase(ruleId);
}

DetectionResult SecurityDetector::DetectRequest(const HttpRequest& request) {
    DetectionResult finalResult;
    finalResult.isSafe = true;
    finalResult.level = DetectionLevel::INFO;

    for (auto& rule : rules_) {
        if (!ruleEnabled_[rule->GetId()]) {
            continue; // 跳过禁用的规则
        }

        // 请求里的密码/Key 不再走同步 BLOCK：由 password-leak-audit 在转发后
        // 异步生成脱敏提醒。响应侧仍保留该规则，避免模型回显凭据时无防护。
        if (std::string(rule->GetId()) == "password_leak") {
            continue;
        }

        DetectionResult result = rule->DetectRequest(request);
        if (!result.isSafe) {
            rule->IncHit();  // M4：命中计数（每条给出非安全结果的规则都计，不只最严重那条）
            // 记录最严重的结果
            if (result.level > finalResult.level) {
                finalResult = result;
            }
        }
    }

    return finalResult;
}

DetectionResult SecurityDetector::DetectResponse(const HttpResponse& response) {
    DetectionResult finalResult;
    finalResult.isSafe = true;
    finalResult.level = DetectionLevel::INFO;

    for (auto& rule : rules_) {
        if (!ruleEnabled_[rule->GetId()]) {
            continue; // 跳过禁用的规则
        }

        DetectionResult result = rule->DetectResponse(response);
        if (!result.isSafe) {
            rule->IncHit();  // M4：命中计数
            if (result.level > finalResult.level) {
                finalResult = result;
            }
        }
    }

    return finalResult;
}

void SecurityDetector::SetDetectionAction(DetectionLevel level, DetectionAction action) {
    actionMap_[level] = action;
}

DetectionAction SecurityDetector::GetDetectionAction(DetectionLevel level) const {
    auto it = actionMap_.find(level);
    if (it != actionMap_.end()) {
        return it->second;
    }
    return DetectionAction::ALLOW;
}

void SecurityDetector::EnableRule(const std::string& ruleId, bool enable) {
    ruleEnabled_[ruleId] = enable;
}

std::vector<std::string> SecurityDetector::GetRuleIds() const {
    std::vector<std::string> ids;
    for (const auto& rule : rules_) {
        ids.push_back(rule->GetId());
    }
    return ids;
}

// ========== M4：自定义词条配置 ==========

bool SecurityDetector::UpdateRuleConfig(const std::string& ruleId,
                                        const std::vector<std::string>& addKeywords,
                                        const std::vector<std::string>& removeKeywords,
                                        const std::vector<std::string>& addPatterns,
                                        const std::vector<std::string>& removePatterns) {
    for (const auto& rule : rules_) {
        if (ruleId != rule->GetId()) continue;
        // 先删后增：同一次提交里"改名"（删旧词添新词）语义正确
        for (const auto& kw : removeKeywords) rule->RemoveCustomKeyword(kw);
        for (const auto& p : removePatterns) rule->RemoveCustomPattern(p);
        for (const auto& kw : addKeywords) rule->AddCustomKeyword(kw);
        for (const auto& p : addPatterns) rule->AddCustomPattern(p);
        return true;
    }
    return false;  // 未知 ruleId：不动任何词条
}

// ========== M4：自定义词条配置（JSON 入口） ==========
// configJson 结构固定、由 ArkTS 侧按契约生成（四个键均可选）；手写最小 JSON 扫描
// 已收敛到 json_scan.h 的 hmsec::JsonCursor（理由见其头部注释）。任何结构性错误
// 让整体解析失败（返回 false），未知键跳过（向后兼容）。

bool SecurityDetector::UpdateRuleConfigFromJson(const std::string& ruleId,
                                                const std::string& configJson) {
    std::vector<std::string> addKw, rmKw, addPat, rmPat;
    hmsec::JsonCursor ps{configJson.c_str(), configJson.size(), 0};
    if (!ps.Consume('{')) return false;
    if (!ps.Consume('}')) {  // 空对象 {} 合法（什么都不改）
        while (true) {
            std::string key;
            if (!ps.ParseString(key)) return false;
            if (!ps.Consume(':')) return false;
            if (key == "addKeywords") {
                if (!ps.ParseStringArray(addKw)) return false;
            } else if (key == "removeKeywords") {
                if (!ps.ParseStringArray(rmKw)) return false;
            } else if (key == "addPatterns") {
                if (!ps.ParseStringArray(addPat)) return false;
            } else if (key == "removePatterns") {
                if (!ps.ParseStringArray(rmPat)) return false;
            } else {
                if (!ps.SkipValue()) return false;  // 未知键：跳过
            }
            if (ps.Consume(',')) continue;
            if (!ps.Consume('}')) return false;
            break;
        }
    }
    if (!ps.Eof()) return false;  // 对象外还有内容 = 非法
    return UpdateRuleConfig(ruleId, addKw, rmKw, addPat, rmPat);
}

std::vector<RuleInfo> SecurityDetector::GetRuleInfos() {
    std::vector<RuleInfo> out;
    out.reserve(rules_.size());
    for (const auto& rule : rules_) {
        RuleInfo info;
        info.id = rule->GetId();
        info.name = rule->GetName();
        // 用 find 而非 operator[]：不为从未显式开关过的规则制造表项
        auto it = ruleEnabled_.find(info.id);
        info.enabled = (it == ruleEnabled_.end()) ? true : it->second;
        info.hitCount = rule->GetHitCount();
        info.customKeywords = rule->GetCustomKeywords();
        info.customPatterns = rule->GetCustomPatterns();
        out.push_back(std::move(info));
    }
    return out;
}

} // namespace aigate
