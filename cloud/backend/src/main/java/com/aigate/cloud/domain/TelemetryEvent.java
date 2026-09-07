package com.aigate.cloud.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import java.time.Instant;
import java.util.UUID;

@Entity
public class TelemetryEvent {
  @Id
  @GeneratedValue
  private UUID id;

  @Column(nullable = false)
  private UUID deviceId;

  @Column(nullable = false, length = 64)
  private String eventType;

  @Column(nullable = false, length = 16)
  private String severity;

  @Column(length = 64)
  private String channelCode;

  @Column(length = 100)
  private String ruleId;

  private Instant occurredAt;

  @Column(nullable = false)
  private Instant receivedAt = Instant.now();

  @Lob
  private String attributesJson;

  public UUID getId() { return id; }
  public UUID getDeviceId() { return deviceId; }
  public void setDeviceId(UUID deviceId) { this.deviceId = deviceId; }
  public String getEventType() { return eventType; }
  public void setEventType(String eventType) { this.eventType = eventType; }
  public String getSeverity() { return severity; }
  public void setSeverity(String severity) { this.severity = severity; }
  public String getChannelCode() { return channelCode; }
  public void setChannelCode(String channelCode) { this.channelCode = channelCode; }
  public String getRuleId() { return ruleId; }
  public void setRuleId(String ruleId) { this.ruleId = ruleId; }
  public Instant getOccurredAt() { return occurredAt; }
  public void setOccurredAt(Instant occurredAt) { this.occurredAt = occurredAt; }
  public Instant getReceivedAt() { return receivedAt; }
  public void setReceivedAt(Instant receivedAt) { this.receivedAt = receivedAt; }
  public String getAttributesJson() { return attributesJson; }
  public void setAttributesJson(String attributesJson) { this.attributesJson = attributesJson; }
}
