import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    table_name: str
    region: str
    fault_rate: float
    port: int
    log_level: str


def load_settings() -> Settings:
    return Settings(
        table_name=_required("TABLE_NAME"),
        region=os.environ.get("AWS_REGION", "ap-northeast-2"),
        # 카나리 자동 롤백 데모 전용 장치. 0이 아니면 그 비율만큼 500을 낸다.
        fault_rate=float(os.environ.get("FAULT_RATE", "0")),
        port=int(os.environ.get("PORT", "8000")),
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
    )


def _required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"required environment variable is missing: {name}")
    return value
