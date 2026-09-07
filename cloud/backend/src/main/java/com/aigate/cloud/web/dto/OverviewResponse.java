package com.aigate.cloud.web.dto;

import java.util.List;

public record OverviewResponse(
    long configVersion,
    long publishedChannels,
    long publishedProviders,
    long activeDevices,
    long eventsLast24Hours,
    long blockedLast24Hours,
    List<RecentEventResponse> recentEvents) {}
