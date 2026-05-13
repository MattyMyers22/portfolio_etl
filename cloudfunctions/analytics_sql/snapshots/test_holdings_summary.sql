-- Test Holdings Summary
-- Current holdings with purchase lots tracked separately, aggregated by account and symbol
-- Remaining shares calculated per lot (account, symbol, purchase_date, purchase_price)
-- Then aggregated to symbol level for cost basis and P&L % calculation

WITH purchase_lots AS (
  -- Calculate remaining shares for each purchase lot (buys minus sells for that specific lot)
  SELECT
    account,
    symbol,
    purchase_date,
    purchase_price,
    SUM(CASE 
      WHEN transaction_type IN ('buy', 'reinvestment') THEN shares
      ELSE -COALESCE(shares, 0)
    END) AS remaining_shares
  FROM `portfolio_analytics.fact_transactions`
  GROUP BY account, symbol, purchase_date, purchase_price
  HAVING remaining_shares > 0
),
latest_prices AS (
  -- Get the most recent price for each symbol
  SELECT
    symbol,
    close_price,
    ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY price_date DESC) AS rn
  FROM `portfolio_analytics.fact_prices`
),
lot_valuations AS (
  -- Value each lot at current price
  SELECT
    pl.account,
    pl.symbol,
    pl.purchase_date,
    pl.purchase_price,
    pl.remaining_shares,
    ROUND(pl.remaining_shares * pl.purchase_price, 2) AS lot_cost_basis,
    ROUND(lp.close_price, 2) AS current_price,
    ROUND(pl.remaining_shares * lp.close_price, 2) AS lot_current_value
  FROM purchase_lots pl
  LEFT JOIN latest_prices lp ON pl.symbol = lp.symbol AND lp.rn = 1
),
symbol_aggregates AS (
  -- Aggregate lots up to symbol level per account
  SELECT
    account,
    symbol,
    ROUND(SUM(remaining_shares), 2) AS total_shares,
    ROUND(SUM(lot_cost_basis), 2) AS total_cost_basis,
    ROUND(SUM(lot_current_value), 2) AS total_current_value,
    ROUND(SUM(lot_current_value) - SUM(lot_cost_basis), 2) AS unrealized_pl,
    CASE
      WHEN SUM(lot_cost_basis) > 0
      THEN ROUND((SUM(lot_current_value) - SUM(lot_cost_basis)) / SUM(lot_cost_basis) * 100, 2)
      ELSE NULL
    END AS unrealized_pl_pct
  FROM lot_valuations
  GROUP BY account, symbol
)
SELECT
  account,
  symbol,
  total_shares,
  ROUND(total_cost_basis / NULLIF(total_shares, 0), 2) AS avg_cost_per_share,
  total_cost_basis,
  ROUND(total_current_value / NULLIF(total_shares, 0), 2) AS current_price,
  total_current_value,
  unrealized_pl,
  unrealized_pl_pct,
  CURRENT_DATE() AS valuation_date
FROM symbol_aggregates
ORDER BY account, symbol;
