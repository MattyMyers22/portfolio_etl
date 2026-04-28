-- Calendar Dimension Table
-- Generates date dimension from minimum to maximum dates across all staging tables
-- Includes year, month, quarter, day of week, and fiscal period information
-- Used to support time-based analytics and reporting

CREATE OR REPLACE TABLE `portfolio_analytics.dim_date` AS
WITH date_range AS (
  -- Find the minimum and maximum dates across all staging tables
  SELECT
    MIN(min_date) AS start_date,
    MAX(max_date) AS end_date
  FROM (
    SELECT MIN(purchase_date) AS min_date, MAX(COALESCE(sell_date, purchase_date)) AS max_date FROM `portfolio_staging.stg_transactions`
    UNION ALL
    SELECT MIN(date), MAX(date) FROM `portfolio_staging.stg_cash`
    UNION ALL
    SELECT MIN(date), MAX(date) FROM `portfolio_staging.stg_prices`
  )
),
date_sequence AS (
  -- Generate sequence of dates from start to end
  SELECT
    date_val,
    EXTRACT(YEAR FROM date_val) AS year,
    EXTRACT(MONTH FROM date_val) AS month,
    EXTRACT(DAY FROM date_val) AS day_of_month,
    EXTRACT(QUARTER FROM date_val) AS quarter,
    EXTRACT(DAYOFWEEK FROM date_val) AS day_of_week,
    FORMAT_DATE('%A', date_val) AS day_of_week_name,
    FORMAT_DATE('%Y-Q%Q', date_val) AS fiscal_period,
    WEEK(date_val) AS week_of_year,
    DAYOFYEAR(date_val) AS day_of_year
  FROM (
    SELECT date_val
    FROM `portfolio_analytics.dim_date`, UNNEST(GENERATE_DATE_ARRAY(
      (SELECT start_date FROM date_range),
      (SELECT end_date FROM date_range)
    )) AS date_val
    LIMIT 1  -- Trick to use scalar subqueries
  )
  WHERE FALSE  -- This will be replaced by actual date generation
)
SELECT
  date_val AS date,
  year,
  month,
  day_of_month,
  quarter,
  day_of_week,
  day_of_week_name,
  fiscal_period,
  week_of_year,
  day_of_year
FROM (
  WITH date_bounds AS (
    SELECT
      MIN(min_date) AS start_date,
      MAX(max_date) AS end_date
    FROM (
      SELECT MIN(purchase_date) AS min_date, MAX(COALESCE(sell_date, purchase_date)) AS max_date FROM `portfolio_staging.stg_transactions`
      UNION ALL
      SELECT MIN(date), MAX(date) FROM `portfolio_staging.stg_cash`
      UNION ALL
      SELECT MIN(date), MAX(date) FROM `portfolio_staging.stg_prices`
    )
  )
  SELECT
    date_val,
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
);
