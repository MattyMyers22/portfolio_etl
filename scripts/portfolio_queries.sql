-- Connect to portfolio_dwh
USE portfolio_dwh;

-- Drop current holdings view if exists
DROP VIEW IF EXISTS portfolio_metrics;

-- Create view for current holdings
CREATE VIEW portfolio_metrics AS
-- Main CTE for performance metrics on all open and closed positions
WITH purchases AS (	
    SELECT symbol, purchase_date, purchase_price, SUM(shares) AS shares_purchased
	FROM portfolio
	WHERE account = 'Roth IRA' AND transaction_type IN ('buy', 'reinvestment')
	GROUP BY symbol, purchase_date, purchase_price),
-- Selling history with shares sold for each purchase
sellings AS (
	SELECT symbol, purchase_date, purchase_price, SUM(shares) AS shares_sold
	FROM portfolio
    WHERE account = 'Roth IRA' AND transaction_type = 'sell'
    GROUP BY symbol, purchase_date, purchase_price),
-- Find current share counts and basis for each purchase
share_counts AS (
	SELECT p.symbol, p.purchase_date, ROUND(p.purchase_price, 2) AS purchase_price, 
		shares_purchased, shares_sold, 
        -- Current shares held
        shares_purchased - COALESCE(shares_sold, 0) AS current_shares,
        -- Unrealized cost basis
        ROUND((shares_purchased - COALESCE(shares_sold, 0)) * p.purchase_price, 2) AS unr_cost_basis,
        -- Realized cost basis
        ROUND(COALESCE(shares_sold, 0) * p.purchase_price, 2) AS real_cost_basis,
        -- Total cost basis
        (ROUND((shares_purchased - COALESCE(shares_sold, 0)) * p.purchase_price, 2) + 
			ROUND(COALESCE(shares_sold, 0) * p.purchase_price, 2)) AS total_cost_basis,
        -- S&P 500 comparible cost basis
        sp.adj_close AS sp500_cost_basis,
        -- S&P 500 recent price
        (SELECT adj_close FROM prices WHERE symbol = '^GSPC'
			AND date = (SELECT MAX(date) FROM prices)) AS sp500_price,
        -- Provide years held for existing shares
        CASE
			WHEN shares_purchased - COALESCE(shares_sold, 0) > 0
				THEN ROUND(DATEDIFF(CURDATE(), p.purchase_date) / 365.2425, 2)
			ELSE NULL
		END AS unr_years_held
	FROM purchases AS p
    -- Join sellings history
	LEFT JOIN sellings AS s
		USING(symbol, purchase_date, purchase_price)
	-- Join S&P 500 price history
    LEFT JOIN (
		SELECT date, adj_close
        FROM prices
        WHERE symbol = '^GSPC'
    ) AS sp
		ON p.purchase_date = sp.date),
-- Current holdings with share counts
holdings AS (
	SELECT symbol, SUM(current_shares) AS shares
	-- Get current chare count for each purchase history
    FROM share_counts
	GROUP BY symbol
    -- Filter for symbols with current_shares > 0
	HAVING SUM(current_shares) <> 0),
-- Find unrealized returns for current holdings and vs SP 500
unr_returns AS (
	SELECT s.symbol, purchase_date, purchase_price, current_shares, unr_cost_basis, real_cost_basis, 
		total_cost_basis, sp500_cost_basis, sp500_price, unr_years_held,
		-- Recent share price
		p.adj_close AS recent_price,
		-- Total unrealized profit/loss
		ROUND((p.adj_close - purchase_price) * current_shares, 2) AS tot_unr_pl,
		-- SP500 unrealized profit/loss
		ROUND(sp500_price / sp500_cost_basis * unr_cost_basis - unr_cost_basis, 2) AS unr_sp500_pl
	FROM share_counts AS s
	INNER JOIN holdings AS h
		USING(symbol)
	LEFT JOIN prices AS p
		USING(symbol)
	WHERE p.date = (SELECT MAX(date) FROM prices)
),
-- Find totals in unrealized metrics for current holdings
unr_totals AS (
	SELECT symbol, 
		SUM(current_shares) AS shares, SUM(unr_cost_basis) AS tot_unr_cost_basis,
        SUM(total_cost_basis) AS tot_cost_basis,
		SUM(tot_unr_pl) AS tot_unr_pl, SUM(unr_sp500_pl) AS tot_unr_sp_pl,
		ROUND(SUM(current_shares * unr_years_held) / SUM(current_shares), 2) AS avg_unr_yrs_held
	FROM unr_returns
	GROUP BY symbol
),
-- Get all realized returns vs S&P 500
real_returns AS (
	SELECT symbol, purchase_date, shares, purchase_price, sell_date, sell_price,
		ROUND(shares * purchase_price, 2) AS real_cost_basis, ROUND(shares * sell_price, 2) AS real_returns,
		ROUND(DATEDIFF(sell_date, purchase_date) / 365.2425, 2) AS real_years_held,
		sp1.adj_close AS real_sp_basis, sp2.adj_close AS real_sp_return
	FROM portfolio AS p
	-- Join S&P 500 prices data for cost basis
	LEFT JOIN (
			SELECT date, adj_close
			FROM prices
			WHERE symbol = '^GSPC'
		) AS sp1
			ON p.purchase_date = sp1.date
	-- Join S&P 500 prices data for realized returns comparison
	LEFT JOIN (
			SELECT date, adj_close
			FROM prices
			WHERE symbol = '^GSPC'
		) AS sp2
			ON p.sell_date = sp2.date
	WHERE account = 'Roth IRA' AND transaction_type = 'sell'
),
real_totals AS (
	SELECT symbol, SUM(shares) AS sold_shares, SUM(real_cost_basis) AS tot_real_cost_basis,
		SUM(real_returns) - SUM(real_cost_basis) AS tot_real_pl,
		ROUND(SUM(real_sp_return / real_sp_basis * real_cost_basis - real_cost_basis), 2) AS tot_real_sp_pl,
		ROUND(SUM(shares * real_years_held) / SUM(shares), 2) AS avg_real_yrs_held
	FROM real_returns
	GROUP BY symbol
)

-- Final data for positions still holding
SELECT u.symbol, shares AS current_shares, tot_unr_cost_basis, tot_real_cost_basis,
	tot_unr_cost_basis + tot_real_cost_basis AS tot_cost_basis, tot_unr_pl,
    tot_unr_sp_pl, avg_unr_yrs_held, tot_real_pl, tot_real_sp_pl, avg_real_yrs_held
FROM unr_totals AS u
LEFT JOIN real_totals AS r
	USING(symbol)
-- Combine with other data set
UNION
-- Final data for closed positions
SELECT symbol, NULL AS current_shares, NULL AS tot_unr_cost_basis, tot_real_cost_basis, 
	tot_real_cost_basis AS tot_cost_basis, NULL AS tot_unr_pl, NULL AS tot_unr_sp_pl,
    NULL AS avg_unr_yrs_held, tot_real_pl, tot_real_sp_pl, avg_real_yrs_held
FROM real_totals
WHERE symbol NOT IN (SELECT symbol FROM holdings);

SELECT *
FROM portfolio_metrics;