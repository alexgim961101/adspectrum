from collections import Counter
from datetime import UTC, datetime
from random import Random

from generator.events import (
    AD_IDS,
    CAMPAIGN_IDS,
    CHANNELS,
    COST_MICRO_RANGE,
    EVENT_TYPES,
    EventFactory,
    chunk,
)

# conftest의 factory 픽스처와 같은 시각. UTC 00:30:12 = KST 09:30:12.
FIXED_NOW = datetime(2026, 8, 25, 0, 30, 12, tzinfo=UTC)

SCHEMA_FIELDS = {
    "event_id",
    "campaign_id",
    "ad_id",
    "channel",
    "event_type",
    "cost_micro",
    "occurred_at",
}


def test_build_matches_the_documented_schema(factory):
    event = factory.build()

    assert set(event) == SCHEMA_FIELDS
    assert event["campaign_id"] in CAMPAIGN_IDS
    assert event["ad_id"] in AD_IDS
    assert event["channel"] in CHANNELS
    assert event["event_type"] in EVENT_TYPES

    low, high = COST_MICRO_RANGE[event["event_type"]]
    assert low <= event["cost_micro"] <= high


def test_occurred_at_carries_the_kst_offset(factory):
    # 소비자가 이 오프셋으로 분 버킷을 정한다. 빠지면 집계가 9시간 어긋난다.
    assert factory.build()["occurred_at"] == "2026-08-25T09:30:12+09:00"


def test_same_seed_reproduces_the_same_events():
    def build_five():
        return EventFactory(rng=Random(7), clock=lambda: FIXED_NOW).build_many(5)

    assert build_five() == build_five()


def test_event_types_follow_the_weighted_distribution():
    events = EventFactory(rng=Random(1), clock=lambda: datetime.now(UTC)).build_many(20_000)
    counts = Counter(event["event_type"] for event in events)

    assert counts["impression"] > counts["click"] > counts["conversion"] > 0
    # 가중치 1000 : 30 : 1 이면 노출이 전체의 약 97%가 된다.
    assert 0.95 < counts["impression"] / len(events) < 0.99


def test_chunk_splits_by_the_sqs_batch_limit(factory):
    batches = list(chunk(factory.build_many(25)))

    assert [len(batch) for batch in batches] == [10, 10, 5]


def test_chunk_of_nothing_yields_nothing():
    assert list(chunk([])) == []
