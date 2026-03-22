"""
Common GCS operations for ETL functions.

Provides utilities for reading and writing data to Google Cloud Storage.
"""

import logging
import pandas as pd
import tempfile
import os
from .gcs_config import GCSClient

logger = logging.getLogger(__name__)


def read_gcs_csv_to_df(blob_path, bucket_name=None):
    """
    Read a CSV file from GCS into a pandas DataFrame.
    
    Args:
        blob_path (str): The path to the file in the bucket (e.g., 'raw/raw_cash.csv').
        bucket_name (str): The bucket name. If None, uses BUCKET_NAME secret.
        
    Returns:
        pd.DataFrame: The contents of the CSV file as a DataFrame.
        
    Raises:
        RuntimeError: If the file cannot be downloaded or read.
    """
    try:
        bucket = GCSClient.get_bucket(bucket_name)
        blob = bucket.blob(blob_path)
        
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as temp_file:
            blob.download_to_filename(temp_file.name)
            df = pd.read_csv(temp_file.name)
            os.remove(temp_file.name)
        
        logger.info(f"Successfully read CSV from gs://{bucket.name}/{blob_path}")
        return df
    except Exception as e:
        logger.error(f"Failed to read CSV from {blob_path}: {str(e)}")
        raise RuntimeError(f"Failed to read CSV from {blob_path}: {str(e)}") from e


def read_gcs_parquet_to_df(blob_path, bucket_name=None):
    """
    Read a Parquet file from GCS into a pandas DataFrame.
    
    Args:
        blob_path (str): The path to the file in the bucket (e.g., 'warehouse/clean_data.parquet').
        bucket_name (str): The bucket name. If None, uses BUCKET_NAME secret.
        
    Returns:
        pd.DataFrame: The contents of the Parquet file as a DataFrame.
        
    Raises:
        RuntimeError: If the file cannot be downloaded or read.
    """
    try:
        bucket = GCSClient.get_bucket(bucket_name)
        blob = bucket.blob(blob_path)
        
        with tempfile.NamedTemporaryFile(delete=False, suffix='.parquet') as temp_file:
            blob.download_to_filename(temp_file.name)
            df = pd.read_parquet(temp_file.name)
            os.remove(temp_file.name)
        
        logger.info(f"Successfully read Parquet from gs://{bucket.name}/{blob_path}")
        return df
    except Exception as e:
        logger.error(f"Failed to read Parquet from {blob_path}: {str(e)}")
        raise RuntimeError(f"Failed to read Parquet from {blob_path}: {str(e)}") from e


def upload_df_to_gcs(df, blob_path, bucket_name=None, file_format='parquet'):
    """
    Upload a pandas DataFrame to GCS as CSV or Parquet.
    
    Args:
        df (pd.DataFrame): The DataFrame to upload.
        blob_path (str): The destination path in the bucket (e.g., 'warehouse/clean_data.parquet').
        bucket_name (str): The bucket name. If None, uses BUCKET_NAME secret.
        file_format (str): The file format - 'parquet' or 'csv'. Defaults to 'parquet'.
        
    Returns:
        str: The GCS path of the uploaded file (gs://bucket/path).
        
    Raises:
        RuntimeError: If the file cannot be uploaded.
        ValueError: If an unsupported file format is specified.
    """
    if file_format not in ['parquet', 'csv']:
        raise ValueError(f"Unsupported file format: {file_format}. Use 'parquet' or 'csv'.")
    
    try:
        bucket = GCSClient.get_bucket(bucket_name)
        
        with tempfile.NamedTemporaryFile(suffix=f'.{file_format}', delete=False) as temp_file:
            if file_format == 'parquet':
                df.to_parquet(temp_file.name, index=False)
            else:
                df.to_csv(temp_file.name, index=False)
            
            blob = bucket.blob(blob_path)
            blob.upload_from_filename(temp_file.name)
            os.remove(temp_file.name)
        
        gcs_path = f"gs://{bucket.name}/{blob_path}"
        logger.info(f"Successfully uploaded DataFrame to {gcs_path}")
        return gcs_path
    except Exception as e:
        logger.error(f"Failed to upload DataFrame to {blob_path}: {str(e)}")
        raise RuntimeError(f"Failed to upload DataFrame to {blob_path}: {str(e)}") from e


def download_gcs_file(blob_path, local_path, bucket_name=None):
    """
    Download a file from GCS to local filesystem.
    
    Args:
        blob_path (str): The path to the file in the bucket.
        local_path (str): The local destination path.
        bucket_name (str): The bucket name. If None, uses BUCKET_NAME secret.
        
    Raises:
        RuntimeError: If the file cannot be downloaded.
    """
    try:
        bucket = GCSClient.get_bucket(bucket_name)
        blob = bucket.blob(blob_path)
        blob.download_to_filename(local_path)
        logger.info(f"Successfully downloaded {blob_path} to {local_path}")
    except Exception as e:
        logger.error(f"Failed to download {blob_path} to {local_path}: {str(e)}")
        raise RuntimeError(f"Failed to download {blob_path}: {str(e)}") from e


def upload_file_to_gcs(local_path, blob_path, bucket_name=None):
    """
    Upload a file from local filesystem to GCS.
    
    Args:
        local_path (str): The local file path to upload.
        blob_path (str): The destination path in the bucket.
        bucket_name (str): The bucket name. If None, uses BUCKET_NAME secret.
        
    Returns:
        str: The GCS path of the uploaded file (gs://bucket/path).
        
    Raises:
        RuntimeError: If the file cannot be uploaded.
    """
    try:
        bucket = GCSClient.get_bucket(bucket_name)
        blob = bucket.blob(blob_path)
        blob.upload_from_filename(local_path)
        
        gcs_path = f"gs://{bucket.name}/{blob_path}"
        logger.info(f"Successfully uploaded {local_path} to {gcs_path}")
        return gcs_path
    except Exception as e:
        logger.error(f"Failed to upload {local_path} to {blob_path}: {str(e)}")
        raise RuntimeError(f"Failed to upload {local_path}: {str(e)}") from e
