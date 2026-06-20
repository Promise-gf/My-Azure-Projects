import pytest
import time
import json
import os
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from datetime import date

# Mark tests so they only run in CI with real Azure credentials
pytestmark = pytest.mark.skipif(not os.getenv("RUN_INTEGRATION_TESTS"), reason="Integration tests require Azure credentials")

SA_NAME = os.getenv("STORAGE_ACCOUNT_NAME")
CSV_DATA = """Date,SubscriptionName,ResourceGroup,ResourceName,ServiceName,MeterCategory,Cost,Currency,Tag
2023-10-01,Sub1,rg-test,vm-test,Compute,VM,100.00,USD,"Department:Engineering"
"""

@pytest.fixture(scope="module")
def blob_client():
    credential = DefaultAzureCredential()
    return BlobServiceClient(account_url=f"https://{SA_NAME}.blob.core.windows.net", credential=credential)

def test_cost_enricher_e2e(blob_client):
    # 1. Upload Raw CSV
    input_path = f"actual-costs/test-{date.today().isoformat()}.csv"
    input_client = blob_client.get_blob_client(container="cost-exports", blob=input_path)
    input_client.upload_blob(CSV_DATA, overwrite=True)

    # 2. Wait for Event Grid -> Function -> Enriched JSON
    output_path = f"enriched-data/{date.today().isoformat()}/enriched-costs.json"
    output_client = blob_client.get_blob_client(container="enriched-data", blob=output_path)

    retries = 10
    while retries > 0:
        if output_client.exists():
            break
        time.sleep(6) # Wait for function execution
        retries -= 1
    
    assert retries > 0, "Enriched data blob did not appear within timeout"

    # 3. Validate Enriched Output
    data = json.loads(output_client.download_blob().readall())
    assert len(data) > 0
    assert data[0]["department"] == "Engineering" # Validates Pydantic + Enrichment logic
    assert data[0]["cost"] == 100.0

    # Cleanup
    input_client.delete_blob()
    output_client.delete_blob()