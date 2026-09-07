#ifndef AIGATE_PLUGIN_MANAGER_H
#define AIGATE_PLUGIN_MANAGER_H

#include <string>
#include <vector>
#include <mutex>
#include <unordered_map>

#include "aigate_plugin.h"

namespace aigate {

// ========== M2：C ABI 动态库插件（统一插件表） ==========

// 插件来源：builtin=内置适配器（随进程注册）；file=动态库加载。
enum class PluginSource {
    BUILTIN,
    FILE
};

// 统一插件表中的一条记录。加载失败的文件插件也入表（enabled=false + error），
// 让 UI 能看到「有个插件没加载起来」，而不是静默消失。
struct PluginRecord {
    std::string id;
    std::string name;
    std::string version;
    std::string description;
    std::string author;
    AigatePluginType type = AIGATE_PLUGIN_OTHER;
    PluginSource source = PluginSource::FILE;
    bool enabled = false;         // 加载成功默认 true；失败条目为 false
    std::string error;            // 加载/校验错误信息（空串=无错误）
    AigatePluginVTable vtable{};  // 函数指针快照（库句柄存活期间有效）
    std::string path;             // 文件插件的动态库路径（内置为空）
};

// 安全插件调用点快照（管线用）：锁内取快照、锁外调用，避免持锁执行插件代码。
struct SecurityHook {
    std::string id;
    AigatePluginDetectFn detectRequest;
};

// 响应侧安全插件调用点快照（M4：ResponseScanner 用，与请求侧同原则）
struct ResponseSecurityHook {
    std::string id;
    AigatePluginDetectFn detectResponse;
};

// 内置安全检测适配器的固定插件 id（aigate::SecurityDetector 的 C ABI 包装）。
inline constexpr const char* kBuiltinSecurityPluginId = "builtin-security-detector";
// 请求侧密码泄露提醒：异步审计、只生成脱敏告警，不参与同步 BLOCK 决策。
inline constexpr const char* kPasswordLeakAuditPluginId = "password-leak-audit";

// 插件管理器
class PluginManager {
public:
    static PluginManager& GetInstance();

    // 从动态库文件加载一个插件：dlopen/LoadLibrary → 取 aigate_plugin_init →
    // 校验 ABI 版本 → 入统一插件表。任何一步失败都把错误记入表（返回 false）。
    bool LoadPluginFromFile(const std::string& path);

    // 扫描目录加载全部插件（设备侧 .so / Windows .dll）。
    // 目录不存在返回 0（不算错误——插件目录本就允许为空）。
    int LoadPluginsFromDir(const std::string& dir);

    // 启用/禁用插件（含内置适配器）。id 不存在返回 false。
    bool SetPluginEnabled(const std::string& pluginId, bool enabled);

    // 查询插件是否启用（不存在的 id 视为 false——管线据此被禁用内置检测器）。
    bool IsPluginEnabled(const std::string& pluginId);

    // 统一插件表快照（id/name/version/type/enabled/source/error）。
    std::vector<PluginRecord> GetPlugins();

    // 已启用、来源为文件、实现了 detect_request 的 security 插件调用点快照。
    // 内置适配器不在其中——管线对内置检测器走直接调用（受 IsPluginEnabled 门控），
    // 避免同一检测跑两遍。
    std::vector<SecurityHook> GetEnabledSecurityHooks();

    // M4：已启用、来源为文件、实现了 detect_response 的 security 插件调用点快照
    //（ResponseScanner 用；内置适配器同样不在其中，理由同上）。
    std::vector<ResponseSecurityHook> GetEnabledResponseHooks();

private:
    PluginManager();
    ~PluginManager() = default;

    // 注册内置适配器（builtin-security-detector，包装 SecurityDetector）
    void RegisterBuiltinPluginsLocked();

    // 动态库句柄（跨平台封装，Windows=HMODULE，其余=void*）
    struct DynLib {
#ifdef _WIN32
        void* handle = nullptr;  // 实际是 HMODULE，头文件不引 windows.h 以保持可移植
#else
        void* handle = nullptr;
#endif
    };
    // 打开/取符号/关闭（实现见 .cpp，内部按平台走 LoadLibraryA/dlopen）
    static bool DynLibOpen(const std::string& path, DynLib& out, std::string& err);
    static void* DynLibSym(const DynLib& lib, const char* name);
    static void DynLibClose(DynLib& lib);

    // 统一插件表 + 动态库句柄表；读写均需持锁（NAPI 线程与转发工作线程都会访问）
    std::mutex pluginsMutex_;
    std::unordered_map<std::string, PluginRecord> plugins_;
    // 文件插件的库句柄：与插件表记录同生命周期，只有移除插件才可 dlclose
    //（vtable 里的函数指针指向库内代码，提前卸载即悬垂指针）。本期不提供卸载接口。
    std::unordered_map<std::string, DynLib> pluginLibs_;
};

} // namespace aigate

#endif // AIGATE_PLUGIN_MANAGER_H
