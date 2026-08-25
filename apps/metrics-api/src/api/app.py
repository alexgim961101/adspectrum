from datetime import UTC, datetime
from random import Random
from typing import Annotated

from fastapi import FastAPI, HTTPException, Path, Query
from pydantic import BaseModel, ConfigDict, Field

from . import observability
from .config import Settings
from .repository import MetricsRepository
from .summary import default_range, parse_bucket, summarize

# 캠페인 ID를 그대로 파티션 키에 넣는다. 형태를 먼저 막아 이상한 값으로
# DynamoDB를 두드리는 요청을 걸러 낸다.
CAMPAIGN_ID_PATTERN = r"^[A-Za-z0-9_-]{1,64}$"


class MetricsResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    campaign_id: str
    # from은 파이썬 예약어라 필드 이름으로 쓸 수 없다. 응답 JSON에서만 from으로 나간다.
    range_from: str = Field(serialization_alias="from")
    range_to: str = Field(serialization_alias="to")
    buckets: int
    impressions: int
    clicks: int
    conversions: int
    cost_micro: int
    ctr: float | None
    cvr: float | None
    cpc_micro: float | None


def create_app(
    settings: Settings,
    repository: MetricsRepository,
    rng: Random | None = None,
    clock=None,
) -> FastAPI:
    rng = rng if rng is not None else Random()
    clock = clock if clock is not None else (lambda: datetime.now(UTC))

    app = FastAPI(title="adspectrum metrics-api", version="0.1.0")
    observability.install(app)

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        # FAULT_RATE의 영향을 받지 않는다. 헬스체크까지 같이 실패시키면 kubelet이
        # 파드를 재시작해 버려서, 카나리 분석이 아니라 기동 실패로 끝난다.
        return {"status": "ok"}

    @app.get("/campaigns/{campaign_id}/metrics", response_model=MetricsResponse)
    def campaign_metrics(
        campaign_id: Annotated[str, Path(pattern=CAMPAIGN_ID_PATTERN)],
        range_from: Annotated[str | None, Query(alias="from")] = None,
        range_to: Annotated[str | None, Query(alias="to")] = None,
    ) -> MetricsResponse:
        if rng.random() < settings.fault_rate:
            observability.FAULTS_INJECTED.inc()
            raise HTTPException(status_code=500, detail="fault injected by FAULT_RATE")

        fallback_from, fallback_to = default_range(clock())
        bucket_from = range_from or fallback_from
        bucket_to = range_to or fallback_to

        try:
            start = parse_bucket(bucket_from, "from")
            end = parse_bucket(bucket_to, "to")
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if start > end:
            raise HTTPException(status_code=400, detail="from must not be later than to")

        totals = summarize(repository.query(campaign_id, bucket_from, bucket_to))
        return MetricsResponse(
            campaign_id=campaign_id,
            range_from=bucket_from,
            range_to=bucket_to,
            buckets=totals.buckets,
            impressions=totals.impressions,
            clicks=totals.clicks,
            conversions=totals.conversions,
            cost_micro=totals.cost_micro,
            ctr=totals.ctr,
            cvr=totals.cvr,
            cpc_micro=totals.cpc_micro,
        )

    return app
