from .aggregator import COUNTER_NAMES

# ADD는 속성이 없으면 0에서 시작하고 항목 자체가 없으면 항목을 만든다.
# 덕분에 "먼저 읽고 없으면 만들고 더한다"는 read-modify-write가 필요 없다.
# 여러 consumer 파드가 같은 분 버킷을 동시에 갱신해도 원자적으로 누적된다.
UPDATE_EXPRESSION = "ADD " + ", ".join(f"{name} :{name}" for name in COUNTER_NAMES)


class MetricsRepository:
    def __init__(self, table) -> None:
        self._table = table

    def add(self, pk: str, sk: str, counters: dict[str, int]) -> None:
        self._table.update_item(
            Key={"pk": pk, "sk": sk},
            UpdateExpression=UPDATE_EXPRESSION,
            ExpressionAttributeValues={f":{name}": counters[name] for name in COUNTER_NAMES},
        )
