# syntax=docker/dockerfile:1
FROM python:3.12-slim AS builder

# uv 바이너리만 가져온다. 빌드에만 필요하므로 런타임 이미지에는 남기지 않는다.
COPY --from=ghcr.io/astral-sh/uv:0.10.7 /uv /bin/uv

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

# 의존성 레이어를 소스와 분리한다. 코드만 바뀐 커밋에서는 이 레이어가 캐시에서 나온다.
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM python:3.12-slim

# 베이스 이미지가 다시 구워지기를 기다리지 않고 OS 보안 패치를 받는다.
# CI의 취약점 게이트가 CVE-2026-14456(openssl, HIGH)을 잡아 추가했다 — 수정본이
# 데비안 저장소에 있는데 베이스에는 아직 반영되지 않은 상태였다 (DECISIONS 019).
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# non-root 실행. Helm 차트의 runAsUser와 같은 UID를 쓴다.
RUN useradd --create-home --uid 10001 app
WORKDIR /app

COPY --from=builder --chown=app:app /app/.venv ./.venv
COPY --chown=app:app src ./src

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONPATH=/app/src \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER app
EXPOSE 9090
CMD ["python", "-m", "consumer.main"]
