package com.aigate.cloud.repository;

import com.aigate.cloud.domain.ChannelState;
import com.aigate.cloud.domain.Provider;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProviderRepository extends JpaRepository<Provider, UUID> {
  boolean existsByCodeIgnoreCase(String code);
  List<Provider> findAllByOrderByChannelCodeAscDisplayNameAsc();
  List<Provider> findByStateAndEnabledTrueOrderByChannelCodeAscDisplayNameAsc(ChannelState state);
}
