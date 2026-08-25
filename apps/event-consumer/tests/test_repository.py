from consumer.repository import MetricsRepository


class FakeTable:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def update_item(self, **kwargs) -> None:
        self.calls.append(kwargs)


def test_add_uses_an_atomic_add_for_every_counter():
    table = FakeTable()

    MetricsRepository(table).add(
        "CAMP#cmp-001",
        "TS#2026-08-25T09:30",
        {"impressions": 3, "clicks": 1, "conversions": 0, "cost_micro": 42},
    )

    call = table.calls[0]
    assert call["Key"] == {"pk": "CAMP#cmp-001", "sk": "TS#2026-08-25T09:30"}
    # ADD여야 여러 파드가 같은 분 버킷을 동시에 갱신해도 값이 덮이지 않는다.
    assert call["UpdateExpression"] == (
        "ADD impressions :impressions, clicks :clicks, "
        "conversions :conversions, cost_micro :cost_micro"
    )
    assert call["ExpressionAttributeValues"] == {
        ":impressions": 3,
        ":clicks": 1,
        ":conversions": 0,
        ":cost_micro": 42,
    }
