##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  bucket_name_override = try(var.settings.bucket.name, "")

  # settings.random_bucket_suffix is the legacy spelling kept for backwards
  # compatibility; settings.bucket.random_suffix takes precedence when both are set.
  bucket_random_suffix = try(var.settings.bucket.random_suffix, try(var.settings.random_bucket_suffix, true))

  create_bucket_suffix = local.bucket_random_suffix && local.bucket_name_override == "" && !local.is_delegated

  ssm_logs_bucket_prefix = "ssm-session-auditlogs-${local.system_name}"

  ssm_logs_bucket = local.bucket_name_override != "" ? local.bucket_name_override : join("", concat(
    [local.ssm_logs_bucket_prefix],
    local.create_bucket_suffix ? ["-"] : [],
    random_string.random[*].result
  ))

  # Deterministic length of the generated name; the random suffix always contributes
  # exactly 9 characters ("-" plus 8 random). Used to guard the 63 character S3 limit
  # without waiting for the random value to be known.
  ssm_logs_bucket_length = local.bucket_name_override != "" ? length(local.bucket_name_override) : length(local.ssm_logs_bucket_prefix) + (local.create_bucket_suffix ? 9 : 0)

  s3_kms_key_arn = local.has_kms_key ? local.kms_key_arn : "arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:alias/aws/s3"
}

resource "random_string" "random" {
  count   = local.create_bucket_suffix ? 1 : 0
  length  = 8
  special = false
  lower   = true
  upper   = false
  numeric = true
}

module "ssm_bucket" {
  source                                = "terraform-aws-modules/s3-bucket/aws"
  version                               = "~> 5.10"
  create_bucket                         = !local.is_delegated
  bucket                                = local.ssm_logs_bucket
  acl                                   = "private"
  block_public_acls                     = true
  block_public_policy                   = true
  ignore_public_acls                    = true
  restrict_public_buckets               = true
  attach_public_policy                  = true
  attach_require_latest_tls_policy      = true
  attach_deny_insecure_transport_policy = true
  attach_policy                         = local.has_allowed_iam_roles
  policy = local.has_allowed_iam_roles ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowIAMRolesAccess"
        Effect = "Allow"
        Principal = {
          AWS = local.allowed_iam_role_arns
        }
        Action = [
          "s3:PutObject",
          "s3:GetEncryptionConfiguration",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}/*",
          "arn:${data.aws_partition.current.partition}:s3:::${local.ssm_logs_bucket}"
        ]
      }
    ]
  }) : null
  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  versioning = {
    enabled = try(var.settings.bucket.versioning, false)
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = local.s3_kms_key_arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule = [
    {
      id      = "audit-log-lifecycle-policy"
      enabled = true

      abort_incomplete_multipart_upload_days = try(var.settings.audit.abort_multipart_days, 7)

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
