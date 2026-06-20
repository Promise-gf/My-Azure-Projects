from pydantic_settings import BaseSettings
from pydantic import Field

class CostConfig(BaseSettings):
    storage_account_name: str = Field(..., alias="STORAGE_ACCOUNT_NAME")
    key_vault_name: str = Field(..., alias="KEY_VAULT_NAME")
    environment: str = Field("dev", alias="ENVIRONMENT")
    monthly_budget_usd: float = Field(1000.0, alias="MONTHLY_BUDGET_USD")
    class Config:
        env_file = ".env"
        extra = "ignore"

config = CostConfig()