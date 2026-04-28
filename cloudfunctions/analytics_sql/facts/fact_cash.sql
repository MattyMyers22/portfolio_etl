-- Cash Position Fact Table
-- One row per date per account (sparse updates, not necessarily daily)
-- Tracks cash balances for portfolio accounts

CREATE OR REPLACE TABLE `portfolio_analytics.fact_cash` AS
SELECT
  account,
  CAST(date AS DATE) AS date,
  CAST(cash_amount AS FLOAT64) AS cash_amount,
  -- Add metadata
  CURRENT_TIMESTAMP() AS load_timestamp
FROM `portfolio_staging.stg_cash`
WHERE account IS NOT NULL
  AND date IS NOT NULL
  AND cash_amount IS NOT NULL
ORDER BY account, date;
