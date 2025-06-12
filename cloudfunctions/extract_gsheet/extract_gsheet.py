# Extract investment data from Google Sheets

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
import pandas as pd
from dotenv import load_dotenv
from pathlib import Path
import os
import json

# Get the path to the project root (2 levels up from current file)
env_path = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(dotenv_path=env_path)

# Access your env variables
key_data = os.getenv("GCP_SERVICE_ACCOUNT_KEY")
api_key = json.loads(key_data)
spreadsheet_id = os.getenv("SPREADSHEET_ID")

# If modifying these scopes, delete the file token.json.
SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"]

# The ID and range of a sample spreadsheet.
SAMPLE_SPREADSHEET_ID = spreadsheet_id
SAMPLE_RANGE_NAMES = ['Transactions!A:H', 'Cash!A:C']


def extract(range_name):
    """Extracts data from the given range of the Google Sheet and prints the head."""
    try:
        creds = service_account.Credentials.from_service_account_info(api_key, scopes=SCOPES)
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
    except HttpError as err:
        print(err)

# Execute script for each sheet range
for range_name in SAMPLE_RANGE_NAMES:
    extract(range_name)
