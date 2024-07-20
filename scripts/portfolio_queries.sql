-- Connect to portfolio_dwh
USE portfolio_dwh;

-- Drop current holdings view if exists
DROP VIEW IF EXISTS current_holdings;

-- Create view for current holdings
CREATE VIEW current_holdings AS
-- Purchase history
WITH purchases AS (	
    SELECT symbol, purchase_date, purchase_price, SUM(shares) AS shares_purchased
	FROM portfolio
	WHERE account = 'Roth IRA' AND transaction_type IN ('buy', 'reinvestment')
	GROUP BY symbol, purchase_date, purchase_price),
-- Selling history
sellings AS (
	SELECT symbol, purchase_date, purchase_price, SUM(shares) AS shares_sold
	FROM portfolio
    WHERE account = 'Roth IRA' AND transaction_type = 'sell'
    GROUP BY symbol, purchase_date, purchase_price),
-- Find current share counts
current AS (
	SELECT p.symbol, p.purchase_date, p.purchase_price, shares_purchased, shares_sold,
		shares_purchased - COALESCE(shares_sold, 0) AS current_shares
	FROM purchases AS p
	LEFT JOIN sellings AS s
		USING(symbol, purchase_date, purchase_price)),
-- Current holdings with share counts
holdings AS (
	SELECT symbol, SUM(current_shares) AS shares
	FROM current
	GROUP BY symbol
	HAVING SUM(current_shares) <> 0),
-- Find cost basis for current holdings
basis AS (
	SELECT h.symbol, shares, ROUND(SUM(unrealized_cost_basis), 2) AS unrealized_cost_basis, 
		ROUND(SUM(realized_cost_basis), 2) AS realized_cost_basis, 
		ROUND((SUM(unrealized_cost_basis) / shares), 2) AS avg_unr_cost_basis,
        ROUND(SUM(COALESCE(unrealized_cost_basis, 0)) + SUM(COALESCE(realized_cost_basis, 0)), 2) AS total_cost_basis
	FROM holdings AS h
	INNER JOIN
		(SELECT symbol, (purchase_price * current_shares) AS unrealized_cost_basis,
			(purchase_price * shares_sold) AS realized_cost_basis
		FROM current) AS sub
	USING(symbol)
	GROUP BY h.symbol),
-- Get current value of current holdings
value AS (
	SELECT b.symbol, shares, ROUND(adj_close, 2) AS latest_price, ROUND((shares * adj_close), 2) AS value, 
		avg_unr_cost_basis, unrealized_cost_basis, ROUND((shares * adj_close), 2) AS unr_return,
		ROUND((shares * adj_close) - unrealized_cost_basis, 2) AS unrealized_pl, realized_cost_basis,
		total_cost_basis
	FROM basis AS b
	INNER JOIN
		(SELECT *
		FROM prices
		WHERE date = (SELECT MAX(date) FROM prices)) AS p
		USING(symbol)
),
-- Calculate all realized returns
realized_returns AS (
	SELECT symbol, purchase_date, shares AS shares_sold, purchase_price, sell_date, sell_price,
		ROUND((shares * sell_price), 2) AS realized_return
	FROM portfolio
	WHERE account = 'Roth IRA' AND transaction_type = 'sell'
)

SELECT *, (real_returns - realized_cost_basis) AS real_pl,
	(SELECT SUM(value)
     FROM value) AS portfolio_value
FROM value AS v
LEFT JOIN (    
	SELECT symbol, SUM(realized_return) AS real_returns
	FROM realized_returns
	GROUP BY symbol) AS r
	USING(symbol)
ORDER BY value DESC;

SELECT *
FROM current_holdings;

SELECT * FROM cash;

-- Main CTE for testing and changing
WITH purchases AS (	
    SELECT symbol, purchase_date, purchase_price, SUM(shares) AS shares_purchased
	FROM portfolio
	WHERE account = 'Roth IRA' AND transaction_type IN ('buy', 'reinvestment')
	GROUP BY symbol, purchase_date, purchase_price),
-- Selling history
sellings AS (
	SELECT symbol, purchase_date, purchase_price, SUM(shares) AS shares_sold
	FROM portfolio
    WHERE account = 'Roth IRA' AND transaction_type = 'sell'
    GROUP BY symbol, purchase_date, purchase_price),
-- Find current share counts
current AS (
	SELECT p.symbol, p.purchase_date, p.purchase_price, shares_purchased, shares_sold,
		shares_purchased - COALESCE(shares_sold, 0) AS current_shares
	FROM purchases AS p
	LEFT JOIN sellings AS s
		USING(symbol, purchase_date, purchase_price)),
-- Current holdings with share counts
holdings AS (
	SELECT symbol, SUM(current_shares) AS shares
	-- Get current chare count for each purchase history
    FROM current
	GROUP BY symbol
    -- Filter for symbols with current_shares > 0
	HAVING SUM(current_shares) <> 0),
-- Find cost basis for current holdings
basis AS (
	SELECT h.symbol, shares, ROUND(SUM(unrealized_cost_basis), 2) AS unrealized_cost_basis, 
		ROUND(SUM(realized_cost_basis), 2) AS realized_cost_basis, 
		ROUND((SUM(unrealized_cost_basis) / shares), 2) AS avg_unr_cost_basis,
        ROUND(SUM(COALESCE(unrealized_cost_basis, 0)) + SUM(COALESCE(realized_cost_basis, 0)), 2) AS total_cost_basis
	FROM holdings AS h
	INNER JOIN
		(SELECT symbol, (purchase_price * current_shares) AS unrealized_cost_basis,
			(purchase_price * shares_sold) AS realized_cost_basis
		FROM current) AS sub
	USING(symbol)
	GROUP BY h.symbol),
-- Get current value of current holdings
value AS (
	SELECT b.symbol, shares, ROUND(adj_close, 2) AS latest_price, ROUND((shares * adj_close), 2) AS value, 
		avg_unr_cost_basis, unrealized_cost_basis, ROUND((shares * adj_close), 2) AS unr_return,
		ROUND((shares * adj_close) - unrealized_cost_basis, 2) AS unrealized_pl, realized_cost_basis,
		total_cost_basis
	FROM basis AS b
	INNER JOIN
		(SELECT *
		FROM prices
		WHERE date = (SELECT MAX(date) FROM prices)) AS p
		USING(symbol)
),
-- Calculate all realized returns
realized_returns AS (
	SELECT symbol, purchase_date, shares AS shares_sold, purchase_price, sell_date, sell_price,
		ROUND((shares * sell_price), 2) AS realized_return
	FROM portfolio
	WHERE account = 'Roth IRA' AND transaction_type = 'sell'
),
-- portfolio values
port_value AS (
	SELECT *, (real_returns - realized_cost_basis) AS real_pl,
		(SELECT SUM(value)
		 FROM value) AS portfolio_value
	FROM value AS v
	LEFT JOIN (    
		SELECT symbol, SUM(realized_return) AS real_returns
		FROM realized_returns
		GROUP BY symbol) AS r
		USING(symbol)
	ORDER BY value DESC
)

SELECT *
FROM value;
-- perhaps instead of adding columns on to basis for value, just get all the new columns and join later
-- then can have a returns table