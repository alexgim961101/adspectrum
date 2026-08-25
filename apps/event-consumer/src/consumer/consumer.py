import logging

from botocore.exceptions import BotoCoreError, ClientError

from .aggregator import COUNTER_BY_EVENT_TYPE, Aggregate, BucketKey, aggregate
from .metrics import BATCH_FLUSH_SECONDS, EVENTS_CONSUMED, MESSAGES_INVALID, WRITE_FAILURES
from .repository import MetricsRepository

logger = logging.getLogger(__name__)

SQS_BATCH_LIMIT = 10
LONG_POLL_SECONDS = 20

EVENT_TYPE_BY_COUNTER = {counter: event for event, counter in COUNTER_BY_EVENT_TYPE.items()}


class Consumer:
    def __init__(
        self,
        sqs_client,
        queue_url: str,
        repository: MetricsRepository,
        batch_size: int = SQS_BATCH_LIMIT,
    ) -> None:
        self._sqs = sqs_client
        self._queue_url = queue_url
        self._repository = repository
        self._batch_size = min(batch_size, SQS_BATCH_LIMIT)
        self._stopped = False

    def stop(self, *_) -> None:
        # KEDA가 scale-in 할 때 SIGTERM이 온다. 처리 중인 배치는 끝내고 나간다.
        logger.info("shutdown requested")
        self._stopped = True

    def run_once(self) -> int:
        """한 번 폴링해 삭제까지 마친 메시지 수를 돌려준다."""
        response = self._sqs.receive_message(
            QueueUrl=self._queue_url,
            MaxNumberOfMessages=self._batch_size,
            # 롱 폴링. 빈 응답을 받으려고 초당 수십 번 호출하는 비용을 없앤다.
            WaitTimeSeconds=LONG_POLL_SECONDS,
        )
        messages = response.get("Messages", [])
        if not messages:
            return 0

        buckets, invalid = aggregate(messages)
        if invalid:
            MESSAGES_INVALID.inc(invalid)

        handles = self._flush(buckets)
        self._delete(handles)
        return len(handles)

    def run(self) -> None:
        while not self._stopped:
            self.run_once()

    def _flush(self, buckets: dict[BucketKey, Aggregate]) -> list[str]:
        """쓰기에 성공한 버킷의 ReceiptHandle만 돌려준다."""
        handles: list[str] = []
        with BATCH_FLUSH_SECONDS.time():
            for (pk, sk), entry in buckets.items():
                try:
                    self._repository.add(pk, sk, entry.counters)
                except (ClientError, BotoCoreError):
                    # 삼키고 삭제하면 이벤트가 사라진다. 남겨 두면 SQS가 다시 준다.
                    WRITE_FAILURES.inc()
                    logger.exception(
                        "aggregate write failed, leaving messages for redelivery",
                        extra={"context": {"pk": pk, "sk": sk}},
                    )
                    continue

                for counter, event_type in EVENT_TYPE_BY_COUNTER.items():
                    if entry.counters[counter]:
                        EVENTS_CONSUMED.labels(event_type=event_type).inc(entry.counters[counter])
                handles.extend(entry.receipt_handles)
        return handles

    def _delete(self, handles: list[str]) -> None:
        for start in range(0, len(handles), SQS_BATCH_LIMIT):
            window = handles[start : start + SQS_BATCH_LIMIT]
            response = self._sqs.delete_message_batch(
                QueueUrl=self._queue_url,
                Entries=[
                    {"Id": str(index), "ReceiptHandle": handle}
                    for index, handle in enumerate(window)
                ],
            )
            failed = response.get("Failed", [])
            if failed:
                # 이미 DynamoDB에 반영한 메시지다. 삭제에 실패하면 가시성 타임아웃 후
                # 다시 받아 중복 집계된다 — SPEC 3장에서 허용한 at-least-once 오차.
                logger.warning(
                    "failed to delete processed messages",
                    extra={"context": {"count": len(failed), "codes": [f["Code"] for f in failed]}},
                )
