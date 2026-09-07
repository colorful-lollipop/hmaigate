/* aigate_plugin.h —— AIGate 动态库插件的纯 C ABI（M2）
 *
 * 为什么用纯 C ABI 而不是 C++ 接口跨动态库传递：
 * C++ 的符号名修饰（name mangling）、类布局、std::string 等标准库类型的 ABI
 * 在不同编译器/编译选项之间不稳定——宿主（BiSheng/clang）与第三方插件若用
 * 不同工具链构建，直接跨边界传 C++ 对象几乎必然崩溃或未定义行为。
 * 纯 C 接口（POD 结构 + 函数指针表 + 唯一的导出入口符号）在所有平台上
 * ABI 都是稳定的，这也是 Lua/NGINX/WinAmp 等插件体系的通行做法。
 *
 * 插件开发约定：
 *  - 插件是独立编译的动态库（鸿蒙设备侧 .so，宿主侧 Windows 为 .dll）；
 *    只需包含本头文件，不依赖 AIGate 的任何其他头文件或符号。
 *  - 插件必须且只需导出一个符号：aigate_plugin_init（见文件末尾）。
 *  - 宿主 dlopen/LoadLibrary 后调用该入口，校验 abi_version，
 *    与 AIGATE_PLUGIN_API_VERSION 不一致即拒绝加载（结构布局可能已变）。
 *
 * 鸿蒙现实约束：第三方应用只能 dlopen 自己沙箱内/随包发货的 .so，
 * 因此插件目录固定为应用 filesDir/plugins（由 ArkTS 侧传入），
 * 不支持加载用户任意路径的动态库。
 */
#ifndef AIGATE_PLUGIN_H
#define AIGATE_PLUGIN_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ABI 版本：结构布局或语义有任何不兼容变更时必须 +1，宿主按此拒绝旧插件。 */
#define AIGATE_PLUGIN_API_VERSION 1u

/* 插件导出入口符号名（宿主侧 GetProcAddress/dlsym 按此查找）。 */
#define AIGATE_PLUGIN_ENTRY_SYMBOL "aigate_plugin_init"

/* 插件导出符号的可见性宏：Windows 需要 __declspec(dllexport)，
 * 其余平台默认可见性即可（显式标注以防插件用 -fvisibility=hidden 构建）。 */
#if defined(_WIN32)
#define AIGATE_PLUGIN_EXPORT __declspec(dllexport)
#else
#define AIGATE_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

/* 插件类型：决定宿主在哪个环节调用它。 */
typedef enum AigatePluginType {
    AIGATE_PLUGIN_SECURITY = 0,  /* 安全检测：detect_request/detect_response */
    AIGATE_PLUGIN_TRANSFORM = 1, /* 内容转换：transform_request/transform_response（M3 接线） */
    AIGATE_PLUGIN_OTHER = 2
} AigatePluginType;

/* 检测结论（detect_request/detect_response 的返回值）。 */
typedef enum AigateDetectVerdict {
    AIGATE_DETECT_PASS = 0,  /* 放行 */
    AIGATE_DETECT_WARN = 1,  /* 警告：记录原因但仍放行 */
    AIGATE_DETECT_BLOCK = 2  /* 阻断：宿主拦截该请求/响应 */
} AigateDetectVerdict;

/* 插件元信息。所有字符串由插件持有（静态存储期），宿主只读不释放。
 * abi_version 必须填插件编译时的 AIGATE_PLUGIN_API_VERSION。 */
typedef struct AigatePluginInfo {
    uint32_t abi_version;
    const char* id;          /* 全局唯一，如 "my-prompt-guard" */
    const char* name;        /* 展示名 */
    const char* version;     /* 插件自身版本，如 "1.0.0" */
    const char* description;
    const char* author;
    AigatePluginType type;
} AigatePluginInfo;

/* 检测/转换函数签名：
 *   body        —— 输入内容（当前只有请求/响应体，刻意不含请求头）
 *   result      —— 插件写出原因/结论的缓冲区（可为空串）
 *   result_size —— result 缓冲区大小，插件写入不得越界（建议 snprintf）
 * detect_* 返回 AigateDetectVerdict；transform_* 返回 0 成功、非 0 失败。
 * 任何函数指针都允许为 NULL，表示该插件不实现对应能力。 */
typedef int (*AigatePluginDetectFn)(const char* body, char* result, size_t result_size);
typedef int (*AigatePluginTransformFn)(const char* input, char* result, size_t result_size);

/* 插件函数表：宿主拿到后按类型挑选调用。 */
typedef struct AigatePluginVTable {
    AigatePluginDetectFn detect_request;      /* 请求体检测（已在转发管线接线） */
    AigatePluginDetectFn detect_response;     /* 响应体检测（M4 已由 ResponseScanner 接线） */
    AigatePluginTransformFn transform_request;  /* 请求转换（M3 接线，ABI 先留位） */
    AigatePluginTransformFn transform_response; /* 响应转换（M3 接线，ABI 先留位） */
} AigatePluginVTable;

/* 插件唯一入口：宿主 dlopen 后调用。
 * 插件返回静态存储期的 AigatePluginInfo*（NULL 表示初始化失败），
 * 并经 vtable_out 输出函数表指针（同样为静态存储期，宿主只读不释放）。 */
typedef const AigatePluginInfo* (*AigatePluginInitFn)(const AigatePluginVTable** vtable_out);

/* 插件侧实现模板：
 *
 *   static const AigatePluginVTable kVTable = { my_detect_request, NULL, NULL, NULL };
 *   static const AigatePluginInfo kInfo = {
 *       AIGATE_PLUGIN_API_VERSION, "my-plugin", "我的插件", "1.0.0",
 *       "描述", "作者", AIGATE_PLUGIN_SECURITY
 *   };
 *   AIGATE_PLUGIN_EXPORT const AigatePluginInfo* aigate_plugin_init(
 *       const AigatePluginVTable** vtable_out) {
 *       if (vtable_out) *vtable_out = &kVTable;
 *       return &kInfo;
 *   }
 */

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* AIGATE_PLUGIN_H */
