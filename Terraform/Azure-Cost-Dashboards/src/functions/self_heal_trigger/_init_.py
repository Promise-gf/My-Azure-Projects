import azure.functions as func
import logging
import os
import httpx
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)

async def main(req: func.HttpRequest) -> func.HttpResponse:
    """Triggered by Azure Monitor Alert to force a Cost Management Export run."""
    logger.info("Self-Heal Trigger invoked by Monitor Alert.")
    
    subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID")
    export_name = f"export-actual-cvd-{os.environ.get('ENVIRONMENT', 'dev')}"
    
    url = f"https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.CostManagement/exports/{export_name}/run?api-version=2023-08-01"
    
    try:
        credential = DefaultAzureCredential()
        token = await credential.get_token("https://management.azure.com/.default")
        headers = {"Authorization": f"Bearer {token.token}"}
        
        async with httpx.AsyncClient() as client:
            response = await client.post(url, headers=headers)
            response.raise_for_status()
            
        logger.info(f"Successfully forced Cost Export run: {export_name}")
        return func.HttpResponse("Self-Heal: Export triggered successfully", status_code=200)
        
    except Exception as e:
        logger.error(f"Self-Heal failed: {e}")
        return func.HttpResponse(f"Self-Heal failed: {str(e)}", status_code=500)