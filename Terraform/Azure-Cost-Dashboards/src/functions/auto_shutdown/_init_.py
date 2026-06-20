import asyncio
import azure.functions as func
import logging
import os
import urllib.request
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)

async def main(myTimer: func.TimerRequest) -> None:
    """
    Dev-Only Cost Optimization: Stops the primary Dev Function App at 7 PM UTC.
    Replaces the Auto-Shutdown Logic App for codebase consistency.
    """
    # These env vars are injected by Terragrunt specifically in the Dev environment
    target_app_name = os.environ.get("TARGET_FUNCTION_APP_NAME")
    target_rg_name  = os.environ.get("TARGET_RESOURCE_GROUP_NAME")
    subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID")

    if not all([target_app_name, target_rg_name, subscription_id]):
        logger.warning("Auto-shutdown configuration missing. Skipping.")
        return

    logger.info(f"Attempting to stop Function App: {target_app_name}")

    try:
        credential = DefaultAzureCredential()
        token = await credential.get_token("https://management.azure.com/.default")
        headers = {"Authorization": f"Bearer {token.token}"}

        url = f"https://management.azure.com/subscriptions/{subscription_id}/resourceGroups/{target_rg_name}/providers/Microsoft.Web/sites/{target_app_name}/stop?api-version=2022-03-01"

        def stop_function_app():
            request = urllib.request.Request(url, headers=headers, method="POST")
            with urllib.request.urlopen(request) as response:
                return response.status

        await asyncio.to_thread(stop_function_app)

        logger.info(f"Successfully stopped Function App: {target_app_name}")

    except Exception as e:
        logger.error(f"Failed to stop Function App: {e}")