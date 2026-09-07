package com.aigate.cloud.web;

import java.util.UUID;

final class IdParser {
  private IdParser() {}

  static UUID uuid(String value) {
    try {
      return UUID.fromString(value);
    } catch (IllegalArgumentException exception) {
      throw ApiException.badRequest("资源 ID 格式不正确");
    }
  }
}
