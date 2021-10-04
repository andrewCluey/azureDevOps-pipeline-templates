# Initialisation parameters 

# Backend Storage account details
#tenant_id       = "" # Tenant ID where terraform remote state Storage Account exists
subscription_id = "blahblahblah" # Subscription ID where the remote state container lives

resource_group_name  = "rg-devops-prd"   # Resource Group where the Terraform remote state storage account lives.
storage_account_name = "storageaccountname00001" # The name of the Storage Account used for terraform remote state.
container_name       = "tfstate"               # Name of the blob container used for the terraform remote state blobs
key                  = "demopipeline.terraform.tfstate" # Name to assign to the remote state file (blob).
