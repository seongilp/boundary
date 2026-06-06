"""주문 워크플로우 시작 + 결과 대기. 실행: python3 start_order.py [order-id]"""
import asyncio
import sys

from temporalio.client import Client

from payment_app import PaymentWorkflow, TASK_QUEUE


async def main():
    order_id = sys.argv[1] if len(sys.argv) > 1 else "order-1234"
    client = await Client.connect("localhost:7233")
    handle = await client.start_workflow(
        PaymentWorkflow.run, order_id, id=order_id, task_queue=TASK_QUEUE
    )
    print(f"워크플로우 시작: {handle.id}")
    print(f"Web UI: http://localhost:8233/namespaces/default/workflows/{handle.id}")
    print("결과 대기 중...")
    print("결과:", await handle.result())


if __name__ == "__main__":
    asyncio.run(main())
