from api.repository import MetricsRepository


class FakeTable:
    def __init__(self, pages: list[dict]) -> None:
        self._pages = pages
        self.requests: list[dict] = []

    def query(self, **kwargs):
        self.requests.append(kwargs)
        return self._pages[len(self.requests) - 1]


def test_query_returns_the_single_page_as_is():
    table = FakeTable([{"Items": [{"impressions": 1}]}])

    items = MetricsRepository(table).query("cmp-001", "2026-08-25T09:00", "2026-08-25T10:00")

    assert items == [{"impressions": 1}]
    assert "ExclusiveStartKey" not in table.requests[0]


def test_query_follows_last_evaluated_key_until_the_result_is_complete():
    # Query 한 번은 1MB까지만 읽는다. 이어 받지 않으면 긴 기간의 집계가 조용히 잘린다.
    last_key = {"pk": "CAMP#cmp-001", "sk": "TS#2026-08-25T09:30"}
    table = FakeTable(
        [
            {"Items": [{"impressions": 1}], "LastEvaluatedKey": last_key},
            {"Items": [{"impressions": 2}]},
        ]
    )

    items = MetricsRepository(table).query("cmp-001", "2026-08-25T09:00", "2026-08-25T10:00")

    assert items == [{"impressions": 1}, {"impressions": 2}]
    assert table.requests[1]["ExclusiveStartKey"] == last_key
