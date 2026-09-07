package com.aigate.cloud.service;

import com.aigate.cloud.web.ApiException;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Iterator;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;

/** 防止运营配置或遥测意外成为真实凭据的存储通道。 */
@Service
public class JsonGuard {
  private static final int CONFIG_MAX_BYTES = 64 * 1024;
  private static final int TELEMETRY_MAX_BYTES = 16 * 1024;
  private static final Pattern KNOWN_SECRET = Pattern.compile(
      "(?i)(sk-[a-z0-9_-]{16,}|AIza[a-z0-9_-]{20,}|bearer\\s+[a-z0-9._-]{16,})");
  private static final Set<String> ACTIONS = Set.of("BLOCK", "WARN", "ALLOW");
  private final ObjectMapper objectMapper;

  public JsonGuard(ObjectMapper objectMapper) {
    this.objectMapper = objectMapper;
  }

  public void requireChannelConfiguration(JsonNode configuration) {
    requireObject(configuration, "渠道配置必须是 JSON 对象", CONFIG_MAX_BYTES);
    assertNoCredential(configuration);
  }

  public void requireProviderConfiguration(JsonNode configuration) {
    requireObject(configuration, "供应商配置必须是 JSON 对象", CONFIG_MAX_BYTES);
    assertNoCredential(configuration);
  }

  public void requireTelemetryAttributes(JsonNode attributes) {
    if (attributes == null || attributes.isNull()) {
      return;
    }
    ensureSerializedSize(attributes, TELEMETRY_MAX_BYTES);
    assertNoCredential(attributes);
  }

  public void requirePolicy(JsonNode policy) {
    requireObject(policy, "安全策略必须是 JSON 对象", CONFIG_MAX_BYTES);
    if (!policy.path("schemaVersion").canConvertToInt() || policy.path("schemaVersion").asInt() != 1) {
      throw ApiException.badRequest("安全策略 schemaVersion 必须为 1");
    }
    if (!policy.path("requestScanEnabled").isBoolean() || !policy.path("responseScanEnabled").isBoolean()) {
      throw ApiException.badRequest("安全策略必须声明请求和响应扫描开关");
    }
    JsonNode rules = policy.path("rules");
    if (!rules.isArray() || rules.size() > 100) {
      throw ApiException.badRequest("安全策略 rules 必须为不超过 100 条的数组");
    }
    for (JsonNode rule : rules) {
      String ruleId = rule.path("ruleId").asText();
      String action = rule.path("action").asText();
      if (!rule.isObject() || !ruleId.matches("^[a-z][a-z0-9_-]{1,64}$")) {
        throw ApiException.badRequest("安全规则 ruleId 格式不合法");
      }
      if (!ACTIONS.contains(action)) {
        throw ApiException.badRequest("安全规则 action 必须为 BLOCK、WARN 或 ALLOW");
      }
      requireStringArray(rule.path("keywords"), "keywords", 100, 256);
      requireStringArray(rule.path("patterns"), "patterns", 100, 512);
    }
    assertNoCredential(policy);
  }

  public String write(JsonNode node) {
    try {
      return objectMapper.writeValueAsString(node);
    } catch (JsonProcessingException exception) {
      throw ApiException.badRequest("JSON 序列化失败");
    }
  }

  public JsonNode read(String json) {
    try {
      return objectMapper.readTree(json);
    } catch (JsonProcessingException exception) {
      throw new IllegalStateException("数据库中的 JSON 配置已损坏", exception);
    }
  }

  private void requireObject(JsonNode node, String message, int maxBytes) {
    if (node == null || !node.isObject()) {
      throw ApiException.badRequest(message);
    }
    ensureSerializedSize(node, maxBytes);
  }

  private void ensureSerializedSize(JsonNode node, int maxBytes) {
    if (write(node).length() > maxBytes) {
      throw ApiException.badRequest("JSON 内容超过大小限制");
    }
  }

  private void requireStringArray(JsonNode node, String field, int maxItems, int maxItemLength) {
    if (!node.isMissingNode() && !node.isArray()) {
      throw ApiException.badRequest(field + " 必须是字符串数组");
    }
    if (node.isArray() && node.size() > maxItems) {
      throw ApiException.badRequest(field + " 条目过多");
    }
    for (JsonNode item : node) {
      if (!item.isTextual() || item.textValue().length() > maxItemLength) {
        throw ApiException.badRequest(field + " 包含不合法条目");
      }
    }
  }

  private void assertNoCredential(JsonNode node) {
    if (node.isTextual() && KNOWN_SECRET.matcher(node.textValue()).find()) {
      throw ApiException.badRequest("配置或遥测中不能出现真实凭据");
    }
    if (node.isObject()) {
      Iterator<Map.Entry<String, JsonNode>> fields = node.fields();
      while (fields.hasNext()) {
        Map.Entry<String, JsonNode> field = fields.next();
        JsonNode value = field.getValue();
        if (isSensitiveField(field.getKey()) && value.isTextual() && !isSafePlaceholder(value.textValue())) {
          throw ApiException.badRequest("字段 " + field.getKey() + " 只能使用空值或 {{placeholder}}，不能保存真实凭据");
        }
        assertNoCredential(value);
      }
      return;
    }
    if (node.isArray()) {
      for (JsonNode item : node) {
        assertNoCredential(item);
      }
    }
  }

  private boolean isSensitiveField(String fieldName) {
    String normalized = fieldName.toLowerCase(Locale.ROOT).replace("_", "").replace("-", "");
    if (normalized.endsWith("field") || normalized.endsWith("placeholder") || normalized.endsWith("name")) {
      return false;
    }
    return normalized.contains("apikey") || normalized.contains("token") || normalized.contains("secret")
        || normalized.contains("password") || normalized.contains("authorization");
  }

  private boolean isSafePlaceholder(String value) {
    return value.isBlank() || value.matches("^\\{\\{[a-zA-Z][a-zA-Z0-9_.-]{0,63}\\}\\}$");
  }
}
