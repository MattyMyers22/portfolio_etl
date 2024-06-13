# Script designed to load clean excel data into MySQL portfolio datawarehouse

# Author: Matthew Myers

# Import parameters from config file
from config import db_name, db_host, db_pwd, db_user

# Import packages
from sqlalchemy import create_engine, text
import pandas as pd

# Read in data to load
cash_df = pd.read_excel('data/clean_cash.xlsx')
portfolio_df = pd.read_excel('data/clean_portfolio.xlsx')
prices_df = pd.read_excel('data/clean_prices.xlsx')

# SQL statement to create portfolio table
create_portfolio_query = """
CREATE TABLE IF NOT EXISTS portfolio (
	id INT AUTO_INCREMENT PRIMARY KEY,
    transaction_type VARCHAR(25),
    account VARCHAR(25),
    symbol VARCHAR(25),
    purchase_date DATETIME,
    shares DECIMAL(12,4),
    purchase_price DECIMAL(12,4),
    sell_date DATETIME,
    sell_price DECIMAL(12,4)
);
"""

# SQL statement to create cash table
create_cash_query = """
CREATE TABLE IF NOT EXISTS cash (
	cash_id INT AUTO_INCREMENT PRIMARY KEY,
    date DATETIME,
    account VARCHAR(25),
    cash_amount NUMERIC(12,4)
);
"""

# SQL statement to create prices table
create_prices_query = """
CREATE TABLE IF NOT EXISTS prices (
	prices_id INT AUTO_INCREMENT PRIMARY KEY,
    date DATETIME,
    open NUMERIC(12,4),
    high NUMERIC(12,4),
    low NUMERIC(12,4),
    close NUMERIC(12,4),
    adj_close NUMERIC(12,4),
    volume BIGINT,
    symbol VARCHAR(25)
);
"""

# Construct the connection string
connection_string = f"mysql+pymysql://{db_user}:{db_pwd}@{db_host}/{db_name}"

# Create the engine
engine = create_engine(connection_string)

# Print a message to confirm connection
print('Connected to MySQL database successfully!')

# Execute tasks
with engine.connect() as conn:
    # Create tables if not exist
    conn.execute(text(create_portfolio_query))
    conn.execute(text(create_cash_query))
    conn.execute(text(create_prices_query))
    
    # Truncate tables if they already exist
    conn.execute(text("TRUNCATE TABLE portfolio;"))
    conn.execute(text("TRUNCATE TABLE cash;"))
    conn.execute(text("TRUNCATE TABLE prices;"))

    # Load tables
    cash_df.to_sql('cash', engine, index=False, if_exists='append')
    print('Loaded cash table \n')
    portfolio_df.to_sql('portfolio', engine, index=False, if_exists='append')
    print('Loaded portfolio table \n')
    prices_df.to_sql('prices', engine, index=False, if_exists='append')
    print('Loaded prices table \n')

# Close engine
engine.dispose()

print('Disconnected from database')
