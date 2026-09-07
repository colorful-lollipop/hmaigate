#include "include/plugin_manager.h"
#include "include/security_detector.h"  // 内置适配器要包装 SecurityDetector
#include "security/password_leak_audit.h"

#include <cstdio>
#include <cstring>

#ifdef _WIN32
#include <windows.h>  // LoadLibraryA / GetProcAddress（宿主侧 MinGW 单测走这里）
#else
#include <dlfcn.h>    // dlopen / dlsym（鸿蒙设备侧）
#include <dirent.h>   // opendir / readdir
#endif

namespace aigate {

// ========== 跨平台动态库封装 ==========
// 鸿蒙设备侧走 POSIX dlopen；宿主侧单测在 Windows/MinGW 下走 LoadLibrary，
// 同一套 C ABI 两边可测。

bool PluginManager::DynLibOpen(const std::string& path, DynLib& out, std::string& err) {
#ifdef _WIN32
    HMODULE h = LoadLibraryA(path.c_str());
    if (!h) {
        err = "LoadLibraryA failed, err=" + std::to_string(GetLastError());
        return false;
    }
    out.handle = reinterpret_cast<void*>(h);
    return true;
#else
    // RTLD_NOW：加载时立即解析符号，尽早暴露缺符号问题
    void* h = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        const char* e = dlerror();
        err = std::string("dlopen failed: ") + (e ? e : "unknown");
        return false;
    }
    out.handle = h;
    return true;
#endif
}

void* PluginManager::DynLibSym(const DynLib& lib, const char* name) {
#ifdef _WIN32
    return reinterpret_cast<void*>(
        GetProcAddress(reinterpret_cast<HMODULE>(lib.handle), name));
#else
    return dlsym(lib.handle, name);
#endif
}

void PluginManager::DynLibClose(DynLib& lib) {
    if (!lib.handle) return;
#ifdef _WIN32
    FreeLibrary(reinterpret_cast<HMODULE>(lib.handle));
#else
    dlclose(lib.handle);
#endif
    lib.handle = nullptr;
}

// ========== 内置适配器：把 SecurityDetector 包装成 C ABI 插件 ==========
// 目的：证明纯 C ABI（aigate_plugin.h）足以承载现有检测能力——
// 内置检测器与第三方动态库插件走同一条 vtable 路径出现在插件列表里。
// 注意：管线对内置检测器仍走 SecurityCheckRequest 里的直接调用
//（受 IsPluginEnabled(kBuiltinSecurityPluginId) 门控），不会经本 vtable 重复检测。

namespace {

void WriteReason(char* result, size_t resultSize, const std::string& message) {
    if (result && resultSize > 0) {
        std::snprintf(result, resultSize, "%s", message.c_str());
    }
}

// M4 起按「级别→动作」映射给结论：WARN 级（如 context_injection）报 WARN 而非 BLOCK。
static int ToVerdict(const DetectionResult& r) {
    if (r.isSafe) return AIGATE_DETECT_PASS;
    return SecurityDetector::GetInstance().IsBlocking(r)
               ? AIGATE_DETECT_BLOCK
               : AIGATE_DETECT_WARN;
}

int BuiltinDetectRequest(const char* body, char* result, size_t resultSize) {
    HttpRequest req;
    req.method = HttpMethod::POST;
    req.url = "/";
    req.body = body ? body : "";
    DetectionResult r = SecurityDetector::GetInstance().DetectRequest(req);
    WriteReason(result, resultSize, r.message);
    return ToVerdict(r);
}

int BuiltinDetectResponse(const char* body, char* result, size_t resultSize) {
    HttpResponse resp;
    resp.statusCode = 200;
    resp.body = body ? body : "";
    DetectionResult r = SecurityDetector::GetInstance().DetectResponse(resp);
    WriteReason(result, resultSize, r.message);
    return ToVerdict(r);
}

} // namespace

// ========== 单例与构造 ==========

PluginManager& PluginManager::GetInstance() {
    static PluginManager instance;
    return instance;
}

PluginManager::PluginManager() {
    // 构造时注册内置适配器（只填表，不触碰 SecurityDetector 单例，
    // 无静态初始化顺序问题——适配器函数在调用时才取 GetInstance()）。
    RegisterBuiltinPluginsLocked();
}

void PluginManager::RegisterBuiltinPluginsLocked() {
    PluginRecord rec;
    rec.id = kBuiltinSecurityPluginId;
    rec.name = "内置安全检测器";
    rec.version = "1.0.0";
    rec.description = "aigate::SecurityDetector 的 C ABI 适配器（密码泄露/恶意 tool use/提示注入）";
    rec.author = "AIGate";
    rec.type = AIGATE_PLUGIN_SECURITY;
    rec.source = PluginSource::BUILTIN;
    rec.enabled = true;
    rec.vtable.detect_request = &BuiltinDetectRequest;
    rec.vtable.detect_response = &BuiltinDetectResponse;
    // transform_* 留空：内置检测器不做内容转换
    plugins_[rec.id] = rec;

    // 密码泄露提醒不走现有 C ABI（它需要异步队列、结构化告警和历史），但仍作为
    // 内置插件出现在统一插件表，沿用现有开关与运行中热更新机制。
    PluginRecord audit;
    audit.id = kPasswordLeakAuditPluginId;
    audit.name = "密码泄露提醒";
    audit.version = "1.0.0";
    audit.description = "异步审计请求体中的可能凭据，仅生成脱敏提醒，不拦截转发";
    audit.author = "AIGate";
    audit.type = AIGATE_PLUGIN_SECURITY;
    audit.source = PluginSource::BUILTIN;
    audit.enabled = true;
    plugins_[audit.id] = audit;
}

// ========== M2：动态库插件 ==========

namespace {

// 从路径取文件名（去掉目录），用于加载失败记录的占位 id/name
std::string BaseName(const std::string& path) {
    size_t pos = path.find_last_of("/\\");
    return pos == std::string::npos ? path : path.substr(pos + 1);
}

// 是否是插件动态库文件名（设备侧 .so / Windows .dll）
bool HasPluginExt(const std::string& name) {
#ifdef _WIN32
    const char* ext = ".dll";
#else
    const char* ext = ".so";
#endif
    size_t n = name.size(), e = std::strlen(ext);
    if (n <= e) return false;
    return name.compare(n - e, e, ext) == 0;
}

} // namespace

bool PluginManager::LoadPluginFromFile(const std::string& path) {
    PluginRecord rec;
    rec.source = PluginSource::FILE;
    rec.enabled = false;
    rec.path = path;
    rec.id = BaseName(path);   // 失败记录先用文件名占位，成功后换成插件自报 id
    rec.name = rec.id;

    DynLib lib;
    std::string err;
    // 逐阶段校验；任一失败都入表（让 UI 能展示"为什么没加载起来"）并返回 false
    do {
        if (!DynLibOpen(path, lib, err)) {
            rec.error = err;
            break;
        }
        void* sym = DynLibSym(lib, AIGATE_PLUGIN_ENTRY_SYMBOL);
        if (!sym) {
            rec.error = std::string("missing entry symbol: ") + AIGATE_PLUGIN_ENTRY_SYMBOL;
            break;
        }
        auto initFn = reinterpret_cast<AigatePluginInitFn>(sym);
        const AigatePluginVTable* vtable = nullptr;
        const AigatePluginInfo* info = initFn(&vtable);
        if (!info) {
            rec.error = "aigate_plugin_init returned null";
            break;
        }
        // ABI 版本不匹配即拒绝：结构布局可能已变，继续读字段就是未定义行为
        if (info->abi_version != AIGATE_PLUGIN_API_VERSION) {
            rec.error = "ABI version mismatch: plugin=" + std::to_string(info->abi_version) +
                        " host=" + std::to_string(AIGATE_PLUGIN_API_VERSION);
            break;
        }
        if (!info->id || info->id[0] == '\0') {
            rec.error = "plugin info has empty id";
            break;
        }
        if (!vtable) {
            rec.error = "plugin returned null vtable";
            break;
        }

        // 全部通过：拷贝元信息与函数表快照，入表并启用
        rec.id = info->id;
        rec.name = info->name ? info->name : "";
        rec.version = info->version ? info->version : "";
        rec.description = info->description ? info->description : "";
        rec.author = info->author ? info->author : "";
        rec.type = info->type;
        rec.enabled = true;
        rec.vtable = *vtable;

        {
            std::lock_guard<std::mutex> lock(pluginsMutex_);
            if (plugins_.find(rec.id) != plugins_.end()) {
                rec.enabled = false;
                rec.error = "duplicate plugin id: " + rec.id;
                break;  // 注意：break 在锁作用域内，守卫析构后才走失败路径
            }
            plugins_[rec.id] = rec;
            pluginLibs_[rec.id] = lib;  // 句柄随记录存活，不卸载（见头文件注释）
        }
        return true;
    } while (false);

    // 失败路径：释放库句柄，把错误记录进表；
    // 若同 id 已有成功记录（重复 id 场景），保留原记录不覆盖。
    DynLibClose(lib);
    std::lock_guard<std::mutex> lock(pluginsMutex_);
    if (plugins_.find(rec.id) == plugins_.end() || !plugins_[rec.id].error.empty()) {
        plugins_[rec.id] = rec;
    }
    return false;
}

int PluginManager::LoadPluginsFromDir(const std::string& dir) {
    // 收集目录下的插件文件名；目录不存在返回 0（插件目录本就允许为空）
    std::vector<std::string> files;
#ifdef _WIN32
    WIN32_FIND_DATAA fd;
    HANDLE hFind = FindFirstFileA((dir + "\\*").c_str(), &fd);
    if (hFind == INVALID_HANDLE_VALUE) return 0;
    do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && HasPluginExt(fd.cFileName)) {
            files.push_back(dir + "\\" + fd.cFileName);
        }
    } while (FindNextFileA(hFind, &fd));
    FindClose(hFind);
#else
    DIR* d = opendir(dir.c_str());
    if (!d) return 0;
    while (struct dirent* ent = readdir(d)) {
        std::string name = ent->d_name;
        if (HasPluginExt(name)) {
            files.push_back(dir + "/" + name);
        }
    }
    closedir(d);
#endif

    int ok = 0;
    for (const auto& f : files) {
        if (LoadPluginFromFile(f)) ++ok;
    }
    return ok;
}

bool PluginManager::SetPluginEnabled(const std::string& pluginId, bool enabled) {
    std::lock_guard<std::mutex> lock(pluginsMutex_);
    auto it = plugins_.find(pluginId);
    if (it == plugins_.end()) return false;
    if (!it->second.error.empty()) return false;  // 加载失败的插件不允许启用
    it->second.enabled = enabled;
    if (pluginId == kPasswordLeakAuditPluginId) {
        PasswordLeakAudit::GetInstance().SetEnabled(enabled);
    }
    return true;
}

bool PluginManager::IsPluginEnabled(const std::string& pluginId) {
    std::lock_guard<std::mutex> lock(pluginsMutex_);
    auto it = plugins_.find(pluginId);
    return it != plugins_.end() && it->second.enabled;
}

std::vector<PluginRecord> PluginManager::GetPlugins() {
    std::vector<PluginRecord> out;
    std::lock_guard<std::mutex> lock(pluginsMutex_);
    out.reserve(plugins_.size());
    for (const auto& kv : plugins_) {
        out.push_back(kv.second);
    }
    return out;
}

std::vector<SecurityHook> PluginManager::GetEnabledSecurityHooks() {
    std::vector<SecurityHook> hooks;
    std::lock_guard<std::mutex> lock(pluginsMutex_);
    for (const auto& kv : plugins_) {
        const PluginRecord& rec = kv.second;
        // 只收文件来源：内置适配器由管线直接调用 SecurityDetector 门控执行，
        // 放进钩子列表会让同一检测跑两遍。
        if (rec.source != PluginSource::FILE) continue;
        if (!rec.enabled) continue;
        if (rec.type != AIGATE_PLUGIN_SECURITY) continue;
        if (!rec.vtable.detect_request) continue;
        hooks.push_back(SecurityHook{rec.id, rec.vtable.detect_request});
    }
    return hooks;
}

std::vector<ResponseSecurityHook> PluginManager::GetEnabledResponseHooks() {
    std::vector<ResponseSecurityHook> hooks;
    std::lock_guard<std::mutex> lock(pluginsMutex_);
    for (const auto& kv : plugins_) {
        const PluginRecord& rec = kv.second;
        // 与 GetEnabledSecurityHooks 同原则：只收文件来源，内置适配器由
        // ResponseScanner 直接调用 SecurityDetector 门控执行。
        if (rec.source != PluginSource::FILE) continue;
        if (!rec.enabled) continue;
        if (rec.type != AIGATE_PLUGIN_SECURITY) continue;
        if (!rec.vtable.detect_response) continue;
        hooks.push_back(ResponseSecurityHook{rec.id, rec.vtable.detect_response});
    }
    return hooks;
}

} // namespace aigate
