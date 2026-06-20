import pytest
from decimal import Decimal
from datetime import date
from src.shared.models import RawCostRecord, EnrichedCostRecord, BudgetStatus, AlertSeverity

def test_raw_cost_record_parsing():
    data = {
        "date": "2023-10-01",
        "subscription_name": "Sub1",
        "resource_group": "rg-test",
        "resource_name": "vm-test",
        "service_name": "Virtual Machines",
        "meter_category": "Compute",
        "cost": "123.45",
        "currency": "USD",
        "tags": {"Department": "Engineering"}
    }
    raw = RawCostRecord(**data)
    assert raw.cost == Decimal("123.45")
    assert raw.tags["Department"] == "Engineering"

def test_budget_status_critical():
    status = BudgetStatus(
        scope_name="Sub1",
        monthly_budget=Decimal("1000"),
        current_spend=Decimal("1050")
    )
    assert status.spend_percentage == 105.0
    assert status.severity == AlertSeverity.CRITICAL

def test_budget_status_warning():
    status = BudgetStatus(
        scope_name="Sub1",
        monthly_budget=Decimal("1000"),
        current_spend=Decimal("850")
    )
    assert status.spend_percentage == 85.0
    assert status.severity == AlertSeverity.WARNING

def test_budget_status_info():
    status = BudgetStatus(
        scope_name="Sub1",
        monthly_budget=Decimal("1000"),
        current_spend=Decimal("500")
    )
    assert status.spend_percentage == 50.0
    assert status.severity == AlertSeverity.INFO