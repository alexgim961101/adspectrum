import json

import pytest

from consumer.aggregator import aggregate, minute_bucket

BASE_EVENT = {
    "event_id": "e-1",
    "campaign_id": "cmp-001",
    "ad_id": "ad-001",
    "channel": "naver",
    "event_type": "impression",
    "cost_micro": 1_000,
    "occurred_at": "2026-08-25T09:30:12+09:00",
}


def message(handle: str, **overrides) -> dict:
    event = BASE_EVENT | overrides
    return {"MessageId": handle, "ReceiptHandle": handle, "Body": json.dumps(event)}


def broken(handle: str, body: str) -> dict:
    return {"MessageId": handle, "ReceiptHandle": handle, "Body": body}


def test_events_in_the_same_campaign_and_minute_collapse_into_one_bucket():
    buckets, invalid = aggregate(
        [
            message("h1"),
            message("h2", occurred_at="2026-08-25T09:30:59+09:00"),
            message("h3", occurred_at="2026-08-25T09:30:00+09:00"),
        ]
    )

    assert invalid == 0
    assert list(buckets) == [("CAMP#cmp-001", "TS#2026-08-25T09:30")]
    entry = buckets[("CAMP#cmp-001", "TS#2026-08-25T09:30")]
    assert entry.counters["impressions"] == 3
    assert entry.counters["cost_micro"] == 3_000
    assert entry.receipt_handles == ["h1", "h2", "h3"]


def test_a_different_minute_becomes_a_different_bucket():
    buckets, _ = aggregate([message("h1"), message("h2", occurred_at="2026-08-25T09:31:00+09:00")])

    assert sorted(key[1] for key in buckets) == ["TS#2026-08-25T09:30", "TS#2026-08-25T09:31"]


def test_each_event_type_lands_in_its_own_counter():
    buckets, _ = aggregate(
        [
            message("h1", event_type="impression", cost_micro=100),
            message("h2", event_type="click", cost_micro=500_000),
            message("h3", event_type="conversion", cost_micro=0),
        ]
    )

    entry = next(iter(buckets.values()))
    assert entry.counters == {
        "impressions": 1,
        "clicks": 1,
        "conversions": 1,
        "cost_micro": 500_100,
    }


def test_events_timestamped_in_utc_land_in_the_kst_bucket():
    # generator는 KST로 보내지만 계약은 "오프셋이 붙은 ISO8601"이다.
    buckets, _ = aggregate([message("h1", occurred_at="2026-08-25T00:30:12+00:00")])

    assert list(buckets)[0][1] == "TS#2026-08-25T09:30"


@pytest.mark.parametrize(
    ("case", "body"),
    [
        ("깨진 JSON", "{not json"),
        ("객체가 아님", '["impression"]'),
        ("필드 누락", json.dumps({k: v for k, v in BASE_EVENT.items() if k != "campaign_id"})),
        ("모르는 event_type", json.dumps(BASE_EVENT | {"event_type": "swipe"})),
        ("cost_micro가 bool", json.dumps(BASE_EVENT | {"cost_micro": True})),
        ("cost_micro가 문자열", json.dumps(BASE_EVENT | {"cost_micro": "1000"})),
        ("오프셋 없는 시각", json.dumps(BASE_EVENT | {"occurred_at": "2026-08-25T09:30:12"})),
    ],
)
def test_malformed_messages_are_left_for_the_dlq(case, body):
    # 삭제 대상에서 빠져야 SQS가 재전달하고, maxReceiveCount 3을 넘기면 DLQ로 간다.
    buckets, invalid = aggregate([broken("bad", body), message("good")])

    assert invalid == 1, case
    handles = [handle for entry in buckets.values() for handle in entry.receipt_handles]
    assert handles == ["good"], case


def test_minute_bucket_rejects_a_timestamp_without_an_offset():
    with pytest.raises(ValueError, match="UTC offset"):
        minute_bucket("2026-08-25T09:30:12")
