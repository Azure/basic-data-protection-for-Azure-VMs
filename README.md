
# (Private Preview) Basic backup protection for Azure Virtual machines (VMs)

We are introducing **basic policy** capability which will allow VM to be backed up once every day achieving an RPO of approximately 24 hours.
The restore points created will be multi-disks crash consistent restore points.
> **Note** Restore points created in your subscription. Pricing: ~$ 0.05/GB per month. This dependent on snapshot cost in the region. Please check pricing [here](https://azure.microsoft.com/pricing/details/managed-disks/).

## Pre-requisites

Pre-requisite    |    Description
-|-
Sign up for preview    |    Sign-up for the preview via this [form](https://aka.ms/VMBasicProtectionPreview). You will receive an email notification once you are enrolled for the preview. It usually takes 5 business days.
Single instance VMs    |    VMs which are not associated with [VM scale sets (Uniform or Flex)](https://learn.microsoft.com/azure/virtual-machine-scale-sets/overview).
Supported regions    |    East Asia, UK South, North Europe and West Central US (Rest by Feb 2026)
VM size family should support premium storage.    |    See command below

**Check Premium Storage support:**

```powershell
(Get-AzComputeResourceSku -Location "eastus" | Where-Object { $_.ResourceType -eq 'virtualMachines' -and $_.Name -eq 'Standard_D2s_v3' }).Capabilities | Where-Object { $_.Name -eq 'PremiumIO' } | Select-Object -ExpandProperty Value
```

## Currently unsupported configurations

Configuration | Supported
-|-
[Premium Storage](https://learn.microsoft.com/azure/virtual-machines/premium-storage-performance)    |    Supported
[Premium Storage caching](https://learn.microsoft.com/azure/virtual-machines/premium-storage-performance)    |    Supported
[Live Migration](https://learn.microsoft.com/azure/virtual-machines/maintenance-and-updates)    |    Supported
[Accelerated Networking](https://learn.microsoft.com/azure/virtual-network/create-vm-accelerated-networking-cli)    |    Supported
[Ephemeral OS Disk](https://learn.microsoft.com/azure/virtual-machines/ephemeral-os-disks)    |    Not Supported
[Write accelerator](https://learn.microsoft.com/azure/virtual-machines/how-to-enable-write-accelerator)    |    Not Supported
[Shared disk](https://learn.microsoft.com/azure/virtual-machines/disks-shared)    |    Not Supported
[VM scale sets (Uniform or Flex)](https://learn.microsoft.com/azure/virtual-machine-scale-sets/overview)    |    Not Supported
[Premium SSD v2 disks](https://learn.microsoft.com/azure/virtual-machines/disks-deploy-premium-v2?tabs=azure-cli)    |    Not Supported
[Ultra SSD disks](https://learn.microsoft.com/azure/virtual-machines/disks-enable-ultra-ssd?tabs=azure-portal)    |    Not Supported

## Get started

In this preview customers will be able to enable a basic backup policy on existing/new virtual machine that meet the supported configurations.

## Existing VM steps

### Option 1: Using PowerShell Script (Recommended)

> **IMPORTANT DISCLAIMER**
>
> This script is not supported under any Microsoft standard support program or service.
>
> This script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
>
> The entire risk arising out of the use or performance of the script and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the script be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.
>
> We provide a PowerShell script wrapper that simplifies enabling/disabling basic backup protection.

#### Prerequisites

- Azure PowerShell module (Az.Accounts) installed

  ```powershell
  Install-Module -Name Az.Accounts -Scope CurrentUser
  ```

- Authenticated to Azure

  ```powershell
  Connect-AzAccount
  ```

#### Step-by-step Instructions

1. **Download the script**: Download the `Enable-BasicVMBackup.ps1` script from this repository.

2. **Run the script to enable basic backup protection**

   ```powershell
   .\Enable-BasicVMBackup.ps1 `
       -SubscriptionId "your-subscription-id" `
       -ResourceGroupName "your-resource-group" `
       -VMName "your-vm-name" `
       -Location "eastasia" `
       -Enable $true
   ```

   **Supported regions:** `eastasia`, `uksouth`, `northeurope`, `uswestcentral`

3. **Verify restore points are being created**

   - The first restore point can be created 3–6 hours after enabling
   - Navigate to your VM in Azure Portal → Restore Points to verify
   - Retention: max 10 restore points, frequency: 24 hours

4. **Disable basic backup protection when done testing**

   ```powershell
   .\Enable-BasicVMBackup.ps1 `
       -SubscriptionId "your-subscription-id" `
       -ResourceGroupName "your-resource-group" `
       -VMName "your-vm-name" `
       -Location "eastasia" `
       -Enable $false
   ```

5. **Clean up restore points**

   - After disabling, manually delete the restore points from your subscription to avoid incurring additional costs
   - Navigate to the VM → Restore Points in Azure Portal and delete existing restore points

#### Script Parameters

| Parameter | Required | Description | Valid Values |
|-----------|----------|-------------|--------------|
| SubscriptionId | Yes | Azure subscription ID | Any valid subscription GUID |
| ResourceGroupName | Yes | Resource group containing the VM | Any existing resource group |
| VMName | Yes | Virtual machine name | Any existing VM name |
| Location | Yes | Azure region where VM is located | eastasia, uksouth, northeurope, westcentralus |
| Enable | Yes | Enable or disable basic backup | $true or $false |

### Option 2: Using REST API Directly

For users who prefer direct REST API calls, follow these detailed steps.

#### Prerequisites

- Azure CLI installed ([Download here](https://learn.microsoft.com/cli/azure/install-azure-cli))
- Authenticated to Azure

  ```bash
  az login
  ```

#### Step-by-step Instructions

1. **Get an access token**

   ```bash
   az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
   ```

   Save this token for use in the API requests.

2. **Set your variables**

   ```bash
   SUBSCRIPTION_ID="your-subscription-id"
   RESOURCE_GROUP="your-resource-group"
   VM_NAME="your-vm-name"
   LOCATION="eastasia"  # or uksouth, northeurope, westcentralus
   ACCESS_TOKEN="your-access-token-from-step-1"
   ```

3. **Enable basic backup protection**

   **Using curl:**

   ```bash
   curl -X PATCH \
     "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}?api-version=2025-04-01" \
     -H "Authorization: Bearer ${ACCESS_TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{
       "location": "'"${LOCATION}"'",
       "properties": {
         "resiliencyProfile": {
           "periodicRestorePoints": {
             "isEnabled": true
           }
         }
       }
     }'
   ```

   **Using PowerShell:**

   ```powershell
   $token = (az account get-access-token --resource https://management.azure.com --query accessToken -o tsv)
   $uri = "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$($VM_NAME)?api-version=2025-04-01"
   $headers = @{
       "Authorization" = "Bearer $token"
       "Content-Type" = "application/json"
   }
   $body = @{
       location = "$LOCATION"
       properties = @{
           resiliencyProfile = @{
               periodicRestorePoints = @{
                   isEnabled = $true
               }
           }
       }
   } | ConvertTo-Json -Depth 10

   Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $body
   ```

4. **Verify restore points are being created**

   - The first restore point can be created 3–6 hours after enabling
   - Navigate to your VM in Azure Portal → Restore Points to verify

5. **Disable basic backup protection when done testing**

   **Using curl:**

   ```bash
   curl -X PATCH \
     "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}?api-version=2025-04-01" \
     -H "Authorization: Bearer ${ACCESS_TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{
       "location": "'"${LOCATION}"'",
       "properties": {
         "resiliencyProfile": {
           "periodicRestorePoints": {
             "isEnabled": false
           }
         }
       }
     }'
   ```

   **Using PowerShell:**

   ```powershell
   $body = @{
       location = "$LOCATION"
       properties = @{
           resiliencyProfile = @{
               periodicRestorePoints = @{
                   isEnabled = $false
               }
           }
       }
   } | ConvertTo-Json -Depth 10

   Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $body
   ```

6. **Clean up restore points**

   - After disabling, manually delete the restore points from your subscription to avoid incurring additional costs
   - Navigate to the VM → Restore Points in Azure Portal and delete existing restore points

#### API Reference

**API Version:** `2025-04-01`

**Endpoint:**

```http
PATCH https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Compute/virtualMachines/{vmName}?api-version=2025-04-01
```

**Headers:**

```json
Authorization: Bearer {access-token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "location": "eastasia",
  "properties": {
    "resiliencyProfile": {
      "periodicRestorePoints": {
        "isEnabled": true
      }
    }
  }
}
```

### Important Notes

- The first RP can be created 3–6 hours once enabled.
- Retention max = 10 (will be 5 in public preview), frequency = 24 hours.

> **Note**: The frequency and retention will not be editabled by customers. Please let us know if you have any concerns over this in our feedback [form](https://forms.office.com/r/XHgDNb8zi1).

- Please complete the steps below after verifying that restore points are being created at the expected intervals and cleaned up to avoid incurring additional costs.
  - Please clean up the restore points created in your subscription.
  - To turn off the feature please use the PowerShell script or PATCH API and set it to false so as not to incur cost.

## Feedback

Please fill up this feedback [form](https://forms.office.com/r/XHgDNb8zi1) as you try out the preview. Your feedback is crucial to help us improve our product.

## Comparison between Azure Backup policies and Basic data protection

| Feature | Standard/Enhanced | Basic |
|--------|-------------------|-------|
| Used for | Infra + Cyber + Data resiliency | Data resiliency |
| Target Users | Enterprises, regulated industries | SMB, SMC, cost conscious workloads |
| Scope | Full VM, file/app consistent | VM with supported disks |
| Consistency | App-consistent and/or crash-consistent | Crash-consistent only |
| RPO | 4-12 hrs (Enhanced), 24 hrs (Standard) | 24 hrs |
| Retention | Days-years | Fixed 5 days |
| Pricing | Vault-based + license | Snapshot (~$0.05/GB/mo) |
