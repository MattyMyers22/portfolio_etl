#!/bin/bash

# Check if virtual environment exists

# Activate virtual environment
source etl_env/bin/activate

# Install dependencies from requirements.txt

cd scripts

# Run python script to extract google sheet data
python3 extract_gsheet.py

# Run python script to extract yahoo finance data
python3 extract_yfinance.py

# Run python script to clean and transform data
python3 transform.py

# Run python script to load data into database
python3 load.py

cd ..

# Deactivate virtual environment
deactivate
