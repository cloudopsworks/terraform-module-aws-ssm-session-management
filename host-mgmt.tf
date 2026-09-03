##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

##
# SSM Quick Setup configuration managers.
#
# These deploy Quick Setup configurations (Default Host Management, Host Management and
# Patch Policy) either into this account and Region or, when target organizational units
# are supplied, across the organization. Organization-wide deployments must be applied
# from the Quick Setup delegated administrator account -- the account registered by
# settings.organization, applied from the management account in delegation mode.
#
# Like the rest of the stack these are skipped in delegation mode, where the module
# only registers delegated administrators.
##
locals {
  quicksetup_enabled = !local.is_delegated

  dhmc_quicksetup_enabled            = local.quicksetup_enabled && try(var.settings.dhmc.enabled, false)
  host_management_quicksetup_enabled = local.quicksetup_enabled && try(var.settings.host_management.enabled, false)
  patch_quicksetup_enabled           = local.quicksetup_enabled && try(var.settings.patch.enabled, false)
}

##
# Target selection.
#
# TargetType selects which of the target parameters Quick Setup requires, and sending the
# ones that do not belong to the selected type is rejected. AWS also documents that
# TargetType must be left unset for deployments aimed at organizational units.
##
locals {
  host_management_target_type = try(var.settings.host_management.target_type, "")
  patch_target_type           = try(var.settings.patch.target_type, "")

  host_management_targets = merge(
    local.host_management_target_type != "" ? { "TargetType" : local.host_management_target_type } : {},
    local.host_management_target_type == "InstanceIds" ? { "TargetInstances" : try(var.settings.host_management.target_instances, "") } : {},
    local.host_management_target_type == "Tags" ? {
      "TargetTagKey" : try(var.settings.host_management.target_tag_key, ""),
      "TargetTagValue" : try(var.settings.host_management.target_tag_value, ""),
    } : {},
    local.host_management_target_type == "ResourceGroups" ? { "ResourceGroupName" : try(var.settings.host_management.resource_group_name, "") } : {},
    # Comma separated list of OU IDs.
    try(var.settings.host_management.target_organizational_units, "") != "" ? { "TargetOrganizationalUnits" : var.settings.host_management.target_organizational_units } : {},
    # Comma separated list of account IDs.
    try(var.settings.host_management.target_accounts, "") != "" ? { "TargetAccounts" : var.settings.host_management.target_accounts } : {},
    { "TargetRegions" : try(var.settings.host_management.target_regions, data.aws_region.current.region) },
  )

  patch_targets = merge(
    local.patch_target_type != "" ? { "TargetType" : local.patch_target_type } : {},
    local.patch_target_type == "InstanceIds" ? { "TargetInstances" : try(var.settings.patch.target_instances, "") } : {},
    local.patch_target_type == "Tags" ? {
      "TargetTagKey" : try(var.settings.patch.target_tag_key, ""),
      "TargetTagValue" : try(var.settings.patch.target_tag_value, ""),
    } : {},
    local.patch_target_type == "ResourceGroups" ? { "ResourceGroupName" : try(var.settings.patch.resource_group_name, "") } : {},
    # Comma separated list of OU IDs.
    try(var.settings.patch.target_organizational_units, "") != "" ? { "TargetOrganizationalUnits" : var.settings.patch.target_organizational_units } : {},
    # Comma separated list of account IDs.
    try(var.settings.patch.target_accounts, "") != "" ? { "TargetAccounts" : var.settings.patch.target_accounts } : {},
    { "TargetRegions" : try(var.settings.patch.target_regions, data.aws_region.current.region) },
  )
}

##
# Patch baselines.
#
# SelectedPatchBaselines is a required parameter of the patch policy type, so it is keyed
# off the patch toggle rather than any of the other blocks.
##
locals {
  patch_operation = try(var.settings.patch.operation, "Scan")

  # transform the output of the aws_ssm_patch_baselines data source
  # into the format expected by the SelectedPatchBaselines parameter
  selected_patch_baselines = local.patch_quicksetup_enabled ? jsonencode({
    for baseline in data.aws_ssm_patch_baselines.this[0].baseline_identities : baseline.operating_system => {
      "value" : baseline.baseline_id
      "label" : baseline.baseline_name
      "description" : baseline.baseline_description
      "disabled" : !baseline.default_baseline
    }
  }) : ""

  # Scan runs on both operations; the install schedule is only accepted by ScanAndInstall.
  patch_schedule = merge(
    {
      "ConfigurationOptionsScanValue" : try(var.settings.patch.scan_value, "cron(0 1 * * ? *)"),
      "ConfigurationOptionsScanNextInterval" : tostring(try(var.settings.patch.scan_next_interval, false)),
    },
    local.patch_operation == "ScanAndInstall" ? {
      "ConfigurationOptionsInstallValue" : try(var.settings.patch.install_value, try(var.settings.patch.scan_value, "cron(0 1 * * ? *)")),
      "ConfigurationOptionsInstallNextInterval" : tostring(try(var.settings.patch.install_next_interval, false)),
    } : {},
  )

  # Command output logging is off unless a destination bucket is actually named.
  patch_output_logs = try(var.settings.patch.output_s3_bucket_name, "") != "" ? merge(
    {
      "OutputLogEnableS3" : "true",
      "OutputS3BucketName" : var.settings.patch.output_s3_bucket_name,
      "OutputBucketRegion" : try(var.settings.patch.output_s3_bucket_region, data.aws_region.current.region),
    },
    try(var.settings.patch.output_s3_key_prefix, "") != "" ? { "OutputS3KeyPrefix" : var.settings.patch.output_s3_key_prefix } : {},
  ) : { "OutputLogEnableS3" : "false" }
}

data "aws_ssm_patch_baselines" "this" {
  count             = local.patch_quicksetup_enabled ? 1 : 0
  default_baselines = try(var.settings.patch.default_baselines, true)
}

resource "aws_ssmquicksetup_configuration_manager" "dhmc" {
  count       = local.dhmc_quicksetup_enabled ? 1 : 0
  name        = "${local.system_name}-dhmc"
  description = "SSM Quick Setup Configuration Manager for Default Host Management Configuration ${local.system_name}"

  configuration_definition {
    type = "AWSQuickSetupType-DHMC"
    parameters = {
      "UpdateSsmAgent" : tostring(try(var.settings.dhmc.update_ssm_agent, true)),
      # Comma separated list of OU IDs.
      "TargetOrganizationalUnits" : var.settings.dhmc.target_organizational_units,
      "TargetRegions" : try(var.settings.dhmc.target_regions, data.aws_region.current.region),
    }
  }

  tags = local.all_tags
}

resource "aws_ssmquicksetup_configuration_manager" "host" {
  count       = local.host_management_quicksetup_enabled ? 1 : 0
  name        = "${local.system_name}-hostmgmt"
  description = "SSM Quick Setup Configuration Manager for Host Management ${local.system_name}"

  configuration_definition {
    type = "AWSQuickSetupType-SSMHostMgmt"
    parameters = merge({
      "UpdateSsmAgent" : tostring(try(var.settings.host_management.update_ssm_agent, true)),
      "UpdateEc2LaunchAgent" : tostring(try(var.settings.host_management.update_ec2_launch_agent, false)),
      "CollectInventory" : tostring(try(var.settings.host_management.collect_inventory, true)),
      "ScanInstances" : tostring(try(var.settings.host_management.scan_instances, true)),
      "InstallCloudWatchAgent" : tostring(try(var.settings.host_management.install_cloudwatch_agent, false)),
      "UpdateCloudWatchAgent" : tostring(try(var.settings.host_management.update_cloudwatch_agent, false)),
      "IsPolicyAttachAllowed" : tostring(try(var.settings.host_management.is_policy_attach_allowed, false)),
      },
      local.host_management_targets,
    )
  }

  tags = local.all_tags
}

resource "aws_ssmquicksetup_configuration_manager" "patch" {
  count       = local.patch_quicksetup_enabled ? 1 : 0
  name        = "${local.system_name}-patch"
  description = "SSM Quick Setup Configuration Manager for Patch Policy ${local.system_name}"

  configuration_definition {
    # A patch policy always needs the local deployment roles, for single account and
    # organization deployments alike. Quick Setup creates them the first time a patch
    # policy is configured in the account.
    local_deployment_administration_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/AWS-QuickSetup-PatchPolicy-LocalAdministrationRole"
    local_deployment_execution_role_name     = "AWS-QuickSetup-PatchPolicy-LocalExecutionRole"
    type                                     = "AWSQuickSetupType-PatchPolicy"

    parameters = merge({
      "ConfigurationOptionsPatchOperation" : local.patch_operation,
      "PatchBaselineRegion" : try(var.settings.patch.baseline_region, data.aws_region.current.region),
      "PatchBaselineUseDefault" : try(var.settings.patch.baseline_use, "default"),
      "PatchPolicyName" : try(var.settings.patch.policy_name, local.system_name_short),
      "SelectedPatchBaselines" : local.selected_patch_baselines,
      "RateControlConcurrency" : try(var.settings.patch.rate_control_concurrency, "10%"),
      "RateControlErrorThreshold" : try(var.settings.patch.rate_control_error_threshold, "2%"),
      "IsPolicyAttachAllowed" : tostring(try(var.settings.patch.is_policy_attach_allowed, false)),
      },
      local.patch_schedule,
      local.patch_output_logs,
      try(var.settings.patch.reboot_option, "") != "" ? { "RebootOption" : var.settings.patch.reboot_option } : {},
      local.patch_targets,
    )
  }

  tags = local.all_tags
}
