package com.aigate.cloud.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;

@Entity
public class ConfigurationRevision {
  @Id
  private Integer id = 1;
  private long currentVersion = 1;

  public Integer getId() { return id; }
  public long getCurrentVersion() { return currentVersion; }
  public void setCurrentVersion(long currentVersion) { this.currentVersion = currentVersion; }
}
