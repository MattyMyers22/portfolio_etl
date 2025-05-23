#!/bin/bash

# Check if virtual environment exists

# Activate virtual environment
source etl_env/bin/activate

# Install dependencies from requirements.txt
pip install -r ./scripts/requirements.txt

# Run python script to extract google sheet data
python3 ./scripts/extract_gsheet.py

# Run python script to extract yahoo finance data
python3 ./scripts/extract_yfinance.py

# Run python script to clean and transform data
python3 ./scripts/transform.py

# Run python script to load data into database
python3 ./scripts/load.py

# Deactivate virtual environment
deactivate
