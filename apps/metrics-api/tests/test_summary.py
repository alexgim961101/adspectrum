from datetime import UTC, datetime
from decimal import Decimal

import pytest

from api.summary import default_range, format_bucket, parse_bucket, sort_key, summarize


def test_summarize_adds_up_every_bucket():
    totals = summarize(
        [
            {"impressions": 10, "clicks": 2, "conversions": 1, "cost_micro": 500},
            {"impressions": 30, "clicks": 6, "conversions": 0, "cost_micro": 1_500},
        ]
    )

    assert totals.buckets == 2
    assert totals.impressions == 40
    assert totals.clicks == 8
    assert totals.conversions == 1
    assert totals.cost_micro == 2_000


def test_summarize_converts_dynamodb_decimals_to_int():
    # 리소스 API는 숫자를 Decimal로 준다. 그대로 두면 응답에 Decimal이 새어 나간다.
    totals = summarize([{"impressions": Decimal("10"), "cost_micro": Decimal("500")}])

    assert isinstance(totals.impressions, int)
    assert totals.impressions == 10
    assert totals.clicks == 0


def test_ratios_are_computed_from_the_totals():
    totals = summarize(
        [{"impressions": 1_000, "clicks": 50, "conversions": 5, "cost_micro": 10_000}]
    )

    assert totals.ctr == pytest.approx(0.05)
    assert totals.cvr == pytest.approx(0.1)
    assert totals.cpc_micro == pytest.approx(200.0)


def test_ratios_are_undefined_rather_than_zero_when_the_denominator_is_zero():
    # 노출이 없는 구간을 CTR 0%로 그리면 성과가 나쁜 것처럼 보인다.
    totals = summarize([])

    assert totals.ctr is None
    assert totals.cvr is None
    assert totals.cpc_micro is None


def test_parse_bucket_reads_the_minute_format_as_kst():
    moment = parse_bucket("2026-08-25T09:30", "from")

    assert moment.isoformat() == "2026-08-25T09:30:00+09:00"


@pytest.mark.parametrize("value", ["2026-08-25", "2026-08-25 09:30", "09:30", "", "oops"])
def test_parse_bucket_rejects_anything_else(value):
    with pytest.raises(ValueError, match="2026-08-25T09:30"):
        parse_bucket(value, "from")


def test_default_range_covers_the_last_hour_in_kst():
    now = datetime(2026, 8, 25, 3, 15, tzinfo=UTC)  # KST 12:15

    assert default_range(now) == ("2026-08-25T11:15", "2026-08-25T12:15")


def test_sort_key_keeps_lexical_order_equal_to_chronological_order():
    earlier = sort_key(format_bucket(datetime(2026, 8, 25, 9, 30, tzinfo=UTC)))
    later = sort_key(format_bucket(datetime(2026, 8, 25, 10, 0, tzinfo=UTC)))

    assert earlier < later
