import pytest
from decimal import Decimal
from datetime import date
from src.shared.enrichment import enrich_cost_record
from src.shared.models import RawCostRecord

@pytest.fixture
def base_raw_record():
    """Fixture for a baseline raw cost record."""
    return RawCostRecord(
        date=date(2023, 10, 1),
        subscription_name="Sub1",
        resource_group="rg-test",
        resource_name="vm-test",
        service_name="Compute",
        cost=Decimal("100.00"),
        currency="USD",
        tags=None
    )

# --- Department Resolution Tests ---

def test_enrichment_adds_department_from_tags_exact(base_raw_record):
    """Test standard exact-match Department tag."""
    base_raw_record.tags = {"Department": "Marketing"}
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.department == "Marketing"

def test_enrichment_normalizes_department_case(base_raw_record):
    """Test that lowercase/mixed-case tags are normalized to proper case."""
    base_raw_record.tags = {"Department": "engineering"}
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.department == "Engineering"

def test_enrichment_normalizes_department_abbreviation(base_raw_record):
    """Test that abbreviations like 'eng' or 'mktg' are expanded."""
    base_raw_record.tags = {"Department": "eng"}
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.department == "Engineering"

def test_enrichment_defaults_unassigned_when_tags_none(base_raw_record):
    """Test fallback when tags object is completely missing."""
    base_raw_record.tags = None
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.department == "Unassigned"

def test_enrichment_defaults_unassigned_when_tags_empty(base_raw_record):
    """Test fallback when tags object exists but is an empty dict."""
    base_raw_record.tags = {}
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.department == "Unassigned"

def test_enrichment_defaults_unassigned_when_department_missing(base_raw_record):
    """Test fallback when tags exist but lack the Department key."""
    base_raw_record.tags = {"Owner": "jdoe@company.com"}
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.department == "Unassigned"

def test_enrichment_fallback_to_naming_convention(base_raw_record):
    """Test fallback to resource naming convention if tags are missing."""
    base_raw_record.tags = None
    base_raw_record.resource_name = "vm-eng-prod-001"
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.department == "Engineering"

# --- Environment Detection Tests ---

def test_enrichment_detects_environment_from_tag(base_raw_record):
    """Test environment explicitly provided via tag."""
    base_raw_record.tags = {"Department": "Engineering", "Environment": "Production"}
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.environment == "production"

def test_enrichment_detects_environment_from_resource_name(base_raw_record):
    """Test environment inferred from resource name when tag is missing."""
    base_raw_record.tags = None
    base_raw_record.resource_name = "app-prod-api-01"
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.environment == "production"

def test_enrichment_detects_unknown_environment(base_raw_record):
    """Test environment falls back to 'unknown' when no clues exist."""
    base_raw_record.tags = None
    base_raw_record.resource_name = "vm-data-01" # No env keywords
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.environment == "unknown"

# --- Cost Center Default Tests ---

def test_enrichment_assigns_correct_cost_center(base_raw_record):
    """Test that departments map to the correct enterprise cost center."""
    base_raw_record.tags = {"Department": "Marketing"}
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.cost_center_code == "MKT-2000"

def test_enrichment_assigns_unknown_cost_center(base_raw_record):
    """Test cost center falls back to '000-UNKNOWN' for unassigned."""
    base_raw_record.tags = None
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.cost_center_code == "000-UNKNOWN"

# --- Data Integrity Tests ---

def test_enrichment_preserves_financial_data(base_raw_record):
    """Test that financial figures are not mutated during enrichment."""
    base_raw_record.tags = {"Department": "Engineering"}
    enriched = enrich_cost_record(base_raw_record)
    assert enriched.cost == Decimal("100.00")
    assert enriched.currency == "USD"
    assert enriched.date == date(2023, 10, 1)