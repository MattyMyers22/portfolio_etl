# Investment Portfolio ETL Pipeline 
This project aims to provide a structure for extracting investment portfolio data stored in Google Sheets, as well 
as financial data through Yahoo Finance, to transform and load into a SQL database.

## Initial Setup
* MySQL
* Python >= Verion 3
* Google Account
* Google Sheet with two tabs containing portfolio data
  * One tab containing portfolio transaction history
  | transaction_type | account | symbol | purchase_date | shares | purchase_price | sell_date | sell_price |
  |---|---|---|---|---|---|---|---|
  | buy              | 401k    | AAPL   |  12/30/2023   | 5      | 160.50         |           |            |
  | sell             | 401k    | AAPL   |  12/30/2023   | 2      | 160.50         | 03/20/2024| 180.00     |
  | reinvestment     | 401k    | AAPL   |  1/10/2024    | 0.004  | 170.25         |           |            |
  
  Currently, there are three options for transaction types (buy, sell, reinvestment), where reinvestment is an 
  automatic reinvestment of dividends into the holding it is paid out from. Each sell transaction is note with 
  the original purchase price and date.
  * One tab for historical cash values in investment accounts
(need example tables)

## Data Sources
There are two data sources that are required for extraction of the information needed.
* Google Sheet (Extracted through API)
  * History of trades, holdings, and cash levels
* Yahoo Finance (Extracted through API)
  * S&P 500 historical prices
  * Historical prices for current portfolio holdings from purchase date

## References
A Google Account and Project must be created. [Here](https://developers.google.com/sheets/api/quickstart/python) is a link to 
Google's documentation for a Python quickstart with their Google Sheets API.

## Workflow

* Create database
* Create venv
* Activate venv
* Install dependencies from requirements.txt
* Connect to GSheet
* Extract from GSheet
* Extract from yahoo finance
* Transform data into tables
* Connect to database
* Load into database

### Setting Up The Database
Once MySQL Server is setup, a database needs to be created. This can be done from the terminal by 
executing the following steps.

**Access MySQL from terminal (replace 'root' with your username)**
``` bash
sudo mysql -u root -p
```
Enter your sudo Linux password, followed by your database user (root) password.

**Create database for fund holdings**
``` sql
CREATE DATABASE portfolio_dwh;
```

## Orchestration
* Set up venv to create and activate from bash script
* Work towards Airflow

### Order of Execution
1. extract_gsheet.py
2. extract_yfinance.py
    * first executed for S&P from start
    * then executed for list of current holdings most recent price
    * concat these dataframes and return raw excel
3. transorm.py
    * save cleaned versions as excels
4. load.py
    * connects to database
    * drops tables
    * loads cleaned excels into tables

## Database Entity Relationships
![image](images/ER_Portfolio_DWH.png)
