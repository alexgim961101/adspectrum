// metrics-api에 일정한 RPS를 흘려보낸다.
//
// 두 가지 용도로 쓴다.
//   1. API 자체의 부하 특성 확인 (p95, 에러율)
//   2. 카나리 배포 중 트래픽 공급 — 요청이 없으면 카나리 파드의 5xx 비율을
//      계산할 표본이 없어 분석이 아무것도 판단하지 못한다.
//
//   k6 run -e BASE_URL=http://<ALB DNS> loadtest/k6-api.js
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL;
const RPS = Number(__ENV.RPS || 30);
const DURATION = __ENV.DURATION || '10m';

// generator가 쓰는 캠페인 ID와 같은 범위다 (docs/API.md). 한 캠페인만 계속
// 두드리면 DynamoDB의 같은 파티션에만 부하가 걸려 실제 조회 패턴과 달라진다.
const CAMPAIGNS = Array.from({ length: 10 }, (_, i) => `cmp-${String(i + 1).padStart(3, '0')}`);

export const options = {
  scenarios: {
    steady: {
      // 도착률 고정. VU 수를 고정하는 방식은 응답이 느려지면 요청이 저절로
      // 줄어들어, 느려진 상황에서의 부하를 재현하지 못한다.
      executor: 'constant-arrival-rate',
      rate: RPS,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: RPS,
      maxVUs: RPS * 4,
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    // 결함 주입 데모에서는 이 기준을 일부러 넘긴다. 실패해도 부하는 계속
    // 흘려야 하므로 abortOnFail을 켜지 않는다.
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const campaign = CAMPAIGNS[Math.floor(Math.random() * CAMPAIGNS.length)];
  const res = http.get(`${BASE_URL}/campaigns/${campaign}/metrics`, {
    tags: { name: 'campaign-metrics' },
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}
