
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
        GROUP BY account, symbol, purchase_date, purchase_price)

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
ON p.account = s.account AND p.symbol = s.symbol AND p.purchase_date = s.purchase_date AND p.purchase_price = s.purchase_price