##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

# Standard Host Management Setup Baseline only on delegated accounts
locals {
  # transform the output of the aws_ssm_patch_baselines data source
  # into the format expected by the SelectedPatchBaselines parameter
  selected_patch_baselines = jsonencode({
    for baseline in data.aws_ssm_patch_baselines.this[0].baseline_identities : baseline.operating_system => {
      "value" : baseline.baseline_id
      "label" : baseline.baseline_name
      "description" : baseline.baseline_description
      "disabled" : !baseline.default_baseline
    } if try(var.settings.host_management.enabled, false)
  })
}

data "aws_ssm_patch_baselines" "this" {
  count             = try(var.settings.patch.enabled, false) ? 1 : 0
  default_baselines = try(var.settings.patch.default_baselines, true)
}

resource "aws_ssmquicksetup_configuration_manager" "dhmc" {
  count       = try(var.settings.dhmc.enabled, false) ? 1 : 0
  name        = local.system_name
  description = "SSM Quick Setup Configuration Manager for Default Host Management Configuration ${local.system_name}"
  configuration_definition {
    type = "AWSQuickSetupType-DHMC"
    parameters = {
      "UpdateSsmAgent" : try(var.settings.dhmc.update_ssm_agent, "true"),
      "TargetOrganizationalUnits" : var.settings.dhmc.target_organizational_units, #Comma separated list of OU IDs
      "TargetRegions" : try(var.settings.dhmc.target_regions, data.aws_region.current.region),
    }
  }
}

resource "aws_ssmquicksetup_configuration_manager" "host" {
  count       = try(var.settings.host_management.enabled, false) ? 1 : 0
  name        = local.system_name
  description = "SSM Quick Setup Configuration Manager for Host Management ${local.system_name}"
  configuration_definition {
    type = "AWSQuickSetupType-SSMHostMgmt"
    parameters = merge({
      "UpdateSsmAgent" : try(var.settings.host_management.update_ssm_agent, "true"),
      "UpdateEc2LaunchAgent" : try(var.settings.host_management.update_ec2_launch_agent, "true"),
      "CollectInventory" : try(var.settings.host_management.collect_inventory, "true"),
      "ScanInstances" : try(var.settings.host_management.scan_instances, "true"),
      "InstallCloudWatchAgent" : try(var.settings.host_management.install_cloudwatch_agent, "false"),
      "UpdateCloudWatchAgent" : try(var.settings.host_management.update_cloudwatch_agent, "false"),
      "IsPolicyAttachAllowed" : try(var.settings.host_management.is_policy_attach_allowed, "false"),
      },
      try(var.settings.host_management.target_type, "") != "" ? { "TargetType" : var.settings.host_management.target_type } : {},
      try(var.settings.host_management.target_type, "") != "InstanceIds" ? { "TargetInstances" : var.settings.host_management.target_instances } : {},
      try(var.settings.host_management.target_type, "") != "Tags" ? { "TargetTagKey" : var.settings.host_management.target_tag_key } : {},
      try(var.settings.host_management.target_type, "") != "Tags" ? { "TargetTagValue" : var.settings.host_management.target_tag_value } : {},
      try(var.settings.host_management.target_type, "") != "ResourceGroups" ? { "TargetResourceGroup" : var.settings.host_management.resource_group_name } : {},
      try(var.settings.host_management.target_organizational_units, "") != "" ? { "TargetOrganizationalUnits" : var.settings.host_management.target_organizational_units } : {}, #Comma separated list of OU IDs }
      try(var.settings.host_management.target_accounts, "") != "" ? { "TargetAccounts" : var.settings.host_management.target_accounts } : {},                                    #Comma separated list of account IDs
      { "TargetRegions" : try(var.settings.host_management.target_regions, data.aws_region.current.region), }
    )
  }
}

resource "aws_ssmquicksetup_configuration_manager" "patch" {
  count       = try(var.settings.patch.enabled, false) ? 1 : 0
  name        = local.system_name
  description = "SSM Quick Setup Configuration Manager for Patch Policy ${local.system_name}"
  configuration_definition {
    local_deployment_administration_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/AWS-QuickSetup-PatchPolicy-LocalAdministrationRole"
    local_deployment_execution_role_name     = "AWS-QuickSetup-PatchPolicy-LocalExecutionRole"
    type                                     = "AWSQuickSetupType-PatchPolicy"

    parameters = merge({
      "ConfigurationOptionsPatchOperation" : try(var.settings.patch.operation, "Scan"),
      "PatchBaselineRegion" : data.aws_region.current.region,
      "PatchBaselineUseDefault" : try(var.settings.patch.baseline_use, "default"),
      "PatchPolicyName" : try(var.settings.patch.policy_name, local.system_name_short),
      "SelectedPatchBaselines" : local.selected_patch_baselines,
      "OutputLogEnableS3" : "false",
      "RateControlConcurrency" : "10%",
      "RateControlErrorThreshold" : "2%",
      "IsPolicyAttachAllowed" : "false",
      },
      try(var.settings.patch.operation, "Scan") == "Scan" ? { "ConfigurationOptionsScanValue" : try(var.settings.patch.scan_value, "cron(0 1 * * ? *)") } : {},
      try(var.settings.patch.operation, "Scan") == "Scan" ? { "ConfigurationOptionsScanNextInterval" : try(var.settings.patch.scan_next_interval, "false") } : {},
      try(var.settings.patch.operation, "Scan") == "Install" ? { "ConfigurationOptionsInstallValue" : try(var.settings.patch.scan_value, "cron(0 1 * * ? *)") } : {},
      try(var.settings.patch.operation, "Scan") == "Install" ? { "ConfigurationOptionsInstallNextInterval" : try(var.settings.patch.scan_next_interval, "false") } : {},
      try(var.settings.patch.target_type, "") != "" ? { "TargetType" : var.settings.patch.target_type } : {},
      try(var.settings.patch.target_type, "") != "InstanceIds" ? { "TargetInstances" : var.settings.patch.target_instances } : {},
      try(var.settings.patch.target_type, "") != "Tags" ? { "TargetTagKey" : var.settings.patch.target_tag_key } : {},
      try(var.settings.patch.target_type, "") != "Tags" ? { "TargetTagValue" : var.settings.patch.target_tag_value } : {},
      try(var.settings.patch.target_type, "") != "ResourceGroups" ? { "TargetResourceGroup" : var.settings.patch.resource_group_name } : {},
      try(var.settings.patch.target_organizational_units, "") != "" ? { "TargetOrganizationalUnits" : var.settings.patch.target_organizational_units } : {}, #Comma separated list of OU IDs }
      try(var.settings.patch.target_accounts, "") != "" ? { "TargetAccounts" : var.settings.patch.target_accounts } : {},                                    #Comma separated list of account IDs
      try(var.settings.patch.reboot_option, "") != "" ? { "RebootOption" : var.settings.patch.reboot_option } : {},
      try(var.settings.patch.is_policy_attach_allowed, "") != "" ? { "IsPolicyAttachAllowed" : var.settings.patch.is_policy_attach_allowed } : {},
      try(var.settings.patch.output_log_enable_s3, false) ? { "OutputLogEnableS3" : tostring(var.settings.patch.output_log_enable_s3) } : {},
      try(var.settings.patch.output_s3_location, "") != "" ? { "OutputS3Location" : var.settings.patch.output_s3_location } : {},
      try(var.settings.patch.output_s3_bucket_region, "") != "" ? { "OutputS3BucketRegion" : var.settings.patch.output_s3_bucket_region } : {},
      try(var.settings.patch.output_s3_bucket_name, "") != "" ? { "OutputS3BucketName" : var.settings.patch.output_s3_bucket_name } : {},
      try(var.settings.patch.output_s3_key_prefix, "") != "" ? { "OutputS3KeyPrefix" : var.settings.patch.output_s3_key_prefix } : {},
      { "TargetRegions" : try(var.settings.patch.target_regions, data.aws_region.current.region), }
    )
  }
  tags = local.all_tags
}