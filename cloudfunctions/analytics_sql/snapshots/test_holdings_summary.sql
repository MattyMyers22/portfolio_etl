WITH purchases AS (
  -- Purchased shares by account
  SELECT
    account,
    symbol,
    purchase_date,
    purchase_price,
    SUM(shares) AS shares_purchased
  FROM `portfolio_analytics.fact_transactions`
  WHERE transaction_type IN ('buy', 'reinvestment')
  GROUP BY account, symbol, purchase_date, purchase_price
),
sellings AS (
  -- Shares sold breakdown
  SELECT
    account,
    symbol,
    purchase_date,
    purchase_price,
    SUM(shares) AS shares_sold
  FROM `portfolio_analytics.fact_transactions`
  WHERE transaction_type = 'sell'
  GROUP BY account, symbol, purchase_date, purchase_price
),
remaining_shares AS (
  -- Remaining shares and cost basis
  SELECT 
    p.account, 
    p.symbol, 
    p.purchase_date, 
    p.purchase_price, 
    p.shares_purchased, 
    COALESCE(s.shares_sold, 0) AS shares_sold, 
    p.shares_purchased - COALESCE(s.shares_sold, 0) AS rem_shares,
    (p.shares_purchased - COALESCE(s.shares_sold, 0)) * p.purchase_price AS rem_basis
  FROM purchases p
  LEFT JOIN sellings s
    ON p.account = s.account 
    AND p.symbol = s.symbol 
    AND p.purchase_date = s.purchase_date 
    AND p.purchase_price = s.purchase_price
  WHERE p.shares_purchased - COALESCE(s.shares_sold, 0) > 0
),
sp_purchase_prices AS (
  -- S&P 500 price on day of purchase
  SELECT 
    CAST(price_date AS DATE) AS purchase_date,
    ROUND(close_price, 2) AS sp_purch_close
  FROM `portfolio_analytics.fact_prices`
  WHERE symbol = '^GSPC'
),
sp_latest AS (
  -- Latest S&P 500 price (single row)
  SELECT 
    ROUND(close_price, 2) AS sp_latest_close,
    price_date AS sp_latest_date
  FROM `portfolio_analytics.fact_prices`
  WHERE symbol = '^GSPC'
  QUALIFY ROW_NUMBER() OVER (ORDER BY price_date DESC) = 1
),
stock_latest_prices AS (
  -- Latest price for each symbol in holdings
  SELECT 
    symbol,
    ROUND(close_price, 2) AS stock_latest_close,
    price_date AS stock_latest_date
  FROM `portfolio_analytics.fact_prices`
  WHERE symbol != '^GSPC'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY price_date DESC) = 1
)
SELECT
  rs.account,
  rs.symbol,
  rs.purchase_date,
  rs.purchase_price,
  rs.shares_purchased,
  rs.shares_sold,
  rs.rem_shares,
  ROUND(rs.rem_basis, 2) AS rem_basis,
  spp.sp_purch_close,
  spl.sp_latest_close,
  spl.sp_latest_date,
  slp.stock_latest_close,
  slp.stock_latest_date,
  -- Unrealized gains calculation
  ROUND(rs.rem_shares * slp.stock_latest_close - rs.rem_basis, 2) AS unrealized_pl,
  CASE
    WHEN rs.rem_basis > 0
    THEN ROUND((rs.rem_shares * slp.stock_latest_close - rs.rem_basis) / rs.rem_basis * 100, 2)
    ELSE NULL
  END AS unrealized_pl_pct
FROM remaining_shares rs
LEFT JOIN sp_purchase_prices spp 
  ON CAST(rs.purchase_date AS DATE) = spp.purchase_date
CROSS JOIN sp_latest spl
LEFT JOIN stock_latest_prices slp 
  ON rs.symbol = slp.symbol
ORDER BY rs.account, rs.symbol, rs.purchase_date;