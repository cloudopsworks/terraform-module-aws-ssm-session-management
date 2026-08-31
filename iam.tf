##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Roles granted access to the audit bucket and the KMS key may be supplied either
# as full ARNs (allowed_iam_role_arns) or as plain role names (allowed_iam_role_names),
# which are resolved to ARNs in the current account.
data "aws_iam_role" "allowed" {
  for_each = toset(try(var.settings.allowed_iam_role_names, []))
  name     = each.value
}

locals {
  # Sorted and de-duplicated so the rendered policy documents stay stable across plans.
  allowed_iam_role_arns = sort(distinct(concat(
    try(var.settings.allowed_iam_role_arns, []),
    [for role in data.aws_iam_role.allowed : role.arn],
  )))

  has_allowed_iam_roles = length(local.allowed_iam_role_arns) > 0
}
