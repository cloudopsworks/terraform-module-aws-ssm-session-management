##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/ssm/session-manager/${local.system_name}"
  retention_in_days = try(var.settings.cloudwatch.retention, 7)
  skip_destroy      = true
  kms_key_id        = try(aws_kms_key.this[0].arn, null)
  tags              = local.all_tags
}