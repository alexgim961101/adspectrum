# API — 외부 계약

이 문서는 시스템의 **경계**를 다룬다. 안으로 들어오는 이벤트 스키마와 밖으로 나가는
조회 API 두 가지다. 내부 구현이 아니라 계약이므로, 여기 적힌 것을 바꾸면 반대편이 깨진다.

모든 예시는 실제로 배포된 클러스터에서 받은 응답이다.

---

## 1. 인바운드 — 이벤트 스키마 (SQS)

`ad-event-generator`가 발행하고 `event-consumer`가 소비한다. 두 앱은 코드를 공유하지 않으며
(DECISIONS 007), 이 JSON이 유일한 계약이다.

큐: `adspectrum-events` · 발행 방식: `SendMessageBatch` (최대 10건)

```json
{
  "event_id": "0c5c7fd0-a6a3-4450-a513-270e269e0d37",
  "campaign_id": "cmp-002",
  "ad_id": "ad-035",
  "channel": "naver",
  "event_type": "impression",
  "cost_micro": 1997,
  "occurred_at": "2026-08-25T21:32:44+09:00"
}
```

| 필드 | 타입 | 규칙 |
|---|---|---|
| `event_id` | string | UUID4. 현재 소비 측에서 쓰지 않는다 (아래 "중복" 참조) |
| `campaign_id` | string | `cmp-001` ~ `cmp-010` |
| `ad_id` | string | `ad-001` ~ `ad-050` |
| `channel` | string | `naver` \| `kakao` \| `google` \| `meta` |
| `event_type` | string | `impression` \| `click` \| `conversion` |
| `cost_micro` | integer | 마이크로 원(1원 = 1,000,000). **정수여야 한다** |
| `occurred_at` | string | ISO8601. **UTC 오프셋 필수** |

### 소비 측이 거절하는 값

거절된 메시지는 **삭제되지 않는다.** SQS가 3회 재전달한 뒤 `adspectrum-events-dlq`로 옮긴다.

- JSON이 아니거나 객체가 아닌 본문
- `campaign_id`·`event_type`·`occurred_at`·`cost_micro` 중 하나라도 없음
- 목록에 없는 `event_type`
- `cost_micro`가 정수가 아님 (`true`도 거절한다 — 파이썬에서 `bool`은 `int`의 하위 타입이라
  막지 않으면 1로 더해진다)
- `occurred_at`에 오프셋이 없음 (어느 시간대의 09:30인지 알 수 없다)

### 비율과 분포

`impression : click : conversion = 1000 : 30 : 1`. 실제 광고 지표의 자릿수 차이를 재현해야
CTR·CVR이 의미 있는 값으로 나온다.

`cost_micro`는 이벤트 종류마다 범위가 다르다. 전환에는 매체비가 붙지 않아 항상 0이다.

| `event_type` | `cost_micro` 범위 |
|---|---|
| `impression` | 500 ~ 3,000 |
| `click` | 100,000 ~ 900,000 |
| `conversion` | 0 |

### 중복

SQS는 at-least-once다. 소비 측이 DynamoDB에 반영한 뒤 삭제하므로, 그 사이에 파드가 죽으면
같은 이벤트가 다시 집계된다. **이 오차를 허용한다** (SPEC 3장). `event_id` 기반 dedup은
확장 로드맵이다.

---

## 2. 집계 결과 (DynamoDB)

두 API 사이의 중간 계약이다. `event-consumer`가 쓰고 `metrics-api`가 읽는다.

테이블 `adspectrum-metrics` · 온디맨드

| 항목 | 값 |
|---|---|
| 파티션 키 `pk` | `CAMP#<campaign_id>` |
| 정렬 키 `sk` | `TS#<yyyy-MM-ddTHH:mm>` — **KST 분 버킷** |
| 속성 | `impressions`, `clicks`, `conversions`, `cost_micro` |

```json
{ "pk": "CAMP#cmp-001", "sk": "TS#2026-08-25T22:27",
  "impressions": 37, "clicks": 3, "conversions": 0, "cost_micro": 893369 }
```

네 속성 모두 `UpdateItem`의 `ADD`로만 갱신한다. 원자적 누적이라 여러 consumer 파드가
같은 버킷을 동시에 갱신해도 값이 덮이지 않는다. 해당 배치에 없던 종류도 0을 더해
속성을 항상 네 개로 유지한다 — 조회 측이 없는 속성을 신경 쓰지 않아도 된다.

**비율은 저장하지 않는다.** 분 단위 CTR을 적재하면 기간을 다시 자를 때 평균의 평균이 되어
값이 틀어진다. 더할 수 있는 값만 적재하고 파생 지표는 조회 시점에 계산한다.

---

## 3. 아웃바운드 — metrics-api

ALB 기본 DNS로 HTTP 노출한다. 도메인이 없어 HTTPS는 범위에서 제외했다 (SPEC 12장).

```
http://k8s-adspectrum-<...>.ap-northeast-2.elb.amazonaws.com
```

### `GET /campaigns/{campaign_id}/metrics`

| 파라미터 | 위치 | 필수 | 설명 |
|---|---|---|---|
| `campaign_id` | path | O | `^[A-Za-z0-9_-]{1,64}$` |
| `from` | query | X | `yyyy-MM-ddTHH:mm` (KST). 기본값 = `to` - 1시간 |
| `to` | query | X | `yyyy-MM-ddTHH:mm` (KST). 기본값 = 현재 |

```sh
curl "http://$ALB/campaigns/cmp-002/metrics?from=2026-08-25T22:00&to=2026-08-25T22:30"
```

```json
{
  "campaign_id": "cmp-002",
  "from": "2026-08-25T22:00",
  "to": "2026-08-25T22:30",
  "buckets": 5,
  "impressions": 120,
  "clicks": 3,
  "conversions": 0,
  "cost_micro": 1468022,
  "ctr": 0.025,
  "cvr": 0.0,
  "cpc_micro": 489340.6666666667
}
```

| 필드 | 의미 |
|---|---|
| `buckets` | 합산에 들어간 분 버킷 수. 0이면 그 구간에 데이터가 없다 |
| `ctr` | `clicks / impressions` |
| `cvr` | `conversions / clicks` |
| `cpc_micro` | `cost_micro / clicks` — 클릭당 평균 단가 |

**분모가 0이면 `null`이다. 0.0이 아니다.** 노출이 없는 구간은 "성과 0"이 아니라
"정의되지 않음"이고, 0으로 내보내면 그래프에서 성과가 나쁜 구간처럼 보인다.
반대로 클릭은 있는데 전환이 0이면 그건 진짜 0이라 `0.0`으로 나간다 (위 예시의 `cvr`).

데이터가 없는 구간:

```json
{
  "campaign_id": "cmp-999",
  "from": "2026-08-25T22:00", "to": "2026-08-25T22:30",
  "buckets": 0,
  "impressions": 0, "clicks": 0, "conversions": 0, "cost_micro": 0,
  "ctr": null, "cvr": null, "cpc_micro": null
}
```

존재하지 않는 캠페인도 404가 아니라 200에 빈 집계를 준다. 캠페인 마스터를 따로 갖고 있지
않아서 "없는 캠페인"과 "그 구간에 이벤트가 없는 캠페인"을 구분할 수 없기 때문이다.

### 오류

`400` — 기간 형식이 틀렸거나 `from`이 `to`보다 늦다. DynamoDB를 호출하기 전에 거절한다.

```json
{"detail": "from must look like 2026-08-25T09:30 (KST)"}
{"detail": "from must not be later than to"}
```

`422` — `campaign_id`가 허용 형태를 벗어났다. FastAPI가 라우팅 단계에서 낸다.

```json
{"detail": [{"type": "string_pattern_mismatch", "loc": ["path", "campaign_id"],
             "msg": "String should match pattern '^[A-Za-z0-9_-]{1,64}$'",
             "input": "bad id"}]}
```

`500` — `FAULT_RATE`가 0이 아닐 때 그 비율만큼 발생한다. 카나리 자동 롤백 데모 전용이며
평상시 값은 0이다.

```json
{"detail": "fault injected by FAULT_RATE"}
```

### `GET /healthz`

liveness·readiness 프로브가 쓴다. DynamoDB를 건드리지 않고 **`FAULT_RATE`의 영향도 받지
않는다.** 결함을 주입해도 파드는 계속 Ready여야 카나리 분석이 에러율로 판단할 수 있다.

```json
{"status": "ok"}
```

---

## 4. 지표 (Prometheus)

세 앱 모두 `/metrics`를 노출하고 PodMonitor로 수집된다. generator와 consumer는 9090 포트,
metrics-api는 API와 같은 8000 포트를 쓴다.

| 지표 | 앱 | 라벨 |
|---|---|---|
| `adspectrum_events_published_total` | generator | `event_type` |
| `adspectrum_publish_failures_total` | generator | `code` (SQS 오류 코드) |
| `adspectrum_events_consumed_total` | consumer | `event_type` |
| `adspectrum_batch_flush_seconds` | consumer | — (히스토그램) |
| `adspectrum_messages_invalid_total` | consumer | — |
| `adspectrum_dynamodb_write_failures_total` | consumer | — |
| `adspectrum_http_request_duration_seconds` | metrics-api | `method`, `path`, `status` |
| `adspectrum_faults_injected_total` | metrics-api | — |

```
adspectrum_http_request_duration_seconds_count{method="GET",path="/campaigns/{campaign_id}/metrics",status="200"} 2.0
adspectrum_http_request_duration_seconds_count{method="GET",path="/campaigns/{campaign_id}/metrics",status="400"} 1.0
```

`path` 라벨은 실제 URL이 아니라 **라우트 템플릿**이다. URL을 그대로 쓰면 캠페인 수만큼
시계열이 생긴다. 매칭되지 않은 요청은 `unmatched` 한 값으로 모은다.

HTTP 지표는 히스토그램 하나뿐이다. `_count`가 요청 수, `status` 라벨이 5xx 비율,
`_bucket`이 p95를 준다. 별도 Counter를 두면 같은 사실을 두 번 세게 된다.

**라벨이 붙은 카운터는 첫 증가 전까지 시계열이 없다.** `adspectrum_publish_failures_total`은
발행 실패가 한 번도 없으면 질의 결과가 비어 있다. 대시보드에서는 `or vector(0)`으로 감싸야
패널이 "No data"로 보이지 않는다.
