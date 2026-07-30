# 신신당부 의사 대시보드 v2 — One-Pager 목업

CKD(만성신장질환) 환자 식이·예후 관리 솔루션 **신신당부**의 의료진용 대시보드 재설계 목업.

- 단일 HTML 파일(`index.html`) — 외부 의존성 없음, 데모 데이터(가상 환자 30명) 내장
- 4개 화면: 홈(검사×섭취 통합 차트) · 식단 상세(TOP5 + 일별 기록 마스터-디테일) · 진료 메모(SOAP) · 설정
- 기능 명세: Notion "기능명세서 v2" 문서 참조
- 디자인 전달: Figma `1mW13xV8NormDrZQIjtbw1` (메디올로지 팀)

© Mediology Inc. — 내부 검토·개발 전달용 목업이며 모든 환자 데이터는 합성 데이터입니다.

## 개발 착수 문서

- **[HANDOFF.md](HANDOFF.md)** — 프론트엔드 재구현 가이드 (스택·화면 구조·데이터 규칙·디자인 토큰·마일스톤·인수 기준)
- **[API.md](API.md)** — 서버 데이터 계약 초안 (타입·엔드포인트·서버/클라 책임 분담·CGM 예약)
- **[ESTIMATE_AND_API_REVIEW.md](ESTIMATE_AND_API_REVIEW.md)** — M1~M5 기간·비용 견적과 API 계약 수정 제안
- `index.html` / `demo.html`은 참조 구현 — 동작 기준이며, 이어서 개발하지 않습니다

## Cloud Run 배포

`main` 브랜치에 push 또는 merge되면
`sinsin-doctor-mockup-main-cloudbuild` 트리거가 `cloudbuild.yaml`을 실행합니다.

배포 과정은 다음과 같습니다.

1. 정적 소스 파일 검증
2. nginx 정적 컨테이너 빌드
3. Artifact Registry 이미지 push
4. `asia-northeast3`의 `sinsin-doctor-mockup` Cloud Run 서비스 배포
5. `/health`, `/`, `/demo.html` smoke test

Cloud Run은 배포 시 기본 `run.app` HTTPS 주소를 제공합니다. 커스텀 도메인은
별도 작업입니다. 현재 리전은 Cloud Run 직접 domain mapping 지원 대상이
아니므로 production 도메인은 global external Application Load Balancer,
Google-managed certificate, DNS를 연결하는 방식을 사용합니다.
