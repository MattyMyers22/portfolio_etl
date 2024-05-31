# Script designed to load clean excel data into MySQL portfolio datawarehouse

# Author: Matthew Myers

# Import parameters from config file
from config import db_name, db_host, db_pwd, db_user

# Construct the connection string
connection_string = f"mysql+pymysql://{db_user}:{db_pwd}@{db_host}/{db_name}"
