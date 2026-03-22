"""
GCP Secret Manager and GCS Client utilities for Cloud Functions.

Provides centralized access to GCP secrets and authenticated GCS clients
with caching to minimize API calls.
"""

import logging
import json
from google.cloud import secretmanager, storage
from google.oauth2 import service_account

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Project ID for GCP resources
PROJECT_ID = "holdings-extract"


class SecretManager:
    """
    Centralized secret access with caching to reduce API calls.
    
    All secrets are cached in memory after first retrieval to minimize
    calls to GCP Secret Manager.
    """
    
    _cache = {}
    
    @staticmethod
    def get_secret(secret_id, version_id="latest"):
        """
        Retrieve a secret from GCP Secret Manager with caching.
        
        Args:
            secret_id (str): The ID of the secret to retrieve.
            version_id (str): The version of the secret. Defaults to "latest".
            
        Returns:
            str: The decoded secret payload.
            
        Raises:
            RuntimeError: If the secret cannot be retrieved.
        """
        cache_key = f"{secret_id}:{version_id}"
        
        # Return cached value if available
        if cache_key in SecretManager._cache:
            logger.debug(f"Retrieved secret '{secret_id}' from cache")
            return SecretManager._cache[cache_key]
        
        # Fetch from GCP Secret Manager
        try:
            client = secretmanager.SecretManagerServiceClient()
            name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/{version_id}"
            response = client.access_secret_version(request={"name": name})
            payload = response.payload.data.decode("UTF-8")
            
            # Cache the result
            SecretManager._cache[cache_key] = payload
            logger.info(f"Successfully retrieved secret: {secret_id}")
            
            return payload
        except Exception as e:
            logger.error(f"Failed to retrieve secret '{secret_id}': {str(e)}")
            raise RuntimeError(f"Failed to retrieve secret '{secret_id}': {str(e)}") from e
    
    @staticmethod
    def clear_cache():
        """Clear the secret cache. Useful for testing."""
        SecretManager._cache.clear()
        logger.info("Secret cache cleared")


class GCSClient:
    """
    Factory for authenticated Google Cloud Storage clients and buckets.
    
    Handles credential management via GCP Secret Manager and provides
    convenient methods for getting authenticated storage clients.
    """
    
    @staticmethod
    def get_storage_client():
        """
        Get an authenticated GCS storage client using credentials from Secret Manager.
        
        Returns:
            google.cloud.storage.Client: An authenticated GCS client.
            
        Raises:
            RuntimeError: If credentials cannot be retrieved or are invalid.
        """
        try:
            service_account_key = SecretManager.get_secret("GCP_SERVICE_ACCOUNT_KEY")
            credentials_dict = json.loads(service_account_key)
            
            client = storage.Client.from_service_account_info(credentials_dict)
            logger.info("Successfully created GCS storage client")
            return client
        except Exception as e:
            logger.error(f"Failed to create GCS storage client: {str(e)}")
            raise
    
    @staticmethod
    def get_bucket(bucket_name=None):
        """
        Get a GCS bucket object with authenticated client.
        
        Args:
            bucket_name (str): The name of the bucket. If None, retrieves from
                             BUCKET_NAME secret in Secret Manager.
        
        Returns:
            google.cloud.storage.Bucket: An authenticated bucket object.
            
        Raises:
            RuntimeError: If bucket name cannot be retrieved or bucket doesn't exist.
        """
        try:
            # Get bucket name from secret if not provided
            if bucket_name is None:
                bucket_name = SecretManager.get_secret("BUCKET_NAME")
            
            client = GCSClient.get_storage_client()
            bucket = client.bucket(bucket_name)
            logger.info(f"Successfully retrieved bucket: {bucket_name}")
            return bucket
        except Exception as e:
            logger.error(f"Failed to get bucket '{bucket_name}': {str(e)}")
            raise
