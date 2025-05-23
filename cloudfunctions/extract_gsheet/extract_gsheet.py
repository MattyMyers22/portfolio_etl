# Extract investment data from Google Sheets
import os.path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from config import spreadsheet_id
import pandas as pd

# If modifying these scopes, delete the file token.json.
SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"]

# The ID and range of a sample spreadsheet.
SAMPLE_SPREADSHEET_ID = spreadsheet_id
SAMPLE_RANGE_NAMES = ['Transactions!A:H', 'Cash!A:C']


def extract(range_name):
  """Shows basic usage of the Sheets API.
  Exports values from spreadsheet to excel.
  """
  creds = None
  # The file token.json stores the user's access and refresh tokens, and is
  # created automatically when the authorization flow completes for the first
  # time.
  if os.path.exists("./token.json"):
    creds = Credentials.from_authorized_user_file("./token.json", SCOPES)
  # If there are no (valid) credentials available, let the user log in.
  if not creds or not creds.valid:
    if creds and creds.expired and creds.refresh_token:
      creds.refresh(Request())
    else:
      flow = InstalledAppFlow.from_client_secrets_file(
          "./credentials.json", SCOPES
      )
      creds = flow.run_local_server(port=0)
    # Save the credentials for the next run
    with open("./token.json", "w") as token:
      token.write(creds.to_json())

  try:
    service = build("sheets", "v4", credentials=creds)

    # Call the Sheets API
    sheet = service.spreadsheets()
    result = (
        sheet.values()
        .get(spreadsheetId=SAMPLE_SPREADSHEET_ID, range=range)
        .execute()
    )
    values = result.get("values", [])
    df = pd.DataFrame(data=values[1:], columns=values[0])

    if not values:
      print("No data found.")
      return

    # Check if extracted transaction data
    if range_name.startswith('Transactions'):
      # Save portfolio data as excel
      df.to_excel('./data/raw_portfolio.xlsx', index=False)

    # Check if extracted transaction data
    if range_name.startswith('Cash'):
      # Save portfolio data as excel
      df.to_excel('./data/raw_cash.xlsx', index=False)

  except HttpError as err:
    print(err)

# Execute script for each sheet range
for range in SAMPLE_RANGE_NAMES:
  extract(range)
