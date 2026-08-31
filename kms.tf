##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  kms_create = try(var.settings.kms.enabled, true) && !local.is_delegated

  # Key resolution order: the key created by this module first, then an explicitly
  # supplied key id, then a supplied alias. Empty when the module manages no CMK at
  # all, which callers must treat as "use the AWS managed key / no CMK".
  kms_key_id = try(
    aws_kms_key.this[0].key_id,
    data.aws_kms_key.existing[0].key_id,
    data.aws_kms_alias.existing[0].target_key_id,
    ""
  )

  kms_key_arn = try(
    aws_kms_key.this[0].arn,
    data.aws_kms_key.existing[0].arn,
    data.aws_kms_alias.existing[0].target_key_arn,
    ""
  )

  # Derived from configuration rather than from the resolved ARN so it stays known at
  # plan time, keeping dependent arguments out of "known after apply".
  has_kms_key = local.kms_create || try(var.settings.kms.key_id, "") != "" || try(var.settings.kms.key_alias, "") != ""
}

data "aws_kms_alias" "existing" {
  count = !try(var.settings.kms.enabled, true) && try(var.settings.kms.key_alias, "") != "" ? 1 : 0
  name  = var.settings.kms.key_alias
}

data "aws_kms_key" "existing" {
  count  = !try(var.settings.kms.enabled, true) && try(var.settings.kms.key_id, "") != "" ? 1 : 0
  key_id = var.settings.kms.key_id
}

resource "aws_kms_key" "this" {
  count                   = local.kms_create ? 1 : 0
  description             = "KMS Key for SSM Documents managed by Session Management Module"
  deletion_window_in_days = try(var.settings.kms.deletion_window, 30)
  enable_key_rotation     = try(var.settings.kms.enable_key_rotation, true)
  rotation_period_in_days = try(var.settings.kms.rotation_period_in_days, 90)
  multi_region            = try(var.settings.kms.multi_region, false)
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-default-1"
    Statement = concat([
      {
        Sid    = "AllowRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }],
      local.cloudwatch_enabled ? [{
        Sid    = "AllowCloudWatchLogsAccess"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.audit_log_group_name}"
          }
        }
      }] : [],
      local.has_allowed_iam_roles ? [{
        Sid    = "AllowIAMRolesAccess"
        Effect = "Allow"
        Principal = {
          AWS = local.allowed_iam_role_arns
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
      }] : []
    )
  })
  tags = local.all_tags
}

resource "aws_kms_alias" "this" {
  count         = local.kms_create ? 1 : 0
  target_key_id = aws_kms_key.this[0].key_id
  name          = format("alias/%s", try(var.settings.kms.alias_name, "ssm-session-mgmt-key-${local.system_name}"))
}
