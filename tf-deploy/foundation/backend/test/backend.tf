# Initialisation parameters 

# Backend Storage account details
#tenant_id       = "" # Tenant ID where terraform remote state Storage Account exists
subscription_id = "2301e9c5-b046-4805-ae2e-366cb7176d9f" # Subscription ID where the remote state container lives

resource_group_name  = "rg-devops-prd"   # Resource Group where the Terraform remote state storage account lives.
storage_account_name = "stimtfstatestoreuks01" # The name of the Storage Account used for terraform remote state.
container_name       = "tfstate"               # Name of the blob container used for the terraform remote state blobs
key                  = "terraformTest.terraform.tfstate" # Name to assign to the remote state file (blob).