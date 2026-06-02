
WITH purchases AS (
  -- Purchased shares by account
    SELECT
        account,
        symbol,
        purchase_date,
        purchase_price,
        SUM(shares) as shares_purchased
      FROM `portfolio_analytics.fact_transactions`
      WHERE transaction_type IN ('buy', 'reinvestment')
      GROUP BY account, symbol, purchase_date, purchase_price),
-- Shares sold breakdown
sellings AS (
    SELECT
        account,
        symbol,
        purchase_date,
        purchase_price,
        SUM(shares) as shares_sold
        FROM `portfolio_analytics.fact_transactions`
        WHERE transaction_type = 'sell'
        GROUP BY account, symbol, purchase_date, purchase_price),
remaining_shares AS (
-- Remaining shares and cost basis
    SELECT 
        p.account, 
        p.symbol, 
        p.purchase_date, 
        p.purchase_price, 
        p.shares_purchased, 
        COALESCE(s.shares_sold, 0) as shares_sold, 
        p.shares_purchased - COALESCE(s.shares_sold, 0) as rem_shares,
        (p.shares_purchased - COALESCE(s.shares_sold, 0)) * p.purchase_price as rem_basis
    FROM purchases p
    LEFT JOIN sellings s
    ON p.account = s.account AND p.symbol = s.symbol AND p.purchase_date = s.purchase_date AND p.purchase_price = s.purchase_price)

-- Better to aggregate current holding data and S&P 500 comparison first
-- Current holdings with latest share price
SELECT s.account,
       s.symbol,
       s.purchase_date,
       s.purchase_price,
       s.shares_purchased,
       s.shares_sold,
       s.rem_shares,
       s.rem_basis,
       p.latest_price_date,
       p.latest_price
FROM remaining_shares s
LEFT JOIN (
  SELECT price_date as latest_price_date, symbol, ROUND(close_price, 2) as latest_price
  FROM `portfolio_analytics.fact_prices` AS p
  WHERE symbol IN (SELECT symbol FROM remaining_shares) AND
    price_date = (SELECT MAX(price_date) FROM `portfolio_analytics.fact_prices`)) AS p 
  ON s.symbol = p.symbol
ORDER BY s.account, s.symbol, s.purchase_date