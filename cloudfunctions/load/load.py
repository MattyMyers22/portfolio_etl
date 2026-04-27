"""
Load clean parquet data from GCS into BigQuery portfolio_staging dataset.

Reads three parquet files from GCS clean/ folder (transactions, cash, prices)
and loads them into BigQuery tables with explicit schema definitions and
parallel loading for performance. Implements full refresh strategy with
WRITE_TRUNCATE to ensure clean data on each load.

Author: Matthew Myers
"""

import logging
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, Tuple

import pandas as pd
from google.cloud import bigquery
from google.oauth2 import service_account

# Import shared utilities
import sys
from pathlib import Path

# Add parent directory to path to import shared modules
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from shared import SecretManager, read_gcs_parquet_to_df

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# BigQuery Config
PROJECT_ID = "holdings-extract"
DATASET_ID = "portfolio_staging"

# Define explicit BigQuery schemas for all tables
# Using FLOAT64 for numeric columns (pandas float64 maps cleanly to BigQuery FLOAT64)
SCHEMAS = {
    "stg_transactions": [
        bigquery.SchemaField("transaction_type", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("account", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("symbol", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("purchase_date", "TIMESTAMP", mode="NULLABLE"),
        bigquery.SchemaField("shares", "FLOAT64", mode="NULLABLE"),
        bigquery.SchemaField("purchase_price", "FLOAT64", mode="NULLABLE"),
        bigquery.SchemaField("sell_date", "TIMESTAMP", mode="NULLABLE"),
        bigquery.SchemaField("sell_price", "FLOAT64", mode="NULLABLE")
    ],
    "stg_cash": [
        bigquery.SchemaField("date", "TIMESTAMP", mode="NULLABLE"),
        bigquery.SchemaField("account", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("cash_amount", "FLOAT64", mode="NULLABLE")
    ],
    "stg_prices": [
        bigquery.SchemaField("date", "TIMESTAMP", mode="NULLABLE"),
        bigquery.SchemaField("Ticker", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("close", "FLOAT64", mode="NULLABLE"),
        bigquery.SchemaField("high", "FLOAT64", mode="NULLABLE"),
        bigquery.SchemaField("low", "FLOAT64", mode="NULLABLE"),
        bigquery.SchemaField("open", "FLOAT64", mode="NULLABLE"),
        bigquery.SchemaField("volume", "INT64", mode="NULLABLE")
    ]
}

# Mapping of table names to GCS parquet file paths
TABLE_MAPPINGS = {
    "stg_transactions": "clean/clean_transactions.parquet",
    "stg_cash": "clean/clean_cash.parquet",
    "stg_prices": "clean/clean_prices.parquet",
}


def get_bigquery_client() -> bigquery.Client:
    """
    Get an authenticated BigQuery client using credentials from Secret Manager.
    
    Returns:
        google.cloud.bigquery.Client: An authenticated BigQuery client.
        
    Raises:
        RuntimeError: If credentials cannot be retrieved or are invalid.
    """
    try:
        service_account_key = SecretManager.get_secret("GCP_SERVICE_ACCOUNT_KEY")
        credentials_dict = json.loads(service_account_key)
        
        credentials = service_account.Credentials.from_service_account_info(credentials_dict)
        client = bigquery.Client(project=PROJECT_ID, credentials=credentials)
        logger.info("Successfully created BigQuery client")
        return client
    except Exception as e:
        logger.error(f"Failed to create BigQuery client: {str(e)}")
        raise RuntimeError(f"Failed to create BigQuery client: {str(e)}") from e


def load_table_to_bq(
    table_name: str,
    gcs_parquet_path: str,
    client: bigquery.Client,
    schema: list
) -> Tuple[str, bool, Dict]:
    """
    Load a single table from GCS parquet to BigQuery with explicit schema.
    
    Reads parquet file from GCS, converts to BigQuery-compatible DataFrame,
    and loads with WRITE_TRUNCATE disposition (creates table on first load,
    truncates on subsequent loads).
    
    Args:
        table_name (str): Name of the BigQuery table (e.g., 'stg_transactions').
        gcs_parquet_path (str): Path to parquet file in GCS (e.g., 'clean/clean_transactions.parquet').
        client (bigquery.Client): Authenticated BigQuery client.
        schema (list): List of bigquery.SchemaField objects defining table schema.
        
    Returns:
        Tuple[str, bool, Dict]: A tuple of (table_name, success_flag, result_dict)
                               where result_dict contains status info and row count.
    """
    try:
        logger.info(f"Starting load for table: {table_name}")
        
        # Read parquet from GCS
        logger.info(f"Reading parquet from GCS: {gcs_parquet_path}")
        df = read_gcs_parquet_to_df(gcs_parquet_path)
        logger.info(f"Read {len(df)} rows from {gcs_parquet_path}")
        logger.info(f"DataFrame columns: {list(df.columns)}, dtypes: {dict(df.dtypes)}")
        
        # BigQuery load_table_from_dataframe handles type conversion using the provided schema
        # No need to manually convert timestamps or numerics
        
        # Configure load job
        table_id = f"{PROJECT_ID}.{DATASET_ID}.{table_name}"
        job_config = bigquery.LoadJobConfig(
            schema=schema,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE
        )
        
        # Load data to BigQuery
        logger.info(f"Loading {len(df)} rows to BigQuery table: {table_id}")
        load_job = client.load_table_from_dataframe(
            df,
            table_id,
            job_config=job_config
        )
        load_job.result()  # Wait for job to complete
        logger.info(f"Successfully loaded {len(df)} rows to {table_id}")
        
        result = {
            "table": table_name,
            "status": "success",
            "rows_loaded": len(df),
            "destination": table_id
        }
        return table_name, True, result
        
    except Exception as e:
        logger.error(f"Failed to load table {table_name}: {str(e)}")
        result = {
            "table": table_name,
            "status": "failed",
            "error": str(e)
        }
        return table_name, False, result


def main():
    """
    Main execution function to load all three tables in parallel.
    
    Reads clean parquet files from GCS and loads into BigQuery with explicit
    schema definitions. Uses ThreadPoolExecutor for parallel loading across
    the three tables (stg_transactions, stg_cash, stg_prices).
    """
    try:
        logger.info("=" * 80)
        logger.info("Starting BigQuery portfolio_staging data load")
        logger.info("=" * 80)
        
        # Get authenticated BigQuery client
        client = get_bigquery_client()
        logger.info(f"Target dataset: {PROJECT_ID}.{DATASET_ID}")
        
        # Load tables in parallel using ThreadPoolExecutor
        logger.info("Initiating parallel load for all three tables")
        results = {}
        failures = []
        
        with ThreadPoolExecutor(max_workers=3) as executor:
            # Submit all load tasks
            future_to_table = {
                executor.submit(
                    load_table_to_bq,
                    table_name,
                    TABLE_MAPPINGS[table_name],
                    client,
                    SCHEMAS[table_name]
                ): table_name
                for table_name in TABLE_MAPPINGS.keys()
            }
            
            # Process completed tasks
            for future in as_completed(future_to_table):
                table_name = future_to_table[future]
                try:
                    table_name, success, result = future.result()
                    results[table_name] = result
                    
                    if success:
                        logger.info(f"✓ {table_name}: {result['rows_loaded']} rows loaded")
                    else:
                        logger.error(f"✗ {table_name}: {result['error']}")
                        failures.append(table_name)
                except Exception as e:
                    logger.error(f"Exception executing load for {table_name}: {str(e)}")
                    results[table_name] = {
                        "table": table_name,
                        "status": "failed",
                        "error": str(e)
                    }
                    failures.append(table_name)
        
        # Summary
        logger.info("=" * 80)
        logger.info("Load Summary")
        logger.info("=" * 80)
        for table_name, result in results.items():
            if result["status"] == "success":
                logger.info(f"✓ {table_name}: {result['rows_loaded']} rows → {result['destination']}")
            else:
                logger.info(f"✗ {table_name}: {result['error']}")
        
        if failures:
            logger.warning(f"Load completed with {len(failures)} failure(s): {', '.join(failures)}")
            raise RuntimeError(f"Load failed for tables: {', '.join(failures)}")
        else:
            logger.info("✓ All tables loaded successfully!")
        
        logger.info("=" * 80)
        
    except Exception as e:
        logger.error(f"Fatal error during load: {str(e)}")
        raise


if __name__ == "__main__":
    main()
