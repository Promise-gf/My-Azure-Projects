from shared.models import RawCostRecord, EnrichedCostRecord

DEPARTMENT_TAG_MAPPING = {
    "eng": "Engineering", "engineering": "Engineering", "dev": "Engineering",
    "marketing": "Marketing", "mktg": "Marketing",
    "sales": "Sales", "finance": "Finance", "hr": "Human Resources",
}

def _resolve_department(raw: RawCostRecord) -> str:
    if raw.tags:
        dept_tag = raw.tags.get("Department", "")
        if dept_tag: return DEPARTMENT_TAG_MAPPING.get(dept_tag.lower(), dept_tag)
    name_lower = (raw.resource_name + raw.resource_group).lower()
    for pattern, dept in [("eng", "Engineering"), ("mktg", "Marketing"), ("sales", "Sales")]:
        if pattern in name_lower: return dept
    return "Unassigned"

def _detect_environment(raw: RawCostRecord) -> str:
    if raw.tags and raw.tags.get("Environment"): return raw.tags["Environment"].lower()
    name = (raw.resource_name + raw.resource_group).lower()
    if any(x in name for x in ["prod", "production"]): return "production"
    if any(x in name for x in ["stg", "staging"]): return "staging"
    if any(x in name for x in ["dev", "development"]): return "development"
    return "unknown"

def enrich_cost_record(raw: RawCostRecord) -> EnrichedCostRecord:
    department = _resolve_department(raw)
    environment = _detect_environment(raw)
    dept_defaults = {"Engineering": "ENG-1000", "Marketing": "MKT-2000", "Sales": "SLS-3000", "Human Resources": "HR-5000"}
    cost_center = dept_defaults.get(department, "000-UNKNOWN")
    return EnrichedCostRecord(**raw.model_dump(), department=department, cost_center_code=cost_center, environment=environment)