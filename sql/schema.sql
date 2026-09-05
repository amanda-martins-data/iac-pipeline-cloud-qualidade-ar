-- Schema da camada Gold no RDS Postgres.
-- Aplicado uma única vez após o primeiro `terraform apply` (ver
-- docs/architecture.md, seção "Bootstrap do schema").

CREATE TABLE IF NOT EXISTS air_quality_daily (
    measured_date       date         NOT NULL,
    city                text         NOT NULL,
    parameter           text         NOT NULL,
    unit                text         NOT NULL,
    reading_count       integer      NOT NULL,
    avg_value           numeric(10, 2) NOT NULL,
    min_value           numeric(10, 2) NOT NULL,
    max_value           numeric(10, 2) NOT NULL,
    aqi_category_pm25   text,
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    PRIMARY KEY (measured_date, city, parameter)
);

CREATE INDEX IF NOT EXISTS idx_air_quality_daily_date
    ON air_quality_daily (measured_date DESC);
