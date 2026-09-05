"""
load_rds.py
------------
Carrega os agregados diários (camada Gold) no RDS Postgres via upsert
(`ON CONFLICT ... DO UPDATE`), tornando a carga idempotente: reprocessar
o mesmo dia sobrescreve os valores em vez de duplicar linhas.

psycopg2-binary não vai empacotado no .zip da Lambda (adiciona ~30MB de
binário compilado para a distribuição errada é um erro comum). Em vez
disso, é fornecido como uma Lambda Layer pública (ARN configurável via
Terraform — ver `variables.tf`), mantendo o pacote de deploy pequeno.
"""

from __future__ import annotations

from datetime import timezone, datetime

import psycopg2
from psycopg2.extras import execute_values

UPSERT_SQL = """
    INSERT INTO air_quality_daily (
        measured_date, city, parameter, unit,
        reading_count, avg_value, min_value, max_value, aqi_category_pm25
    )
    VALUES %s
    ON CONFLICT (measured_date, city, parameter)
    DO UPDATE SET
        unit               = EXCLUDED.unit,
        reading_count      = EXCLUDED.reading_count,
        avg_value          = EXCLUDED.avg_value,
        min_value          = EXCLUDED.min_value,
        max_value          = EXCLUDED.max_value,
        aqi_category_pm25  = EXCLUDED.aqi_category_pm25,
        updated_at         = now();
"""


def upsert_daily_aggregates(
    host: str, dbname: str, user: str, password: str, rows: list[dict], port: int = 5432
) -> int:
    if not rows:
        return 0

    measured_date = datetime.now(timezone.utc).date().isoformat()
    values = [
        (
            measured_date,
            r["city"],
            r["parameter"],
            r["unit"],
            r["reading_count"],
            r["avg_value"],
            r["min_value"],
            r["max_value"],
            r["aqi_category_pm25"],
        )
        for r in rows
    ]

    conn = psycopg2.connect(host=host, port=port, dbname=dbname, user=user, password=password, connect_timeout=10)
    try:
        with conn.cursor() as cur:
            execute_values(cur, UPSERT_SQL, values)
        conn.commit()
    finally:
        conn.close()

    return len(values)
