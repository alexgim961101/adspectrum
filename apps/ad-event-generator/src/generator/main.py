import logging
import signal
import time

import boto3
from prometheus_client import start_http_server

from .config import Settings, load_settings
from .events import EventFactory, chunk
from .log import setup_logging
from .publisher import Publisher

logger = logging.getLogger(__name__)

TICK_SECONDS = 1.0


class Generator:
    """1초에 events_per_sec건을 발행하는 루프."""

    def __init__(self, factory: EventFactory, publisher: Publisher, events_per_sec: int) -> None:
        self._factory = factory
        self._publisher = publisher
        self._events_per_sec = events_per_sec
        self._stopped = False

    def stop(self, *_) -> None:
        # SIGTERM 핸들러. 진행 중인 틱은 끝내고 다음 틱을 시작하지 않는다.
        logger.info("shutdown requested")
        self._stopped = True

    def tick(self) -> int:
        events = self._factory.build_many(self._events_per_sec)
        published = 0
        for batch in chunk(events):
            published += self._publisher.publish(batch)
        return published

    def run(self, sleep=time.sleep, monotonic=time.monotonic) -> None:
        while not self._stopped:
            started = monotonic()
            published = self.tick()
            elapsed = monotonic() - started

            if elapsed >= TICK_SECONDS:
                # 발행이 1초를 넘겼다. 목표 초당 건수를 못 채우고 있다는 뜻이라
                # 조용히 넘기면 부하 시나리오의 숫자가 거짓이 된다.
                logger.warning(
                    "tick exceeded its budget",
                    extra={"context": {"elapsed_sec": round(elapsed, 3), "published": published}},
                )
                continue
            sleep(TICK_SECONDS - elapsed)


def build(settings: Settings) -> Generator:
    sqs = boto3.client("sqs", region_name=settings.region)
    return Generator(
        factory=EventFactory(),
        publisher=Publisher(sqs, settings.queue_url),
        events_per_sec=settings.events_per_sec,
    )


def main() -> None:
    settings = load_settings()
    setup_logging(settings.log_level)

    # PodMonitor가 긁어 갈 /metrics. 별도 스레드로 뜬다.
    start_http_server(settings.metrics_port)

    generator = build(settings)
    signal.signal(signal.SIGTERM, generator.stop)
    signal.signal(signal.SIGINT, generator.stop)

    logger.info(
        "generator started",
        extra={
            "context": {
                "events_per_sec": settings.events_per_sec,
                "queue_url": settings.queue_url,
            }
        },
    )
    generator.run()
    logger.info("generator stopped")


if __name__ == "__main__":
    main()
