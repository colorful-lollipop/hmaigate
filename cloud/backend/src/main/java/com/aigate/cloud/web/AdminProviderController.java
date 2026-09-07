package com.aigate.cloud.web;

import com.aigate.cloud.service.ProviderService;
import com.aigate.cloud.web.dto.ProviderRequest;
import com.aigate.cloud.web.dto.ProviderResponse;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/providers")
public class AdminProviderController {
  private final ProviderService service;

  public AdminProviderController(ProviderService service) {
    this.service = service;
  }

  @GetMapping
  List<ProviderResponse> list() {
    return service.list();
  }

  @PostMapping
  ResponseEntity<ProviderResponse> create(@Valid @RequestBody ProviderRequest request) {
    return ResponseEntity.status(HttpStatus.CREATED).body(service.create(request));
  }

  @PutMapping("/{id}")
  ProviderResponse update(@PathVariable String id, @Valid @RequestBody ProviderRequest request) {
    return service.update(IdParser.uuid(id), request);
  }

  @PostMapping("/{id}/publish")
  ProviderResponse publish(@PathVariable String id) {
    return service.publish(IdParser.uuid(id));
  }

  @PostMapping("/{id}/archive")
  ProviderResponse archive(@PathVariable String id) {
    return service.archive(IdParser.uuid(id));
  }
}
