import json

from botocore.exceptions import ClientError

from consumer.consumer import LONG_POLL_SECONDS, Consumer

QUEUE_URL = "https://sqs.ap-northeast-2.amazonaws.com/000000000000/adspectrum-events"

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
    return {
        "MessageId": handle,
        "ReceiptHandle": handle,
        "Body": json.dumps(BASE_EVENT | overrides),
    }


class FakeSqs:
    def __init__(self, messages: list[dict] | None = None) -> None:
        self._messages = messages or []
        self.receive_calls: list[dict] = []
        self.deleted: list[list[str]] = []

    def receive_message(self, **kwargs):
        self.receive_calls.append(kwargs)
        return {"Messages": self._messages} if self._messages else {}

    def delete_message_batch(self, **kwargs):
        self.deleted.append([entry["ReceiptHandle"] for entry in kwargs["Entries"]])
        return {}


class FakeRepository:
    def __init__(self, failing: set[tuple[str, str]] | None = None) -> None:
        self.writes: list[tuple[str, str, dict]] = []
        self._failing = failing or set()

    def add(self, pk: str, sk: str, counters: dict[str, int]) -> None:
        if (pk, sk) in self._failing:
            raise ClientError(
                {"Error": {"Code": "ProvisionedThroughputExceededException"}}, "UpdateItem"
            )
        self.writes.append((pk, sk, dict(counters)))


def test_an_empty_poll_touches_nothing():
    sqs = FakeSqs()
    repository = FakeRepository()

    assert Consumer(sqs, QUEUE_URL, repository).run_once() == 0
    assert repository.writes == []
    assert sqs.deleted == []


def test_receive_uses_long_polling_and_the_configured_batch_size():
    sqs = FakeSqs([message("h1")])

    Consumer(sqs, QUEUE_URL, FakeRepository(), batch_size=7).run_once()

    call = sqs.receive_calls[0]
    assert call["QueueUrl"] == QUEUE_URL
    assert call["MaxNumberOfMessages"] == 7
    assert call["WaitTimeSeconds"] == LONG_POLL_SECONDS


def test_batch_size_never_exceeds_the_sqs_limit():
    sqs = FakeSqs([message("h1")])

    Consumer(sqs, QUEUE_URL, FakeRepository(), batch_size=50).run_once()

    assert sqs.receive_calls[0]["MaxNumberOfMessages"] == 10


def test_processed_messages_are_deleted_once_the_aggregate_is_written():
    sqs = FakeSqs([message("h1"), message("h2")])
    repository = FakeRepository()

    processed = Consumer(sqs, QUEUE_URL, repository).run_once()

    assert processed == 2
    assert repository.writes == [
        (
            "CAMP#cmp-001",
            "TS#2026-08-25T09:30",
            {
                "impressions": 2,
                "clicks": 0,
                "conversions": 0,
                "cost_micro": 2_000,
            },
        )
    ]
    assert sqs.deleted == [["h1", "h2"]]


def test_a_failed_write_only_holds_back_its_own_messages():
    # 두 버킷 중 09:31만 쓰기에 실패한다. 09:30에 기여한 메시지는 삭제되어야 하고,
    # 09:31 메시지는 남아 SQS 재전달을 받아야 한다.
    sqs = FakeSqs(
        [
            message("ok-1"),
            message("ok-2"),
            message("stuck", occurred_at="2026-08-25T09:31:00+09:00"),
        ]
    )
    repository = FakeRepository(failing={("CAMP#cmp-001", "TS#2026-08-25T09:31")})

    processed = Consumer(sqs, QUEUE_URL, repository).run_once()

    assert processed == 2
    assert sqs.deleted == [["ok-1", "ok-2"]]


def test_malformed_messages_are_never_deleted():
    sqs = FakeSqs([{"MessageId": "bad", "ReceiptHandle": "bad", "Body": "{"}, message("good")])

    processed = Consumer(sqs, QUEUE_URL, FakeRepository()).run_once()

    assert processed == 1
    assert sqs.deleted == [["good"]]


def test_run_exits_after_stop():
    sqs = FakeSqs([message("h1")])
    repository = FakeRepository()
    consumer = Consumer(sqs, QUEUE_URL, repository)

    original_add = repository.add

    def add_then_stop(*args, **kwargs):
        original_add(*args, **kwargs)
        consumer.stop()

    repository.add = add_then_stop
    consumer.run()

    assert len(sqs.receive_calls) == 1


def test_every_event_type_has_a_series_before_the_first_poll():
    from prometheus_client import REGISTRY

    for event_type in ("impression", "click", "conversion"):
        assert (
            REGISTRY.get_sample_value(
                "adspectrum_events_consumed_total", {"event_type": event_type}
            )
            is not None
        )
