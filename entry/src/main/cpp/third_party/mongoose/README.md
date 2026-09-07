# mongoose (vendored)

Single-file amalgamation of the [mongoose](https://github.com/cesanta/mongoose)
embedded network library, used by the C++ forward proxy for high-throughput,
low-memory HTTP(S) relaying to upstream LLM providers.

- **Source:** `cesanta/mongoose`, `master` branch (**MG_VERSION 7.22** snapshot)
- **Files:** `mongoose.h`, `mongoose.c` (amalgamated, built-in TLS 1.3 stack)
- **Fetched:** 2025-07-09 (via jsDelivr CDN mirror of GitHub master)
- **License:** GPLv2 / commercial dual-license (see header of each file)

> Note: 7.22 renamed several members vs. older docs — `mg_str.buf` (was `ptr`),
> `MG_MAX_HTTP_HEADERS` (was `MG_MAX_HEADERS`), `mg_tls_opts.name` (was
> `servername`, now an `mg_str`). `proxy_server.cpp` targets this API.

## Build integration

Compiled as part of `libentry.so` via `entry/src/main/cpp/CMakeLists.txt`:

- `MG_TLS=MG_TLS_BUILTIN` — built-in TLS, no external mbedtls dependency.
- `MG_ENABLE_LOG=0` — suppress log noise.
- Links `pthread` (POSIX sockets + `std::thread`).

To update, re-download both files from upstream master (or pin a release tag for
reproducibility) and replace them in place.
