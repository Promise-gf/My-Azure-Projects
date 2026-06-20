import logging
import os
from datetime import datetime
from azure.identity import DefaultAzureCredential
from azure.monitor.ingestion import LogsIngestionClient
from azure.core.exceptions import HttpResponseError

logger = logging.getLogger(__name__)

class CostLogIngestor:
    def __init__(self):
        self.credential = DefaultAzureCredential()
        self.endpoint = os.environ.get("AZURE_MONITOR_DCE_ENDPOINT")
        self.rule_id = os.environ.get("AZURE_MONITOR_DCR_IMMUTABLE_ID")
        self.stream_name = os.environ.get("AZURE_MONITOR_STREAM_NAME", "Custom-CostEnrichmentLogs_CL")
        
        if self.endpoint and self.rule_id:
            self.client = LogsIngestionClient(endpoint=self.endpoint, credential=self.credential)
        else:
            self.client = None
            logger.warning("DCR Endpoint/Rule not configured. Falling back to standard logging.")

    async def upload(self, enriched_records: list):
        """Uploads structured enrichment data directly to Log Analytics via DCR."""
        if not self.client:
            # Fallback for local dev or missing config
            for r in enriched_records:
                logger.info(f"CostEnrichmentLogs | Department={r.department} TotalCost={r.cost}")
            return

        # Map Pydantic models to the DCR Schema
        log_data = [
            {
                "TimeGenerated": datetime.utcnow().isoformat(),
                "Department_s":  r.department,
                "ResourceName_s": r.resource_name,
                "TotalCost_d":   float(r.cost),
                "Environment_s": r.environment
            }
            for r in enriched_records
        ]

        try:
            # Enterprise: Native Azure Monitor Ingestion
            self.client.upload(rule_id=self.rule_id, stream_name=self.stream_name, logs=log_data)
            logger.info(f"Successfully ingested {len(log_data)} records via DCR to {self.stream_name}")
        except HttpResponseError as e:
            logger.error(f"Failed to ingest logs via DCR: {e}")
            # Fallback to standard logging so we don't lose the data entirely
            for r in enriched_records:
                logger.info(f"CostEnrichmentLogs | Department={r.department} TotalCost={r.cost}")

# Singleton for import
ingestor = CostLogIngestor()