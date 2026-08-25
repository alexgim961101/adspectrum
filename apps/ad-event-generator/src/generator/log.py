"""구조화 JSON 로깅.

컨테이너 로그는 사람이 아니라 수집기가 먼저 읽는다. 한 줄에 하나의 JSON 객체를
쓰면 CloudWatch Logs Insights나 Grafana에서 필드로 질의할 수 있다.
"""

import json
import logging
import sys
from datetime import UTC, datetime

_RESERVED = ("context",)


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        # logger.info(..., extra={"context": {...}}) 로 넘긴 값을 최상위에 펼친다.
        context = getattr(record, "context", None)
        if isinstance(context, dict):
            payload.update(context)
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, default=str)


def setup_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    root = logging.getLogger()
    # uvicorn/boto3가 먼저 붙여 둔 핸들러가 있으면 로그가 두 번 나간다.
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)

    # botocore는 DEBUG에서 요청 서명까지 찍는다. 항상 WARNING으로 눌러 둔다.
    for noisy in ("botocore", "boto3", "urllib3"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
