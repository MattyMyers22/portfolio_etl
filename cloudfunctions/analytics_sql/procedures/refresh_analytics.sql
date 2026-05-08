-- Analytics Refresh Orchestrator Procedure
-- Refreshes all analytics layer objects (dimensions, facts, tables) in dependency order
-- Called by load.py after staging data loads complete
-- Provides error handling and execution logging

CREATE OR REPLACE PROCEDURE `portfolio_analytics.refresh_analytics`()
BEGIN
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;
  DECLARE error_msg STRING;
  
  SET start_time = CURRENT_TIMESTAMP();
  
  BEGIN
    -- Log procedure start
    RAISE NOTICE 'Starting analytics refresh at %s', start_time;
    
    -- Phase 1: Refresh Dimensions
    RAISE NOTICE 'Refreshing dimension tables...';
    
    -- Refresh date dimension
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.dim_date` AS
      WITH date_bounds AS (
        SELECT
          MIN(min_date) AS start_date,
          MAX(max_date) AS end_date
        FROM (
          SELECT MIN(purchase_date) AS min_date, MAX(COALESCE(sell_date, purchase_date)) AS max_date FROM `portfolio_staging.stg_transactions`
          UNION ALL
          SELECT MIN(date) AS min_date, MAX(date) AS max_date FROM `portfolio_staging.stg_cash`
          UNION ALL
          SELECT MIN(date) AS min_date, MAX(date) AS max_date FROM `portfolio_staging.stg_prices`
        )
      )
      SELECT
        date_val AS date,
        EXTRACT(YEAR FROM date_val) AS year,
        EXTRACT(MONTH FROM date_val) AS month,
        EXTRACT(DAY FROM date_val) AS day_of_month,
        EXTRACT(QUARTER FROM date_val) AS quarter,
        EXTRACT(DAYOFWEEK FROM date_val) AS day_of_week,
        FORMAT_DATE('%A', date_val) AS day_of_week_name,
        FORMAT_DATE('%Y-Q%Q', date_val) AS fiscal_period,
        WEEK(date_val) AS week_of_year,
        DAYOFYEAR(date_val) AS day_of_year
      FROM date_bounds,
        UNNEST(GENERATE_DATE_ARRAY(date_bounds.start_date, date_bounds.end_date)) AS date_val
      ORDER BY date_val
    """;
    RAISE NOTICE 'Successfully refreshed dim_date';
    
    -- Refresh security dimension
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.dim_security` AS
      WITH all_symbols AS (
        SELECT DISTINCT symbol FROM `portfolio_staging.stg_transactions` WHERE symbol IS NOT NULL
        UNION DISTINCT
        SELECT DISTINCT Ticker AS symbol FROM `portfolio_staging.stg_prices` WHERE Ticker IS NOT NULL
      )
      SELECT
        symbol,
        NULL AS asset_class,
        NULL AS sector
      FROM all_symbols
      ORDER BY symbol
    """;
    RAISE NOTICE 'Successfully refreshed dim_security';
    
    -- Phase 2: Refresh Fact Tables
    RAISE NOTICE 'Refreshing fact tables...';
    
    -- Refresh transactions fact table
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.fact_transactions` AS
      SELECT
        symbol,
        account,
        transaction_type,
        purchase_date,
        CAST(shares AS FLOAT64) AS shares,
        CAST(purchase_price AS FLOAT64) AS purchase_price,
        sell_date,
        CAST(sell_price AS FLOAT64) AS sell_price,
        CURRENT_TIMESTAMP() AS load_timestamp
      FROM `portfolio_staging.stg_transactions`
      WHERE symbol IS NOT NULL
        AND account IS NOT NULL
        AND purchase_date IS NOT NULL
      ORDER BY symbol, account, purchase_date, COALESCE(sell_date, purchase_date)
    """;
    RAISE NOTICE 'Successfully refreshed fact_transactions';
    
    -- Refresh cash fact table
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.fact_cash` AS
      SELECT
        account,
        CAST(date AS DATE) AS date,
        CAST(cash_amount AS FLOAT64) AS cash_amount,
        CURRENT_TIMESTAMP() AS load_timestamp
      FROM `portfolio_staging.stg_cash`
      WHERE account IS NOT NULL
        AND date IS NOT NULL
        AND cash_amount IS NOT NULL
      ORDER BY account, date
    """;
    RAISE NOTICE 'Successfully refreshed fact_cash';
    
    -- Refresh prices fact table
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.fact_prices` AS
      WITH price_enrichment AS (
        SELECT
          CAST(date AS DATE) AS price_date,
          Ticker AS symbol,
          CAST(open AS FLOAT64) AS open_price,
          CAST(high AS FLOAT64) AS high_price,
          CAST(low AS FLOAT64) AS low_price,
          CAST(close AS FLOAT64) AS close_price,
          CAST(volume AS INT64) AS volume,
          ROUND(CAST(close AS FLOAT64) - CAST(open AS FLOAT64), 4) AS daily_change,
          CASE 
            WHEN CAST(open AS FLOAT64) != 0 
            THEN ROUND((CAST(close AS FLOAT64) - CAST(open AS FLOAT64)) / CAST(open AS FLOAT64) * 100, 2)
            ELSE NULL
          END AS daily_change_pct,
          ROUND(CAST(high AS FLOAT64) - CAST(low AS FLOAT64), 4) AS daily_range,
          CASE 
            WHEN CAST(low AS FLOAT64) != 0
            THEN ROUND((CAST(high AS FLOAT64) - CAST(low AS FLOAT64)) / CAST(low AS FLOAT64) * 100, 2)
            ELSE NULL
          END AS daily_range_pct,
          CASE
            WHEN (CAST(high AS FLOAT64) - CAST(low AS FLOAT64)) != 0
            THEN ROUND((CAST(close AS FLOAT64) - CAST(low AS FLOAT64)) / (CAST(high AS FLOAT64) - CAST(low AS FLOAT64)), 4)
            ELSE NULL
          END AS close_position_in_range,
          LAG(CAST(close AS FLOAT64)) OVER (PARTITION BY Ticker ORDER BY date) AS previous_close,
          CURRENT_TIMESTAMP() AS load_timestamp
        FROM `portfolio_staging.stg_prices`
      )
      SELECT
        price_date,
        symbol,
        open_price,
        high_price,
        low_price,
        close_price,
        volume,
        daily_change,
        daily_change_pct,
        daily_range,
        daily_range_pct,
        close_position_in_range,
        ROUND(close_price - COALESCE(previous_close, close_price), 4) AS price_change_from_previous,
        CASE
          WHEN COALESCE(previous_close, close_price) != 0
          THEN ROUND((close_price - COALESCE(previous_close, close_price)) / COALESCE(previous_close, close_price) * 100, 2)
          ELSE NULL
        END AS price_change_from_previous_pct,
        volume > 0 AS is_trading_day,
        load_timestamp
      FROM price_enrichment
      WHERE symbol IS NOT NULL
        AND price_date IS NOT NULL
        AND close_price IS NOT NULL
      ORDER BY symbol, price_date DESC
    """;
    RAISE NOTICE 'Successfully refreshed fact_prices';
    
    -- Phase 3: Refresh Analytics Tables (can be parallel but executing sequentially for clarity)
    RAISE NOTICE 'Refreshing analytics tables...';
    
    -- Refresh portfolio_metrics table
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.portfolio_metrics` AS
      WITH current_holdings AS (
        SELECT
          symbol,
          account,
          SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) AS shares_bought,
          SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS shares_sold,
          SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) - 
            SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS current_shares,
          AVG(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN purchase_price ELSE NULL END) AS avg_buy_price,
          MIN(purchase_date) AS first_purchase_date,
          MAX(COALESCE(sell_date, purchase_date)) AS last_transaction_date
        FROM `portfolio_analytics.fact_transactions`
        GROUP BY symbol, account
        HAVING current_shares > 0
      ),
      cost_basis AS (
        SELECT
          symbol,
          account,
          SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares * purchase_price ELSE 0 END) AS total_cost_basis
        FROM `portfolio_analytics.fact_transactions`
        GROUP BY symbol, account
      ),
      latest_prices AS (
        SELECT
          Ticker AS symbol,
          close AS current_price,
          ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
        FROM `portfolio_staging.stg_prices`
      ),
      sp500_benchmark AS (
        SELECT
          close AS sp500_price,
          date AS sp500_date,
          ROW_NUMBER() OVER (ORDER BY date DESC) AS rn
        FROM `portfolio_staging.stg_prices`
        WHERE Ticker = '^GSPC'
      ),
      latest_cash AS (
        SELECT
          account,
          cash_amount,
          date,
          ROW_NUMBER() OVER (PARTITION BY account ORDER BY date DESC) AS rn
        FROM `portfolio_analytics.fact_cash`
      )
      SELECT
        h.symbol,
        h.account,
        h.current_shares,
        ROUND(h.avg_buy_price, 2) AS avg_purchase_price,
        ROUND(cb.total_cost_basis, 2) AS cost_basis,
        ROUND(lp.current_price, 2) AS current_price,
        ROUND(h.current_shares * lp.current_price, 2) AS current_value,
        ROUND(h.current_shares * lp.current_price - cb.total_cost_basis, 2) AS unrealized_pl,
        CASE 
          WHEN cb.total_cost_basis > 0 
          THEN ROUND((h.current_shares * lp.current_price - cb.total_cost_basis) / cb.total_cost_basis * 100, 2)
          ELSE NULL 
        END AS unrealized_pl_pct,
        ROUND(DATE_DIFF(CURRENT_DATE(), h.first_purchase_date, DAY) / 365.25, 2) AS years_held,
        lc.cash_amount AS account_cash,
        sb.sp500_price,
        ROUND(sb.sp500_price * h.current_shares * COALESCE((SELECT AVG(purchase_price) FROM `portfolio_analytics.fact_transactions` WHERE symbol = '^GSPC'), 1), 2) AS sp500_value_equivalent,
        h.first_purchase_date,
        h.last_transaction_date
      FROM current_holdings h
      LEFT JOIN cost_basis cb USING (symbol, account)
      LEFT JOIN latest_prices lp ON h.symbol = lp.symbol AND lp.rn = 1
      LEFT JOIN sp500_benchmark sb ON sb.rn = 1
      LEFT JOIN latest_cash lc ON h.account = lc.account AND lc.rn = 1
      ORDER BY h.account, h.symbol
    """;
    RAISE NOTICE 'Successfully refreshed portfolio_metrics';
    
    -- Refresh holdings_summary table
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.holdings_summary` AS
      WITH current_holdings AS (
        SELECT
          symbol,
          account,
          SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) AS shares_bought,
          SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS shares_sold,
          SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) - 
            SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS current_shares,
          COUNT(DISTINCT CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN purchase_date END) AS num_purchase_lots,
          MIN(purchase_date) AS first_purchase_date,
          MAX(COALESCE(sell_date, purchase_date)) AS last_transaction_date
        FROM `portfolio_analytics.fact_transactions`
        GROUP BY symbol, account
        HAVING current_shares > 0
      ),
      cost_basis AS (
        SELECT
          symbol,
          account,
          SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares * purchase_price ELSE 0 END) AS total_cost_basis
        FROM `portfolio_analytics.fact_transactions`
        GROUP BY symbol, account
      ),
      latest_prices AS (
        SELECT
          Ticker AS symbol,
          close AS current_price,
          ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
        FROM `portfolio_staging.stg_prices`
      )
      SELECT
        h.symbol,
        h.account,
        h.current_shares,
        ROUND(cb.total_cost_basis, 2) AS cost_basis,
        ROUND(h.current_shares * lp.current_price, 2) AS current_value,
        ROUND(h.current_shares * lp.current_price - cb.total_cost_basis, 2) AS unrealized_pl,
        CASE 
          WHEN cb.total_cost_basis > 0 
          THEN ROUND((h.current_shares * lp.current_price - cb.total_cost_basis) / cb.total_cost_basis * 100, 2)
          ELSE NULL 
        END AS unrealized_pl_pct,
        h.num_purchase_lots,
        h.first_purchase_date,
        h.last_transaction_date
      FROM current_holdings h
      LEFT JOIN cost_basis cb USING (symbol, account)
      LEFT JOIN latest_prices lp ON h.symbol = lp.symbol AND lp.rn = 1
      ORDER BY h.account, h.symbol
    """;
    RAISE NOTICE 'Successfully refreshed holdings_summary';
    
    -- Refresh cash_summary table
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.cash_summary` AS
      WITH latest_cash AS (
        SELECT
          account,
          cash_amount,
          date,
          ROW_NUMBER() OVER (PARTITION BY account ORDER BY date DESC) AS rn
        FROM `portfolio_analytics.fact_cash`
      ),
      securities_value_by_account AS (
        SELECT
          account,
          SUM(ch.current_shares * lp.current_price) AS total_securities_value
        FROM (
          SELECT
            symbol,
            account,
            SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) - 
              SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS current_shares
          FROM `portfolio_analytics.fact_transactions`
          GROUP BY symbol, account
          HAVING current_shares > 0
        ) ch
        LEFT JOIN (
          SELECT
            Ticker AS symbol,
            close AS current_price,
            ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
          FROM `portfolio_staging.stg_prices`
        ) lp ON ch.symbol = lp.symbol AND lp.rn = 1
        GROUP BY account
      )
      SELECT
        lc.account,
        ROUND(lc.cash_amount, 2) AS cash_amount,
        ROUND(COALESCE(sv.total_securities_value, 0), 2) AS total_securities_value,
        ROUND(lc.cash_amount + COALESCE(sv.total_securities_value, 0), 2) AS total_portfolio_value,
        CASE
          WHEN lc.cash_amount + COALESCE(sv.total_securities_value, 0) > 0
          THEN ROUND(lc.cash_amount / (lc.cash_amount + COALESCE(sv.total_securities_value, 0)) * 100, 2)
          ELSE 0
        END AS cash_pct_of_portfolio,
        CASE
          WHEN lc.cash_amount + COALESCE(sv.total_securities_value, 0) > 0
          THEN ROUND(COALESCE(sv.total_securities_value, 0) / (lc.cash_amount + COALESCE(sv.total_securities_value, 0)) * 100, 2)
          ELSE 0
        END AS securities_pct_of_portfolio,
        lc.date AS last_cash_update_date
      FROM latest_cash lc
      LEFT JOIN securities_value_by_account sv ON lc.account = sv.account
      WHERE lc.rn = 1
      ORDER BY lc.account
    """;
    RAISE NOTICE 'Successfully refreshed cash_summary';
    
    -- Refresh realized_gains table
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.realized_gains` AS
      SELECT
        symbol,
        account,
        purchase_date,
        ROUND(purchase_price, 2) AS purchase_price,
        sell_date,
        ROUND(sell_price, 2) AS sell_price,
        ROUND(shares, 2) AS shares,
        ROUND(shares * purchase_price, 2) AS cost_basis,
        ROUND(shares * sell_price, 2) AS proceeds,
        ROUND(shares * sell_price - shares * purchase_price, 2) AS gain_loss_amount,
        CASE
          WHEN shares * purchase_price > 0
          THEN ROUND((shares * sell_price - shares * purchase_price) / (shares * purchase_price) * 100, 2)
          ELSE NULL
        END AS gain_loss_pct,
        DATE_DIFF(sell_date, purchase_date, DAY) AS holding_period_days,
        ROUND(DATE_DIFF(sell_date, purchase_date, DAY) / 365.25, 2) AS holding_period_years,
        CASE
          WHEN DATE_DIFF(sell_date, purchase_date, DAY) > 365 THEN TRUE
          ELSE FALSE
        END AS is_long_term_gain,
        transaction_type
      FROM `portfolio_analytics.fact_transactions`
      WHERE sell_date IS NOT NULL
        AND sell_price IS NOT NULL
      ORDER BY account, symbol, sell_date
    """;
    RAISE NOTICE 'Successfully refreshed realized_gains';
    
    -- Refresh account_performance_summary table
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.account_performance_summary` AS
      WITH account_holdings AS (
        SELECT
          account,
          SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END) - 
            SUM(CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END) AS current_shares,
          symbol
        FROM `portfolio_analytics.fact_transactions`
        GROUP BY symbol, account
        HAVING current_shares > 0
      ),
      account_unrealized AS (
        SELECT
          account,
          SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares * purchase_price ELSE 0 END) AS total_cost_basis,
          SUM(ah.current_shares * lp.current_price) AS total_current_value,
          SUM(ah.current_shares * lp.current_price) - 
            SUM(CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares * purchase_price ELSE 0 END) AS total_unrealized_pl
        FROM `portfolio_analytics.fact_transactions` ft
        LEFT JOIN account_holdings ah USING (account, symbol)
        LEFT JOIN (
          SELECT Ticker AS symbol, close AS current_price,
            ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
          FROM `portfolio_staging.stg_prices`
        ) lp ON ah.symbol = lp.symbol AND lp.rn = 1
        GROUP BY account
      ),
      account_realized AS (
        SELECT
          account,
          SUM(CASE WHEN sell_price IS NOT NULL THEN shares * sell_price - shares * purchase_price ELSE 0 END) AS total_realized_pl
        FROM `portfolio_analytics.fact_transactions`
        WHERE sell_date IS NOT NULL
        GROUP BY account
      ),
      account_cash AS (
        SELECT
          account,
          cash_amount,
          ROW_NUMBER() OVER (PARTITION BY account ORDER BY date DESC) AS rn
        FROM `portfolio_analytics.fact_cash`
      ),
      sp500_prices AS (
        SELECT
          close AS sp500_current_price,
          ROW_NUMBER() OVER (ORDER BY date DESC) AS rn
        FROM `portfolio_staging.stg_prices`
        WHERE Ticker = '^GSPC'
      ),
      sp500_performance AS (
        SELECT
          ft.account,
          AVG(CASE WHEN ft.transaction_type IN ('buy', 'reinvestment') THEN ft.purchase_price END) AS avg_sp500_purchase_price,
          COALESCE(
            (SELECT close FROM `portfolio_staging.stg_prices` 
             WHERE Ticker = '^GSPC' AND date <= MIN(ft.purchase_date) 
             ORDER BY date DESC LIMIT 1),
            (SELECT close FROM `portfolio_staging.stg_prices` 
             WHERE Ticker = '^GSPC' 
             ORDER BY date DESC LIMIT 1)
          ) AS sp500_cost_basis
        FROM `portfolio_analytics.fact_transactions` ft
        WHERE ft.symbol IS NOT NULL
        GROUP BY ft.account
      )
      SELECT
        au.account,
        ROUND(COALESCE(au.total_current_value, 0) + COALESCE(ac.cash_amount, 0), 2) AS total_portfolio_value,
        ROUND(COALESCE(au.total_current_value, 0), 2) AS total_securities_value,
        ROUND(COALESCE(ac.cash_amount, 0), 2) AS total_cash,
        ROUND(COALESCE(au.total_cost_basis, 0), 2) AS total_cost_basis,
        ROUND(COALESCE(au.total_unrealized_pl, 0), 2) AS total_unrealized_pl,
        CASE
          WHEN au.total_cost_basis > 0
          THEN ROUND(COALESCE(au.total_unrealized_pl, 0) / au.total_cost_basis * 100, 2)
          ELSE NULL
        END AS total_unrealized_pl_pct,
        ROUND(COALESCE(ar.total_realized_pl, 0), 2) AS total_realized_pl,
        CASE
          WHEN COALESCE(au.total_unrealized_pl, 0) + COALESCE(ar.total_realized_pl, 0) > 0 THEN
            ROUND((COALESCE(au.total_unrealized_pl, 0) + COALESCE(ar.total_realized_pl, 0)) / 
              (au.total_cost_basis + COALESCE((SELECT SUM(shares * sell_price) FROM `portfolio_analytics.fact_transactions` WHERE account = au.account AND sell_date IS NOT NULL), 0)) * 100, 2)
          ELSE NULL
        END AS total_realized_pl_pct,
        sp500p.sp500_current_price,
        ROUND(COALESCE(au.total_current_value, 0) / NULLIF(sp500p.sp500_current_price / sp500p2.sp500_cost_basis * au.total_cost_basis, 0) - 1, 4) AS vs_sp500_return_multiple,
        CASE
          WHEN sp500p2.sp500_cost_basis > 0
          THEN ROUND((COALESCE(au.total_current_value, 0) - sp500p.sp500_current_price / sp500p2.sp500_cost_basis * au.total_cost_basis) / 
                     (sp500p.sp500_current_price / sp500p2.sp500_cost_basis * au.total_cost_basis) * 100, 2)
          ELSE NULL
        END AS vs_sp500_return_pct,
        CURRENT_TIMESTAMP() AS refresh_timestamp
      FROM account_unrealized au
      LEFT JOIN account_realized ar USING (account)
      LEFT JOIN account_cash ac ON au.account = ac.account AND ac.rn = 1
      LEFT JOIN sp500_prices sp500p ON sp500p.rn = 1
      LEFT JOIN sp500_performance sp500p2 ON au.account = sp500p2.account
      ORDER BY au.account
    """;
    RAISE NOTICE 'Successfully refreshed account_performance_summary';
    
    -- Refresh price_history_with_transactions table
    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `portfolio_analytics.price_history_with_transactions` AS
      WITH price_data AS (
        SELECT
          Ticker AS symbol,
          date,
          close AS price,
          open,
          high,
          low,
          volume,
          ROW_NUMBER() OVER (PARTITION BY Ticker ORDER BY date DESC) AS rn
        FROM `portfolio_staging.stg_prices`
      ),
      transaction_dates AS (
        SELECT
          symbol,
          purchase_date AS transaction_date,
          'buy' AS transaction_type,
          account,
          CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN shares ELSE 0 END AS buy_shares,
          0 AS sell_shares,
          CASE WHEN transaction_type IN ('buy', 'reinvestment') THEN purchase_price ELSE NULL END AS buy_price,
          NULL AS sell_price
        FROM `portfolio_analytics.fact_transactions`
        WHERE transaction_type IN ('buy', 'reinvestment')
        
        UNION ALL
        
        SELECT
          symbol,
          sell_date AS transaction_date,
          'sell' AS transaction_type,
          account,
          0 AS buy_shares,
          CASE WHEN transaction_type = 'sell' THEN shares ELSE 0 END AS sell_shares,
          NULL AS buy_price,
          CASE WHEN transaction_type = 'sell' THEN sell_price ELSE NULL END AS sell_price
        FROM `portfolio_analytics.fact_transactions`
        WHERE transaction_type = 'sell' AND sell_date IS NOT NULL
      )
      SELECT
        pd.symbol,
        CAST(pd.date AS DATE) AS date,
        ROUND(pd.price, 2) AS close_price,
        ROUND(pd.open, 2) AS open_price,
        ROUND(pd.high, 2) AS high_price,
        ROUND(pd.low, 2) AS low_price,
        pd.volume,
        COALESCE(SUM(CASE WHEN td.transaction_type = 'buy' THEN td.buy_shares ELSE 0 END), 0) AS total_buy_shares,
        COALESCE(SUM(CASE WHEN td.transaction_type = 'sell' THEN td.sell_shares ELSE 0 END), 0) AS total_sell_shares,
        ROUND(COALESCE(AVG(CASE WHEN td.transaction_type = 'buy' THEN td.buy_price END), NULL), 2) AS avg_buy_price,
        ROUND(COALESCE(AVG(CASE WHEN td.transaction_type = 'sell' THEN td.sell_price END), NULL), 2) AS avg_sell_price,
        STRING_AGG(DISTINCT CASE WHEN td.transaction_type = 'buy' THEN td.account END, ', ') AS accounts_bought,
        STRING_AGG(DISTINCT CASE WHEN td.transaction_type = 'sell' THEN td.account END, ', ') AS accounts_sold,
        CASE WHEN SUM(CASE WHEN td.transaction_type = 'buy' THEN td.buy_shares ELSE 0 END) > 0 THEN TRUE ELSE FALSE END AS has_buy,
        CASE WHEN SUM(CASE WHEN td.transaction_type = 'sell' THEN td.sell_shares ELSE 0 END) > 0 THEN TRUE ELSE FALSE END AS has_sell
      FROM price_data pd
      LEFT JOIN transaction_dates td ON pd.symbol = td.symbol AND CAST(pd.date AS DATE) = CAST(td.transaction_date AS DATE)
      WHERE pd.rn IS NOT NULL
      GROUP BY pd.symbol, pd.date, pd.price, pd.open, pd.high, pd.low, pd.volume
      ORDER BY pd.symbol, pd.date DESC
    """;
    RAISE NOTICE 'Successfully refreshed price_history_with_transactions';
    
    SET end_time = CURRENT_TIMESTAMP();
    RAISE NOTICE 'Analytics refresh completed successfully at %s (duration: %s)', end_time, TIMESTAMP_DIFF(end_time, start_time, SECOND);
    
  EXCEPTION WHEN ERROR THEN
    SET error_msg = @@error.message;
    RAISE USING MESSAGE = CONCAT('Analytics refresh failed: ', error_msg);
  END;
  
END;
