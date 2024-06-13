# Script to perform data cleaning and transformation of stock portfolio data
# Saves the clean version of Excels as new copies

# Author: Matthew Myers

# Import packages
import pandas as pd

# Read in data sources
portfolio_df = pd.read_excel('data/raw_portfolio.xlsx')
cash_df = pd.read_excel('data/raw_cash.xlsx')
prices_df = pd.read_excel('data/raw_prices.xlsx')

# Set data types for cash records
cash_df['date'] = pd.to_datetime(cash_df['date'])

# Save clean cash Excel
cash_df.to_excel('data/clean_cash.xlsx', index=False)

# Set data types for portfolio transactions
portfolio_df['purchase_date'] = pd.to_datetime(portfolio_df['purchase_date'], format='mixed', dayfirst=False)
portfolio_df['sell_date'] = pd.to_datetime(portfolio_df['sell_date'], format='mixed', dayfirst=False)

# Save clean portfolio transactions
portfolio_df.to_excel('data/clean_portfolio.xlsx', index=False)

# Rename columns for historical prices
new_names = {'Date':'date', 'Open':'open', 'High':'high', 'Low':'low', 'Close':'close',
             'Adj Close':'adj_close', 'Volume':'volume'}
prices_df = prices_df.rename(columns=new_names)

# Save clean historical prices
prices_df.to_excel('data/clean_prices.xlsx', index=False)
