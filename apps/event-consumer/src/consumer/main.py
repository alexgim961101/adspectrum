import logging
import signal

import boto3
from prometheus_client import start_http_server

from .config import Settings, load_settings
from .consumer import Consumer
from .log import setup_logging
from .repository import MetricsRepository

logger = logging.getLogger(__name__)


def build(settings: Settings) -> Consumer:
    sqs = boto3.client("sqs", region_name=settings.region)
    table = boto3.resource("dynamodb", region_name=settings.region).Table(settings.table_name)
    return Consumer(
        sqs_client=sqs,
        queue_url=settings.queue_url,
        repository=MetricsRepository(table),
        batch_size=settings.batch_size,
    )


def main() -> None:
    settings = load_settings()
    setup_logging(settings.log_level)
    start_http_server(settings.metrics_port)

    consumer = build(settings)
    signal.signal(signal.SIGTERM, consumer.stop)
    signal.signal(signal.SIGINT, consumer.stop)

    logger.info(
        "consumer started",
        extra={"context": {"queue_url": settings.queue_url, "table": settings.table_name}},
    )
    consumer.run()
    logger.info("consumer stopped")


if __name__ == "__main__":
    main()
