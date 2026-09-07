package com.aigate.cloud.service;

import com.aigate.cloud.domain.SecurityPolicy;
import com.aigate.cloud.repository.SecurityPolicyRepository;
import com.aigate.cloud.web.ApiException;
import com.aigate.cloud.web.dto.PolicyRequest;
import com.aigate.cloud.web.dto.PolicyResponse;
import java.time.Instant;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SecurityPolicyService {
  public static final String DEFAULT_POLICY = """
      {"schemaVersion":1,"requestScanEnabled":true,"responseScanEnabled":true,"rules":[
        {"ruleId":"password_leak","action":"BLOCK","keywords":[],"patterns":[]},
        {"ruleId":"prompt_injection","action":"BLOCK","keywords":[],"patterns":[]},
        {"ruleId":"context_injection","action":"WARN","keywords":[],"patterns":[]},
        {"ruleId":"malicious_tool_use","action":"BLOCK","keywords":[],"patterns":[]}
      ]}
      """;

  private final SecurityPolicyRepository repository;
  private final ConfigurationRevisionService revisions;
  private final JsonGuard json;

  public SecurityPolicyService(SecurityPolicyRepository repository, ConfigurationRevisionService revisions, JsonGuard json) {
    this.repository = repository;
    this.revisions = revisions;
    this.json = json;
  }

  @Transactional(readOnly = true)
  public PolicyResponse current() {
    return response(find());
  }

  @Transactional
  public PolicyResponse updateDraft(PolicyRequest request) {
    json.requirePolicy(request.policy());
    SecurityPolicy policy = find();
    policy.setDraftJson(json.write(request.policy()));
    policy.setDraftVersion(policy.getDraftVersion() + 1);
    policy.setUpdatedAt(Instant.now());
    return response(repository.save(policy));
  }

  @Transactional
  public PolicyResponse publish() {
    SecurityPolicy policy = find();
    policy.setPublishedJson(policy.getDraftJson());
    policy.setPublishedVersion(revisions.nextPublishedVersion());
    policy.setPublishedAt(Instant.now());
    policy.setUpdatedAt(Instant.now());
    return response(repository.save(policy));
  }

  private SecurityPolicy find() {
    return repository.findFirstByOrderByCreatedAtAsc()
        .orElseThrow(() -> ApiException.notFound("默认安全策略尚未初始化"));
  }

  private PolicyResponse response(SecurityPolicy policy) {
    return new PolicyResponse(json.read(policy.getDraftJson()), policy.getDraftVersion(), policy.getPublishedVersion(),
        policy.getPublishedAt(), policy.getUpdatedAt());
  }
}
