# Script to clean transaction data stored in GCP Storage

import logging
import pandas as pd

# Import shared utilities
import sys
from pathlib import Path

# Add parent directory to path to import shared modules
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from shared import SecretManager, read_gcs_csv_to_df, upload_df_to_gcs

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main():
    """Main execution function to pull raw data stored in GCS, clean it, and upload cleaned data back to GCS."""
    try:
        logger.info("Starting transaction data transformation")
        
        # Extract raw transaction CSV from GCS
        logger.info("Reading raw transaction data from GCS")
        raw_transactions_df = read_gcs_csv_to_df('raw/raw_transactions.csv')
        logger.info(f"Raw transaction data extracted successfully")
        logger.info(f"Shape: {raw_transactions_df.shape}")
        logger.info(f"\nFirst few rows:\n{raw_transactions_df.head()}\n")

        # Transform: Clean raw transaction data
        logger.info("Cleaning data - converting date columns to datetime")
        raw_transactions_df['purchase_date'] = pd.to_datetime(raw_transactions_df['purchase_date'], format='mixed', dayfirst=False)
        raw_transactions_df['sell_date'] = pd.to_datetime(raw_transactions_df['sell_date'], format='mixed', dayfirst=False)
        logger.info(f"Data types after cleaning:\n{raw_transactions_df.dtypes}\n")

        # Load: Upload cleaned data as Parquet to GCS
        logger.info("Uploading cleaned transaction data to GCS as Parquet")
        gcs_path = upload_df_to_gcs(raw_transactions_df, 'clean/clean_transactions.parquet', file_format='parquet')
        logger.info(f"Parquet file uploaded to {gcs_path}")
        
        logger.info("Transaction data transformation completed successfully")

    except Exception as e:
        logger.error(f"Fatal error during execution: {str(e)}")
        raise

if __name__ == "__main__":
    main()
