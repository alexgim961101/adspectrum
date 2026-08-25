from prometheus_client import Counter, Histogram

EVENTS_CONSUMED = Counter(
    "adspectrum_events_consumed_total",
    "Events whose aggregate reached DynamoDB",
    ["event_type"],
)

BATCH_FLUSH_SECONDS = Histogram(
    "adspectrum_batch_flush_seconds",
    "Time spent writing one poll's aggregates to DynamoDB",
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5),
)

MESSAGES_INVALID = Counter(
    "adspectrum_messages_invalid_total",
    "Messages that failed schema validation and were left for the DLQ",
)

WRITE_FAILURES = Counter(
    "adspectrum_dynamodb_write_failures_total",
    "Aggregate writes that failed and whose messages were left for redelivery",
)
