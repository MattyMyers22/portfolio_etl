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
    AVG(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN purchase_price ELSE NULL END) AS avg_buy_price,
    MIN(purchase_date) AS first_purchase_date,
    MAX(COALESCE(sell_date, purchase_date)) AS last_transaction_date
  FROM `portfolio_analytics.fact_transactions`
  GROUP BY symbol, account
  HAVING current_shares > 0  -- Only current holdings
),
account_totals AS (
  -- Calculate total portfolio value per account
  SELECT
    account,
    SUM(CASE WHEN current_shares > 0 THEN current_shares * lp.current_price ELSE 0 END) + COALESCE(SUM(lc.cash_amount), 0) AS account_total_value
  FROM (
    SELECT symbol, account, 
      SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) - 
        SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS current_shares
    FROM `portfolio_analytics.fact_transactions`
    GROUP BY symbol, account
    HAVING current_shares > 0
  ) ch
  LEFT JOIN (
    SELECT Ticker AS symbol, close AS current_price,
      ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
    FROM `portfolio_staging.stg_prices`
  ) lp ON ch.symbol = lp.symbol AND lp.rn = 1
  LEFT JOIN (
    SELECT account, cash_amount,
      ROW_NUMBER() OVER (PARTITION BY account ORDER BY date DESC) AS rn
    FROM `portfolio_analytics.fact_cash`
  ) lc ON ch.account = lc.account AND lc.rn = 1
  GROUP BY account
),
sp500_data AS (
  -- Get S&P 500 prices for comparison
  SELECT
    COALESCE(
      (SELECT close FROM `portfolio_staging.stg_prices` WHERE Ticker = '^GSPC' ORDER BY date DESC LIMIT 1),
      0
    ) AS sp500_current_price
),
sp500_on_purchase_date AS (
  -- Get S&P 500 price on or before each holding's first purchase date
  SELECT
    ch.symbol,
    ch.account,
    COALESCE(
      (SELECT close FROM `portfolio_staging.stg_prices` 
       WHERE Ticker = '^GSPC' AND date <= ch.first_purchase_date 
       ORDER BY date DESC LIMIT 1),
      (SELECT close FROM `portfolio_staging.stg_prices` 
       WHERE Ticker = '^GSPC' 
       ORDER BY date DESC LIMIT 1)
    ) AS sp500_purchase_price
  FROM current_holdings ch
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
  h.last_transaction_date,
  CASE
    WHEN at.account_total_value > 0
    THEN ROUND(h.current_shares * lp.current_price / at.account_total_value * 100, 2)
    ELSE 0
  END AS position_pct_of_account,
  CASE
    WHEN sp500pp.sp500_purchase_price > 0 AND sd.sp500_current_price > 0
    THEN ROUND(
      ((lp.current_price - h.avg_buy_price) / h.avg_buy_price * 100) -
      ((sd.sp500_current_price - sp500pp.sp500_purchase_price) / sp500pp.sp500_purchase_price * 100),
      2
    )
    ELSE NULL
  END AS vs_sp500_pl_pct
FROM current_holdings h
LEFT JOIN cost_basis cb USING (symbol, account)
LEFT JOIN latest_prices lp ON h.symbol = lp.symbol AND lp.rn = 1
LEFT JOIN account_totals at ON h.account = at.account
LEFT JOIN sp500_data sd ON TRUE
LEFT JOIN sp500_on_purchase_date sp500pp ON h.symbol = sp500pp.symbol AND h.account = sp500pp.account
ORDER BY h.account, h.symbol;
