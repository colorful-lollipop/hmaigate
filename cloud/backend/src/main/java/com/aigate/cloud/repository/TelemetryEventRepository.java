package com.aigate.cloud.repository;

import com.aigate.cloud.domain.TelemetryEvent;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TelemetryEventRepository extends JpaRepository<TelemetryEvent, UUID> {
  long countByReceivedAtAfter(Instant since);
  long countByReceivedAtAfterAndSeverityIgnoreCase(Instant since, String severity);
  List<TelemetryEvent> findTop12ByOrderByReceivedAtDesc();
}
