# Script designed to load clean excel data into MySQL portfolio datawarehouse

# Author: Matthew Myers

# Import parameters from config file
from config import db_name, db_host, db_pwd, db_user

# Import packages
from sqlalchemy import create_engine, text
import pandas as pd

# Construct the connection string
connection_string = f"mysql+pymysql://{db_user}:{db_pwd}@{db_host}/{db_name}"

# Create the engine
engine = create_engine(connection_string)

# Print a message to confirm connection
print('Connected to MySQL database successfully!')

# Read in data to load
cash_df = pd.read_excel('data/clean_cash.xlsx')
portfolio_df = pd.read_excel('data/clean_portfolio.xlsx')
prices_df = pd.read_excel('data/historical_prices.xlsx')

# Execute tasks
with engine.connect() as conn:
    # Load tables
    cash_df.to_sql('cash', engine, index=False, if_exists='replace')
    print('Loaded cash table \n')
    portfolio_df.to_sql('portfolio', engine, index=False, if_exists='replace')
    print('Loaded portfolio table \n')
    prices_df.to_sql('prices', engine, index=False, if_exists='replace')
    print('Loaded prices table \n')

# Close engine
engine.dispose()

print('Disconnected from database')
