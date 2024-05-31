# Script designed to load clean excel data into MySQL portfolio datawarehouse

# Author: Matthew Myers

# Import parameters from config file
from config import db_name, db_host, db_pwd, db_user

# Import packages
from sqlalchemy import create_engine, text

# Construct the connection string
connection_string = f"mysql+pymysql://{db_user}:{db_pwd}@{db_host}/{db_name}"

# Create the engine
engine = create_engine(connection_string)

# Print a message to confirm connection
print('Connected to MySQL database successfully!')

# Target tables
