locals {
  # Medallion layers. `lakehouse` is each layer's OWN curated store (D2: physical
  # per-layer tables). IaC creates the EMPTY lakehouse; data lands later (Phase 3),
  # never here, and never by copying from retail-demo-dev.
  layers = {
    bronze     = { suffix = "bronze", desc = "Retail bronze - raw landing, eventhouses, ingestion.", lakehouse = "bronze_lh" }
    silver     = { suffix = "silver", desc = "Retail silver - cleansed/conformed dimensions and facts.", lakehouse = "silver_lh" }
    gold       = { suffix = "gold", desc = "Retail gold - aggregates, Direct Lake model, data agents.", lakehouse = "gold_lh" }
    ds-sandbox = { suffix = "ds-sandbox", desc = "Retail DS sandbox - experimentation and ML.", lakehouse = "ds_lh" }
  }
}

resource "fabric_workspace" "layer" {
  for_each = local.layers

  display_name                   = "retail-${each.value.suffix}-${var.environment}"
  description                    = each.value.desc
  capacity_id                    = data.fabric_capacity.shared.id
  skip_capacity_state_validation = var.skip_capacity_state_validation
}

# Each layer physically owns its curated lakehouse (D2). Empty at create time -
# no data-copy logic in IaC.
resource "fabric_lakehouse" "layer" {
  for_each = local.layers

  display_name = each.value.lakehouse
  workspace_id = fabric_workspace.layer[each.key].id

  configuration = {
    enable_schemas = true
  }

  # Schema-enabled lakehouse provisioning can exceed the provider's default
  # create timeout when several are created in parallel (observed context
  # deadline at ~10m); allow more headroom.
  timeouts = {
    create = "30m"
  }
}
