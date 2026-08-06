# API 데이터 계약 초안 (v0.1)

> 참조 구현의 데이터 구조를 서버 책임으로 뒤집은 초안입니다. 백엔드와 프론트가 이 문서를 기준으로 계약을 확정하세요.
> 규칙: 날짜는 `YYYY-MM-DD`, 시각은 ISO 8601, 수치 단위는 필드명에 명시(mg/g/mL/%). 인증은 Bearer JWT 가정.

## 0. 공통 타입 (TypeScript)

```ts
type CkdStage = 'G2'|'3a'|'3b'|'G4'|'G5';
type Albuminuria = 'A1'|'A2'|'A3';
type Cause = '당뇨병성 신증'|'고혈압성 신경화증'|'사구체신염'|'다낭신'|'루푸스 신염';
type Severity = 'info'|'warn'|'crit';          // 배지 시맨틱 (그레이/앰버 틴트/진한 틴트)

interface Patient {
  id: string;
  name: string; sex: 'M'|'F'; age: number;
  stage: CkdStage; egfr: number; cause: Cause;
  albuminuria: Albuminuria;
  weightKg: number; heightCm: number; bmi: number;
  bp: { systolic: number; diastolic: number };
  isDiabetic: boolean;                          // 혈당 모듈 노출 스위치 (cause 파생이지만 명시 전달)
  flags: { label: string; severity: Severity }[]; // 목록 칩 (예: "K 5.6"=crit)
  lastVisit: string;                            // 최근 채혈/외래일
  recordingState: { pattern: 'steady'|'sparse'|'lapse'|'dropout'; stoppedDays?: number; recRate6m: number };
  connections: { diet: boolean; labs: boolean; checkup: boolean };
}

interface LabPanel {                            // 채혈 1회분
  date: string;
  egfr: number; creatinine: number;
  k: number; p: number; uacr: number;
  sbp: number;
  hba1c?: number; fpg?: number;                 // 당뇨 환자만
}

interface IntakeDay {                           // 앱 기록 1일 집계 (서버가 끼니 합산)
  date: string;
  recorded: boolean;
  na_mg: number; k_mg: number; p_mg: number; protein_g: number;
  fluid_ml?: number;
  smbgAvg_mgdl?: number;                        // 자가혈당 일평균 (당뇨만) — CGM 도입 시 tir_pct로 대체 예약
  meals: MealRecord[];
}

interface MealRecord {
  id: string; slot: '아침'|'점심'|'저녁'|'간식';
  name?: string; photoUrl?: string;             // 환자 업로드
  na_mg: number; k_mg: number; p_mg: number; protein_g: number;
  isProblem: boolean;                           // 서버 판정: 하루 초과 주요인 끼니
  impact?: string; advice?: string;             // 식품 DB 기반 문구
}

interface Limits {                              // 의사 설정 1일 제한 (환자 앱 목표와 동기화)
  na_mg: number; k_mg: number; p_mg: number; protein_g: number;
  fluid: { mode: 'record'|'limit'; limit_ml?: number };
  proteinBasis: { gPerKg: 0.6|0.8; source: 'A3'|'default' };  // KDIGO 파생 근거
  updatedAt: string; updatedBy: string;
}

interface Note {                                // SOAP 진료 메모
  id: string; date: string; type: '외래'|'식이상담'|'전화';
  s: string; o: string; a: string; p: string;   // o는 서버가 최신 수치·식이 요약 자동 생성 가능
  locked: boolean; signedAt?: string; signedBy?: string;
}

interface TaskItem {                            // 환자 실천 과제
  id: string; text: string; source: '제안'|'메모'|'직접';
  selected: boolean;                            // 선택된 것만 리포트/환자 앱에 노출
}

interface ScheduleItem { id: string; label: string; at: string; }   // D-day는 클라 계산
interface Medication { name: string; dose: string; timing: string; }
interface Adherence { medPct4w: number; }

interface ConnectionRequest {
  id: string; patientName: string; sex: 'M'|'F'; age: number;
  via: string;                                  // "이준혁 의사명 검색" 등
  requestedAt: string; state: 'pending'|'accepted'|'rejected';
  rejectReason?: string;                        // 거절 시 30일 재요청 제한 정책
}

interface PatientReport {                       // 환자 앱 전송 리포트 (환자용 PDF와 동일 소스)
  comment: string;
  includeTasks: boolean; includeSummary: boolean;
  includeMealPlan: boolean;                     // 의사 승인 필수 (승인 전 false 강제)
  mealPlanApproved: boolean;
}
```

## 1. 엔드포인트

### 인증
| Method | Path | 설명 |
|---|---|---|
| POST | `/auth/login` | `{email, password}` → `{otpRequired: true, txId}` |
| POST | `/auth/otp` | `{txId, code}` → `{accessToken, refreshToken, doctor}` |
| POST | `/auth/logout` | 토큰 무효화 (변경 시 타 기기 로그아웃 정책) |
| POST | `/access-requests` | **도입 신청(비인증)**: `{hospital, dept, name, contact}` → 접수. 메디올로지 백오피스에서 의료진 확인 후 승인·계정 발급 (SLA 영업일 2일). 스팸 방지 rate-limit 필요 |

### 환자
| Method | Path | 설명 |
|---|---|---|
| GET | `/patients?sort=warn\|visit\|stage\|reg\|name&q=` | 목록 (플래그·정렬 서버 계산) |
| GET | `/patients/:id` | Patient 상세 |
| GET | `/patients/:id/labs?limit=9` | LabPanel[] (차트용 시계열) |
| PATCH | `/patients/:id/labs/latest` | 수치 수정 모달 (검사 연동 전 수기 입력) |
| GET | `/patients/:id/intake?from&to` | IntakeDay[] — **일별 집계는 서버 책임**, 주 평균 집계는 클라 |
| GET | `/patients/:id/limits` / PUT 동일 경로 | 제한 조회/저장 → 저장 시 환자 앱 목표 push |
| GET | `/patients/:id/insights?window=28d` | 총평 행·해석 블록 문구의 원천 수치(평균·초과일·추세). 문장 조립은 클라 |

### 진료 흐름
| Method | Path | 설명 |
|---|---|---|
| GET/POST | `/patients/:id/notes` | SOAP 목록/작성 |
| POST | `/notes/:id/sign` | 전자서명 잠금 (이후 수정 불가, 사본 생성만) |
| GET/PUT | `/patients/:id/tasks` | 실천 과제 (selected 포함) |
| GET | `/patients/:id/schedule` | 검사·일정 |
| GET | `/patients/:id/medications` | 복용약 + 순응도 |
| POST | `/patients/:id/report` | PatientReport 전송 (환자 앱 + PDF 소스) |

### 연결·설정
| Method | Path | 설명 |
|---|---|---|
| GET | `/connection-requests?state=pending` | 알림 패널 (8건+ 대비 페이지네이션) |
| POST | `/connection-requests/:id/accept` · `/reject` | 거절 사유 선택, 30일 재요청 제한 |
| GET | `/connection-requests?state=processed` | 처리 이력 (감사 로그) |
| GET/PUT | `/doctor/profile` | 프로필 (검색 노출명 미리보기 동기화) |
| GET/PUT | `/doctor/alert-thresholds` | K/P 임계, 기록 중단 일수, 체중 급증 기준 |

## 2. 서버 책임 vs 클라이언트 책임

| 계산 | 담당 | 근거 |
|---|---|---|
| 끼니→일별 영양소 합산, 문제 끼니 판정 | 서버 | 식품 DB 접근 필요 |
| 플래그/배지 심각도(K≥5.5=crit 등) | 서버 | 알림 임계값 설정과 일관 |
| 초과일 카운트·4주 평균·기록률 | 서버 (`/insights`) | 총평·해석 문구의 단일 원천 |
| 주 평균 집계(>35일 창), D-day, % 모드 변환 | 클라 | 표시 로직 |
| 제한 변경 시 차트 재계산 | 클라(즉시) + 서버(저장) | UX 즉시성 |
| KDIGO 단백질 g/일 환산(체중×g/kg) | 서버 제공, 클라 표시 | Limits.proteinBasis |

## 3. CGM 인터페이스 예약 (계약만, 구현 보류)

```
GET /patients/:id/cgm?from&to → { date, tir_pct, tbr_pct, gmi }[]
```
도입 시 혈당 차트 하단 트랙을 `smbgAvg_mgdl` 막대 → `tir_pct` 막대(목표 >70%)로 교체. 저혈당(TBR>4%)은 알림 채널로.

## 4. 비당뇨 혈당 선별 규칙 (UI 위젯 없음 — 알림만)

채혈 패널 `fpg ≥ 126` 2회 또는 `≥100` 지속 시 서버가 "당뇨 선별 필요" 알림 발행. 프론트는 알림 패널에 표시만.
