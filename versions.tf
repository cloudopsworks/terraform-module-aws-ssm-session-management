##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

terraform {
  required_version = ">= 1.3"
  # Complete with required providers for the module
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.35"
    }
    # Fleet Manager Remote Desktop recording preferences are only exposed through Cloud
    # Control; hashicorp/aws has no GUI Connect resource. 1.40 is the first release
    # carrying awscc_ssmguiconnect_preferences. Nothing is created from this provider
    # unless settings.fleet_manager.remote_desktop.recording is turned on.
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.40"
    }
  }
}
