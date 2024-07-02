-- Connect to portfolio_dwh
USE portfolio_dwh;

-- Create view for current holdings
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
current AS (
	SELECT p.symbol, p.purchase_date, p.purchase_price, shares_purchased, shares_sold,
		shares_purchased - COALESCE(shares_sold, 0) AS current_shares
	FROM purchases AS p
	LEFT JOIN sellings AS s
		USING(symbol, purchase_date, purchase_price))
        
SELECT symbol, SUM(current_shares)
FROM current
GROUP BY symbol
HAVING SUM(current_shares) <> 0;

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

SELECT * FROM prices;