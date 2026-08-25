import json
import logging

from .metrics import EVENTS_PUBLISHED, PUBLISH_FAILURES

logger = logging.getLogger(__name__)


class Publisher:
    def __init__(self, sqs_client, queue_url: str) -> None:
        self._sqs = sqs_client
        self._queue_url = queue_url

    def publish(self, events: list[dict]) -> int:
        """배치를 발행하고 실제로 접수된 건수를 돌려준다."""
        if not events:
            return 0

        entries = [
            {"Id": str(index), "MessageBody": json.dumps(event)}
            for index, event in enumerate(events)
        ]
        response = self._sqs.send_message_batch(QueueUrl=self._queue_url, Entries=entries)

        # SendMessageBatch의 부분 실패는 예외가 아니라 응답 본문의 Failed로 온다.
        # 여기를 확인하지 않으면 이벤트가 조용히 사라지고 지표만 정상으로 보인다.
        failed = response.get("Failed", [])
        failed_ids = {entry["Id"] for entry in failed}

        for index, event in enumerate(events):
            if str(index) in failed_ids:
                continue
            EVENTS_PUBLISHED.labels(event_type=event["event_type"]).inc()

        for entry in failed:
            PUBLISH_FAILURES.labels(code=entry.get("Code", "Unknown")).inc()
            logger.warning(
                "sqs rejected batch entry",
                extra={
                    "context": {
                        "code": entry.get("Code"),
                        "message": entry.get("Message"),
                        "sender_fault": entry.get("SenderFault"),
                    }
                },
            )

        return len(events) - len(failed)
