import pandas as pd
import yfinance as yf

data = yf.download('^GSPC', start='2019-01-30', end=None).reset_index(inplace=True)
# Flatten the multi-level columns
data.columns = ['Date'] + [col[0] if col[0] != 'Price' else col[1] for col in data.columns[1:]]

# Add 'Ticker' column with the ticker value (e.g., '^GSPC')
data['Ticker'] = data.columns[1]
# Reorder columns as needed
cols = ['Date', 'Ticker', 'Open', 'High', 'Low', 'Close', 'Volume']

data = data[cols]
print(data.head())
