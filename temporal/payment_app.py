"""
Temporal 결제 워크플로우 데모.
  결제 → 재고확보 → (배송준비 타이머) → 배송
  재고확보 액티비티는 일부러 2번 실패하고 3번째에 성공 → Web UI 에서 자동 재시도가 보인다.
실행: python3 payment_app.py   (워커 시작)
"""
import asyncio
from datetime import timedelta

from temporalio import activity, workflow
from temporalio.client import Client
from temporalio.common import RetryPolicy
from temporalio.worker import Worker

TASK_QUEUE = "payments"


# ── Activities (실제 부수효과 작업; 실패하면 자동 재시도) ──
@activity.defn
async def charge_card(order_id: str) -> str:
    activity.logger.info(f"카드 결제: {order_id}")
    return f"결제완료({order_id})"


@activity.defn
async def reserve_inventory(order_id: str) -> str:
    attempt = activity.info().attempt
    activity.logger.info(f"재고확보 시도 #{attempt}: {order_id}")
    if attempt < 3:
        # 재고 서비스가 불안정하다고 가정 → 2번 실패
        raise RuntimeError(f"재고 서비스 일시 장애 (시도 #{attempt})")
    return f"재고확보({order_id})"


@activity.defn
async def ship(order_id: str) -> str:
    activity.logger.info(f"배송 시작: {order_id}")
    return f"배송시작({order_id})"


# ── Workflow (오케스트레이션; 죽어도 멈춘 곳부터 재개) ──
@workflow.defn
class PaymentWorkflow:
    @workflow.run
    async def run(self, order_id: str) -> str:
        opts = dict(
            start_to_close_timeout=timedelta(seconds=10),
            retry_policy=RetryPolicy(
                initial_interval=timedelta(seconds=1),
                backoff_coefficient=2.0,
                maximum_attempts=5,
            ),
        )
        r1 = await workflow.execute_activity(charge_card, order_id, **opts)
        r2 = await workflow.execute_activity(reserve_inventory, order_id, **opts)
        # 배송 준비 대기 (메모리 안 잡는 내구성 타이머)
        await workflow.sleep(timedelta(seconds=8))
        r3 = await workflow.execute_activity(ship, order_id, **opts)
        return f"{r1} | {r2} | {r3}"


async def main():
    client = await Client.connect("localhost:7233")
    worker = Worker(
        client,
        task_queue=TASK_QUEUE,
        workflows=[PaymentWorkflow],
        activities=[charge_card, reserve_inventory, ship],
    )
    print(f"워커 시작 (task_queue={TASK_QUEUE}) — Ctrl-C 로 종료")
    await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
