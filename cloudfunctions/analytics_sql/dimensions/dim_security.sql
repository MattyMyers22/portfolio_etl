-- Security Master Dimension Table
-- Extracts unique securities from transactions and prices
-- Includes metadata columns for future expansion (asset_class, sector)

CREATE OR REPLACE TABLE `portfolio_analytics.dim_security` AS
WITH all_symbols AS (
  -- Collect all unique symbols from transactions and prices
  SELECT DISTINCT symbol FROM `portfolio_staging.stg_transactions` WHERE symbol IS NOT NULL
  UNION DISTINCT
  SELECT DISTINCT Ticker AS symbol FROM `portfolio_staging.stg_prices` WHERE Ticker IS NOT NULL
)
SELECT
  symbol,
  NULL AS asset_class,  -- Placeholder for future enrichment
  NULL AS sector        -- Placeholder for future enrichment
FROM all_symbols
ORDER BY symbol;
