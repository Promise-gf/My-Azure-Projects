import logging
logger = logging.getLogger(__name__)

async def send_alert(message: str, severity: str):
    # In a real enterprise setup, this would post to a Microsoft Teams webhook or ServiceNow
    logger.warning(f"ALERT [{severity}]: {message}")