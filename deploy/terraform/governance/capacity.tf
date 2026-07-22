# Resolve the shared Fabric capacity once by display name (D3). Its id is assigned
# to all four medallion workspaces so cost is attributed per-workspace downstream
# (Phase 5 chargeback), not by separate SKUs. Mirrors the capacity-resolution
# pattern in the existing single-workspace root (../main.tf).
data "fabric_capacity" "shared" {
  display_name = var.capacity_name

  lifecycle {
    postcondition {
      condition     = var.skip_capacity_state_validation || self.state == "Active"
      error_message = "Fabric capacity '${var.capacity_name}' is not Active. Assign an active Fabric (F) SKU capacity before deploying."
    }
  }
}
