package com.aigate.cloud.service;

import com.aigate.cloud.domain.ManagedDevice;
import com.aigate.cloud.domain.TelemetryEvent;
import com.aigate.cloud.repository.ChannelRepository;
import com.aigate.cloud.repository.ManagedDeviceRepository;
import com.aigate.cloud.repository.ProviderRepository;
import com.aigate.cloud.repository.TelemetryEventRepository;
import com.aigate.cloud.web.dto.OverviewResponse;
import com.aigate.cloud.web.dto.RecentEventResponse;
import com.aigate.cloud.web.dto.TelemetryRequest;
import java.time.Instant;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TelemetryService {
  private final TelemetryEventRepository events;
  private final ChannelRepository channels;
  private final ProviderRepository providers;
  private final ManagedDeviceRepository devices;
  private final ConfigurationRevisionService revisions;
  private final JsonGuard json;

  public TelemetryService(TelemetryEventRepository events, ChannelRepository channels, ProviderRepository providers,
      ManagedDeviceRepository devices, ConfigurationRevisionService revisions, JsonGuard json) {
    this.events = events;
    this.channels = channels;
    this.providers = providers;
    this.devices = devices;
    this.revisions = revisions;
    this.json = json;
  }

  @Transactional
  public void record(ManagedDevice device, TelemetryRequest request) {
    json.requireTelemetryAttributes(request.attributes());
    TelemetryEvent event = new TelemetryEvent();
    event.setDeviceId(device.getId());
    event.setEventType(request.eventType());
    event.setSeverity(request.severity());
    event.setChannelCode(ChannelService.blankToNull(request.channelCode()));
    event.setRuleId(ChannelService.blankToNull(request.ruleId()));
    event.setOccurredAt(request.occurredAt());
    event.setAttributesJson(request.attributes() == null || request.attributes().isNull() ? null : json.write(request.attributes()));
    events.save(event);
  }

  @Transactional(readOnly = true)
  public OverviewResponse overview() {
    Instant since = Instant.now().minusSeconds(24 * 60 * 60);
    return new OverviewResponse(revisions.currentVersion(),
        channels.findByStateAndEnabledTrueOrderByClientTypeAscDisplayNameAsc(com.aigate.cloud.domain.ChannelState.PUBLISHED).size(),
        providers.findByStateAndEnabledTrueOrderByChannelCodeAscDisplayNameAsc(com.aigate.cloud.domain.ChannelState.PUBLISHED).size(),
        devices.countByStatus(com.aigate.cloud.domain.DeviceStatus.ACTIVE),
        events.countByReceivedAtAfter(since), events.countByReceivedAtAfterAndSeverityIgnoreCase(since, "BLOCK"),
        events.findTop12ByOrderByReceivedAtDesc().stream().map(event -> new RecentEventResponse(
            event.getId().toString(), event.getDeviceId().toString(), event.getEventType(), event.getSeverity(),
            event.getChannelCode(), event.getRuleId(), event.getOccurredAt(), event.getReceivedAt())).toList());
  }
}
