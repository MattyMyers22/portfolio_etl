-- Historical Prices Fact Table
-- One row per security per date from the staging prices table
-- Grain: date, symbol (one price snapshot per security per trading day)
-- Serves as foundation for price history analysis and technical indicators

CREATE OR REPLACE TABLE `portfolio_analytics.fact_prices` AS
WITH price_enrichment AS (
  SELECT
    CAST(date AS DATE) AS price_date,
    Ticker AS symbol,
    CAST(open AS FLOAT64) AS open_price,
    CAST(high AS FLOAT64) AS high_price,
    CAST(low AS FLOAT64) AS low_price,
    CAST(close AS FLOAT64) AS close_price,
    CAST(volume AS INT64) AS volume,
    -- Calculate daily metrics
    ROUND(CAST(close AS FLOAT64) - CAST(open AS FLOAT64), 4) AS daily_change,
    CASE 
      WHEN CAST(open AS FLOAT64) != 0 
      THEN ROUND((CAST(close AS FLOAT64) - CAST(open AS FLOAT64)) / CAST(open AS FLOAT64) * 100, 2)
      ELSE NULL
    END AS daily_change_pct,
    -- High-Low range for volatility
    ROUND(CAST(high AS FLOAT64) - CAST(low AS FLOAT64), 4) AS daily_range,
    CASE 
      WHEN CAST(low AS FLOAT64) != 0
      THEN ROUND((CAST(high AS FLOAT64) - CAST(low AS FLOAT64)) / CAST(low AS FLOAT64) * 100, 2)
      ELSE NULL
    END AS daily_range_pct,
    -- Price position within day's range (0=low, 1=high)
    CASE
      WHEN (CAST(high AS FLOAT64) - CAST(low AS FLOAT64)) != 0
      THEN ROUND((CAST(close AS FLOAT64) - CAST(low AS FLOAT64)) / (CAST(high AS FLOAT64) - CAST(low AS FLOAT64)), 4)
      ELSE NULL
    END AS close_position_in_range,
    -- Previous close comparison (if available)
    LAG(CAST(close AS FLOAT64)) OVER (PARTITION BY Ticker ORDER BY date) AS previous_close,
    CURRENT_TIMESTAMP() AS load_timestamp
  FROM `portfolio_staging.stg_prices`
)
SELECT
  price_date,
  symbol,
  open_price,
  high_price,
  low_price,
  close_price,
  volume,
  daily_change,
  daily_change_pct,
  daily_range,
  daily_range_pct,
  close_position_in_range,
  ROUND(close_price - COALESCE(previous_close, close_price), 4) AS price_change_from_previous,
  CASE
    WHEN COALESCE(previous_close, close_price) != 0
    THEN ROUND((close_price - COALESCE(previous_close, close_price)) / COALESCE(previous_close, close_price) * 100, 2)
    ELSE NULL
  END AS price_change_from_previous_pct,
  volume > 0 AS is_trading_day,
  load_timestamp
FROM price_enrichment
WHERE symbol IS NOT NULL
  AND price_date IS NOT NULL
  AND close_price IS NOT NULL
ORDER BY symbol, price_date DESC;
