## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.35 |
| <a name="requirement_awscc"></a> [awscc](#requirement\_awscc) | >= 1.40 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.35 |
| <a name="provider_awscc"></a> [awscc](#provider\_awscc) | >= 1.40 |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_ssm_bucket"></a> [ssm\_bucket](#module\_ssm\_bucket) | terraform-aws-modules/s3-bucket/aws | ~> 5.10 |
| <a name="module_tags"></a> [tags](#module\_tags) | cloudopsworks/tags/local | 1.0.10 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.default_host_management](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.default_host_management_session_logging](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.default_host_management](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.default_host_management_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_organizations_delegated_administrator.cloud_formation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_delegated_administrator) | resource |
| [aws_organizations_delegated_administrator.quick_setup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_delegated_administrator) | resource |
| [aws_organizations_delegated_administrator.resource_explorer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_delegated_administrator) | resource |
| [aws_organizations_delegated_administrator.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_delegated_administrator) | resource |
| [aws_ssm_association.inventory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_document.session_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |
| [aws_ssm_resource_data_sync.inventory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_resource_data_sync) | resource |
| [aws_ssm_service_setting.default_host_management](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_service_setting) | resource |
| [aws_ssmquicksetup_configuration_manager.dhmc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssmquicksetup_configuration_manager) | resource |
| [aws_ssmquicksetup_configuration_manager.host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssmquicksetup_configuration_manager) | resource |
| [aws_ssmquicksetup_configuration_manager.patch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssmquicksetup_configuration_manager) | resource |
| [awscc_ssmguiconnect_preferences.remote_desktop](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/ssmguiconnect_preferences) | resource |
| [random_string.random](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_role.allowed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_role) | data source |
| [aws_iam_roles.allowed_wildcard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_roles) | data source |
| [aws_kms_alias.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_alias) | data source |
| [aws_kms_key.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_key) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_ssm_patch_baselines.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_patch_baselines) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra tags to add to the resources | `map(string)` | `{}` | no |
| <a name="input_is_hub"></a> [is\_hub](#input\_is\_hub) | Is this a hub or spoke configuration? | `bool` | `false` | no |
| <a name="input_org"></a> [org](#input\_org) | Organization details | <pre>object({<br/>    organization_name = string<br/>    organization_unit = string<br/>    environment_type  = string<br/>    environment_name  = string<br/>  })</pre> | n/a | yes |
| <a name="input_settings"></a> [settings](#input\_settings) | Settings for SSM Session Manager & SSM Fleet Manager | `any` | `{}` | no |
| <a name="input_spoke_def"></a> [spoke\_def](#input\_spoke\_def) | Spoke ID Number, must be a 3 digit number | `string` | `"001"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_allowed_iam_role_arns"></a> [allowed\_iam\_role\_arns](#output\_allowed\_iam\_role\_arns) | Resolved list of IAM role ARNs granted access to the audit bucket and KMS key, merging settings.allowed\_iam\_role\_arns with the exact names and wildcard patterns resolved from settings.allowed\_iam\_role\_names. |
| <a name="output_audit_bucket_arn"></a> [audit\_bucket\_arn](#output\_audit\_bucket\_arn) | ARN of the S3 bucket holding Session Manager audit logs. Empty in delegation mode. |
| <a name="output_audit_bucket_id"></a> [audit\_bucket\_id](#output\_audit\_bucket\_id) | Name of the S3 bucket holding Session Manager audit logs. Empty in delegation mode. |
| <a name="output_audit_bucket_key_prefix"></a> [audit\_bucket\_key\_prefix](#output\_audit\_bucket\_key\_prefix) | Key prefix under which Session Manager writes audit logs in the bucket. |
| <a name="output_cloudwatch_log_group_arn"></a> [cloudwatch\_log\_group\_arn](#output\_cloudwatch\_log\_group\_arn) | ARN of the CloudWatch log group receiving session logs. Empty when CloudWatch logging is disabled. |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudWatch log group receiving session logs. Empty when CloudWatch logging is disabled. |
| <a name="output_default_host_management_role_arn"></a> [default\_host\_management\_role\_arn](#output\_default\_host\_management\_role\_arn) | ARN of the IAM role Systems Manager assumes for Default Host Management Configuration. Empty when the module does not create the role. |
| <a name="output_default_host_management_role_name"></a> [default\_host\_management\_role\_name](#output\_default\_host\_management\_role\_name) | Name of the IAM role Systems Manager assumes for Default Host Management Configuration. Empty when the module does not create the role. |
| <a name="output_default_host_management_setting_value"></a> [default\_host\_management\_setting\_value](#output\_default\_host\_management\_setting\_value) | Value written to the Default Host Management Configuration service setting, as the role path and name Systems Manager expects. Empty when Default Host Management Configuration is disabled. |
| <a name="output_delegated_administrator_account_id"></a> [delegated\_administrator\_account\_id](#output\_delegated\_administrator\_account\_id) | Account ID registered as SSM delegated administrator. Empty when delegation mode is disabled. |
| <a name="output_dhmc_quicksetup_manager_arn"></a> [dhmc\_quicksetup\_manager\_arn](#output\_dhmc\_quicksetup\_manager\_arn) | ARN of the Quick Setup configuration manager deploying Default Host Management Configuration. Empty when settings.dhmc is disabled. |
| <a name="output_host_management_quicksetup_manager_arn"></a> [host\_management\_quicksetup\_manager\_arn](#output\_host\_management\_quicksetup\_manager\_arn) | ARN of the Quick Setup configuration manager deploying Host Management. Empty when settings.host\_management is disabled. |
| <a name="output_inventory_association_id"></a> [inventory\_association\_id](#output\_inventory\_association\_id) | ID of the State Manager association running AWS-GatherSoftwareInventory. Empty when Inventory collection is disabled. |
| <a name="output_inventory_association_name"></a> [inventory\_association\_name](#output\_inventory\_association\_name) | Name of the State Manager association running AWS-GatherSoftwareInventory. Empty when Inventory collection is disabled. |
| <a name="output_kms_key_alias"></a> [kms\_key\_alias](#output\_kms\_key\_alias) | Alias of the KMS key created by this module. Empty when the module does not create a key. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key used to encrypt session data. Empty when no customer managed key is in use. |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | Key ID of the KMS key used to encrypt session data, whether created by this module or supplied. Empty when no customer managed key is in use. |
| <a name="output_patch_policy_name"></a> [patch\_policy\_name](#output\_patch\_policy\_name) | Name of the patch policy, which Quick Setup also applies to targeted instances as a tag. Empty when settings.patch is disabled. |
| <a name="output_patch_quicksetup_manager_arn"></a> [patch\_quicksetup\_manager\_arn](#output\_patch\_quicksetup\_manager\_arn) | ARN of the Quick Setup configuration manager deploying the Patch Policy. Empty when settings.patch is disabled. |
| <a name="output_remote_desktop_recording_bucket"></a> [remote\_desktop\_recording\_bucket](#output\_remote\_desktop\_recording\_bucket) | Name of the S3 bucket receiving Fleet Manager Remote Desktop connection recordings. Empty when RDP recording is disabled. |
| <a name="output_remote_desktop_recording_kms_key_arn"></a> [remote\_desktop\_recording\_kms\_key\_arn](#output\_remote\_desktop\_recording\_kms\_key\_arn) | ARN of the KMS key used to encrypt Remote Desktop recordings while Systems Manager processes them. Empty when RDP recording is disabled. |
| <a name="output_resource_data_sync_bucket"></a> [resource\_data\_sync\_bucket](#output\_resource\_data\_sync\_bucket) | Name of the S3 bucket receiving synchronised Inventory data. Empty when resource data sync is disabled. |
| <a name="output_resource_data_sync_name"></a> [resource\_data\_sync\_name](#output\_resource\_data\_sync\_name) | Name of the Inventory resource data sync. Empty when resource data sync is disabled. |
| <a name="output_resource_data_sync_prefix"></a> [resource\_data\_sync\_prefix](#output\_resource\_data\_sync\_prefix) | Key prefix under which resource data sync writes Inventory data. Empty when resource data sync is disabled or writes to the bucket root. |
| <a name="output_session_document_arn"></a> [session\_document\_arn](#output\_session\_document\_arn) | ARN of the SSM Session document holding the regional Session Manager preferences. Empty in delegation mode. |
| <a name="output_session_document_name"></a> [session\_document\_name](#output\_session\_document\_name) | Name of the SSM Session document holding the regional Session Manager preferences. Empty in delegation mode. |
