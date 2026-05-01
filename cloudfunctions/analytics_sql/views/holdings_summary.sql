-- Holdings Summary Table
-- Simplified aggregate of current holdings by symbol and account
-- Shows holdings with cost basis, current value, and unrealized gains
-- Grain: One row per symbol per account (current holdings only)
-- Refreshed on each data load via orchestrator procedure

CREATE OR REPLACE TABLE `portfolio_analytics.holdings_summary` AS
WITH current_holdings AS (
  -- Aggregate current shares for each symbol/account (buys - sells)
  SELECT
    symbol,
    account,
    SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) AS shares_bought,
    SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS shares_sold,
    SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) - 
      SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS current_shares,
    COUNT(DISTINCT CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN purchase_date END) AS num_purchase_lots,
    MIN(purchase_date) AS first_purchase_date,
    MAX(COALESCE(sell_date, purchase_date)) AS last_transaction_date
  FROM `portfolio_analytics.fact_transactions`
  GROUP BY symbol, account
  HAVING current_shares > 0  -- Only current holdings
),
cost_basis AS (
  -- Calculate total cost basis for each holding (all purchases)
  SELECT
    symbol,
    account,
    SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares * purchase_price ELSE 0 END) AS total_cost_basis
  FROM `portfolio_analytics.fact_transactions`
  GROUP BY symbol, account
),
latest_prices AS (
  -- Get the most recent price for each symbol
  SELECT
    Ticker AS symbol,
    close AS current_price,
    ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
  FROM `portfolio_staging.stg_prices`
)
SELECT
  h.symbol,
  h.account,
  h.current_shares,
  ROUND(cb.total_cost_basis, 2) AS cost_basis,
  ROUND(h.current_shares * lp.current_price, 2) AS current_value,
  ROUND(h.current_shares * lp.current_price - cb.total_cost_basis, 2) AS unrealized_pl,
  CASE 
    WHEN cb.total_cost_basis > 0 
    THEN ROUND((h.current_shares * lp.current_price - cb.total_cost_basis) / cb.total_cost_basis * 100, 2)
    ELSE NULL 
  END AS unrealized_pl_pct,
  h.num_purchase_lots,
  h.first_purchase_date,
  h.last_transaction_date
FROM current_holdings h
LEFT JOIN cost_basis cb USING (symbol, account)
LEFT JOIN latest_prices lp ON h.symbol = lp.symbol AND lp.rn = 1
ORDER BY h.account, h.symbol;
