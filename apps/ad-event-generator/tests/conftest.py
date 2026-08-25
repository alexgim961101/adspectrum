from datetime import UTC, datetime
from random import Random

import pytest

from generator.events import EventFactory

# UTC 00:30:12 = KST 09:30:12. 시간대 변환이 실제로 일어나는 값을 쓴다.
FIXED_NOW = datetime(2026, 8, 25, 0, 30, 12, tzinfo=UTC)


@pytest.fixture
def factory():
    return EventFactory(rng=Random(7), clock=lambda: FIXED_NOW)
