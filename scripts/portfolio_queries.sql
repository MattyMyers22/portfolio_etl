-- Create view for investment portfolio breakdown

-- Connect to portfolio_dwh
USE portfolio_dwh;

-- Get current holdings
-- Purchase history
WITH purchases AS (	
    SELECT symbol, purchase_date, purchase_price, SUM(shares) AS shares_purchased
	FROM portfolio
	WHERE account = 'Roth IRA' AND transaction_type IN ('buy', 'reinvestment')
	GROUP BY symbol, purchase_date, purchase_price),
-- Selling history
sellings AS (
	SELECT symbol, purchase_date, purchase_price, SUM(shares) AS shares_sold, 
		sell_date, sell_price
	FROM portfolio
    WHERE account = 'Roth IRA' AND transaction_type = 'sell'
    GROUP BY symbol, purchase_date, purchase_price, sell_date, sell_price
)

SELECT p.symbol, p.purchase_date, p.purchase_price, shares_purchased, 
	shares_sold, sell_date, sell_price, 
    (shares_purchased - COALESCE(shares_sold, 0)) AS current_shares,
    purchase_price * shares_purchased AS cost_basis,
    shares_sold * sell_price AS realized_return,
    (shares_sold * sell_price) - (purchase_price * shares_purchased) AS realized_pl
FROM purchases AS p
LEFT JOIN sellings AS s
	USING(symbol, purchase_date, purchase_price);