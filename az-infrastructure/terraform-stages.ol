# Default parameter values.
parameters:
  environment: dev
  environmentDisplayName: Development
  workingDirectory: tf-deploy/foundation
  deploymentName: terraformDev
  destructionPlanOutputName : destructionPlan_$(Build.BuildNumber).tfplan
  terraformVersion: '1.0.0'
  anyTfChanges: false
  tfvarsPath: ../environments/dev/environment.tfvars
  terraformStateStorageAccountUri: https://stimtfstatestoreuks01.blob.core.windows.net/tfplan/
  backendPath: ./backend/dev/backend.tf     # Terarform backend config file is located in the Terraform configuration repo'.
  addDestructionStep: false
  artifactName: $(Build.BuildNumber)
  dependsOn: []

stages:
# deployment Stage
- stage: ${{ parameters.environment }}_deployment
  displayName: Deploy to ${{ parameters.environmentDisplayName }}
  dependsOn: ${{ parameters.dependsOn  }}
  jobs:
    # Validate Terraform code using Terrascan (Static Security Scan) & terraform validate (Syntax validation)
    - job: Validate
      timeoutInMinutes: 60
      continueOnError: false
      steps:
      - task: CmdLine@2
        displayName: "Show environment variables"
        inputs:
          script: printenv
      - task: TerraformInstaller@0
        displayName: 'install Terraform'
        inputs:
          terraformVersion: ${{ parameters.terraformVersion }}
      - bash: |
          curl --location https://github.com/accurics/terrascan/releases/download/v1.4.0/terrascan_1.4.0_Linux_x86_64.tar.gz --output terrascan.tar.gz
          tar xzf terrascan.tar.gz
          sudo install terrascan /usr/local/bin
          terrascan version
        displayName:      'Install Terrascan'
        workingDirectory: ${{ parameters.workingDirectory }}
      - bash: |
          terrascan scan -v
          scan = terrascan scan -v
          echo "##vso[task.setvariable variable=Terrascan_output;]$scan"
        displayName:     'Run security scan'
        workingDirectory: ${{ parameters.workingDirectory }}
      
      - bash: |
          find $(Build.SourcesDirectory)/ -type f -name '*.tf' -exec sed -i 's~git::https://dev.azure.com~git::https://pat:$(System.AccessToken)@dev.azure.com~g' {} \;
        displayName: 'Token Replace'
      
      - bash: |
          terraform fmt
          terraform init -backend=false
          terraform validate
        displayName:     'Terraform Validate'
        workingDirectory: ${{ parameters.workingDirectory }}

# Publish the Terraform configuration as a DevOps Artifact
    - job: 'publishArtifact'
      dependsOn: Validate
      steps:
      - task: CopyFiles@2
        displayName: 'Copy Files to: $(build.artifactstagingdirectory)'
        inputs:
          TargetFolder: '$(build.artifactstagingdirectory)'
      - task: PublishBuildArtifacts@1
        displayName: 'Publish Artifact ${{ parameters.environment }}-${{ parameters.deploymentName }}-${{ parameters.artifactName }}'
        inputs:
          ArtifactName: '${{ parameters.environment }}-${{ parameters.deploymentName }}-${{ parameters.artifactName }}'

# Plan the terraform deployment using 'terraform plan'
    - job: 'Plan'
      dependsOn: publishArtifact
      steps:
      - task: TerraformInstaller@0
        displayName: 'Install Terraform'
        inputs:
          terraformVersion: ${{ parameters.terraformVersion }}
      - task: DownloadPipelineArtifact@2
        displayName: 'Download Terraform configuration Artifact'
        inputs:
          buildType:    'current'
          artifactName: ${{ parameters.environment }}-${{ parameters.deploymentName }}-${{ parameters.artifactName }}
          targetPath:   '$(Pipeline.Workspace)'
      
      - bash: |
          find $(Build.SourcesDirectory)/ -type f -name '*.tf' -exec sed -i 's~git::https://dev.azure.com~git::https://pat:$(System.AccessToken)@dev.azure.com~g' {} \;
        displayName: 'Token Replace'
      
      - task: CmdLine@2
        displayName: "Initialise Terraform deployment"
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            terraform init -var-file=${{ parameters.tfvarsPath }} -backend-config=${{ parameters.backendPath }}
      # Plan the deployment using the artifact generated previously to ensure consistency.
      - task: CmdLine@2
        displayName: 'Plan Terraform deployment'
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            terraform plan -var-file=${{ parameters.tfvarsPath }} -out=${{ parameters.planOutputName }}
      - task: CmdLine@2
        displayName: 'Copy TF plan output to blob'
        env:
          AZCOPY_SPA_CLIENT_SECRET: ${{ parameters.sp_client_secret }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            azcopy login --tenant-id ${{ parameters.tenant_id }} --service-principal --application-id ${{ parameters.sp_client_id }}
            azcopy copy ${{parameters.planOutputName }} ${{ parameters.terraformStateStorageAccountUri }}${{ parameters.planOutputName }}
      # PowerShell script to check the TFPlanOutput for any changes. If TRUE, then set variable ('anyTfChanges').
      - task: PowerShell@2
        name: checkChanges
        displayName: 'Check the tfplan file for any changes to the deployment.'
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
          OUTPUT: ${{ parameters.planOutputname }}
          tfvarsPath: ${{ parameters.tfvarsPath }}
          backendPath: ${{ parameters.backendPath }}
        inputs:
          pwsh: true
          workingDirectory: ${{ parameters.workingDirectory }}
          targetType: 'inline'
          script: |
            terraform init -var-file=$Env:tfvarsPath
            write-host "plan file is $Env:OUTPUT"
            $plan = $(terraform show -json $Env:OUTPUT | ConvertFrom-Json)
            $actions = $plan.resource_changes.change.actions
            Write-Host "Terraform actions : $actions"
            if (($actions -contains 'create') -or ($actions -contains 'delete') -or ($actions -contains 'update'))
            {
              Write-Host "Terraform will perform the following actions : $actions"
              Write-Host "##vso[task.setvariable variable=anyTfChanges;isOutput=true]true"
            }
            else
            {
              Write-Host "There is no change detected in Terraform tfplan file"
            }

# Manual Review to add a manual approval step before final Terraform deployment. 
# Conditional on the variable 'anyTfChanges' to equal TRUE.
    - job: ManualReview
      dependsOn: Plan  # 'Plan' job has to have complted and succeeded before this job can run.
      condition: eq(dependencies.Plan.outputs['checkChanges.anyTfChanges'], 'true')   # Changes in tfplanOutput must have been detected.
      displayName: 'Manual Review/approval to confirm deployment.'
      pool: server
      steps:
      - task: ManualValidation@0
        timeoutInMinutes: 1440
        inputs:
          notifyUsers: ''
          instructions: 'Please review the results of the Terraform plan and approve or reject the deployment of the Foundation infrastructure'

# Perform the Terraform deployment.
    - job: 'TerraformDeploy'
      dependsOn: 'ManualReview'  # Manual Review job must have succeeded (someone must have approved the deployment.)
      steps:
      - task: TerraformInstaller@0
        inputs:
          terraformVersion: ${{ parameters.terraformVersion }}
      # Copy the tfPlanOutput file from the blob container to the local agent VM. Ensures deployment matches what has been approved.
      - task: CmdLine@2
        displayName: 'Copy tfplan file FROM blob container'
        env:
          AZCOPY_SPA_CLIENT_SECRET: ${{ parameters.sp_client_secret }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            azcopy login --tenant-id ${{ parameters.tenant_id }} --service-principal --application-id ${{ parameters.sp_client_id }}
            azcopy copy ${{ parameters.terraformStateStorageAccountUri }}${{ parameters.planOutputName }} ${{parameters.planOutputName }}
      
      - bash: |
          find $(Build.SourcesDirectory)/ -type f -name '*.tf' -exec sed -i 's~git::https://dev.azure.com~git::https://pat:$(System.AccessToken)@dev.azure.com~g' {} \;
        displayName: 'Token Replace'
      
      - task: CmdLine@2
        displayName: "Initialise Terraform deployment"
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            terraform init -var-file=${{ parameters.tfvarsPath }} -backend-config=${{ parameters.backendPath }}
      # Perform Terraform deployment using the tfPlanOutput file.
      - task: CmdLine@2
        displayName: "Deploy configuration described in the tfplan file."
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            terraform apply ${{ parameters.planOutputName  }} 


- stage: ${{ parameters.environment }}_destruction
  displayName: 'Destroy ${{ parameters.environmentDisplayName }} infrastructure'
  dependsOn: ${{ parameters.environment  }}_deployment
  condition: eq('${{ parameters.addDestructionStep }}', true)
  jobs:
    - job: 'PlanDestroy'
      continueOnError: false
      steps:
      - task: TerraformInstaller@0
        name: installTf
        displayName: 'Install Terraform'
        inputs:
          terraformVersion: ${{ parameters.terraformVersion }} 
      - task: DownloadPipelineArtifact@2
        displayName: 'Download Terraform configuration Artifact'
        inputs:
          buildType:    'current'
          artifactName: ${{ parameters.environment }}-${{ parameters.deploymentName }}-${{ parameters.artifactName }}
          targetPath:   '$(Pipeline.Workspace)'
      - task: CmdLine@2
        name: initialiseTf
        displayName: "Initialise Terraform deployment"
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            terraform init -var-file=${{ parameters.tfvarsPath }} -backend-config=${{ parameters.backendPath }}
      - task: CmdLine@2
        name: planDestruction
        displayName: 'Plan Terraform destruction'
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            terraform plan -destroy -var-file=${{ parameters.tfvarsPath }} -out=${{ parameters.destructionPlanOutputName }}
      - task: CmdLine@2
        name: copyDestructionPlanToBlob
        displayName: 'Copy TF destruction plan output to blob'
        env:
          AZCOPY_SPA_CLIENT_SECRET: ${{ parameters.sp_client_secret }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            echo ${{ parameters.terraformStateStorageAccountUri }}${{ parameters.destructionPlanOutputName }}
            azcopy login --tenant-id ${{ parameters.tenant_id }} --service-principal --application-id ${{ parameters.sp_client_id }}
            azcopy copy ${{ parameters.destructionPlanOutputName }} ${{ parameters.terraformStateStorageAccountUri }}${{ parameters.destructionPlanOutputName }}
      # PowerShell script to check the TFPlanOutput for any changes. If TRUE, then set variable ('anyTfChanges').
      - task: PowerShell@2
        name: checkChanges
        displayName: 'Check the tfplan to see if there is anything to destroy.'
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
          OUTPUT: ${{ parameters.destructionPlanOutputName }}
          tfvarsPath: ${{ parameters.tfvarsPath }}
          backendPath: ${{ parameters.backendPath }}
        inputs:
          pwsh: true
          workingDirectory: ${{ parameters.workingDirectory }}
          targetType: 'inline'
          script: |
            terraform init -var-file=$Env:tfvarsPath
            write-host "plan file is $Env:OUTPUT"
            $plan = $(terraform show -json $Env:OUTPUT | ConvertFrom-Json)
            $actions = $plan.resource_changes.change.actions
            Write-Host "Terraform actions : $actions"
            if (($actions -contains 'create') -or ($actions -contains 'delete') -or ($actions -contains 'update'))
            {
              Write-Host "Terraform will perform the following actions : $actions"
              Write-Host "##vso[task.setvariable variable=anyTfChanges;isOutput=true]true"
            }
            else
            {
              Write-Host "There is no change detected in Terraform tfplan file"
            }
            write-host "tf change variable is set to: ($anyTfChanges)"

    - job: destructionReview
      dependsOn: 'PlanDestroy'
      condition: eq(dependencies.PlanDestroy.outputs['checkChanges.anyTfChanges'], 'true')   # Changes to terraform config detected.
      displayName: 'Manual review & approval to confirm destruction.'
      pool: server
      steps:
      - task: ManualValidation@0
        timeoutInMinutes: 1440
        inputs:
          notifyUsers: ''
          instructions: 'Please review the desrtruction plan and approve the infrastructure destruction.'

    - job: 'TerraformDestroy'
      dependsOn: destructionReview
      condition: in(dependencies.destructionReview.result, 'Succeeded')
      steps:
      - task: TerraformInstaller@0
        inputs:
          terraformVersion: ${{ parameters.terraformVersion }}
      
      - task: CmdLine@2
        name: copyDestroyPlan
        displayName: 'Copy destruction plan file FROM blob container'
        env:
          AZCOPY_SPA_CLIENT_SECRET: ${{ parameters.sp_client_secret }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            azcopy login --tenant-id ${{ parameters.tenant_id }} --service-principal --application-id ${{ parameters.sp_client_id }}
            azcopy copy ${{ parameters.terraformStateStorageAccountUri }}${{ parameters.destructionPlanOutputName }} ${{ parameters.destructionPlanOutputName }}
      
      - task: CmdLine@2
        name: initialiseTfBackend
        displayName: "Initialise Terraform deployment"
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            terraform init -var-file=${{ parameters.tfvarsPath }} -backend-config=${{ parameters.backendPath }}

      - task: CmdLine@2
        name: destroy
        displayName: "destroy configuration as described in the tfplan file."
        env:
          ARM_CLIENT_ID:       ${{ parameters.sp_client_id }}
          ARM_CLIENT_SECRET:   ${{ parameters.sp_client_secret }}
          ARM_SUBSCRIPTION_ID: ${{ parameters.subscription_id }}
          ARM_TENANT_ID:       ${{ parameters.tenant_id }}
        inputs:
          workingDirectory: ${{ parameters.workingDirectory }}
          script: |
            terraform apply ${{ parameters.destructionPlanOutputName }}


