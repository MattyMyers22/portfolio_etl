# Investment Portfolio ETL Pipeline 
This project aims to provide a workflow for extracting investment portfolio data stored in Google Sheets, as well 
as financial data through Yahoo Finance, to transform and load into a SQL database for analysis with a BI tool 
such as Power BI.

## Initial Requirements
The following are needed in order to get setup and properly run this project
* MySQL
* Python >= Verion 3
  * IDE of choice
* Google Account
* Google Sheet with two tabs containing portfolio data
  * One tab named 'Transactions' containing portfolio transaction history
  ![image](images/portfolio_data_example.JPG)
  
  Currently, there are three options for transaction types (buy, sell, reinvestment), where reinvestment is an 
  automatic reinvestment of dividends into the holding it is paid out from.

  * One tab named 'Cash' for historical cash values in investment accounts
  ![image](images/cash_gSheet_example.JPG)

### Operating System
This project and directions are tailored towards a Linux operating system. It can be adjusted for windows or 
used through Windows Subsystem Linux.

## Data Sources
There are two data sources that are required for extraction of the information needed.
* Google Sheet (Extracted through API)
  * History of trades, holdings, and cash levels
* Yahoo Finance (Extracted through API)
  * S&P 500 historical prices
  * Historical prices for current portfolio holdings from purchase date

A Google Account and Project must be created. [Here](https://developers.google.com/sheets/api/quickstart/python) is a link to 
Google's documentation for a Python quickstart with their Google Sheets API.

## Initial Setup

* Database setup
* Create venv
* Setup config.py file
* Orchestration
* Create View for portfolio metrics in database
* Connect BI Tool to database

### Setting Up The Database
Once MySQL Server is downloaded and a user profile is made, a database needs to be created. This can be done from the terminal 
by executing the following steps.

**Access MySQL from terminal (replace 'root' with your username)**
``` bash
sudo mysql -u root -p
```
Enter your sudo Linux password, followed by your database user (root) password.

**Create database for fund holdings**
``` sql
CREATE DATABASE portfolio_dwh;
```

### Orchestration
* Set up venv to create and activate from bash script
* Work towards Airflow

#### Order of Execution
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
