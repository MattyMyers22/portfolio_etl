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

/*
-- Get full returns history
-- Purchase history
WITH purchases AS (	
    SELECT transaction_type, symbol, purchase_date, purchase_price, SUM(shares) AS shares_purchased
	FROM portfolio
	WHERE account = 'Roth IRA' AND transaction_type IN ('buy', 'reinvestment')
	GROUP BY transaction_type, symbol, purchase_date, purchase_price),
-- Selling history
sellings AS (
	SELECT symbol, purchase_date, purchase_price, SUM(shares) AS shares_sold, 
		sell_date, sell_price
	FROM portfolio
    WHERE account = 'Roth IRA' AND transaction_type = 'sell'
    GROUP BY symbol, purchase_date, purchase_price, sell_date, sell_price
),
-- Get latest prices
lates_prices AS (
	SELECT symbol, date, adj_close
	FROM prices
	WHERE date = (SELECT MAX(date) FROM prices)
	-- Add row for VFIAX
	UNION
	SELECT 'VFIAX' AS symbol,
		(SELECT MAX(date) FROM prices) AS date,
		-- Set VFIAX price equal to that for VOO
		(SELECT adj_close 
		FROM prices 
		WHERE symbol = 'VOO' AND
			date = (SELECT MAX(date) FROM prices)) AS adj_close
)

SELECT transaction_type, p.symbol, p.purchase_date, p.purchase_price, shares_purchased, 
	shares_sold, sell_date, sell_price,
    -- Current shares
    (shares_purchased - COALESCE(shares_sold, 0)) AS current_shares,
    -- Total cost basis, 0 if reinvested dividends
    CASE
		WHEN transaction_type = 'buy' THEN purchase_price * shares_purchased
        WHEN transaction_type = 'reinvestment' THEN 0
	END AS cost_basis,
    -- Return from sold shares
    shares_sold * sell_price AS realized_return,
    -- Profit/loss for shares sold
    (shares_sold * sell_price) - (purchase_price * shares_sold) AS realized_pl,
    -- Cost basis for unsold shares, 0 if reinvested dividends
    CASE
		WHEN transaction_type = 'buy' THEN (shares_purchased - COALESCE(shares_sold, 0)) * purchase_price
        WHEN transaction_type = 'reinvestment' THEN 0
	END AS unrealized_cost_basis,
    -- Cost basis for sold shares, 0 if reinvested dividends
    CASE
		WHEN transaction_type = 'buy' THEN COALESCE(shares_sold, 0) * purchase_price
        WHEN transaction_type = 'reinvestment' THEN 0
	END AS realized_cost_basis,
    -- Latest price
    adj_close AS latest_price,
    -- Unrealized return
    adj_close * (shares_purchased - COALESCE(shares_sold, 0)) AS unrealized_return,
    -- Unrealized profit/loss
    (adj_close * (shares_purchased - COALESCE(shares_sold, 0))) - (
		CASE
			WHEN transaction_type = 'buy' THEN (shares_purchased - COALESCE(shares_sold, 0)) * purchase_price
			WHEN transaction_type = 'reinvestment' THEN 0
		END
    ) AS unrealized_pl
FROM purchases AS p
-- Join sellings by symbol and purchase date and price
LEFT JOIN sellings AS s
	USING(symbol, purchase_date, purchase_price)
-- Join for latest prices
LEFT JOIN lates_prices AS l
	USING(symbol);
*/

SELECT * FROM prices
WHERE symbol = 'VFIAX';