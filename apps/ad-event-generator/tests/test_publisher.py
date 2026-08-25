import json

from prometheus_client import REGISTRY

from generator.publisher import Publisher

QUEUE_URL = "https://sqs.ap-northeast-2.amazonaws.com/000000000000/adspectrum-events"


class FakeSqs:
    def __init__(self, failed: list[dict] | None = None) -> None:
        self.calls: list[dict] = []
        self._failed = failed or []

    def send_message_batch(self, **kwargs):
        self.calls.append(kwargs)
        failed_ids = {entry["Id"] for entry in self._failed}
        return {
            "Successful": [
                {"Id": entry["Id"]} for entry in kwargs["Entries"] if entry["Id"] not in failed_ids
            ],
            "Failed": self._failed,
        }


def published(event_type: str) -> float:
    value = REGISTRY.get_sample_value(
        "adspectrum_events_published_total", {"event_type": event_type}
    )
    return value or 0.0


def failures(code: str) -> float:
    value = REGISTRY.get_sample_value("adspectrum_publish_failures_total", {"code": code})
    return value or 0.0


def event(event_type: str) -> dict:
    return {"event_id": f"id-{event_type}", "event_type": event_type, "cost_micro": 1}


def test_publish_sends_one_entry_per_event():
    sqs = FakeSqs()
    events = [event("click"), event("impression")]
    before = published("click")

    accepted = Publisher(sqs, QUEUE_URL).publish(events)

    assert accepted == 2
    entries = sqs.calls[0]["Entries"]
    assert sqs.calls[0]["QueueUrl"] == QUEUE_URL
    assert [entry["Id"] for entry in entries] == ["0", "1"]
    assert json.loads(entries[0]["MessageBody"]) == events[0]
    assert published("click") == before + 1


def test_publish_does_not_count_entries_sqs_rejected():
    # SendMessageBatch는 일부가 거절돼도 예외를 던지지 않는다. 응답의 Failed를
    # 무시하면 발행 지표만 정상으로 보이고 이벤트는 사라진다.
    sqs = FakeSqs(
        failed=[
            {"Id": "1", "Code": "ThrottlingException", "Message": "slow down", "SenderFault": False}
        ]
    )
    events = [event("impression"), event("conversion")]
    before_ok = published("conversion")
    before_failed = failures("ThrottlingException")

    accepted = Publisher(sqs, QUEUE_URL).publish(events)

    assert accepted == 1
    assert published("conversion") == before_ok
    assert failures("ThrottlingException") == before_failed + 1


def test_publish_skips_the_api_call_for_an_empty_batch():
    sqs = FakeSqs()

    assert Publisher(sqs, QUEUE_URL).publish([]) == 0
    assert sqs.calls == []


def test_every_event_type_has_a_series_before_the_first_publish():
    # 값이 0이어도 시계열은 존재해야 한다. 없으면 대시보드가 "No data"를 그린다.
    for event_type in ("impression", "click", "conversion"):
        assert (
            REGISTRY.get_sample_value(
                "adspectrum_events_published_total", {"event_type": event_type}
            )
            is not None
        )
