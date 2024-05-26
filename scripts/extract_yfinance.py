# Script to extract the historical prices from yfinance

# Author: Matthew Myers

# Import packages
import yfinance as yf
import pandas as pd

# Function to extract S&P data of interest
def extract_yfinance(ticker='^GSPC', start_date='2019-09-16', end_date=None):
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

# Read in raw_portfolio.xlsx
raw_portfolio = pd.read_excel('data/raw_portfolio.xlsx')

# Get DataFrame of unique symbol and min purchase_date
tickers = raw_portfolio.groupby('symbol')['purchase_date'].min().reset_index()
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

# Union dataframes
historical_prices = pd.concat(all_dfs, axis=0)

# Save as excel
historical_prices.to_excel('data/historical_prices.xlsx')
