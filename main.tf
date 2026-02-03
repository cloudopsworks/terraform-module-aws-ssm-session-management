##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

resource "aws_ssm_document" "session_manager" {
  name          = "SSM-SessionManagerRunShell"
  document_type = "Session"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Document to hold regional settings for Session Manager"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = module.ssm_bucket.s3_bucket_id
      s3KeyPrefix                 = "session-manager/"
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = try(var.settings.cloudwatch.enabled, false) ? aws_cloudwatch_log_group.this[0].name : ""
      cloudWatchEncryptionEnabled = try(var.settings.cloudwatch.enabled, false) ? true : false
      cloudWatchStreamingEnabled  = false
      kmsKeyId                    = try(var.settings.kms.key_id, data.aws_kms_alias.existing[0].target_key_id, aws_kms_key.this[0].id)
      runAsEnabled                = false
      runAsDefaultUser            = try(var.settings.session.run_as, "")
      idleSessionTimeout          = try(var.settings.session.timeout, 20)
      maxSessionDuration          = try(var.settings.session.max_duration, 60)
    }
  })
  tags = local.all_tags
}