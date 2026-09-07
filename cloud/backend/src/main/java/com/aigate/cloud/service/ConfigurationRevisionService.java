package com.aigate.cloud.service;

import com.aigate.cloud.domain.ConfigurationRevision;
import com.aigate.cloud.repository.ConfigurationRevisionRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ConfigurationRevisionService {
  private final ConfigurationRevisionRepository repository;

  public ConfigurationRevisionService(ConfigurationRevisionRepository repository) {
    this.repository = repository;
  }

  @Transactional
  public synchronized long nextPublishedVersion() {
    ConfigurationRevision revision = repository.findById(1).orElseGet(ConfigurationRevision::new);
    long next = revision.getCurrentVersion() + 1;
    revision.setCurrentVersion(next);
    repository.save(revision);
    return next;
  }

  @Transactional(readOnly = true)
  public long currentVersion() {
    return repository.findById(1).map(ConfigurationRevision::getCurrentVersion).orElse(0L);
  }
}
