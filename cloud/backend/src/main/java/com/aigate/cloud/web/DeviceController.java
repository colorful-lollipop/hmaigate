package com.aigate.cloud.web;

import com.aigate.cloud.domain.ManagedDevice;
import com.aigate.cloud.service.DeviceConfigurationService;
import com.aigate.cloud.service.DeviceKeyService;
import com.aigate.cloud.service.TelemetryService;
import com.aigate.cloud.web.dto.DeviceConfigurationResponse;
import com.aigate.cloud.web.dto.TelemetryRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/device")
public class DeviceController {
  private final DeviceKeyService keys;
  private final DeviceConfigurationService configurations;
  private final TelemetryService telemetry;

  public DeviceController(DeviceKeyService keys, DeviceConfigurationService configurations, TelemetryService telemetry) {
    this.keys = keys;
    this.configurations = configurations;
    this.telemetry = telemetry;
  }

  @GetMapping("/config")
  ResponseEntity<DeviceConfigurationResponse> config(
      @RequestHeader("X-AIGate-Device-Key") String key,
      @RequestHeader(value = "If-None-Match", required = false) String ifNoneMatch) {
    keys.authenticate(key);
    DeviceConfigurationResponse response = configurations.current();
    // providerPresets 替代早期的 providers 目录，使用新命名空间使旧端 ETag 不会错误命中 304。
    String eTag = "\"aigate-preset-config-v2-" + response.configVersion() + "\"";
    if (ifNoneMatch != null && (ifNoneMatch.contains(eTag) || ifNoneMatch.contains("*"))) {
      return ResponseEntity.status(HttpStatus.NOT_MODIFIED).eTag(eTag).build();
    }
    return ResponseEntity.ok().eTag(eTag).body(response);
  }

  @PostMapping("/telemetry")
  ResponseEntity<Void> telemetry(@RequestHeader("X-AIGate-Device-Key") String key,
      @Valid @RequestBody TelemetryRequest request) {
    ManagedDevice device = keys.authenticate(key);
    telemetry.record(device, request);
    return ResponseEntity.accepted().build();
  }
}
