// json_scan.h —— 手写最小 JSON 扫描器（header-only，R2 公共抽取）
//
// 不引入 JSON 库的理由（沿用 router.cpp 原有注释）：消费的 JSON（M3 路由规则表、
// M4 规则自定义词条）结构固定且由 ArkTS 侧按契约生成、字段集合封闭，为它们引入
// 完整 JSON 库是多余的体积与依赖；大 body 场景也要避免通用解析器的开销。
// 解析是严格的：任何结构性错误让调用方整体失败（路由表不动旧表、词条不增删），
// 未知字段一律跳过（向后兼容）。
#ifndef HMSEC_JSON_SCAN_H
#define HMSEC_JSON_SCAN_H

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

namespace hmsec {

// 最小 JSON 游标：只支持字符串/整数/逐值跳过/字符串数组，够契约 JSON 用。
struct JsonCursor {
  const char* s;
  size_t n;
  size_t p = 0;

  void SkipWs() {
    while (p < n && (s[p] == ' ' || s[p] == '\t' || s[p] == '\n' || s[p] == '\r')) ++p;
  }
  bool Eof() {
    SkipWs();
    return p >= n;
  }
  bool Consume(char c) {
    SkipWs();
    if (p < n && s[p] == c) {
      ++p;
      return true;
    }
    return false;
  }
  bool ParseString(std::string& out) {
    SkipWs();
    if (p >= n || s[p] != '"') return false;
    ++p;
    out.clear();
    while (p < n) {
      char c = s[p++];
      if (c == '"') return true;
      if (c == '\\') {
        if (p >= n) return false;
        char e = s[p++];
        switch (e) {
          case '"': out += '"'; break;
          case '\\': out += '\\'; break;
          case '/': out += '/'; break;
          case 'n': out += '\n'; break;
          case 't': out += '\t'; break;
          case 'r': out += '\r'; break;
          case 'b': out += '\b'; break;
          case 'f': out += '\f'; break;
          case 'u': {
            // \uXXXX：ASCII 范围内如实解码，其余降级为 '?'（不因此中断解析）。
            // 中文字段以 UTF-8 原始字节出现在 JSON 里、不经 \u 转义，降级不影响使用。
            if (p + 4 > n) return false;
            int v = 0;
            for (int i = 0; i < 4; ++i) {
              char h = s[p++];
              v <<= 4;
              if (h >= '0' && h <= '9') v += h - '0';
              else if (h >= 'a' && h <= 'f') v += h - 'a' + 10;
              else if (h >= 'A' && h <= 'F') v += h - 'A' + 10;
              else return false;
            }
            out += (v < 0x80) ? static_cast<char>(v) : '?';
            break;
          }
          default: return false;
        }
      } else {
        out += c;
      }
    }
    return false;  // 字符串未闭合
  }
  bool ParseInt(long& out) {
    SkipWs();
    size_t b = p;
    if (p < n && (s[p] == '-' || s[p] == '+')) ++p;
    bool any = false;
    while (p < n && s[p] >= '0' && s[p] <= '9') {
      ++p;
      any = true;
    }
    if (!any) return false;
    out = std::atol(std::string(s + b, p - b).c_str());
    return true;
  }
  // 跳过任意值（未知字段用）：字符串/数字/布尔/null/嵌套对象/数组。
  bool SkipValue() {
    SkipWs();
    if (p >= n) return false;
    char c = s[p];
    if (c == '"') {
      std::string tmp;
      return ParseString(tmp);
    }
    if (c == '{') {
      ++p;
      if (Consume('}')) return true;
      while (true) {
        std::string k;
        if (!ParseString(k)) return false;
        if (!Consume(':')) return false;
        if (!SkipValue()) return false;
        if (Consume(',')) continue;
        return Consume('}');
      }
    }
    if (c == '[') {
      ++p;
      if (Consume(']')) return true;
      while (true) {
        if (!SkipValue()) return false;
        if (Consume(',')) continue;
        return Consume(']');
      }
    }
    // 数字 / true / false / null：扫到分隔符为止（跳过场景无需区分）
    size_t b = p;
    while (p < n &&
           (std::isalnum(static_cast<unsigned char>(s[p])) || s[p] == '.' ||
            s[p] == '-' || s[p] == '+')) {
      ++p;
    }
    return p > b;
  }
  // 解析字符串数组（M4 规则自定义词条用）：["a","b",...]
  bool ParseStringArray(std::vector<std::string>& out) {
    if (!Consume('[')) return false;
    out.clear();
    if (Consume(']')) return true;
    while (true) {
      std::string item;
      if (!ParseString(item)) return false;
      out.push_back(item);
      if (Consume(',')) continue;
      return Consume(']');
    }
  }
};

// JSON 字符串转义（插件名/错误信息/阻断原因可能含引号、反斜杠与控制字符，
// 要嵌进 JSON 输出或 SSE 错误事件）
inline std::string JsonEscape(const std::string& s) {
  std::string out;
  out.reserve(s.size() + 8);
  for (char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          char buf[8];
          snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out += c;
        }
    }
  }
  return out;
}

}  // namespace hmsec

#endif  // HMSEC_JSON_SCAN_H
