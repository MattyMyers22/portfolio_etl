# Script to extract the historical prices of the S&P 500

# Author: Matthew Myers

# Import packages
import yfinance as yf
import pandas as pd

# Function to extract S&P data of interest
def extract_yfinance():
    # Start date for dataset
    start_date = '2019-09-16'

    # Get the current date as end date for dataset
    end_date = pd.Timestamp.now().strftime('%Y-%m-%d')

    # Get the S&P 500 data
    sp500_data = yf.download('^GSPC', start=start_date)

    # Return S&P 500 dataframe
    return sp500_data
