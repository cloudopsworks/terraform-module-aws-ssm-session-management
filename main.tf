##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  session_run_as = try(var.settings.session.run_as, "")

  # Run-as is meaningless unless AWS is told to honour it, so default the toggle to
  # whether a default user was actually supplied.
  session_run_as_enabled = try(var.settings.session.run_as_enabled, local.session_run_as != "")

  # Session Manager rejects streaming to a log group it cannot confirm is encrypted,
  # so only advertise CloudWatch encryption when a customer managed key is in play.
  cloudwatch_encryption_enabled = local.cloudwatch_enabled && local.has_kms_key
}

resource "aws_ssm_document" "session_manager" {
  count         = !local.is_delegated ? 1 : 0
  name          = "SSM-SessionManagerRunShell"
  document_type = "Session"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Document to hold regional settings for Session Manager"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = module.ssm_bucket.s3_bucket_id
      s3KeyPrefix                 = local.audit_s3_key_prefix
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = local.cloudwatch_enabled ? aws_cloudwatch_log_group.this[0].name : ""
      cloudWatchEncryptionEnabled = local.cloudwatch_encryption_enabled
      cloudWatchStreamingEnabled  = try(var.settings.cloudwatch.streaming, false)
      kmsKeyId                    = local.kms_key_id
      runAsEnabled                = local.session_run_as_enabled
      runAsDefaultUser            = local.session_run_as
      # AWS expects these two as strings in the Session document schema.
      idleSessionTimeout = tostring(try(var.settings.session.timeout, 20))
      maxSessionDuration = tostring(try(var.settings.session.max_duration, 60))
      shellProfile = {
        linux   = try(var.settings.session.shell_profile.linux, "")
        windows = try(var.settings.session.shell_profile.windows, "")
      }
    }
  })
  tags = local.all_tags
}
