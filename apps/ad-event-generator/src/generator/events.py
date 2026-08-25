"""광고 성과 이벤트 생성. 스키마는 docs/SPEC.md 3장을 따른다."""

import uuid
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta, timezone
from random import Random

KST = timezone(timedelta(hours=9))

CAMPAIGN_IDS = tuple(f"cmp-{index:03d}" for index in range(1, 11))
AD_IDS = tuple(f"ad-{index:03d}" for index in range(1, 51))
CHANNELS = ("naver", "kakao", "google", "meta")

# 노출 ≫ 클릭 ≫ 전환. 실제 광고 지표의 자릿수 차이를 재현해야 CTR/CVR이 의미 있는
# 값으로 나온다. SPEC 3장의 1000 : 30 : 1.
EVENT_TYPES = ("impression", "click", "conversion")
EVENT_WEIGHTS = (1000, 30, 1)

# 매체비는 노출과 클릭에서 발생한다. 전환은 성과 지표일 뿐 과금 대상이 아니므로 0.
# 단위는 마이크로 원(1원 = 1_000_000)이라 정수 합산만으로 오차가 생기지 않는다.
COST_MICRO_RANGE = {
    "impression": (500, 3_000),
    "click": (100_000, 900_000),
    "conversion": (0, 0),
}

SQS_BATCH_LIMIT = 10


class EventFactory:
    """난수원과 시계를 주입받는다. 테스트에서 결과를 고정할 수 있다."""

    def __init__(self, rng: Random | None = None, clock=None) -> None:
        self._rng = rng if rng is not None else Random()
        self._clock = clock if clock is not None else (lambda: datetime.now(UTC))

    def build(self) -> dict:
        event_type = self._rng.choices(EVENT_TYPES, weights=EVENT_WEIGHTS, k=1)[0]
        low, high = COST_MICRO_RANGE[event_type]
        return {
            # uuid4() 대신 주입된 난수원을 쓴다. 시드가 같으면 event_id까지 재현된다.
            "event_id": str(uuid.UUID(int=self._rng.getrandbits(128), version=4)),
            "campaign_id": self._rng.choice(CAMPAIGN_IDS),
            "ad_id": self._rng.choice(AD_IDS),
            "channel": self._rng.choice(CHANNELS),
            "event_type": event_type,
            "cost_micro": self._rng.randint(low, high),
            # 소비자가 분 버킷을 KST로 계산한다. 오프셋을 반드시 실어 보낸다.
            "occurred_at": self._clock().astimezone(KST).isoformat(timespec="seconds"),
        }

    def build_many(self, count: int) -> list[dict]:
        return [self.build() for _ in range(count)]


def chunk(items: list[dict], size: int = SQS_BATCH_LIMIT) -> Iterator[list[dict]]:
    """SendMessageBatch는 한 번에 10건까지만 받는다."""
    for start in range(0, len(items), size):
        yield items[start : start + size]
