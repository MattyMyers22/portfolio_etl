-- Transaction-Level Fact Table
-- One row per buy/sell transaction from the staging transactions table
-- Serves as the foundation for holdings and realized gains analysis

CREATE OR REPLACE TABLE `portfolio_analytics.fact_transactions` AS
SELECT
  symbol,
  account,
  transaction_type,
  purchase_date,
  CAST(shares AS FLOAT64) AS shares,
  CAST(purchase_price AS FLOAT64) AS purchase_price,
  sell_date,
  CAST(sell_price AS FLOAT64) AS sell_price,
  -- Add metadata
  CURRENT_TIMESTAMP() AS load_timestamp
FROM `portfolio_staging.stg_transactions`
WHERE symbol IS NOT NULL
  AND account IS NOT NULL
  AND purchase_date IS NOT NULL
ORDER BY symbol, account, purchase_date, COALESCE(sell_date, purchase_date);
