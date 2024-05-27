# Script to perform data cleaning and transformation of stock portfolio data
# Saves the clean version of Excels as new copies

# Author: Matthew Myers

# Import packages
import pandas as pd

# Read in data sources
portfolio_df = pd.read_excel('data/raw_portfolio.xlsx')
cash_df = pd.read_excel('data/raw_cash.xlsx')
prices_df = pd.read_excel('data/historical_prices.xlsx')

# Set data types for cash records
cash_df['date'] = pd.to_datetime(cash_df['date'])

# Save clean cash Excel
cash_df.to_excel('data/clean_cash.xlsx', index=False)

# Set data types for portfolio transactions

# Save clean portfolio transactions
