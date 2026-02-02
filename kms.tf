##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

data "aws_kms_alias" "existing" {
  count = !try(var.settings.kms.enabled, true) && try(var.settings.kms.key_alias, "") != "" ? 1 : 0
  name  = var.settings.kms.key_alias
}

data "aws_kms_key" "existing" {
  count  = !try(var.settings.kms.enabled, true) && try(var.settings.kms.key_id, "") != "" ? 1 : 0
  key_id = var.settings.kms.key_id
}

resource "aws_kms_key" "this" {
  count                   = try(var.settings.kms.enabled, true) ? 1 : 0
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
        Sid    = "Allow Root Account Access"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.id}.amazonaws.com"
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
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:${local.audit_log_group_name}"
          }
        }
      }],
      length(try(var.settings.allowed_iam_role_arns, [])) > 0 ? [{
        Effect = "Allow"
        Principal = {
          AWS = var.settings.allowed_iam_role_arns
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
  count         = try(var.settings.kms.enabled, true) ? 1 : 0
  target_key_id = aws_kms_key.this[0].key_id
  name          = format("alias/%s", try(var.settings.kms.alias_name, "ssm-session-mgmt-key-${local.system_name}"))
}