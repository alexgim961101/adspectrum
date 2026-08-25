"""분 버킷을 합산하고 파생 지표를 계산한다. AWS도 HTTP도 모르는 순수 함수 영역."""

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

KST = timezone(timedelta(hours=9))
BUCKET_FORMAT = "%Y-%m-%dT%H:%M"
DEFAULT_WINDOW = timedelta(hours=1)

COUNTER_NAMES = ("impressions", "clicks", "conversions", "cost_micro")


@dataclass(frozen=True)
class Totals:
    buckets: int
    impressions: int
    clicks: int
    conversions: int
    cost_micro: int

    # 저장하지 않고 조회 시 계산한다. 비율을 미리 적재하면 기간을 다시 자를 때
    # 평균의 평균이 되어 값이 틀어진다.
    @property
    def ctr(self) -> float | None:
        return _ratio(self.clicks, self.impressions)

    @property
    def cvr(self) -> float | None:
        return _ratio(self.conversions, self.clicks)

    @property
    def cpc_micro(self) -> float | None:
        return _ratio(self.cost_micro, self.clicks)


def _ratio(numerator: int, denominator: int) -> float | None:
    # 분모가 0인 구간은 "0%"가 아니라 "정의되지 않음"이다. 0으로 내보내면
    # 그래프에서 성과가 나쁜 것처럼 보인다.
    if denominator == 0:
        return None
    return numerator / denominator


def summarize(items: Iterable[dict]) -> Totals:
    totals = dict.fromkeys(COUNTER_NAMES, 0)
    buckets = 0
    for item in items:
        buckets += 1
        for name in COUNTER_NAMES:
            # DynamoDB 리소스 API는 숫자를 Decimal로 준다. int로 되돌려 합산한다.
            totals[name] += int(item.get(name, 0))
    return Totals(buckets=buckets, **totals)


def parse_bucket(value: str, field: str) -> datetime:
    try:
        return datetime.strptime(value, BUCKET_FORMAT).replace(tzinfo=KST)
    except ValueError as exc:
        raise ValueError(f"{field} must look like 2026-08-25T09:30 (KST)") from exc


def default_range(now: datetime) -> tuple[str, str]:
    end = now.astimezone(KST)
    return format_bucket(end - DEFAULT_WINDOW), format_bucket(end)


def format_bucket(moment: datetime) -> str:
    return moment.astimezone(KST).strftime(BUCKET_FORMAT)


def sort_key(bucket: str) -> str:
    """분 문자열을 DynamoDB 정렬 키로 바꾼다. ISO 표기라 사전순 = 시간순이다."""
    return f"TS#{bucket}"
