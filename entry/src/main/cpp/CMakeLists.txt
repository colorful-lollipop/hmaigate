# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(aigate)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

# ---- mbedtls：cpp-httplib 的 TLS 后端（CPPHTTPLIB_MBEDTLS_SUPPORT）----
# 上游 TLS 需要能解析真实服务器证书的完整 TLS/X.509 实现；httplib 的 mbedTLS
# 后端按 MBEDTLS_VERSION_MAJOR 自适配 3.x/4.x（本仓库 vendored 3.6）。
set(MBEDTLS_ROOT ${NATIVERENDER_ROOT_PATH}/third_party/mbedtls)
file(GLOB MBEDTLS_SRCS CONFIGURE_DEPENDS ${MBEDTLS_ROOT}/library/*.c)
add_library(mbedtls STATIC ${MBEDTLS_SRCS})
target_include_directories(mbedtls PUBLIC
    ${MBEDTLS_ROOT}/include       # mbedtls/*.h、psa/*.h、mbedtls_config.h
    ${MBEDTLS_ROOT}/library)      # 内部头（common.h 等）

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include
                    ${NATIVERENDER_ROOT_PATH}/third_party)

add_library(entry SHARED
    # NAPI 层
    napi/napi_proxy.cpp

    # 代理核心
    core/proxy/proxy_engine.cpp      # 对外门面（薄外壳）
    core/proxy/proxy_server.cpp      # httplib 转发实现（pump 线程桥接 + 连接生命周期）
    core/proxy/request_pipeline.cpp  # 转发管线：路由/请求体安全检测/请求构造（有宿主单测）
    core/proxy/upstream.cpp          # 纯逻辑：URL 解析/拼接（有宿主单测）
    core/proxy/router.cpp            # M3 规则路由表（手写最小 JSON 解析，有宿主单测）

    # 协议识别
    core/protocol/protocol_adapter.cpp  # M3 多 LLM 协议识别 + 元数据提取（有宿主单测）

    # 安全检测 / 插件
    core/security/security_detector.cpp
    core/security/response_scanner.cpp  # M4 响应流式安全扫描（SSE 事件边界切分，有宿主单测）
    core/security/password_leak_audit.cpp  # 请求侧密码泄露提醒（异步脱敏审计）
    core/plugin/plugin_manager.cpp
)

# cpp-httplib：启用 mbedTLS 后端（解析真实 https 上游证书）。
# 单头库无需额外源文件；本构建未编 zlib/brotli，代理侧不收压缩响应
#（转发头里已剥 Accept-Encoding，见 proxy_server.cpp）。
target_compile_definitions(entry PUBLIC
    CPPHTTPLIB_MBEDTLS_SUPPORT)

target_link_libraries(entry PUBLIC libace_napi.z.so pthread mbedtls libhilog_ndk.z.so)
