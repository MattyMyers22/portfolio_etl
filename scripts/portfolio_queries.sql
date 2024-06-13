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

CREATE TABLE IF NOT EXISTS prices (
	prices_id INT AUTO_INCREMENT PRIMARY KEY,
    date DATETIME,
    open NUMERIC(12,4),
    high NUMERIC(12,4),
    low NUMERIC(12,4),
    close NUMERIC(12,4),
    adj_close NUMERIC(12,4),
    volume BIGINT,
    symbol VARCHAR(25)
);

SELECT * FROM portfolio;

SHOW TABLES;

TRUNCATE portfolio;

SELECT * FROM portfolio
WHERE id IS NULL;