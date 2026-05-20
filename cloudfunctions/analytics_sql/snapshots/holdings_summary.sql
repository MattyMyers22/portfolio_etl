-- Holdings Summary Materialized Table
-- Current holdings with purchase lots tracked separately, aggregated by account and symbol
-- Plus cash values by account shown as separate rows
-- Includes percentage of total account value (holdings + cash) for each row

CREATE OR REPLACE TABLE `portfolio_analytics.holdings_summary` AS
WITH
  purchase_lots AS (
    -- Calculate remaining shares for each purchase lot (buys minus sells for that specific lot)
    SELECT
      account,
      symbol,
      purchase_date,
      purchase_price,
      SUM(
        CASE
          WHEN transaction_type IN ('buy', 'reinvestment') THEN shares
          ELSE -COALESCE(shares, 0)
          END)
        AS remaining_shares
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
  sp500_benchmark AS (
    -- Get S&P 500 prices: current and at each purchase date
    SELECT
      'sp500_current' AS benchmark_type,
      CAST(NULL AS DATE) AS purchase_date,
      fp_current.close_price AS sp500_price
    FROM `portfolio_analytics.fact_prices` fp_current
    WHERE fp_current.symbol = '^GSPC'
      AND fp_current.price_date = (
        SELECT MAX(price_date) FROM `portfolio_analytics.fact_prices` 
        WHERE symbol = '^GSPC'
      )
    UNION ALL
    -- S&P 500 price on each purchase date
    SELECT
      'sp500_at_purchase' AS benchmark_type,
      pl.purchase_date,
      fp_hist.close_price AS sp500_price
    FROM purchase_lots pl
    LEFT JOIN `portfolio_analytics.fact_prices` fp_hist
      ON fp_hist.symbol = '^GSPC'
      AND fp_hist.price_date = pl.purchase_date
  ),
  lot_valuations AS (
    -- Value each lot at current price and calculate benchmark comparison
    SELECT
      pl.account,
      pl.symbol,
      pl.purchase_date,
      pl.purchase_price,
      pl.remaining_shares,
      ROUND(pl.remaining_shares * pl.purchase_price, 2) AS lot_cost_basis,
      ROUND(lp.close_price, 2) AS current_price,
      ROUND(pl.remaining_shares * lp.close_price, 2) AS lot_current_value,
      -- S&P 500 benchmark prices
      ROUND(sp500_purch.sp500_price, 2) AS sp500_purchase_price,
      ROUND(sp500_curr.sp500_price, 2) AS sp500_current_price,
      -- Calculate returns
      CASE
        WHEN pl.purchase_price > 0
          THEN ROUND((lp.close_price - pl.purchase_price) / pl.purchase_price * 100, 2)
        ELSE NULL
      END AS portfolio_return_pct,
      CASE
        WHEN sp500_purch.sp500_price > 0
          THEN ROUND(
            (sp500_curr.sp500_price - sp500_purch.sp500_price) / sp500_purch.sp500_price * 100, 2)
        ELSE NULL
      END AS sp500_return_pct
    FROM purchase_lots pl
    LEFT JOIN latest_prices lp
      ON pl.symbol = lp.symbol AND lp.rn = 1
    LEFT JOIN (
      SELECT purchase_date, sp500_price 
      FROM sp500_benchmark 
      WHERE benchmark_type = 'sp500_at_purchase'
    ) sp500_purch
      ON pl.purchase_date = sp500_purch.purchase_date
    LEFT JOIN (
      SELECT sp500_price 
      FROM sp500_benchmark 
      WHERE benchmark_type = 'sp500_current'
    ) sp500_curr
      ON 1=1
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
          THEN
            ROUND(
              (SUM(lot_current_value) - SUM(lot_cost_basis))
                / SUM(lot_cost_basis)
                * 100,
              2)
        ELSE NULL
        END
        AS unrealized_pl_pct,
      -- S&P 500 Comparison: weighted average outperformance
      CASE
        WHEN SUM(lot_cost_basis) > 0
          THEN ROUND(
            SUM(portfolio_return_pct * lot_cost_basis) / SUM(lot_cost_basis) 
            - SUM(sp500_return_pct * lot_cost_basis) / SUM(lot_cost_basis),
            2)
        ELSE NULL
      END AS sp500_comparison_pct
    FROM lot_valuations
    GROUP BY account, symbol
  ),
  latest_cash AS (
    -- Get most recent cash per account
    SELECT
      account,
      cash_amount,
      ROW_NUMBER() OVER (PARTITION BY account ORDER BY date DESC) AS rn
    FROM `portfolio_analytics.fact_cash`
  ),
  holdings_summary AS (
    -- Format holdings for final output
    SELECT
      account,
      symbol,
      total_shares,
      ROUND(total_cost_basis / NULLIF(total_shares, 0), 2)
        AS avg_cost_per_share,
      total_cost_basis,
      ROUND(total_current_value / NULLIF(total_shares, 0), 2) AS current_price,
      total_current_value,
      unrealized_pl,
      unrealized_pl_pct,
      sp500_comparison_pct
    FROM symbol_aggregates
  ),
  account_summary AS (
    -- Sum all holdings per account
    SELECT account, ROUND(SUM(total_current_value), 2) AS total_holdings_value
    FROM holdings_summary
    GROUP BY account
  ),
  account_with_cash AS (
    -- Join holdings totals with latest cash
    SELECT
      ats.account,
      ats.total_holdings_value,
      COALESCE(lc.cash_amount, 0) AS cash_value,
      ROUND(ats.total_holdings_value + COALESCE(lc.cash_amount, 0), 2)
        AS account_total_value
    FROM account_summary ats
    LEFT JOIN (SELECT account, cash_amount FROM latest_cash WHERE rn = 1) lc
      ON ats.account = lc.account
  )
-- Holdings with percentage of account
SELECT
  hs.account,
  hs.symbol,
  hs.total_shares,
  hs.avg_cost_per_share,
  hs.total_cost_basis,
  hs.current_price,
  hs.total_current_value,
  hs.unrealized_pl,
  hs.unrealized_pl_pct,
  hs.sp500_comparison_pct,
  ROUND(hs.total_current_value / NULLIF(awc.account_total_value, 0) * 100, 2)
    AS pct_of_account,
  CURRENT_DATE() AS valuation_date
FROM holdings_summary hs
LEFT JOIN account_with_cash awc
  ON hs.account = awc.account
UNION ALL

-- Cash values as separate rows
SELECT
  awc.account,
  'Cash Holdings' AS symbol,
  NULL AS total_shares,
  NULL AS avg_cost_per_share,
  NULL AS total_cost_basis,
  NULL AS current_price,
  awc.cash_value AS total_current_value,
  NULL AS unrealized_pl,
  NULL AS unrealized_pl_pct,
  NULL AS sp500_comparison_pct,
  ROUND(awc.cash_value / NULLIF(awc.account_total_value, 0) * 100, 2)
    AS pct_of_account,
  CURRENT_DATE() AS valuation_date
FROM account_with_cash awc
ORDER BY account, CASE WHEN symbol = 'Cash Holdings' THEN 1 ELSE 0 END, symbol;
