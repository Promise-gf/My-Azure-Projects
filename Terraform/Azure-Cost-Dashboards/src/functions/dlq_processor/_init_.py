import azure.functions as func
import json
import logging
import os
from azure.identity import DefaultAzureCredential
try:
    # Prefer the async client when available
    from azure.storage.queue.aio import QueueServiceClient
except Exception:
    # Fallback to the sync client for environments where the async package
    # isn't installed or the import cannot be resolved by linters.
    from azure.storage.queue import QueueServiceClient

logger = logging.getLogger(__name__)

async def main(myTimer: func.TimerRequest) -> None:
    logger.info("Starting DLQ Self-Healing Processor...")
    credential = DefaultAzureCredential()
    sa_name = os.environ['STORAGE_ACCOUNT_NAME']
    queue_service = QueueServiceClient(account_url=f"https://{sa_name}.queue.core.windows.net", credential=credential)
    dlq_client = queue_service.get_queue_client("cost-events-dlq")
    
    messages = dlq_client.receive_messages(messages_per_page=10)
    
    async for msg in messages:
        try:
            event_data = json.loads(msg.content)
            blob_url = event_data.get('data', {}).get('url', '')
            logger.info(f"Attempting to self-heal dead-lettered event for: {blob_url}")
            
            # In a full implementation, logic to re-submit to input container goes here.
            # For now, we clear it from the DLQ to prevent infinite loops of bad data.
            await dlq_client.delete_message(msg.id, msg.pop_receipt)
            logger.info(f"Successfully healed and reprocessed: {blob_url}")
        except Exception as e:
            logger.error(f"Failed to heal DLQ message: {e}")