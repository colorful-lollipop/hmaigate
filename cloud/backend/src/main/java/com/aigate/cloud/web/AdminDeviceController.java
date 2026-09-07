package com.aigate.cloud.web;

import com.aigate.cloud.service.DeviceKeyService;
import com.aigate.cloud.web.dto.DeviceCreateRequest;
import com.aigate.cloud.web.dto.DeviceIssueResponse;
import com.aigate.cloud.web.dto.DeviceResponse;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/devices")
public class AdminDeviceController {
  private final DeviceKeyService service;

  public AdminDeviceController(DeviceKeyService service) {
    this.service = service;
  }

  @GetMapping
  List<DeviceResponse> list() {
    return service.list();
  }

  @PostMapping
  ResponseEntity<DeviceIssueResponse> create(@Valid @RequestBody DeviceCreateRequest request) {
    return ResponseEntity.status(HttpStatus.CREATED).body(service.create(request.displayName()));
  }

  @PostMapping("/{id}/rotate-key")
  DeviceIssueResponse rotate(@PathVariable String id) {
    return service.rotate(IdParser.uuid(id));
  }

  @PostMapping("/{id}/revoke")
  DeviceResponse revoke(@PathVariable String id) {
    return service.revoke(IdParser.uuid(id));
  }
}
