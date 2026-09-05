"""
transform.py
------------
Agregação diária em Python puro — deliberadamente sem pandas/numpy
para não exigir uma Lambda Layer só para a etapa de transformação.
100% testável localmente, sem AWS, sem mocks: é só uma função pura
que recebe uma lista de registros e devolve uma lista de linhas
agregadas.
"""

from __future__ import annotations

from collections import defaultdict


def _aqi_category_pm25(avg_value: float) -> str | None:
    """Classificação de AQI simplificada (escala EPA) — mesma regra
    de negócio do Projeto 03, agora em Python puro."""
    if avg_value <= 12.0:
        return "Boa"
    if avg_value <= 35.4:
        return "Moderada"
    if avg_value <= 55.4:
        return "Insalubre p/ grupos sensíveis"
    if avg_value <= 150.4:
        return "Insalubre"
    return "Muito insalubre"


def aggregate_daily(records: list[dict]) -> list[dict]:
    """Agrega medições brutas por (cidade, poluente), calculando
    média/min/max e a classificação de AQI quando aplicável (PM2.5)."""
    groups: dict[tuple[str, str, str], list[float]] = defaultdict(list)

    for r in records:
        value = r.get("value")
        if value is None or value < 0:
            continue  # mesma regra de limpeza dos projetos anteriores
        city = r.get("_city_query")
        parameter = r.get("parameter")
        unit = r.get("unit")
        groups[(city, parameter, unit)].append(float(value))

    rows = []
    for (city, parameter, unit), values in groups.items():
        avg_value = round(sum(values) / len(values), 2)
        row = {
            "city": city,
            "parameter": parameter,
            "unit": unit,
            "reading_count": len(values),
            "avg_value": avg_value,
            "min_value": round(min(values), 2),
            "max_value": round(max(values), 2),
            "aqi_category_pm25": _aqi_category_pm25(avg_value) if parameter == "pm25" else None,
        }
        rows.append(row)

    return sorted(rows, key=lambda r: (r["city"], r["parameter"]))
