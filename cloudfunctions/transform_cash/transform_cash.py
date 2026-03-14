# Extract raw cash data for cleaning and storage in GCS

# Imports
from google.oauth2 import service_account
from google.cloud import secretmanager
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
import pandas as pd
from dotenv import load_dotenv
from pathlib import Path
import os
import json
from google.cloud import storage
import tempfile

# Project ID
PROJECT_ID = "holdings-extract"

# Function to extract secret from GCP Secret Manager
def access_secret_version(secret_id, version_id="latest"):
    """
    Access the payload for the given secret version if one exists.
    """
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/{version_id}"
    response = client.access_secret_version(request={"name": name})
    payload = response.payload.data.decode("UTF-8")
    return payload

# Get secrets
GCP_SERVICE_ACCOUNT_KEY = access_secret_version('GCP_SERVICE_ACCOUNT_KEY')
STORAGE_BUCKET = access_secret_version('BUCKET_NAME')

# Define scopes for GCP Service Account connections
GCS_SCOPES = ["https://www.googleapis.com/auth/devstorage.read_write"]

# Extract raw cash csv in bucket
storage_client = storage.Client.from_service_account_info(json.loads(GCP_SERVICE_ACCOUNT_KEY))
bucket = storage_client.bucket(STORAGE_BUCKET)
blob = bucket.blob('raw/raw_cash.csv')
with tempfile.NamedTemporaryFile() as temp_file:
    blob.download_to_filename(temp_file.name)
    raw_cash_df = pd.read_csv(temp_file.name)

print(f'\nRaw cash data extracted successfully {raw_cash_df.head()}\n')
print(f'\nShape {raw_cash_df.shape}\n')

# Clean raw cash data
print('Changing date column data type')
raw_cash_df['date'] = pd.to_datetime(raw_cash_df['date'])
print(f'\nData types after cleaning:\n{raw_cash_df.dtypes}\n')

# Save as parquet in GCS

