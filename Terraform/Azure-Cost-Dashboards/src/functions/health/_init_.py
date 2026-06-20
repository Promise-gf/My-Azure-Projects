import azure.functions as func
import logging
import os
from importlib import import_module
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
try:
    SecretClient = import_module("azure.keyvault.secrets").SecretClient
except Exception:  # pragma: no cover - optional dependency / lint import fallback
    SecretClient = None

logger = logging.getLogger(__name__)

async def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    Deep Health Check for Auto-Heal.
    If this returns 503, Azure App Service will automatically recycle the worker process.
    """
    checks = {"zrs_storage": False, "key_vault": False}
    
    try:
        credential = DefaultAzureCredential()
        sa_name = os.environ['STORAGE_ACCOUNT_NAME']
        kv_name = os.environ['KEY_VAULT_NAME']
        
        # Check 1: ZRS Storage (Data Path)
        blob_client = BlobServiceClient(account_url=f"https://{sa_name}.blob.core.windows.net", credential=credential)
        blob_client.get_container_client("cost-exports").exists()
        checks["zrs_storage"] = True
        
        # Check 2: Key Vault (Secrets Path)
        kv_client = SecretClient(vault_url=f"https://{kv_name}.vault.azure.net", credential=credential)
        # Just attempting a list operation validates network and RBAC
        list(kv_client.list_properties_of_secrets())
        checks["key_vault"] = True
        
    except Exception as e:
        logger.error(f"Health check failed: Dependency unreachable - {e}")

    # If ANY critical dependency is down, return 503 to trigger Auto-Heal
    if all(checks.values()):
        return func.HttpResponse("Healthy", status_code=200)
    else:
        return func.HttpResponse(f"Unhealthy: {checks}", status_code=503)