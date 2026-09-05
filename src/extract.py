"""
extract.py
----------
Camada de extração, reaproveitando o padrão dos Projetos 01-03: dados
reais da OpenAQ (precisa de API key) ou um fixture sintético — para que
a Lambda funcione "out of the box" logo após o primeiro deploy, antes
mesmo de configurar credenciais externas.
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta, timezone

import requests

BASE_URL = "https://api.openaq.org/v3"

CITIES = {
    "São Paulo": [{"id": 1001, "name": "São Paulo - Cerqueira César"}],
    "Rio de Janeiro": [{"id": 2001, "name": "Rio de Janeiro - Centro"}],
    "Belo Horizonte": [{"id": 3001, "name": "Belo Horizonte - Pampulha"}],
}

PARAMETERS = [
    {"name": "pm25", "unit": "µg/m³", "range": (5, 60)},
    {"name": "pm10", "unit": "µg/m³", "range": (10, 90)},
    {"name": "o3", "unit": "ppb", "range": (5, 80)},
]


def generate_synthetic_payload(seed: int = 42) -> dict:
    """Gera um payload sintético no mesmo formato do payload real,
    para permitir rodar a Lambda sem credenciais externas."""
    rng = random.Random(seed)
    now = datetime.now(timezone.utc)
    records = []

    for city, stations in CITIES.items():
        for station in stations:
            for param in PARAMETERS:
                lo, hi = param["range"]
                records.append(
                    {
                        "parameter": param["name"],
                        "value": round(rng.uniform(lo, hi), 2),
                        "unit": param["unit"],
                        "date": {"utc": now.isoformat().replace("+00:00", "Z")},
                        "_city_query": city,
                        "_location_id": station["id"],
                        "_location_name": station["name"],
                    }
                )

    return {
        "extracted_at": now.isoformat(),
        "cities": list(CITIES.keys()),
        "record_count": len(records),
        "results": records,
        "_synthetic": True,
    }


def fetch_from_openaq(api_key: str, days_back: int = 1) -> dict:
    """Busca medições reais da API da OpenAQ v3."""
    session = requests.Session()
    session.headers.update({"X-API-Key": api_key})

    today = datetime.now(timezone.utc).date()
    date_from = (today - timedelta(days=days_back)).isoformat()
    date_to = today.isoformat()

    all_records = []
    for city in CITIES:
        locations = session.get(
            f"{BASE_URL}/locations", params={"iso": "BR", "city": city, "limit": 5}, timeout=30
        ).json().get("results", [])

        for loc in locations:
            measurements = session.get(
                f"{BASE_URL}/locations/{loc['id']}/measurements",
                params={"date_from": date_from, "date_to": date_to, "limit": 1000},
                timeout=30,
            ).json().get("results", [])
            for m in measurements:
                m["_city_query"] = city
                m["_location_id"] = loc["id"]
                m["_location_name"] = loc.get("name")
            all_records.extend(measurements)

    return {
        "extracted_at": datetime.now(timezone.utc).isoformat(),
        "cities": list(CITIES.keys()),
        "record_count": len(all_records),
        "results": all_records,
        "_synthetic": False,
    }
