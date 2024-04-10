#!/bin/bash

# Check if virtual environment exists

# Activate virtual environment
source etl_env/bin/activate

# Install dependencies from requirements.txt

cd scripts

# Run python script
python3 extract.py

cd ..

# Deactivate virtual environment
deactivate
