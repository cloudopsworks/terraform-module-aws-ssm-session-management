##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  ssm_logs_bucket = try(var.settings.random_bucket_suffix, true) ? "ssm-session-auditlogs-${local.system_name}-${random_string.random[0].result}" : "ssm-session-auditlogs-${local.system_name}"
  kms_key_arn     = try(data.aws_kms_key.existing[0].arn, data.aws_kms_alias.existing[0].target_key_arn, aws_kms_key.this[0].arn, "arn:aws:kms:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:alias/aws/s3")
}

resource "random_string" "random" {
  count   = try(var.settings.random_bucket_suffix, true) ? 1 : 0
  length  = 8
  special = false
  lower   = true
  upper   = false
  numeric = true
}


module "ssm_bucket" {
  source                                = "terraform-aws-modules/s3-bucket/aws"
  version                               = "~> 5.10"
  bucket                                = local.ssm_logs_bucket
  acl                                   = "private"
  block_public_acls                     = true
  block_public_policy                   = true
  ignore_public_acls                    = true
  restrict_public_buckets               = true
  attach_public_policy                  = true
  attach_require_latest_tls_policy      = true
  attach_deny_insecure_transport_policy = true
  attach_policy                         = length(try(var.settings.allowed_iam_role_arns, [])) > 0
  policy = length(try(var.settings.allowed_iam_role_arns, [])) > 0 ? jsonencode({
    version = "2012-10-17"
    statement = [
      {
        Sid    = "AllowIAMRolesAccess"
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
      }
    ]
  }) : null
  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  versioning = {
    enabled = false
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = local.kms_key_arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule = [
    {
      id      = "audit-log-lifecycle-policy"
      enabled = true

      transition = [
        {
          days          = try(var.settings.audit.transition_days, 30)
          storage_class = "STANDARD_IA"
        },
        {
          days          = try(var.settings.audit.archive_days, 60)
          storage_class = "GLACIER"
        }
      ]

      expiration = {
        days = try(var.settings.audit.retention_years * 365, 5 * 365)
      }
    }
  ]
  tags = local.all_tags
}