##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  # When the module runs in delegation mode it only registers delegated administrators
  # in the Organizations management account; no session-logging resources are created.
  is_delegated = try(var.settings.organization.delegated, false)
}

resource "aws_organizations_delegated_administrator" "this" {
  count             = local.is_delegated ? 1 : 0
  account_id        = var.settings.organization.account_id
  service_principal = "ssm.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "quick_setup" {
  count             = local.is_delegated ? 1 : 0
  account_id        = var.settings.organization.account_id
  service_principal = "ssm-quicksetup.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "cloud_formation" {
  count             = local.is_delegated ? 1 : 0
  account_id        = var.settings.organization.account_id
  service_principal = "member.org.stacksets.cloudformation.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "resource_explorer" {
  count             = local.is_delegated ? 1 : 0
  account_id        = var.settings.organization.account_id
  service_principal = "resource-explorer-2.amazonaws.com"
}
