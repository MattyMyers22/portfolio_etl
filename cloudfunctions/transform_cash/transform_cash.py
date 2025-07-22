# Extract raw cash data for cleaning and storage in GCS

# Imports
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
import pandas as pd
from dotenv import load_dotenv
from pathlib import Path
import os
import json
from google.cloud import storage
import tempfile

# Get the path to the project root (2 levels up from current file)
env_path = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(dotenv_path=env_path)

# Access your env variables
key_data = os.getenv("GCP_SERVICE_ACCOUNT_KEY")
api_key = json.loads(key_data)
spreadsheet_id = os.getenv("SPREADSHEET_ID")
storage_bucket = os.getenv("BUCKET_NAME")

# Define scopes for GCP Service Account connections
GCS_SCOPES = ["https://www.googleapis.com/auth/devstorage.read_write"]

# Extact raw cash data in GCS


# Clean raw cash data


# Save as parquet in GCS