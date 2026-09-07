// hm_test.h —— 极简测试辅助（仅用于宿主侧 C++ 单元测试，不参与设备构建）
#pragma once

#include <cstdio>
#include <string>

namespace hmtest {

inline int& Fails() {
  static int f = 0;
  return f;
}
inline int& Passes() {
  static int p = 0;
  return p;
}

inline void EqStr(const char* file, int line, const std::string& a, const std::string& b,
                  const char* ea, const char* eb) {
  if (a == b) {
    Passes()++;
  } else {
    Fails()++;
    printf("FAIL %s:%d  %s == %s\n  got: [%s]\n  exp: [%s]\n", file, line, ea, eb, a.c_str(), b.c_str());
  }
}

inline void EqBool(const char* file, int line, bool a, bool b, const char* ea, const char* eb) {
  if (a == b) {
    Passes()++;
  } else {
    Fails()++;
    printf("FAIL %s:%d  %s == %s  got=%d exp=%d\n", file, line, ea, eb, a, b);
  }
}

inline void EqInt(const char* file, int line, long long a, long long b, const char* ea, const char* eb) {
  if (a == b) {
    Passes()++;
  } else {
    Fails()++;
    printf("FAIL %s:%d  %s == %s  got=%lld exp=%lld\n", file, line, ea, eb, a, b);
  }
}

}  // namespace hmtest

#define EQ_STR(a, b) hmtest::EqStr(__FILE__, __LINE__, (a), (b), #a, #b)
#define EQ_BOOL(a, b) hmtest::EqBool(__FILE__, __LINE__, (a), (b), #a, #b)
#define EQ_INT(a, b) hmtest::EqInt(__FILE__, __LINE__, static_cast<long long>(a), static_cast<long long>(b), #a, #b)

#define RUN_TEST(fn)                                                         \
  do {                                                                       \
    printf("[ RUN      ] %s\n", #fn);                                        \
    int before = hmtest::Fails();                                            \
    fn();                                                                    \
    if (hmtest::Fails() == before) printf("[       OK ] %s\n", #fn);        \
  } while (0)

#define SUMMARY()                                                           \
  do {                                                                       \
    printf("\n==== %d passed, %d failed ====\n", hmtest::Passes(), hmtest::Fails()); \
    return hmtest::Fails() == 0 ? 0 : 1;                                    \
  } while (0)
