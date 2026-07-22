locals {
  # Seven governance groups. `kind` documents intended membership (user vs service
  # principal); it drives which member map wires each group but does not change the
  # azuread_group resource itself.
  security_groups = {
    platform-admins = { display = "sg-fabric-retail-platform-admins", desc = "Retail Fabric governance/platform team (workspace Admins).", kind = "user" }
    data-eng        = { display = "sg-fabric-retail-data-eng", desc = "Retail data engineering.", kind = "user" }
    data-sci        = { display = "sg-fabric-retail-data-sci", desc = "Retail data science.", kind = "user" }
    analysts        = { display = "sg-fabric-retail-analysts", desc = "Retail BI / analytics developers.", kind = "user" }
    ai-apps         = { display = "sg-fabric-retail-ai-apps", desc = "Service principals for retail AI applications.", kind = "sp" }
    report-users    = { display = "sg-fabric-retail-report-users", desc = "Retail reporting consumers (Power BI App audience).", kind = "user" }
    deploy-sp       = { display = "sg-fabric-retail-deploy-sp", desc = "Retail CI/CD deploy service principal(s).", kind = "sp" }
  }
}

resource "azuread_group" "retail" {
  for_each = local.security_groups

  display_name     = each.value.display
  description      = each.value.desc
  security_enabled = true
  mail_enabled     = false
}
