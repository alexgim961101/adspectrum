# 외부에서 가져온 정책

이 디렉터리의 파일은 직접 작성하지 않고 벤더가 발행한 것을 그대로 가져온 것이다.
갱신할 때는 아래 출처에서 다시 받고, 어떤 동작이 추가·삭제됐는지 diff로 확인한 뒤 커밋한다.

| 파일 | 출처 | 버전 |
|---|---|---|
| `aws-load-balancer-controller.json` | [kubernetes-sigs/aws-load-balancer-controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.5.0/docs/install/iam_policy.json) | v3.5.0 |

## 왜 직접 작성하지 않는가

이 프로젝트의 다른 IRSA 정책은 전부 파드가 실제로 호출하는 API만 나열한 최소 권한이다.
Load Balancer Controller만 예외인데, 컨트롤러가 ALB의 수명주기 전체(리스너, 대상 그룹,
규칙, 보안 그룹, 태그)를 관리하느라 필요한 동작이 80개가 넘고 버전마다 바뀐다.
직접 추리면 누락된 권한 때문에 Ingress 생성이 실패하고 원인은 컨트롤러 로그에만 남는다.

대신 무엇이 들어 있는지는 파악하고 쓴다. v3.5.0 기준 내역은 다음과 같다.

| 서비스 | 동작 수 | 용도 |
|---|---|---|
| elasticloadbalancing | 43 | ALB·NLB와 리스너·대상 그룹 생성 및 관리 |
| ec2 | 25 | 서브넷·보안 그룹 조회와 규칙 관리 |
| wafv2 / waf-regional | 8 | WAF 연동 (이 프로젝트 미사용) |
| shield | 4 | DDoS 보호 연동 (이 프로젝트 미사용) |
| iam | 3 | 서비스 연결 역할 생성, 인증서 조회 |
| acm | 2 | HTTPS 인증서 조회 (이 프로젝트 미사용) |
| cognito-idp | 1 | 인증 연동 (이 프로젝트 미사용) |

WAF·Shield·ACM·Cognito 관련 권한은 이 프로젝트에서 쓰지 않는다. 잘라낼 수는 있지만
벤더 정책과 어긋나 다음 버전 업그레이드에서 조용히 깨질 수 있어 그대로 둔다.
