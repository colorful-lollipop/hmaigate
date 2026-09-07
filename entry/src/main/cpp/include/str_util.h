// str_util.h —— 字符串小工具（header-only，R2 公共抽取）
//
// 合并 hmsec::ToLower（原 upstream.cpp）与 security_detector.cpp 里四处
// 重复的小写化 lambda：大小写不敏感匹配在两边的检测/解析路径都需要。
#ifndef HMSEC_STR_UTIL_H
#define HMSEC_STR_UTIL_H

#include <algorithm>
#include <cctype>
#include <string>

namespace hmsec {

inline std::string ToLower(const std::string& s) {
  std::string out = s;
  std::transform(out.begin(), out.end(), out.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return out;
}

}  // namespace hmsec

#endif  // HMSEC_STR_UTIL_H
