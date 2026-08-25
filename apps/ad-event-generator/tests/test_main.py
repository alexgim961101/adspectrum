from random import Random

import pytest

from generator.events import EventFactory
from generator.main import Generator


class RecordingPublisher:
    def __init__(self) -> None:
        self.batches: list[list[dict]] = []

    def publish(self, events: list[dict]) -> int:
        self.batches.append(events)
        return len(events)


def build_generator(events_per_sec: int) -> tuple[Generator, RecordingPublisher]:
    publisher = RecordingPublisher()
    generator = Generator(
        factory=EventFactory(rng=Random(3)),
        publisher=publisher,
        events_per_sec=events_per_sec,
    )
    return generator, publisher


def test_tick_publishes_the_target_rate_in_batches_of_ten():
    generator, publisher = build_generator(events_per_sec=25)

    assert generator.tick() == 25
    assert [len(batch) for batch in publisher.batches] == [10, 10, 5]


def test_run_stops_after_stop_is_called():
    generator, publisher = build_generator(events_per_sec=3)
    slept: list[float] = []

    def sleep(seconds: float) -> None:
        slept.append(seconds)
        generator.stop()

    generator.run(sleep=sleep, monotonic=iter([0.0, 0.2]).__next__)

    assert len(slept) == 1
    assert len(publisher.batches) == 1


def test_run_does_not_sleep_when_a_tick_overruns_its_second():
    generator, _ = build_generator(events_per_sec=1)
    slept: list[float] = []

    def sleep(seconds: float) -> None:
        slept.append(seconds)
        generator.stop()

    # 첫 틱은 1.5초가 걸려 예산을 넘기고, 두 번째 틱만 남은 시간을 잔다.
    generator.run(sleep=sleep, monotonic=iter([0.0, 1.5, 0.0, 0.1]).__next__)

    assert slept == [pytest.approx(0.9)]
