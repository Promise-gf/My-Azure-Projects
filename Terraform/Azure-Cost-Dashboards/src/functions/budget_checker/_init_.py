import azure.functions as func
import logging
import os
from datetime import date
from decimal import Decimal
from shared.cost_client import CostManagementAPIClient
from shared.models import BudgetStatus, AlertSeverity
from shared.alerting import send_alert

try:
    httpx = __import__("httpx")
except ImportError:
    httpx = None

logger = logging.getLogger(__name__)

async def main(myTimer: func.TimerRequest) -> None:
    logger.info("Budget checker started")
    cost_client = CostManagementAPIClient()

    try:
        subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000000")
        scope = f"subscriptions/{subscription_id}"
        budget_usd = Decimal(os.environ.get("MONTHLY_BUDGET_USD", "1000"))

        # ---------------------------------------------------------
        # 0. Pre-fetch Auth Headers for downstream API calls
        # ---------------------------------------------------------
        headers = None
        try:
            token = await cost_client.credential.get_token(f"{cost_client.BASE_URL}/.default")
            headers = {"Authorization": f"Bearer {token.token}"}
        except Exception as auth_err:
            logger.error(f"Failed to get Azure AD token for API calls: {auth_err}")

        # ---------------------------------------------------------
        # 1. Check Budget Status (with ZRS Fallback Circuit Breaker)
        # ---------------------------------------------------------
        result = await cost_client.query_cost_with_fallback(
            scope=scope, 
            time_period_start=date.today().replace(day=1), 
            time_period_end=date.today()
        )
        current_spend = sum(row[0] for row in result.get("rows", []))

        status = BudgetStatus(
            scope_name=subscription_id, 
            monthly_budget=budget_usd, 
            current_spend=Decimal(str(current_spend))
        )

        if status.severity == AlertSeverity.CRITICAL:
            await send_alert(f"CRITICAL: Budget at {status.spend_percentage}%", "CRITICAL")
            
            # ---------------------------------------------------------
            # Phase 9: Trigger Auto-Remediation Logic App
            # ---------------------------------------------------------
            auto_stop_url = os.environ.get("AUTO_STOP_WEBHOOK_URL")
            if auto_stop_url:
                try:
                    async with httpx.AsyncClient() as client:
                        await client.post(auto_stop_url, json={
                            "subscription_id": subscription_id,
                            "severity": "CRITICAL",
                            "action": "StopNonProd" # Runbook handles the logic based on this action
                        })
                        logger.info(f"Triggered Auto-Stop Logic App for subscription {subscription_id}")
                except Exception as auto_stop_err:
                    logger.error(f"Failed to trigger Auto-Stop Logic App: {auto_stop_err}")

        elif status.severity == AlertSeverity.WARNING:
            await send_alert(f"WARNING: Budget at {status.spend_percentage}%", "WARNING")

        # ---------------------------------------------------------
        # 2. Exceptional Enterprise Feature: Azure Advisor Cost Savings
        # ---------------------------------------------------------
        if headers:
            try:
                advisor_url = f"{cost_client.BASE_URL}/{scope}/providers/Microsoft.Advisor/recommendations?api-version=2023-01-01&$filter=Category eq 'Cost'"
                
                response = await cost_client.http_client.get(advisor_url, headers=headers)
                if response.status_code == 200:
                    savings_data = response.json().get("value", [])
                    total_savings = sum(
                        float(item.get("properties", {}).get("extendedProperty", {}).get("savingsAmount", 0)) 
                        for item in savings_data
                    )

                    if total_savings > 100:  # Only alert if savings > $100/mo to prevent noise
                        await send_alert(f"💰 FinOps Alert: Found ${total_savings:,.2f}/month in potential Azure Advisor savings (Right-size/RIs).", "INFO")
            except Exception as adv_err:
                logger.warning(f"Advisor check failed (non-critical): {adv_err}")

        # ---------------------------------------------------------
        # 3. Exceptional Enterprise Feature: Defender for Cloud Integration
        # ---------------------------------------------------------
        if headers:
            try:
                defender_url = f"{cost_client.BASE_URL}/{scope}/providers/Microsoft.Security/assessments?api-version=2020-01-01"
                response = await cost_client.http_client.get(defender_url, headers=headers)

                if response.status_code == 200:
                    assessments = response.json().get("value", [])
                    critical_findings = [
                        a for a in assessments
                        if a.get("properties", {}).get("status", {}).get("code") == "Unhealthy"
                        and a.get("properties", {}).get("severity") in ("High", "Critical")
                    ]

                    if critical_findings:
                        await send_alert(
                            f"🚨 FinOps Security Alert: {len(critical_findings)} critical Defender for Cloud findings detected. Unsecured resources risk cryptojacking or data egress costs.",
                            "CRITICAL"
                        )
            except Exception as sec_err:
                logger.warning(f"Defender check failed (non-critical): {sec_err}")

    finally:
        await cost_client.close()