-- Create view for investment portfolio breakdown

-- Connect to portfolio_dwh
USE portfolio_dwh;

-- Get current holdings
WITH purchases AS (	
    SELECT symbol, purchase_date, SUM(shares) AS shares_purchased
	FROM portfolio
	WHERE account = 'Roth IRA' AND transaction_type IN ('buy', 'reinvestment')
	GROUP BY symbol, purchase_date),
sellings AS (
	SELECT symbol, purchase_date, SUM(shares) AS sold_shares
	FROM portfolio
    WHERE account = 'Roth IRA' AND transaction_type = 'sell'
    GROUP BY symbol, purchase_date
)

SELECT * from purchases;

SELECT * FROM portfolio;