package com.aigate.cloud.repository;

import com.aigate.cloud.domain.SecurityPolicy;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SecurityPolicyRepository extends JpaRepository<SecurityPolicy, UUID> {
  Optional<SecurityPolicy> findFirstByOrderByCreatedAtAsc();
}
