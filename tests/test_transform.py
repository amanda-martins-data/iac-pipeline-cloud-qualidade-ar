"""
Testes da camada de transformação — 100% offline, sem AWS.
Roda com: python -m pytest tests/
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from transform import aggregate_daily, _aqi_category_pm25


def test_aggregate_daily_groups_by_city_and_parameter():
    records = [
        {"_city_query": "São Paulo", "parameter": "pm25", "unit": "µg/m³", "value": 10.0},
        {"_city_query": "São Paulo", "parameter": "pm25", "unit": "µg/m³", "value": 20.0},
        {"_city_query": "São Paulo", "parameter": "o3", "unit": "ppb", "value": 30.0},
    ]

    rows = aggregate_daily(records)

    assert len(rows) == 2
    pm25_row = next(r for r in rows if r["parameter"] == "pm25")
    assert pm25_row["reading_count"] == 2
    assert pm25_row["avg_value"] == 15.0
    assert pm25_row["min_value"] == 10.0
    assert pm25_row["max_value"] == 20.0


def test_aggregate_daily_ignores_negative_and_null_values():
    records = [
        {"_city_query": "São Paulo", "parameter": "pm25", "unit": "µg/m³", "value": 10.0},
        {"_city_query": "São Paulo", "parameter": "pm25", "unit": "µg/m³", "value": -5.0},
        {"_city_query": "São Paulo", "parameter": "pm25", "unit": "µg/m³", "value": None},
    ]

    rows = aggregate_daily(records)

    assert len(rows) == 1
    assert rows[0]["reading_count"] == 1
    assert rows[0]["avg_value"] == 10.0


def test_aqi_category_only_applies_to_pm25():
    records = [
        {"_city_query": "São Paulo", "parameter": "o3", "unit": "ppb", "value": 200.0},
    ]

    rows = aggregate_daily(records)

    assert rows[0]["aqi_category_pm25"] is None


def test_aqi_category_boundaries():
    assert _aqi_category_pm25(12.0) == "Boa"
    assert _aqi_category_pm25(12.1) == "Moderada"
    assert _aqi_category_pm25(35.4) == "Moderada"
    assert _aqi_category_pm25(35.5) == "Insalubre p/ grupos sensíveis"
    assert _aqi_category_pm25(55.5) == "Insalubre"
    assert _aqi_category_pm25(150.5) == "Muito insalubre"


def test_aggregate_daily_sorts_by_city_then_parameter():
    records = [
        {"_city_query": "Rio de Janeiro", "parameter": "pm25", "unit": "µg/m³", "value": 10.0},
        {"_city_query": "Belo Horizonte", "parameter": "o3", "unit": "ppb", "value": 10.0},
    ]

    rows = aggregate_daily(records)

    assert [r["city"] for r in rows] == ["Belo Horizonte", "Rio de Janeiro"]
