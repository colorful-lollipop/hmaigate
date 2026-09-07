package com.aigate.cloud.web;

import com.aigate.cloud.service.ChannelService;
import com.aigate.cloud.web.dto.ChannelRequest;
import com.aigate.cloud.web.dto.ChannelResponse;
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
@RequestMapping("/api/v1/admin/channels")
public class AdminChannelController {
  private final ChannelService service;

  public AdminChannelController(ChannelService service) {
    this.service = service;
  }

  @GetMapping
  List<ChannelResponse> list() {
    return service.list();
  }

  @PostMapping
  ResponseEntity<ChannelResponse> create(@Valid @RequestBody ChannelRequest request) {
    return ResponseEntity.status(HttpStatus.CREATED).body(service.create(request));
  }

  @PutMapping("/{id}")
  ChannelResponse update(@PathVariable String id, @Valid @RequestBody ChannelRequest request) {
    return service.update(IdParser.uuid(id), request);
  }

  @PostMapping("/{id}/publish")
  ChannelResponse publish(@PathVariable String id) {
    return service.publish(IdParser.uuid(id));
  }

  @PostMapping("/{id}/archive")
  ChannelResponse archive(@PathVariable String id) {
    return service.archive(IdParser.uuid(id));
  }
}
