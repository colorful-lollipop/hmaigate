package com.aigate.cloud.web;

import org.springframework.http.HttpStatus;

public class ApiException extends RuntimeException {
  private final HttpStatus status;
  private final String code;

  public ApiException(HttpStatus status, String code, String message) {
    super(message);
    this.status = status;
    this.code = code;
  }

  public HttpStatus getStatus() { return status; }
  public String getCode() { return code; }

  public static ApiException badRequest(String message) {
    return new ApiException(HttpStatus.BAD_REQUEST, "bad_request", message);
  }

  public static ApiException notFound(String message) {
    return new ApiException(HttpStatus.NOT_FOUND, "not_found", message);
  }

  public static ApiException conflict(String message) {
    return new ApiException(HttpStatus.CONFLICT, "conflict", message);
  }

  public static ApiException forbidden(String message) {
    return new ApiException(HttpStatus.FORBIDDEN, "forbidden", message);
  }
}
