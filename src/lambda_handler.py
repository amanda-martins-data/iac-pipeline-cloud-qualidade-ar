"""
lambda_handler.py
------------------
Função serverless que roda o pipeline de qualidade do ar na nuvem:

  1. Extrai dados (reais da OpenAQ ou sintéticos, conforme variável de
     ambiente OPENAQ_USE_SYNTHETIC) e grava o bruto no S3 (prefixo bronze/).
  2. Limpa, tipa e agrega os dados (lógica pura em Python, sem
     dependências pesadas — ver `transform.py`).
  3. Grava o agregado limpo no S3 (prefixo silver/) e faz upsert na
     tabela `air_quality_daily` do RDS Postgres (camada gold, pronta
     para BI).

Decisão de design: a lógica de transformação (`transform.py`) não
importa boto3 nem psycopg2 — é testável localmente, sem nuvem, sem
mocks pesados. Só o `lambda_handler` propriamente dito fala com AWS.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone

import boto3

from extract import generate_synthetic_payload, fetch_from_openaq
from transform import aggregate_daily
from load_rds import upsert_daily_aggregates

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("lambda_handler")

BUCKET_NAME = os.environ["BUCKET_NAME"]
OPENAQ_SECRET_ARN = os.environ.get("OPENAQ_SECRET_ARN", "")
DB_SECRET_ARN = os.environ["DB_SECRET_ARN"]
DB_HOST = os.environ["DB_HOST"]
DB_NAME = os.environ["DB_NAME"]
USE_SYNTHETIC = os.environ.get("OPENAQ_USE_SYNTHETIC", "true").lower() == "true"

s3 = boto3.client("s3")
secretsmanager = boto3.client("secretsmanager")


def _get_secret(secret_arn: str) -> str:
    resp = secretsmanager.get_secret_value(SecretId=secret_arn)
    return resp["SecretString"]


def handler(event, context):
    today = datetime.now(timezone.utc).date().isoformat()
    log.info("Iniciando execução do pipeline para %s (synthetic=%s)", today, USE_SYNTHETIC)

    # 1. Extract
    if USE_SYNTHETIC:
        payload = generate_synthetic_payload()
    else:
        api_key = _get_secret(OPENAQ_SECRET_ARN)
        payload = fetch_from_openaq(api_key)

    bronze_key = f"bronze/air_quality/ingestion_date={today}/data.json"
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=bronze_key,
        Body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
    )
    log.info("Bronze gravado em s3://%s/%s (%d registros)", BUCKET_NAME, bronze_key, len(payload["results"]))

    # 2. Transform (pure Python, sem dependências de nuvem)
    daily_rows = aggregate_daily(payload["results"])

    silver_key = f"silver/air_quality_daily/measured_date={today}/data.json"
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=silver_key,
        Body=json.dumps(daily_rows, ensure_ascii=False).encode("utf-8"),
    )
    log.info("Silver gravado em s3://%s/%s (%d linhas agregadas)", BUCKET_NAME, silver_key, len(daily_rows))

    # 3. Load na camada Gold (RDS Postgres)
    db_credentials = json.loads(_get_secret(DB_SECRET_ARN))
    rows_upserted = upsert_daily_aggregates(
        host=DB_HOST,
        dbname=DB_NAME,
        user=db_credentials["username"],
        password=db_credentials["password"],
        rows=daily_rows,
    )
    log.info("Gold (RDS) atualizado: %d linhas upsertadas", rows_upserted)

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "date": today,
                "bronze_key": bronze_key,
                "silver_key": silver_key,
                "rows_upserted": rows_upserted,
            }
        ),
    }
