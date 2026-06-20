from pydantic import BaseModel, Field, computed_field
from datetime import date, datetime
from decimal import Decimal
from typing import Optional
from enum import Enum

class AlertSeverity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"

class RawCostRecord(BaseModel):
    date: date
    subscription_name: str = ""
    resource_group: str = ""
    resource_name: str = ""
    service_name: str = ""
    meter_category: str = ""
    cost: Decimal = Decimal("0.0")
    currency: str = "USD"
    tags: Optional[dict[str, str]] = None

class EnrichedCostRecord(BaseModel):
    date: date
    subscription_name: str
    resource_group: str
    resource_name: str
    service_name: str
    cost: Decimal
    currency: str
    department: str = "Unassigned"
    cost_center_code: str = "000-UNKNOWN"
    environment: str = "unknown"
    enriched_at: datetime = Field(default_factory=datetime.utcnow)

class BudgetStatus(BaseModel):
    scope_name: str
    monthly_budget: Decimal
    current_spend: Decimal
    
    @computed_field
    @property
    def spend_percentage(self) -> float:
        return round((float(self.current_spend) / float(self.monthly_budget)) * 100, 2)

    @computed_field
    @property
    def severity(self) -> AlertSeverity:
        pct = self.spend_percentage
        if pct >= 100: return AlertSeverity.CRITICAL
        elif pct >= 80: return AlertSeverity.WARNING
        return AlertSeverity.INFO