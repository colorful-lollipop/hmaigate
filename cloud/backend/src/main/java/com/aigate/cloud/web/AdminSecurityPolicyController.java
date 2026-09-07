package com.aigate.cloud.web;

import com.aigate.cloud.service.SecurityPolicyService;
import com.aigate.cloud.web.dto.PolicyRequest;
import com.aigate.cloud.web.dto.PolicyResponse;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/security-policy")
public class AdminSecurityPolicyController {
  private final SecurityPolicyService service;

  public AdminSecurityPolicyController(SecurityPolicyService service) {
    this.service = service;
  }

  @GetMapping
  PolicyResponse current() {
    return service.current();
  }

  @PutMapping
  PolicyResponse updateDraft(@Valid @RequestBody PolicyRequest request) {
    return service.updateDraft(request);
  }

  @PostMapping("/publish")
  PolicyResponse publish() {
    return service.publish();
  }
}
