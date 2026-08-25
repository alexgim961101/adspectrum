import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    queue_url: str
    events_per_sec: int
    region: str
    metrics_port: int
    log_level: str


def load_settings() -> Settings:
    return Settings(
        queue_url=_required("QUEUE_URL"),
        events_per_sec=int(os.environ.get("EVENTS_PER_SEC", "5")),
        region=os.environ.get("AWS_REGION", "ap-northeast-2"),
        metrics_port=int(os.environ.get("METRICS_PORT", "9090")),
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
    )


def _required(name: str) -> str:
    # 없는 채로 뜨면 첫 발행에서야 실패한다. 기동 시점에 죽는 편이 낫다.
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"required environment variable is missing: {name}")
    return value
