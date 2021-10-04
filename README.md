# Introduction 
Pipeline templates

## terraform pipelines

There are several template files that can be used for terraform deployments.

The first and perhaps simplest, is the ```terraform-stages.yml``` template file.

This template contains all stages, jobs and tasks required to validate, plan, deploy and (if required) destroy an infrastrucutre using terraform.

To use this template, all that is required is to create a pipeline.yml file as follows:

```yml
pool:
  vmImage: 'ubuntu-20.04'
variables:
  - group: Dev-AzureFoundation-PipelineVars
  - group: ADO-PipelineInitialiser-SecureVariables


stages:
- template: az-infrastructure/terraform-stages.yml
  parameters:
    sp_client_id: $(foundationBuilderNonProdClientId)
    sp_client_secret: $(iac-foundation-builder-nonprod)
    subscription_id: $(IM-AZ-nonProd-Subscription)
    tenant_id: $(im-prod-tenant)
    environment: 'dev'
    environmentDisplayName: Development
    deploymentName: terraformDemo
    terraformVersion: '1.0.0'
    workingDirectory: tf-deploy/foundation
    tfvarsPath: ../environments/dev/environment.tfvars
    planOutputName: 'dev-terraformDemo-$(Build.BuildNumber).tfplan'
    backendPath: ./backend/dev/backend.tf
    addDestructionStep: true
    dependsOn: []
```

While there is an option to set a dependency using the ```dependsOn``` parameter, this is not necessary and is intended to be used in a multi-stage pipeline where the order in which the stages are run can be controlled.

If the parameter ```addDestructionStep``` is set to true, then a destruction plan will be performed along with a Manual Review job to check whether the infrastructure shoudl be destroyed. By default this parameter is set to ```false```, meaning the destrucion plan is not performed. 

### Separate deploy & destruction templates.

Templates also exist that separate out the deploy & destruction stages into their own templates. This can provide a little more flexibility when designing a deployment pipeline. However, it does mean manual dependencies have to be set, and also increases the amount of duplication required. See example below:

```yml
pool:
  vmImage: 'ubuntu-20.04'
variables:
  - group: Dev-AzureFoundation-PipelineVars
  - group: ADO-PipelineInitialiser-SecureVariables
  - name: devDeployment
    value: terraformDevDemo

stages:
# Dev Demo Deployment Stage
- template: az-infrastructure/terraform-planDeploy.yml
  parameters:
    stageName: devDemoDeployment
    sp_client_id: $(foundationBuilderNonProdClientId)   # Read from ADO-PipelineInitialiser-SecureVariables variable group
    sp_client_secret: $(iac-foundation-builder-nonprod) # Read from ADO-PipelineInitialiser-SecureVariables variable group
    subscription_id: $(IM-AZ-nonProd-Subscription)      # Read from ADO-PipelineInitialiser-SecureVariables variable group
    tenant_id: $(im-prod-tenant)                        # Read from ADO-PipelineInitialiser-SecureVariables variable group
    environment: 'dev'
    environmentDisplayName: Development
    deploymentName: ${{ variables.devDeployment }}
    terraformVersion: '1.0.0'
    workingDirectory: tf-deploy/foundation
    tfvarsPath: ../environments/dev/environment.tfvars
    planOutputName: 'dev-terraformDemo-$(Build.BuildNumber).tfplan'
    backendPath: ./backend/dev/backend.tf
    dependsOn: []

# Dev Demo Destruction Stage
- template: az-infrastructure/terraform-destroy.yml
  parameters:
    sp_client_id: $(foundationBuilderNonProdClientId)   # Read from ADO-PipelineInitialiser-SecureVariables variable group
    sp_client_secret: $(iac-foundation-builder-nonprod) # Read from ADO-PipelineInitialiser-SecureVariables variable group
    subscription_id: $(IM-AZ-nonProd-Subscription)      # Read from ADO-PipelineInitialiser-SecureVariables variable group
    tenant_id: $(im-prod-tenant)                        # Read from ADO-PipelineInitialiser-SecureVariables variable group
    environment: dev
    environmentDisplayName: Development
    workingDirectory: tf-deploy/foundation
    deploymentName: ${{ variables.devDeployment }}
    destructionPlanOutputName : destructionPlan_$(Build.BuildNumber).tfplan
    terraformVersion: '1.0.0'
    tfvarsPath: ../environments/dev/environment.tfvars
    terraformStateStorageAccountUri: https://stimtfstatestoreuks01.blob.core.windows.net/tfplan/
    backendPath: ./backend/dev/backend.tf  # Terarform backend config file from the Terraform configuration repo'.
    addDestructionStep: true
    artifactName: $(Build.BuildNumber)
    dependsOn: [devDemoDeployment]
```

Notice that in the stage where we call the destruction template, a dependency has been set to ensure the destruction does not run until the 'devDemoDeployment' stage has completed.

The examples above all refer to templates located in the same repository. In reality, this is unlikely to be the case. The section below explains how to utilise templates from different respositories.


### Cross repository templates

```yml
# Repo: Azure%20Platform/pipeline-templates
# File: terraform-stages.yml
resources:
  repositories:
    - repository: tfTemplates                   # Name to assign to this repo within this pipeline.
      type: git                                 # Repository type. Azure DevOps would be 'git'. Other options include github.
      name: 'Azure Platform/pipeline-templates' # <project>/<repo>

stages:
- template: az-infrastructure/terraform-stages.yml@tfTemplates
  parameters:
    sp_client_id: $(foundationBuilderNonProdClientId)
    sp_client_secret: $(iac-foundation-builder-nonprod)
    subscription_id: $(IM-AZ-nonProd-Subscription)
    tenant_id: $(im-prod-tenant)
    environment: 'dev'
    environmentDisplayName: Development
    deploymentName: terraformDemo
    terraformVersion: '1.0.0'
    workingDirectory: tf-deploy/foundation
    tfvarsPath: ../environments/dev/environment.tfvars
    planOutputName: 'dev-terraformDemo-$(Build.BuildNumber).tfplan'
    backendPath: ./backend/dev/backend.tf
    addDestructionStep: true
    dependsOn: []
```
