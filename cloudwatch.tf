##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  cloudwatch_enabled   = try(var.settings.cloudwatch.enabled, false)
  audit_log_group_name = "/aws/ssm/session-manager/audit-${local.system_name}"
}

resource "aws_cloudwatch_log_group" "this" {
  count             = local.cloudwatch_enabled && !local.is_delegated ? 1 : 0
  depends_on        = [aws_kms_key.this]
  name              = local.audit_log_group_name
  retention_in_days = try(var.settings.cloudwatch.retention, 7)
  skip_destroy      = true
  # Only a customer managed key is valid here; the S3 fallback key cannot encrypt
  # CloudWatch Logs, so leave the group on CloudWatch's default encryption instead.
  kms_key_id = local.has_kms_key ? local.kms_key_arn : null
  tags       = local.all_tags
}
