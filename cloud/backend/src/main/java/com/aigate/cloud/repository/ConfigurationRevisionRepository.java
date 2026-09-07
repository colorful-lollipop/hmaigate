package com.aigate.cloud.repository;

import com.aigate.cloud.domain.ConfigurationRevision;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ConfigurationRevisionRepository extends JpaRepository<ConfigurationRevision, Integer> {}
