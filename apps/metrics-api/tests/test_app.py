from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from api.config import Settings

FIXED_NOW = datetime(2026, 8, 25, 3, 15, tzinfo=UTC)  # KST 12:15


class StubRepository:
    def __init__(self, items: list[dict] | None = None) -> None:
        self.items = items if items is not None else []
        self.calls: list[tuple[str, str, str]] = []

    def query(self, campaign_id: str, bucket_from: str, bucket_to: str) -> list[dict]:
        self.calls.append((campaign_id, bucket_from, bucket_to))
        return self.items


class FixedRandom:
    """rng.random()이 늘 같은 값을 내도록 고정한다. 결함 주입을 결정적으로 만든다."""

    def __init__(self, value: float) -> None:
        self._value = value

    def random(self) -> float:
        return self._value


def build_client(repository=None, fault_rate: float = 0.0, roll: float = 0.5) -> TestClient:
    settings = Settings(
        table_name="adspectrum-metrics",
        region="ap-northeast-2",
        fault_rate=fault_rate,
        port=8000,
        log_level="INFO",
    )
    app = create_app(
        settings,
        repository if repository is not None else StubRepository(),
        rng=FixedRandom(roll),
        clock=lambda: FIXED_NOW,
    )
    return TestClient(app, raise_server_exceptions=False)


def test_healthz_stays_healthy_even_when_every_request_is_faulted():
    # 헬스체크까지 같이 실패시키면 kubelet이 파드를 재시작해서, 카나리 분석이 아니라
    # 기동 실패로 끝난다.
    response = build_client(fault_rate=1.0, roll=0.0).get("/healthz")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_metrics_returns_the_summary_with_from_and_to_aliases():
    repository = StubRepository(
        [{"impressions": 1_000, "clicks": 50, "conversions": 5, "cost_micro": 10_000}]
    )

    response = build_client(repository).get(
        "/campaigns/cmp-001/metrics",
        params={"from": "2026-08-25T09:00", "to": "2026-08-25T10:00"},
    )

    assert response.status_code == 200
    assert response.json() == {
        "campaign_id": "cmp-001",
        "from": "2026-08-25T09:00",
        "to": "2026-08-25T10:00",
        "buckets": 1,
        "impressions": 1_000,
        "clicks": 50,
        "conversions": 5,
        "cost_micro": 10_000,
        "ctr": pytest.approx(0.05),
        "cvr": pytest.approx(0.1),
        "cpc_micro": pytest.approx(200.0),
    }
    assert repository.calls == [("cmp-001", "2026-08-25T09:00", "2026-08-25T10:00")]


def test_an_omitted_range_falls_back_to_the_last_hour():
    repository = StubRepository()

    response = build_client(repository).get("/campaigns/cmp-001/metrics")

    assert response.status_code == 200
    assert repository.calls == [("cmp-001", "2026-08-25T11:15", "2026-08-25T12:15")]


@pytest.mark.parametrize(
    "params",
    [
        {"from": "oops"},
        {"to": "2026-08-25"},
        {"from": "2026-08-25T10:00", "to": "2026-08-25T09:00"},
    ],
)
def test_an_unusable_range_is_rejected_before_touching_dynamodb(params):
    repository = StubRepository()

    response = build_client(repository).get("/campaigns/cmp-001/metrics", params=params)

    assert response.status_code == 400
    assert repository.calls == []


def test_a_campaign_id_outside_the_allowed_shape_is_rejected():
    response = build_client().get("/campaigns/cmp 001!/metrics")

    assert response.status_code == 422


def test_fault_rate_turns_responses_into_500s():
    repository = StubRepository()

    response = build_client(repository, fault_rate=1.0, roll=0.0).get("/campaigns/cmp-001/metrics")

    assert response.status_code == 500
    assert repository.calls == []


def test_the_default_fault_rate_never_faults():
    response = build_client(fault_rate=0.0, roll=0.0).get("/campaigns/cmp-001/metrics")

    assert response.status_code == 200


def test_the_scrape_endpoint_exposes_the_request_histogram():
    client = build_client()
    client.get("/campaigns/cmp-001/metrics")

    body = client.get("/metrics").text

    assert (
        "adspectrum_http_request_duration_seconds_count"
        '{method="GET",path="/campaigns/{campaign_id}/metrics",status="200"}' in body
    )
