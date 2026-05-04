-- Account Performance Summary Table
-- Aggregated account-level metrics showing total portfolio performance
-- Includes unrealized/realized gains and comparison to S&P 500 benchmark
-- Grain: One row per account

CREATE OR REPLACE TABLE `portfolio_analytics.account_performance_summary`
AS
WITH
  account_holdings AS (
    -- Current holdings aggregated by account
    SELECT
      account,
      SUM(
        CASE
          WHEN transaction_type IN ('buy', 'reinvestment') THEN shares
          ELSE 0
          END)
        - SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END)
        AS current_shares,
      symbol
    FROM `portfolio_analytics.fact_transactions`
    GROUP BY symbol, account
    HAVING current_shares > 0
  ),
  account_unrealized AS (
    -- Calculate total unrealized gains per account
    SELECT
      account,
      SUM(
        CASE
          WHEN transaction_type IN ('buy', 'reinvestment')
            THEN shares * purchase_price
          ELSE 0
          END)
        AS total_cost_basis,
      SUM(ah.current_shares * lp.current_price) AS total_current_value,
      SUM(ah.current_shares * lp.current_price)
        - SUM(
          CASE
            WHEN transaction_type IN ('buy', 'reinvestment')
              THEN shares * purchase_price
            ELSE 0
            END)
        AS total_unrealized_pl
    FROM `portfolio_analytics.fact_transactions` ft
    LEFT JOIN account_holdings ah
      USING (account, symbol)
    LEFT JOIN
      (
        SELECT
          Ticker AS symbol,
          close AS current_price,
          ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
        FROM `portfolio_staging.stg_prices`
      ) lp
      ON ah.symbol = lp.symbol AND lp.rn = 1
    GROUP BY account
  ),
  account_realized AS (
    -- Calculate total realized gains per account
    SELECT
      account,
      SUM(
        CASE
          WHEN sell_price IS NOT NULL
            THEN shares * sell_price - shares * purchase_price
          ELSE 0
          END)
        AS total_realized_pl
    FROM `portfolio_analytics.fact_transactions`
    WHERE sell_date IS NOT NULL
    GROUP BY account
  ),
  account_cash AS (
    -- Get latest cash balance per account
    SELECT
      account,
      cash_amount,
      ROW_NUMBER() OVER (PARTITION BY account ORDER BY date DESC) AS rn
    FROM `portfolio_analytics.fact_cash`
  ),
  sp500_prices AS (
    -- Get S&P 500 current price
    SELECT
      close AS sp500_current_price, ROW_NUMBER() OVER (ORDER BY date DESC) AS rn
    FROM `portfolio_staging.stg_prices`
    WHERE Ticker = '^GSPC'
  ),
  account_start_dates AS (
    -- Get the earliest purchase date per account
    SELECT account, MIN(purchase_date) AS min_purchase_date
    FROM `portfolio_analytics.fact_transactions`
    WHERE symbol IS NOT NULL
    GROUP BY account
  ),
  sp500_at_start AS (
    -- Get S&P 500 price as close as possible to each account's start date
    SELECT
      asd.account,
      MAX(p.close) OVER (PARTITION BY asd.account) AS sp500_cost_basis
    FROM account_start_dates asd
    JOIN `portfolio_staging.stg_prices` p
      ON p.Ticker = '^GSPC' AND p.date <= asd.min_purchase_date
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY asd.account ORDER BY p.date DESC) = 1
  ),
  sp500_performance AS (
    -- Calculate what S&P 500 investment would have returned
    SELECT
      ft.account,
      AVG(
        CASE
          WHEN ft.transaction_type IN ('buy', 'reinvestment')
            THEN ft.purchase_price
          END)
        AS avg_sp500_purchase_price,
      ANY_VALUE(sas.sp500_cost_basis) AS sp500_cost_basis
    FROM `portfolio_analytics.fact_transactions` ft
    LEFT JOIN sp500_at_start sas
      ON ft.account = sas.account
    WHERE ft.symbol IS NOT NULL
    GROUP BY ft.account
  )
SELECT
  au.account,
  ROUND(COALESCE(au.total_current_value, 0) + COALESCE(ac.cash_amount, 0), 2)
    AS total_portfolio_value,
  ROUND(COALESCE(au.total_current_value, 0), 2) AS total_securities_value,
  ROUND(COALESCE(ac.cash_amount, 0), 2) AS total_cash,
  ROUND(COALESCE(au.total_cost_basis, 0), 2) AS total_cost_basis,
  ROUND(COALESCE(au.total_unrealized_pl, 0), 2) AS total_unrealized_pl,
  CASE
    WHEN au.total_cost_basis > 0
      THEN
        ROUND(
          COALESCE(au.total_unrealized_pl, 0) / au.total_cost_basis * 100, 2)
    ELSE NULL
    END
    AS total_unrealized_pl_pct,
  ROUND(COALESCE(ar.total_realized_pl, 0), 2) AS total_realized_pl,
  CASE
    WHEN
      COALESCE(au.total_unrealized_pl, 0) + COALESCE(ar.total_realized_pl, 0)
      > 0
      THEN
        ROUND(
          (
            COALESCE(au.total_unrealized_pl, 0)
            + COALESCE(ar.total_realized_pl, 0))
            / (
              au.total_cost_basis + COALESCE(
                (
                  SELECT SUM(shares * sell_price)
                  FROM `portfolio_analytics.fact_transactions`
                  WHERE account = au.account AND sell_date IS NOT NULL
                ),
                0))
            * 100,
          2)
    ELSE NULL
    END
    AS total_realized_pl_pct,
  sp500p.sp500_current_price,
  ROUND(
    COALESCE(au.total_current_value, 0)
        / NULLIF(
          sp500p.sp500_current_price
            / sp500p2.sp500_cost_basis
            * au.total_cost_basis,
          0)
      - 1,
    4)
    AS vs_sp500_return_multiple,
  CASE
    WHEN sp500p2.sp500_cost_basis > 0
      THEN
        ROUND(
          (
            COALESCE(au.total_current_value, 0)
            - sp500p.sp500_current_price
              / sp500p2.sp500_cost_basis
              * au.total_cost_basis)
            / (
              sp500p.sp500_current_price
              / sp500p2.sp500_cost_basis
              * au.total_cost_basis)
            * 100,
          2)
    ELSE NULL
    END
    AS vs_sp500_return_pct,
  CURRENT_TIMESTAMP() AS refresh_timestamp
FROM account_unrealized au
LEFT JOIN account_realized ar
  USING (account)
LEFT JOIN account_cash ac
  ON au.account = ac.account AND ac.rn = 1
LEFT JOIN sp500_prices sp500p
  ON sp500p.rn = 1
LEFT JOIN sp500_performance sp500p2
  ON au.account = sp500p2.account
ORDER BY au.account;
