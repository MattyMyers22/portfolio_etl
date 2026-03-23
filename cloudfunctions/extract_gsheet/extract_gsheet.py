# Extract investment data from Google Sheets and save in Storage Bucket

import logging
import json
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
import pandas as pd

# Import shared utilities
import sys
from pathlib import Path

# Add parent directory to path to import shared modules
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from shared import SecretManager, upload_df_to_gcs

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Define scopes for GCP Service Account connections
SHEETS_SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"]

# The ID and range of a sample spreadsheet
SAMPLE_RANGE_NAMES = ['Transactions!A:H', 'Cash!A:C']


def get_api_credentials():
    """
    Retrieve and parse GCP service account credentials from Secret Manager.
    
    Returns:
        dict: The parsed service account credentials.
        
    Raises:
        RuntimeError: If credentials cannot be retrieved or parsed.
    """
    try:
        service_account_key = SecretManager.get_secret("GCP_SERVICE_ACCOUNT_KEY")
        credentials_dict = json.loads(service_account_key)
        logger.info("Successfully retrieved API credentials from Secret Manager")
        return credentials_dict
    except Exception as e:
        logger.error(f"Failed to retrieve API credentials: {str(e)}")
        raise


def get_spreadsheet_id():
    """
    Retrieve the Google Sheets spreadsheet ID from Secret Manager.
    
    Returns:
        str: The spreadsheet ID.
        
    Raises:
        RuntimeError: If the spreadsheet ID cannot be retrieved.
    """
    try:
        spreadsheet_id = SecretManager.get_secret("SPREADSHEET_ID")
        logger.info("Successfully retrieved spreadsheet ID from Secret Manager")
        return spreadsheet_id
    except Exception as e:
        logger.error(f"Failed to retrieve spreadsheet ID: {str(e)}")
        raise


def extract_and_save(range_name, api_key, spreadsheet_id):
    """
    Extracts data from the given range of the Google Sheet and saves as CSV in GCS.
    
    Args:
        range_name (str): The sheet range to extract (e.g., 'Transactions!A:H').
        api_key (dict): The service account credentials dictionary.
        spreadsheet_id (str): The Google Sheets spreadsheet ID.
    """
    try:
        logger.info(f"Extracting data from range: {range_name}")
        
        # Create credentials for Google Sheets API
        creds = service_account.Credentials.from_service_account_info(
            api_key, scopes=SHEETS_SCOPES
        )
        service = build("sheets", "v4", credentials=creds)
        sheet = service.spreadsheets()
        
        # Fetch data from Google Sheets
        result = (
            sheet.values()
            .get(spreadsheetId=spreadsheet_id, range=range_name)
            .execute()
        )
        
        values = result.get("values", [])
        if not values:
            logger.warning(f"No data found for range {range_name}")
            return
        
        # Create DataFrame from the sheet data
        df = pd.DataFrame(data=values[1:], columns=values[0])
        logger.info(f"Extracted {len(df)} rows from {range_name}")
        
        print(f"\nHead of data for range '{range_name}':")
        print(df.head())
        
        # Determine the output filename based on range name
        safe_name = 'transactions' if range_name.startswith('Transactions') else 'cash'
        destination_blob_name = f"raw/raw_{safe_name}.csv"
        
        # Upload DataFrame to GCS as CSV
        gcs_path = upload_df_to_gcs(df, destination_blob_name, file_format='csv')
        logger.info(f"Successfully saved data to {gcs_path}")
        
    except HttpError as err:
        logger.error(f"Google Sheets API error: {err}")
        raise
    except Exception as err:
        logger.error(f"Error extracting and saving data from {range_name}: {str(err)}")
        raise


def main():
    """Main execution function."""
    try:
        logger.info("Starting Google Sheets extraction")
        
        # Retrieve credentials and spreadsheet ID from Secret Manager
        api_key = get_api_credentials()
        spreadsheet_id = get_spreadsheet_id()
        
        # Process each sheet range
        for range_name in SAMPLE_RANGE_NAMES:
            extract_and_save(range_name, api_key, spreadsheet_id)
        
        logger.info("Google Sheets extraction completed successfully")
    except Exception as err:
        logger.error(f"Fatal error during execution: {str(err)}")
        raise


if __name__ == "__main__":
    main()
