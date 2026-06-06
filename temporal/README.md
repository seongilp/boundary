# Temporal — Durable Execution 데모 (결제 워크플로우)

긴 비즈니스 로직을 평범한 코드로 짜면, **워커가 죽든 재배포되든 멈춘 지점부터 자동 재개**된다.

## 데모: 결제 워크플로우
```
결제(charge) → 재고확보(reserve) → [8초 타이머] → 배송(ship)
```
- 재고확보는 일부러 2번 실패 → 3번째 성공 (**자동 재시도** 시각화)
- 8초 타이머는 메모리 안 잡는 **내구성 타이머**

## 실행
```bash
# 1) Temporal dev 서버 (서버 :7233 + Web UI :8233)
temporal server start-dev --ui-port 8233 &

# 2) 워커
python3 payment_app.py &

# 3) 주문 시작
python3 start_order.py order-1
# 결과: 결제완료(order-1) | 재고확보(order-1) | 배송시작(order-1)
```
Web UI: http://localhost:8233 → Workflows → 타임라인에서 재시도/타이머/이력 확인

## 검증한 것
- **자동 재시도**: reserve_inventory 가 `↻ 3` (2번 실패→성공) 으로 Web UI 타임라인에 표시
- **내구성(durability)**: 타이머 도중 워커를 `kill` → 재시작 → 워크플로우가 **이어서 완료** (order-demo-3)

## 핵심 개념
| 용어 | 뜻 |
|------|-----|
| Workflow | 오케스트레이션 코드 (결정적, 몇 초~몇 달) |
| Activity | 실제 부수효과 작업 — 실패 시 자동 재시도 |
| Worker | 코드를 실행하는 프로세스 (죽어도 됨) |
| Server | 이벤트 이력 저장 + 내구성 보장 |

## 어디 쓰나
결제/주문 사가, 프로비저닝, ETL, 스케줄 작업, 사람 승인 대기(며칠), 재시도 많은 외부 연동.
