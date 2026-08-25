from prometheus_client import Counter, Histogram

from .aggregator import COUNTER_BY_EVENT_TYPE

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


# 라벨이 붙은 카운터는 첫 증가 전까지 시계열이 없다. KEDA로 0에서 올라온 직후의
# consumer는 한동안 아무것도 소비하지 않으므로, 미리 0으로 만들어 두지 않으면
# 스케일 아웃 그래프의 시작 구간이 비어 보인다.
for _event_type in COUNTER_BY_EVENT_TYPE:
    EVENTS_CONSUMED.labels(event_type=_event_type)
