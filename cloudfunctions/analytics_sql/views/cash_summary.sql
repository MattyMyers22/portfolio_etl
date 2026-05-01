-- Cash Summary Table
-- Shows cash position per account and its proportion of total portfolio
-- Integrates cash with securities holdings to calculate allocation percentage
-- Grain: One row per account
-- Refreshed on each data load via orchestrator procedure

CREATE OR REPLACE TABLE `portfolio_analytics.cash_summary` AS
WITH latest_cash AS (
  -- Get most recent cash balance per account
  SELECT
    account,
    cash_amount,
    date,
    ROW_NUMBER() OVER (PARTITION BY account ORDER BY date DESC) AS rn
  FROM `portfolio_analytics.fact_cash`
),
securities_value_by_account AS (
  -- Calculate total securities value per account (all current holdings)
  SELECT
    account,
    SUM(ch.current_shares * lp.current_price) AS total_securities_value
  FROM (
    SELECT
      symbol,
      account,
      SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) - 
        SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS current_shares
    FROM `portfolio_analytics.fact_transactions`
    GROUP BY symbol, account
    HAVING current_shares > 0
  ) ch
  LEFT JOIN (
    SELECT
      Ticker AS symbol,
      close AS current_price,
      ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
    FROM `portfolio_staging.stg_prices`
  ) lp ON ch.symbol = lp.symbol AND lp.rn = 1
  GROUP BY account
)
SELECT
  lc.account,
  ROUND(lc.cash_amount, 2) AS cash_amount,
  ROUND(COALESCE(sv.total_securities_value, 0), 2) AS total_securities_value,
  ROUND(lc.cash_amount + COALESCE(sv.total_securities_value, 0), 2) AS total_portfolio_value,
  CASE
    WHEN lc.cash_amount + COALESCE(sv.total_securities_value, 0) > 0
    THEN ROUND(lc.cash_amount / (lc.cash_amount + COALESCE(sv.total_securities_value, 0)) * 100, 2)
    ELSE 0
  END AS cash_pct_of_portfolio,
  CASE
    WHEN lc.cash_amount + COALESCE(sv.total_securities_value, 0) > 0
    THEN ROUND(COALESCE(sv.total_securities_value, 0) / (lc.cash_amount + COALESCE(sv.total_securities_value, 0)) * 100, 2)
    ELSE 0
  END AS securities_pct_of_portfolio,
  lc.date AS last_cash_update_date
FROM latest_cash lc
LEFT JOIN securities_value_by_account sv ON lc.account = sv.account
WHERE lc.rn = 1
ORDER BY lc.account;
