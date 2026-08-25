import time

from fastapi import FastAPI, Request
from prometheus_client import Counter, Histogram, make_asgi_app

# Histogram 하나로 세 가지를 다 낸다. _count는 요청 수, status 라벨로 5xx 비율,
# _bucket으로 p95. Counter를 따로 두면 같은 사실을 두 번 세게 된다.
REQUEST_DURATION = Histogram(
    "adspectrum_http_request_duration_seconds",
    "HTTP request latency",
    ["method", "path", "status"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

METRICS_PATH = "/metrics"

FAULTS_INJECTED = Counter(
    "adspectrum_faults_injected_total",
    "Responses failed on purpose by FAULT_RATE (canary rollback demo)",
)


def install(app: FastAPI) -> None:
    @app.middleware("http")
    async def record_request(request: Request, call_next):
        # 스크레이프 자체는 API 지연 분포에 섞지 않는다. 30초마다 들어오는
        # 빠른 요청이 p95를 낙관적으로 끌어내린다.
        if request.url.path.startswith(METRICS_PATH):
            return await call_next(request)

        started = time.perf_counter()
        response = await call_next(request)
        REQUEST_DURATION.labels(
            method=request.method,
            path=_route_template(request),
            status=str(response.status_code),
        ).observe(time.perf_counter() - started)
        return response

    app.mount(METRICS_PATH, make_asgi_app())


def _route_template(request: Request) -> str:
    # 실제 URL을 라벨로 쓰면 캠페인 수만큼 시계열이 생긴다. 라우트 템플릿
    # (/campaigns/{campaign_id}/metrics)으로 묶고, 매칭 실패는 한 값으로 모은다.
    route = request.scope.get("route")
    return getattr(route, "path", "unmatched")
