from boto3.dynamodb.conditions import Key

from .summary import sort_key


class MetricsRepository:
    def __init__(self, table) -> None:
        self._table = table

    def query(self, campaign_id: str, bucket_from: str, bucket_to: str) -> list[dict]:
        items: list[dict] = []
        request = {
            "KeyConditionExpression": Key("pk").eq(f"CAMP#{campaign_id}")
            & Key("sk").between(sort_key(bucket_from), sort_key(bucket_to)),
        }
        while True:
            response = self._table.query(**request)
            items.extend(response.get("Items", []))
            # Query 한 번은 1MB까지만 읽는다. 긴 기간을 조회하면 잘려서 오므로
            # LastEvaluatedKey가 없어질 때까지 이어 받는다.
            last_key = response.get("LastEvaluatedKey")
            if not last_key:
                return items
            request["ExclusiveStartKey"] = last_key
