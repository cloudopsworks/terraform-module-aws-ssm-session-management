##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

resource "aws_organizations_delegated_administrator" "this" {
  count             = try(var.settings.delegate.enabled, false) ? 1 : 0
  account_id        = var.settings.delegate.account_id
  service_principal = "ssm.amazonaws.com"
}