# Investment Portfolio ETL Pipeline 
This project aims to provide a structure for extracting investment portfolio data stored in Google Sheets, as well 
as financial data through Yahoo Finance, to transform and load into a SQL database.

# References
A Google Account and Project must be created. [Here](https://developers.google.com/sheets/api/quickstart/python) is a link to 
Google's documentation for a Python quickstart with their Google Sheets API.

## Workflow

* Create venv
* Activate venv
* Install dependencies from requirements.txt
* Connect to GSheet
* Extract from GSheet
* Extract from yahoo finance
* Transform data into tables
* Connect to database
* Load into database

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
