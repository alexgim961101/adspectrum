import logging

import boto3
import uvicorn

from .app import create_app
from .config import load_settings
from .log import setup_logging
from .repository import MetricsRepository

logger = logging.getLogger(__name__)


def main() -> None:
    settings = load_settings()
    setup_logging(settings.log_level)

    table = boto3.resource("dynamodb", region_name=settings.region).Table(settings.table_name)
    app = create_app(settings, MetricsRepository(table))

    logger.info(
        "metrics-api started",
        extra={"context": {"table": settings.table_name, "fault_rate": settings.fault_rate}},
    )
    # log_config=None을 주지 않으면 uvicorn이 자기 로깅 설정으로 루트 핸들러를
    # 덮어써서 JSON 로그가 평문으로 돌아간다.
    uvicorn.run(app, host="0.0.0.0", port=settings.port, log_config=None)


if __name__ == "__main__":
    main()
