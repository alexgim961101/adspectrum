from prometheus_client import Counter

from .events import EVENT_TYPES

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


# 라벨이 붙은 카운터는 첫 증가 전까지 시계열이 아예 없다. 그대로 두면 아직 한 건도
# 발행하지 않은 동안 Grafana 패널이 "No data"로 보여, 값이 0인 것과 수집이 끊긴 것을
# 구분할 수 없다. 알고 있는 라벨은 미리 0으로 만들어 둔다.
for _event_type in EVENT_TYPES:
    EVENTS_PUBLISHED.labels(event_type=_event_type)
