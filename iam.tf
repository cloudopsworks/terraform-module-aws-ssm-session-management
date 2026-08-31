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

locals {
  requested_iam_role_names = try(var.settings.allowed_iam_role_names, [])

  # IAM role names are limited to [A-Za-z0-9_+=,.@-], so neither "*" nor "?" can occur in
  # a real name. Their presence therefore marks an entry as a wildcard pattern with no
  # ambiguity, and no separate settings key is needed to tell the two apart.
  exact_iam_role_names    = [for name in local.requested_iam_role_names : name if !can(regex("[*?]", name))]
  wildcard_iam_role_globs = [for name in local.requested_iam_role_names : name if can(regex("[*?]", name))]

  # Glob to anchored RE2, as consumed by the name_regex filter below. Escape the only two
  # regex metacharacters that are legal in an IAM role name ("." and "+") before expanding
  # the glob wildcards, so a literal dot cannot widen the match. Anchoring matters because
  # name_regex is an unanchored substring match: without it "ssm-*" would also select
  # "my-ssm-session-role".
  wildcard_iam_role_regexes = {
    for glob in local.wildcard_iam_role_globs :
    glob => format("^%s$", replace(replace(replace(replace(glob, ".", "\\."), "+", "\\+"), "*", ".*"), "?", "."))
  }
}

# Exact names resolve individually so a typo fails the plan loudly.
data "aws_iam_role" "allowed" {
  for_each = toset(local.exact_iam_role_names)
  name     = each.value
}

# Wildcards resolve by listing roles and filtering client-side. Membership is re-evaluated
# on every plan, so a role created later that matches an existing pattern is picked up
# without a configuration change.
data "aws_iam_roles" "allowed_wildcard" {
  for_each   = local.wildcard_iam_role_regexes
  name_regex = each.value
}

locals {
  # Sorted and de-duplicated so the rendered policy documents stay stable across plans.
  allowed_iam_role_arns = sort(distinct(concat(
    try(var.settings.allowed_iam_role_arns, []),
    [for role in data.aws_iam_role.allowed : role.arn],
    flatten([for result in data.aws_iam_roles.allowed_wildcard : tolist(result.arns)]),
  )))

  has_allowed_iam_roles = length(local.allowed_iam_role_arns) > 0
}
