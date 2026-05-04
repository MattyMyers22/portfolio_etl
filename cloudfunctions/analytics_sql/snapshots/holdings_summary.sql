-- Holdings Summary Table
-- Simplified aggregate of current holdings by symbol and account
-- Grain: One row per symbol per account (current holdings only)

CREATE OR REPLACE TABLE `portfolio_analytics.holdings_summary`
AS
WITH
  current_holdings AS (
    SELECT
      symbol,
      account,
      SUM(
        CASE
          WHEN transaction_type IN ('buy', 'reinvestment') THEN shares
          ELSE 0
          END)
        - SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END)
        AS current_shares,
      COUNT(
        DISTINCT
          CASE
            WHEN transaction_type IN ('buy', 'reinvestment') THEN purchase_date
            END)
        AS num_purchase_lots,
      AVG(
        CASE
          WHEN transaction_type IN ('buy', 'reinvestment') THEN purchase_price
          ELSE NULL
          END)
        AS avg_buy_price,
      MIN(purchase_date) AS first_purchase_date,
      MAX(COALESCE(sell_date, purchase_date)) AS last_transaction_date
    FROM `portfolio_analytics.fact_transactions`
    GROUP BY symbol, account
    HAVING current_shares > 0
  ),
  latest_prices AS (
    SELECT Ticker AS symbol, close AS current_price
    FROM
      (
        SELECT
          Ticker,
          close,
          ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
        FROM `portfolio_staging.stg_prices`
      )
    WHERE rn = 1
  ),
  latest_cash AS (
    SELECT account, cash_amount
    FROM
      (
        SELECT
          account,
          cash_amount,
          ROW_NUMBER() OVER (PARTITION BY account ORDER BY date DESC) AS rn
        FROM `portfolio_analytics.fact_cash`
      )
    WHERE rn = 1
  ),
  account_totals AS (
    SELECT
      ch.account,
      SUM(ch.current_shares * lp.current_price)
        + COALESCE(MAX(lc.cash_amount), 0)
        AS account_total_value
    FROM current_holdings ch
    JOIN latest_prices lp
      ON ch.symbol = lp.symbol
    LEFT JOIN latest_cash lc
      ON ch.account = lc.account
    GROUP BY ch.account
  ),
  sp500_current AS (
    SELECT close AS sp500_price
    FROM `portfolio_staging.stg_prices`
    WHERE Ticker = '^GSPC'
    ORDER BY date DESC
    LIMIT 1
  ),
  sp500_history AS (
    SELECT date, close AS sp500_price
    FROM `portfolio_staging.stg_prices`
    WHERE Ticker = '^GSPC'
  ),
  sp500_on_purchase AS (
    SELECT
      ch.symbol,
      ch.account,
      LAST_VALUE(sh.sp500_price IGNORE NULLS)
        OVER (
          PARTITION BY ch.symbol, ch.account
          ORDER BY sh.date
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
        AS sp500_purchase_price
    FROM current_holdings ch
    LEFT JOIN sp500_history sh
      ON sh.date <= ch.first_purchase_date
  ),
  sp500_on_purchase_dedup AS (
    SELECT symbol, account, MAX(sp500_purchase_price) AS sp500_purchase_price
    FROM sp500_on_purchase
    GROUP BY 1, 2
  ),
  cost_basis AS (
    SELECT
      symbol,
      account,
      SUM(
        CASE
          WHEN transaction_type IN ('buy', 'reinvestment')
            THEN shares * purchase_price
          ELSE 0
          END)
        AS total_cost_basis
    FROM `portfolio_analytics.fact_transactions`
    GROUP BY symbol, account
  )
SELECT
  h.symbol,
  h.account,
  h.current_shares,
  ROUND(cb.total_cost_basis, 2) AS cost_basis,
  ROUND(h.current_shares * lp.current_price, 2) AS current_value,
  ROUND(h.current_shares * lp.current_price - cb.total_cost_basis, 2)
    AS unrealized_pl,
  CASE
    WHEN cb.total_cost_basis > 0
      THEN
        ROUND(
          (h.current_shares * lp.current_price - cb.total_cost_basis)
            / cb.total_cost_basis
            * 100,
          2)
    ELSE NULL
    END
    AS unrealized_pl_pct,
  h.num_purchase_lots,
  h.first_purchase_date,
  h.last_transaction_date,
  CASE
    WHEN act.account_total_value > 0
      THEN
        ROUND(
          h.current_shares * lp.current_price / act.account_total_value * 100,
          2)
    ELSE 0
    END
    AS position_pct_of_account,
  CASE
    WHEN spp.sp500_purchase_price > 0 AND sc.sp500_price > 0
      THEN
        ROUND(
          ((lp.current_price - h.avg_buy_price) / h.avg_buy_price * 100)
            - (
              (sc.sp500_price - spp.sp500_purchase_price)
              / spp.sp500_purchase_price
              * 100),
          2)
    ELSE NULL
    END
    AS vs_sp500_pl_pct
FROM current_holdings h
JOIN cost_basis cb
  ON h.symbol = cb.symbol AND h.account = cb.account
JOIN latest_prices lp
  ON h.symbol = lp.symbol
JOIN account_totals act
  ON h.account = act.account
CROSS JOIN sp500_current sc
LEFT JOIN sp500_on_purchase_dedup spp
  ON h.symbol = spp.symbol AND h.account = spp.account
ORDER BY h.account, h.symbol;
