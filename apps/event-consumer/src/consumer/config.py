import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    queue_url: str
    table_name: str
    batch_size: int
    region: str
    metrics_port: int
    log_level: str


def load_settings() -> Settings:
    return Settings(
        queue_url=_required("QUEUE_URL"),
        table_name=_required("TABLE_NAME"),
        batch_size=int(os.environ.get("BATCH_SIZE", "10")),
        region=os.environ.get("AWS_REGION", "ap-northeast-2"),
        metrics_port=int(os.environ.get("METRICS_PORT", "9090")),
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
    )


def _required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"required environment variable is missing: {name}")
    return value
