import azure.functions as func
import logging
import os
import json
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from datetime import date, timedelta

logger = logging.getLogger(__name__)

async def main(req: func.HttpRequest) -> func.HttpResponse:
    """Phase 10: Exposes enriched cost data. Enforces APIM origin."""
    
    # Defense-in-Depth: Verify request came through API Management
    apim_header = req.headers.get('x-azure-apim-api-id')
    if not apim_header:
        logger.warning("Unauthorized direct access attempt to Showback API blocked.")
        return func.HttpResponse(
            json.dumps({"error": "Unauthorized. Must be accessed via API Management."}),
            status_code=403,
            mimetype="application/json"
        )

    department = req.route_params.get('department')
    if not department:
        return func.HttpResponse("Please provide a department name.", status_code=400)

    try:
        credential = DefaultAzureCredential()
        sa_name = os.environ['STORAGE_ACCOUNT_NAME']
        blob_service_client = BlobServiceClient(account_url=f"https://{sa_name}.blob.core.windows.net", credential=credential)
        
        # Read the latest enriched data from ZRS Storage
        today = date.today().isoformat()
        blob_path = f"enriched-data/{today}/enriched-costs.json"
        blob_client = blob_service_client.get_blob_client(container="enriched-data", blob=blob_path)
        
        if not blob_client.exists():
            blob_path = f"enriched-data/{(date.today() - timedelta(days=1)).isoformat()}/enriched-costs.json"
            blob_client = blob_service_client.get_blob_client(container="enriched-data", blob=blob_path)

        data = json.loads(blob_client.download_blob().readall())
        dept_data = [r for r in data if r.get("department", "").lower() == department.lower()]
        
        return func.HttpResponse(json.dumps(dept_data), mimetype="application/json")
    except Exception as e:
        logger.error(f"Showback API failed: {e}")
        return func.HttpResponse("Internal Server Error", status_code=500)