# Extract investment data from Google Sheets and save in Storage Bucket

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
SHEETS_SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
GCS_SCOPES = ["https://www.googleapis.com/auth/devstorage.read_write"]

# The ID and range of a sample spreadsheet.
SAMPLE_SPREADSHEET_ID = spreadsheet_id
SAMPLE_RANGE_NAMES = ['Transactions!A:H', 'Cash!A:C']


def upload_to_gcs(bucket_name, source_file_name, destination_blob_name, creds):
    """Uploads a file to the bucket."""
    client = storage.Client(credentials=creds)
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(destination_blob_name)
    blob.upload_from_filename(source_file_name)
    print(f"File {source_file_name} uploaded to gs://{bucket_name}/{destination_blob_name}.")


def extract_and_save(range_name):
    """Extracts data from the given range of the Google Sheet and saves as CSV in GCS."""
    try:
        creds = service_account.Credentials.from_service_account_info(api_key, scopes=SHEETS_SCOPES)
        service = build("sheets", "v4", credentials=creds)
        sheet = service.spreadsheets()
        result = (
            sheet.values()
            .get(spreadsheetId=SAMPLE_SPREADSHEET_ID, range=range_name)
            .execute()
        )
        values = result.get("values", [])
        if not values:
            print(f"No data found for range {range_name}.")
            return
        df = pd.DataFrame(data=values[1:], columns=values[0])
        print(f"\nHead of data for range '{range_name}':")
        print(df.head())

        # Create separate credentials for Google Cloud Storage
        gcs_creds = service_account.Credentials.from_service_account_info(api_key, scopes=GCS_SCOPES)
        # Save to temp CSV and upload
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as tmp:
            print(tmp.name)
            df.to_csv(tmp.name, index=False)
            tmp.flush()
            # Clean up range_name for filename
            safe_name = 'Transactions' if range_name.startswith('Transactions') else 'Cash'
            destination_blob_name = f"raw/{safe_name}.csv"
            upload_to_gcs(storage_bucket, tmp.name, destination_blob_name, gcs_creds)
        os.remove(tmp.name)
    except HttpError as err:
        print(err)

# Execute script for each sheet range
for range_name in SAMPLE_RANGE_NAMES:
    extract_and_save(range_name)
