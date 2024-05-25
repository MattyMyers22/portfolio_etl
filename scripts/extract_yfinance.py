# Script to extract the historical prices from yfinance

# Author: Matthew Myers

# Import packages
import yfinance as yf
import pandas as pd

# Read in raw_portfolio.xlsx
raw_portfolio = pd.read_excel('data/raw_portfolio.xlsx')

# Get list of active tickers

# Function to extract S&P data of interest
def extract_yfinance(ticker='^GSPC', start_date='2019-09-16', end_date=None):
    """
    Extracts historical prices of the of stocks/funds using the yfinance library.

    Args:
        ticker (str): The ticker symbol of the stock to extract prices for. Defaults to '^GSPC' (S&P 500).
        start_date (str): The start date of the price data to extract. Defaults to '2019-09-16'.
        end_date (str or None): The end date of the price data to extract. Defaults to None.

    Returns:
        pandas.DataFrame: A DataFrame containing the historical prices of the S&P 500.

    """
    # Start date for dataset
    start_date = start_date

    # Get the current date as end date for dataset
    end_date = end_date

    # Get the S&P 500 data
    sp500_data = yf.download('^GSPC', start=start_date, end=end_date)

    # Return S&P 500 dataframe
    return sp500_data

# Initiate empty list all_dfs
all_dfs = []

# Loop through list of tickers
for ticker in raw_portfolio['Ticker']:
    # Extract data
    ticker_df = extract_yfinance(ticker=ticker)
    # Append dataframes
    all_dfs.append(ticker_df)
