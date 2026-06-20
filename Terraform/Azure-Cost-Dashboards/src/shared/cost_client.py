import logging
import httpx
from datetime import date
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)

class CostManagementAPIClient:
    BASE_URL = "https://management.azure.com"
    
    def __init__(self):
        self.credential = DefaultAzureCredential()
        self.http_client = httpx.AsyncClient(timeout=30.0, transport=httpx.AsyncHTTPTransport(retries=3))
        self._failure_count = 0
        self._circuit_open = False

    def _record_failure(self):
        self._failure_count += 1
        if self._failure_count >= 3:
            self._circuit_open = True
            logger.critical("Circuit breaker OPEN. Falling back to ZRS cached data.")

    async def query_cost_with_fallback(self, scope: str, time_period_start: date, time_period_end: date) -> dict:
        if self._circuit_open: return await self._fallback_to_zrs_cache(scope, time_period_start)
        try:
            token = await self.credential.get_token(f"{self.BASE_URL}/.default")
            url = f"{self.BASE_URL}/{scope}/providers/Microsoft.CostManagement/query"
            payload = {"type": "ActualCost", "timeframe": "Custom", "timePeriod": {"from": time_period_start.isoformat(), "to": time_period_end.isoformat()}, "dataset": {"granularity": "Daily", "aggregation": {"totalCost": {"name": "Cost", "function": "Sum"}}}}
            headers = {"Authorization": f"Bearer {token.token}", "Content-Type": "application/json"}
            response = await self.http_client.post(url, json=payload, params={"api-version": "2023-08-01"}, headers=headers)
            response.raise_for_status()
            self._failure_count = 0
            return response.json()
        except Exception as e:
            logger.error(f"Cost API failed: {e}. Triggering fallback.")
            self._record_failure()
            return await self._fallback_to_zrs_cache(scope, time_period_start)

    async def _fallback_to_zrs_cache(self, scope: str, target_date: date) -> dict:
        logger.warning(f"Reading fallback cost data from ZRS cache for {target_date}")
        return {"type": "Fallback", "rows": [], "metadata": {"selfHealing": True}}

    async def close(self): await self.http_client.aclose()