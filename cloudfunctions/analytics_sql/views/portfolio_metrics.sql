-- Portfolio Metrics Table
-- Real-time portfolio snapshot with holdings, performance, and allocation
-- Shows current holdings with unrealized gains, cash, total portfolio value, and S&P 500 comparison
-- Grain: One row per security per account (current holdings only)
-- Refreshed on each data load via orchestrator procedure

CREATE OR REPLACE TABLE `portfolio_analytics.portfolio_metrics` AS
WITH current_holdings AS (
  -- Aggregate current shares for each symbol/account (buys - sells)
  SELECT
    symbol,
    account,
    SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) AS shares_bought,
    SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS shares_sold,
    SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) - 
      SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS current_shares,
    AVG(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN purchase_price ELSE NULL END) AS avg_buy_price,
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
),
sp500_benchmark AS (
  -- Get S&P 500 price for comparison
  SELECT
    close AS sp500_price,
    date AS sp500_date,
    ROW_NUMBER() OVER (ORDER BY date DESC) AS rn
  FROM `portfolio_staging.stg_prices`
  WHERE Ticker = '^GSPC'
),
latest_cash AS (
  -- Get most recent cash balance per account
  SELECT
    account,
    cash_amount,
    date,
    ROW_NUMBER() OVER (PARTITION BY account ORDER BY date DESC) AS rn
  FROM `portfolio_analytics.fact_cash`
)
SELECT
  h.symbol,
  h.account,
  h.current_shares,
  ROUND(h.avg_buy_price, 2) AS avg_purchase_price,
  ROUND(cb.total_cost_basis, 2) AS cost_basis,
  ROUND(lp.current_price, 2) AS current_price,
  ROUND(h.current_shares * lp.current_price, 2) AS current_value,
  ROUND(h.current_shares * lp.current_price - cb.total_cost_basis, 2) AS unrealized_pl,
  CASE 
    WHEN cb.total_cost_basis > 0 
    THEN ROUND((h.current_shares * lp.current_price - cb.total_cost_basis) / cb.total_cost_basis * 100, 2)
    ELSE NULL 
  END AS unrealized_pl_pct,
  ROUND(DATE_DIFF(CURRENT_DATE(), EXTRACT(DATE FROM h.first_purchase_date), DAY) / 365.25, 2) AS years_held,
  lc.cash_amount AS account_cash,
  sb.sp500_price,
  ROUND(sb.sp500_price * h.current_shares * COALESCE((SELECT AVG(purchase_price) FROM `portfolio_analytics.fact_transactions` WHERE symbol = '^GSPC'), 1), 2) AS sp500_value_equivalent,
  h.first_purchase_date,
  h.last_transaction_date
FROM current_holdings h
LEFT JOIN cost_basis cb USING (symbol, account)
LEFT JOIN latest_prices lp ON h.symbol = lp.symbol AND lp.rn = 1
LEFT JOIN sp500_benchmark sb ON sb.rn = 1
LEFT JOIN latest_cash lc ON h.account = lc.account AND lc.rn = 1
ORDER BY h.account, h.symbol;
