-- Realized Gains Table
-- Shows closed positions with realized gains/losses and holding periods
-- Used for tax planning and performance analysis on sold positions
-- Grain: One row per closed position (sell transaction)
-- Refreshed on each data load via orchestrator procedure

CREATE OR REPLACE TABLE `portfolio_analytics.realized_gains` AS
SELECT
  symbol,
  account,
  purchase_date,
  ROUND(purchase_price, 2) AS purchase_price,
  sell_date,
  ROUND(sell_price, 2) AS sell_price,
  ROUND(shares, 2) AS shares,
  ROUND(shares * purchase_price, 2) AS cost_basis,
  ROUND(shares * sell_price, 2) AS proceeds,
  ROUND(shares * sell_price - shares * purchase_price, 2) AS gain_loss_amount,
  CASE
    WHEN shares * purchase_price > 0
    THEN ROUND((shares * sell_price - shares * purchase_price) / (shares * purchase_price) * 100, 2)
    ELSE NULL
  END AS gain_loss_pct,
  DATE_DIFF(sell_date, purchase_date, DAY) AS holding_period_days,
  ROUND(DATE_DIFF(sell_date, purchase_date, DAY) / 365.25, 2) AS holding_period_years,
  CASE
    WHEN DATE_DIFF(sell_date, purchase_date, DAY) > 365 THEN TRUE
    ELSE FALSE
  END AS is_long_term_gain,
  transaction_type
FROM `portfolio_analytics.fact_transactions`
WHERE sell_date IS NOT NULL
  AND sell_price IS NOT NULL
ORDER BY account, symbol, sell_date;
