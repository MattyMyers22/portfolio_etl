# Script to extract historical prices from yfinance

import logging
import yfinance as yf
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

# Portfolio Start Date
PORTFOLIO_START_DATE = '2019-01-30'


def extract_yfinance_data(ticker='^GSPC', start_date=PORTFOLIO_START_DATE, end_date=None):
    """
    Extracts historical prices of stocks/funds using the yfinance library.

    Args:
        ticker (str): The ticker symbol of the stock to extract prices for.
                     Defaults to '^GSPC' (S&P 500).
        start_date (str): The start date of the price data to extract.
                         Defaults to PORTFOLIO_START_DATE.
        end_date (str or None): The end date of the price data to extract.
                               Defaults to None (current date).

    Returns:
        pd.DataFrame: A DataFrame containing the historical prices of a stock.
    """
    try:
        logger.info(f"Downloading {ticker} data from {start_date} to {end_date}")
        
        # Download price data
        data = yf.download(ticker, start=start_date, end=end_date, progress=False)

        # Flatten the multi-level columns if necessary
        if isinstance(data.columns, pd.MultiIndex):
            data = data.stack(level=1, future_stack=True).rename_axis(['Date', 'Ticker']).reset_index()
        
        # Remove column name
        data.columns.name = None
        
        logger.info(f"Successfully downloaded {len(data)} rows for {ticker}")
        return data
    except Exception as e:
        logger.error(f"Failed to download data for {ticker}: {str(e)}")
        raise


def main():
    """Main execution function."""
    try:
        logger.info("Starting yfinance price extraction")
        
        # Read Transactions.csv from GCS
        logger.info("Reading transactions from GCS")
        transactions_df = read_gcs_csv_to_df('raw/raw_transactions.csv')
        logger.info(f"Transactions DataFrame shape: {transactions_df.shape}")

        # Get DataFrame of unique symbols and min purchase_date
        tickers = transactions_df.groupby('symbol')['purchase_date'].min().reset_index()
        tickers['purchase_date'] = pd.to_datetime(tickers['purchase_date']).dt.strftime('%Y-%m-%d')
        
        logger.info(f"Extracted {len(tickers)} unique tickers from transactions")

        # Initiate empty list to collect all dataframes
        all_dfs = []

        # Loop through list of tickers and extract historical data
        for ticker in tickers['symbol']:
            try:
                # Extract purchase_date for ticker
                purchase_date = tickers[tickers['symbol'] == ticker]['purchase_date'].values[0]
                # Extract ticker data from purchase date
                ticker_df = extract_yfinance_data(ticker=ticker, start_date=purchase_date)
                all_dfs.append(ticker_df)
                logger.info(f"Successfully processed {ticker}")
            except Exception as e:
                logger.error(f"Failed to process {ticker}: {str(e)}")
                continue

        # Append S&P 500 benchmark data
        try:
            logger.info("Downloading S&P 500 benchmark data")
            sp500_df = extract_yfinance_data()
            all_dfs.append(sp500_df)
        except Exception as e:
            logger.warning(f"Failed to download S&P 500 data: {str(e)}")

        # Filter empty dataframes and concatenate
        historical_prices = [df for df in all_dfs if not df.empty]
        if not historical_prices:
            logger.error("No historical price data was collected")
            raise ValueError("Failed to extract any historical price data")
        
        historical_prices_combined = pd.concat(historical_prices, axis=0)
        logger.info(f"Combined historical prices DataFrame shape: {historical_prices_combined.shape}")

        # Upload the combined DataFrame to GCS as CSV
        gcs_path = upload_df_to_gcs(historical_prices_combined, 'raw/raw_prices.csv', file_format='csv')
        logger.info(f"Successfully uploaded historical prices to {gcs_path}")
        
        logger.info("yfinance price extraction completed successfully")

    except Exception as e:
        logger.error(f"Fatal error during execution: {str(e)}")
        raise


if __name__ == "__main__":
    main()
