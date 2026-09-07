package com.aigate.cloud.web;

import com.aigate.cloud.service.TelemetryService;
import com.aigate.cloud.web.dto.OverviewResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/overview")
public class AdminOverviewController {
  private final TelemetryService service;

  public AdminOverviewController(TelemetryService service) {
    this.service = service;
  }

  @GetMapping
  OverviewResponse overview() {
    return service.overview();
  }
}
