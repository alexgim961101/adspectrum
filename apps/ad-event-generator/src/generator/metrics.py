from prometheus_client import Counter

EVENTS_PUBLISHED = Counter(
    "adspectrum_events_published_total",
    "Events accepted by SQS",
    ["event_type"],
)

PUBLISH_FAILURES = Counter(
    "adspectrum_publish_failures_total",
    "Events rejected by SQS, labelled with the error code returned per entry",
    ["code"],
)
