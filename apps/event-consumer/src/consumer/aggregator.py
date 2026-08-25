"""배치 안에서 (캠페인, 분) 단위로 미리 합친다.

10건을 10번 쓰는 대신 겹치는 분 버킷을 합쳐 한 번에 쓴다. DynamoDB 쓰기 건수가
줄어드는 것이 1차 목적이고, 같은 버킷에 대한 UpdateItem 경합이 줄어드는 것이 덤이다.
"""

import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

logger = logging.getLogger(__name__)

KST = timezone(timedelta(hours=9))

COUNTER_BY_EVENT_TYPE = {
    "impression": "impressions",
    "click": "clicks",
    "conversion": "conversions",
}
COUNTER_NAMES = ("impressions", "clicks", "conversions", "cost_micro")

BucketKey = tuple[str, str]


@dataclass
class Aggregate:
    # 모든 카운터를 0으로 채워 둔다. UpdateItem 표현식이 버킷마다 같아지고,
    # 조회 쪽에서 없는 속성을 신경 쓸 필요가 없어진다.
    counters: dict[str, int] = field(default_factory=lambda: dict.fromkeys(COUNTER_NAMES, 0))
    receipt_handles: list[str] = field(default_factory=list)


def aggregate(messages: list[dict]) -> tuple[dict[BucketKey, Aggregate], int]:
    """(버킷, 스키마 위반 건수)를 돌려준다.

    스키마를 위반한 메시지의 ReceiptHandle은 어느 버킷에도 담기지 않는다.
    삭제되지 않으므로 SQS가 재전달하고, maxReceiveCount 3을 넘기면 DLQ로 간다.
    """
    buckets: dict[BucketKey, Aggregate] = {}
    invalid = 0

    for message in messages:
        try:
            event = parse_event(message["Body"])
            # 버킷 키 계산까지 try 안에 둔다. 밖으로 빼면 오프셋 없는 occurred_at
            # 하나가 폴링 전체를 죽이고, 그 메시지는 삭제되지 않으므로 다음 폴링도
            # 같은 자리에서 죽는다 — 컨슈머가 영구히 멈추는 poison pill이 된다.
            key = (f"CAMP#{event['campaign_id']}", minute_bucket(event["occurred_at"]))
        except (ValueError, KeyError, TypeError) as exc:
            invalid += 1
            logger.warning(
                "leaving malformed message for redelivery",
                extra={"context": {"reason": str(exc), "message_id": message.get("MessageId")}},
            )
            continue

        entry = buckets.setdefault(key, Aggregate())
        entry.counters[COUNTER_BY_EVENT_TYPE[event["event_type"]]] += 1
        entry.counters["cost_micro"] += event["cost_micro"]
        entry.receipt_handles.append(message["ReceiptHandle"])

    return buckets, invalid


def parse_event(body: str) -> dict:
    event = json.loads(body)
    if not isinstance(event, dict):
        raise ValueError("event body is not an object")

    for name in ("campaign_id", "event_type", "occurred_at", "cost_micro"):
        if name not in event:
            raise ValueError(f"missing field: {name}")

    if event["event_type"] not in COUNTER_BY_EVENT_TYPE:
        raise ValueError(f"unknown event_type: {event['event_type']}")
    # bool은 int의 하위 타입이라 따로 막지 않으면 True가 1로 더해진다.
    if isinstance(event["cost_micro"], bool) or not isinstance(event["cost_micro"], int):
        raise ValueError("cost_micro must be an integer")

    return event


def minute_bucket(occurred_at: str) -> str:
    moment = datetime.fromisoformat(occurred_at)
    if moment.tzinfo is None:
        # 오프셋이 없으면 어느 시간대의 09:30인지 알 수 없다. 추측하지 않고 거절한다.
        raise ValueError("occurred_at must carry a UTC offset")
    return "TS#" + moment.astimezone(KST).strftime("%Y-%m-%dT%H:%M")
