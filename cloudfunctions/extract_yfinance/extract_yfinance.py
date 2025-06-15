# Script to extract the historical prices from yfinance

# Import packages
import yfinance as yf
import pandas as pd
from dotenv import load_dotenv
from pathlib import Path
import os
import json
from google.cloud import storage
import tempfile
from google.oauth2 import service_account

# Get the path to the project root (2 levels up from current file)
env_path = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(dotenv_path=env_path)

# Access your env variables
key_data = os.getenv("GCP_SERVICE_ACCOUNT_KEY")
api_key = json.loads(key_data)
storage_bucket = os.getenv("BUCKET_NAME")

# Define scopes for GCP Service Account connections
GCS_SCOPES = ["https://www.googleapis.com/auth/devstorage.read_write"]

# Portfolio Start Date
PORTFOLIO_START_DATE = '2019-01-30'

# Function to extract S&P data of interest
def extract_yfinance(ticker='^GSPC', start_date=PORTFOLIO_START_DATE, end_date=None):
    """
    Extracts historical prices of the of stocks/funds using the yfinance library.

    Args:
        ticker (str): The ticker symbol of the stock to extract prices for. Defaults to '^GSPC' (S&P 500).
        start_date (str): The start date of the price data to extract. Defaults to '2019-09-16'.
        end_date (str or None): The end date of the price data to extract. Defaults to None.

    Returns:
        pandas.DataFrame: A DataFrame containing the historical prices of a stock.

    """
    # Start date for dataset
    start_date = start_date

    # Get the current date as end date for dataset
    end_date = end_date

    # Get the S&P 500 data
    data = yf.download(ticker, start=start_date, end=end_date)

    # Create symbol column with ticker
    data['symbol'] = ticker

    # Return S&P 500 dataframe
    return data

# Create credentials for Google Cloud Storage
gcs_creds = service_account.Credentials.from_service_account_info(api_key, scopes=GCS_SCOPES)
client = storage.Client(credentials=gcs_creds)

# Download Transactions.csv from GCS and read into DataFrame
def read_gcs_csv_to_df(bucket_name, blob_name, client):
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as temp_file:
        blob.download_to_filename(temp_file.name)
        df = pd.read_csv(temp_file.name)
        os.remove(temp_file.name)
    return df

# Read Transactions.csv from GCS
transactions_df = read_gcs_csv_to_df(storage_bucket, 'raw/Transactions.csv', client)

# Get DataFrame of unique symbol and min purchase_date
tickers = transactions_df.groupby('symbol')['purchase_date'].min().reset_index()
# Change purchase_date to datetime
tickers['purchase_date'] = pd.to_datetime(tickers['purchase_date']).dt.strftime('%Y-%m-%d')

# Initiate empty list all_dfs
all_dfs = []

# Loop through list of tickers
for ticker in tickers['symbol']:
    # Extract purchase_date for ticker
    purchase_date = tickers[tickers['symbol'] == ticker]['purchase_date'].values[0]
    # Extract ticker data
    ticker_df = extract_yfinance(ticker=ticker, start_date=purchase_date)
    # Append dataframes
    all_dfs.append(ticker_df)

# Append S&P 500 data
all_dfs.append(extract_yfinance())

# Filter empty dataframes
historical_prices = [df for df in all_dfs if not df.empty]
# Union all dataframes
historical_prices = pd.concat(historical_prices, axis=0)

# Save as CSV to a temp file and upload to GCS
with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as temp_csv:
    historical_prices.to_csv(temp_csv.name, index=False)
    temp_csv_path = temp_csv.name

# Upload the CSV to GCS
bucket = client.bucket(storage_bucket)
blob = bucket.blob('raw/raw_prices.csv')
blob.upload_from_filename(temp_csv_path)

# Remove the temp file after upload
os.remove(temp_csv_path)
