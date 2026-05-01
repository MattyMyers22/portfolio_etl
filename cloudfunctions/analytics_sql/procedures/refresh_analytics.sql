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
    
    SET end_time = CURRENT_TIMESTAMP();
    RAISE NOTICE 'Analytics refresh completed successfully at %s (duration: %s)', end_time, TIMESTAMP_DIFF(end_time, start_time, SECOND);
    
  EXCEPTION WHEN ERROR THEN
    SET error_msg = @@error.message;
    RAISE USING MESSAGE = CONCAT('Analytics refresh failed: ', error_msg);
  END;
  
END;
