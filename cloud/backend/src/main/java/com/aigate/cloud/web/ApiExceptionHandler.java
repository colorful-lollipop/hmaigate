package com.aigate.cloud.web;

import java.time.Instant;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {
  @ExceptionHandler(ApiException.class)
  ResponseEntity<ErrorResponse> handleApi(ApiException exception) {
    return ResponseEntity.status(exception.getStatus())
        .body(new ErrorResponse(Instant.now(), exception.getStatus().value(), exception.getCode(), exception.getMessage()));
  }

  @ExceptionHandler(MethodArgumentNotValidException.class)
  ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException exception) {
    List<FieldError> errors = exception.getBindingResult().getFieldErrors();
    String message = errors.isEmpty() ? "请求参数不合法" : errors.getFirst().getField() + " " + errors.getFirst().getDefaultMessage();
    return ResponseEntity.badRequest()
        .body(new ErrorResponse(Instant.now(), 400, "validation_error", message));
  }

  @ExceptionHandler(HttpMessageNotReadableException.class)
  ResponseEntity<ErrorResponse> handleUnreadableBody(HttpMessageNotReadableException exception) {
    return ResponseEntity.badRequest()
        .body(new ErrorResponse(Instant.now(), 400, "invalid_json", "请求体不是合法 JSON"));
  }

  @ExceptionHandler(Exception.class)
  ResponseEntity<ErrorResponse> handleUnexpected(Exception exception) {
    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
        .body(new ErrorResponse(Instant.now(), 500, "internal_error", "服务内部错误"));
  }

  public record ErrorResponse(Instant timestamp, int status, String code, String message) {}
}
