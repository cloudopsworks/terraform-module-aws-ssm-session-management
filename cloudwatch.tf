##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  audit_log_group_name = "/aws/ssm/session-manager/audit-${local.system_name}"
}
resource "aws_cloudwatch_log_group" "this" {
  depends_on        = [aws_kms_key.this]
  name              = local.audit_log_group_name
  retention_in_days = try(var.settings.cloudwatch.retention, 7)
  skip_destroy      = true
  kms_key_id        = try(var.settings.kms.key_id, aws_kms_key.this[0].id, null)
  tags              = local.all_tags
}