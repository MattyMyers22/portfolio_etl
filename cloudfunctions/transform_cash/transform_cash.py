# Transform raw cash data for cleaning and storage in GCS

import logging
import pandas as pd

# Import shared utilities
import sys
from pathlib import Path

# Add parent directory to path to import shared modules
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from shared import read_gcs_csv_to_df, upload_df_to_gcs

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def main():
    """Main execution function to extract, transform, and load cash data."""
    try:
        logger.info("Starting cash data transformation")
        
        # Extract raw cash CSV from GCS
        logger.info("Reading raw cash data from GCS")
        raw_cash_df = read_gcs_csv_to_df('raw/raw_cash.csv')
        logger.info(f"Raw cash data extracted successfully")
        logger.info(f"Shape: {raw_cash_df.shape}")
        logger.info(f"\nFirst few rows:\n{raw_cash_df.head()}\n")

        # Transform: Clean raw cash data
        logger.info("Cleaning data - converting date column to datetime")
        raw_cash_df['date'] = pd.to_datetime(raw_cash_df['date'])
        logger.info(f"Data types after cleaning:\n{raw_cash_df.dtypes}\n")

        # Load: Upload cleaned data as Parquet to GCS
        logger.info("Uploading cleaned cash data to GCS as Parquet")
        gcs_path = upload_df_to_gcs(raw_cash_df, 'clean/clean_cash.parquet', file_format='parquet')
        logger.info(f"Parquet file uploaded to {gcs_path}")
        
        logger.info("Cash data transformation completed successfully")

    except Exception as e:
        logger.error(f"Fatal error during execution: {str(e)}")
        raise


if __name__ == "__main__":
    main()
