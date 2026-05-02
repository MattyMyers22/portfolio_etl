-- Price History with Transactions Table
-- Daily price history for each security with buy/sell transaction markers
-- Used to visualize price movements alongside transaction activity
-- Grain: One row per date per symbol (with transaction details if applicable)

CREATE OR REPLACE TABLE `portfolio_analytics.price_history_with_transactions` AS
WITH price_data AS (
  -- Get all daily prices
  SELECT
    Ticker AS symbol,
    date,
    close AS price,
    open,
    high,
    low,
    volume,
    ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
  FROM `portfolio_staging.stg_prices`
),
transaction_dates AS (
  -- Get buy and sell transactions
  SELECT
    symbol,
    purchase_date AS transaction_date,
    'buy' AS transaction_type,
    account,
    CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END AS buy_shares,
    0 AS sell_shares,
    CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN purchase_price ELSE NULL END AS buy_price,
    NULL AS sell_price
  FROM `portfolio_analytics.fact_transactions`
  WHERE transaction_type IN ('buy', 'reinvestment')
  
  UNION ALL
  
  SELECT
    symbol,
    sell_date AS transaction_date,
    'sell' AS transaction_type,
    account,
    0 AS buy_shares,
    CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END AS sell_shares,
    NULL AS buy_price,
    CASE WHEN transaction_type = 'sell' THEN sell_price ELSE NULL END AS sell_price
  FROM `portfolio_analytics.fact_transactions`
  WHERE transaction_type = 'sell' AND sell_date IS NOT NULL
)
SELECT
  pd.symbol,
  CAST(pd.date AS DATE) AS date,
  ROUND(pd.price, 2) AS close_price,
  ROUND(pd.open, 2) AS open_price,
  ROUND(pd.high, 2) AS high_price,
  ROUND(pd.low, 2) AS low_price,
  pd.volume,
  COALESCE(SUM(CASE WHEN td.transaction_type = 'buy' THEN td.buy_shares ELSE 0 END), 0) AS total_buy_shares,
  COALESCE(SUM(CASE WHEN td.transaction_type = 'sell' THEN td.sell_shares ELSE 0 END), 0) AS total_sell_shares,
  ROUND(COALESCE(AVG(CASE WHEN td.transaction_type = 'buy' THEN td.buy_price END), NULL), 2) AS avg_buy_price,
  ROUND(COALESCE(AVG(CASE WHEN td.transaction_type = 'sell' THEN td.sell_price END), NULL), 2) AS avg_sell_price,
  STRING_AGG(DISTINCT CASE WHEN td.transaction_type = 'buy' THEN td.account END, ', ') AS accounts_bought,
  STRING_AGG(DISTINCT CASE WHEN td.transaction_type = 'sell' THEN td.account END, ', ') AS accounts_sold,
  CASE WHEN SUM(CASE WHEN td.transaction_type = 'buy' THEN td.buy_shares ELSE 0 END) > 0 THEN TRUE ELSE FALSE END AS has_buy,
  CASE WHEN SUM(CASE WHEN td.transaction_type = 'sell' THEN td.sell_shares ELSE 0 END) > 0 THEN TRUE ELSE FALSE END AS has_sell
FROM price_data pd
LEFT JOIN transaction_dates td ON pd.symbol = td.symbol AND CAST(pd.date AS DATE) = CAST(td.transaction_date AS DATE)
WHERE pd.rn IS NOT NULL  -- Only include prices that exist
GROUP BY pd.symbol, pd.date, pd.price, pd.open, pd.high, pd.low, pd.volume
ORDER BY pd.symbol, pd.date DESC;
