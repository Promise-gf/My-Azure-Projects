import azure.functions as func
import csv
import io
import json
import logging
import os
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient  # type: ignore[reportMissingImports]
from shared.models import RawCostRecord, EnrichedCostRecord
from shared.enrichment import enrich_cost_record
from shared.azure_monitor_ingest import ingestor

logger = logging.getLogger(__name__)

async def main(event: func.EventGridEvent):
    logger.info(f"Cost enricher triggered by event: {event.id}")
    try:
        event_data = event.get_json()
        blob_url = event_data.get("url", "")
        if "actual-costs" not in blob_url:
            return

        credential = DefaultAzureCredential()
        sa_name = os.environ['STORAGE_ACCOUNT_NAME']
        blob_service_client = BlobServiceClient(account_url=f"https://{sa_name}.blob.core.windows.net", credential=credential)

        blob_name = blob_url.split("cost-exports/")[1]
        blob_client = blob_service_client.get_blob_client(container="cost-exports", blob=blob_name)
        blob_content = blob_client.download_blob().readall().decode("utf-8")

        csv_reader = csv.DictReader(io.StringIO(blob_content))
        enriched_records = []

        for row in csv_reader:
            try:
                raw = RawCostRecord(**row)
                # Enterprise: Use the robust multi-strategy enrichment
                enriched = enrich_cost_record(raw)
                enriched_records.append(enriched)
            except Exception as row_err:
                logger.warning(f"Skipping bad row: {row_err}")
                continue

        if enriched_records:
            output_path = f"enriched-data/{enriched_records[0].date}/enriched-costs.json"
            out_client = blob_service_client.get_blob_client(container="enriched-data", blob=output_path)
            out_client.upload_blob(json.dumps([r.model_dump(mode="json") for r in enriched_records]), overwrite=True)

            # Phase 2: Ingest Structured Data to Log Analytics via DCR
            await ingestor.upload(enriched_records)

            logger.info(f"Successfully enriched {len(enriched_records)} records to ZRS and Log Analytics.")
    except Exception as e:
        logger.error(f"Cost enricher failed: {e}", exc_info=True)
        raise
