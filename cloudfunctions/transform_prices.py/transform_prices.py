# Transform raw historical price data for cleaning and storage in GCS

import pandas as pd
import logging

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
    """Main execution function to extract, transform, and load historical price data."""
    try:
        logger.info("Starting historical price data transformation")
        
        # Extract raw historical price CSV from GCS
        logger.info("Reading raw historical price data from GCS")
        raw_prices_df = read_gcs_csv_to_df('raw/raw_prices.csv')
        logger.info(f"Raw historical price data extracted successfully")
        logger.info(f"Shape: {raw_prices_df.shape}")
        logger.info(f"\nFirst few rows:\n{raw_prices_df.head()}\n")

        # Transform: Clean raw historical price data
        logger.info("Cleaning data - renaming columns and converting date column to datetime")
        new_names = {'Date':'date', 'Open':'open', 'High':'high', 'Low':'low', 'Close':'close',
                     'Adj Close':'adj_close', 'Volume':'volume'}
        raw_prices_df = raw_prices_df.rename(columns=new_names)
        raw_prices_df['date'] = pd.to_datetime(raw_prices_df['date'])
        logger.info(f"Data types after cleaning:\n{raw_prices_df.dtypes}\n")

        # Load: Upload cleaned data as Parquet to GCS
        logger.info("Uploading cleaned historical price data to GCS as Parquet")
        gcs_path = upload_df_to_gcs(raw_prices_df, 'clean/clean_prices.parquet', file_format='parquet')
        logger.info(f"Parquet file uploaded to {gcs_path}")
        
        logger.info("Historical price data transformation completed successfully")

    except Exception as e:
        logger.error(f"Fatal error during execution: {str(e)}")
        raise

if __name__ == "__main__":
    main()
