
# (Private Preview) Basic data protection for Azure Virtual machines (VMs)

We are introducing **Basic data protection - Lightweight VM resiliency for everyday workloads—providing basic protection that keeps business continuity simple and cost effective**.

## Key features

Feature | Description
-|-
Cost advantage | Pay only for snapshot storage, [Pricing](https://azure.microsoft.com/pricing/details/managed-disks/): ~$ 0.05/GB per month, no extra licensing or support fees
Recovery point objective (RPO) | Rapid recovery with up to 24-hour Recovery Point Objective (RPO)
Consistency | Multi-disks Crash-consistent snapshots for VM configuration and attached disks
Retention | 5-day retention with automatic pruning
Sovereignty | Restore points created in your subscription.

## Pre-requisites

Pre-requisite    |    Description
-|-
Sign up for preview    |    Sign-up for the preview via this [form](https://aka.ms/VMBasicProtectionPreview). You will receive an email notification once you are enrolled for the preview. It usually takes 5 business days.
Single instance VMs    |    VMs which are not associated with [VM scale sets (Uniform or Flex)](https://learn.microsoft.com/azure/virtual-machine-scale-sets/overview).
Supported regions    |    East Asia, UK South, North Europe and West Central US (Remaining public cloud regions by end of Feb 2026)<sup>(1)</sup>
VM size family should support premium storage.<sup>(2)</sup>    |    See Azure PowerShell command below. Output `True` indicates support for premium storage.

> **NOTE**:
> 
> - <sup>(1)</sup> Support for government & sovereign cloud regions will be added in next release.
> - <sup>(2)</sup> Majority of VM size families will be supported in next release without dependency on premium storage.

**Check Premium Storage support:<sup>(2)</sup>**

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

- Azure PowerShell module (Az.Accounts, Az.Compute) installed

  ```powershell
  Install-Module -Name Az.Accounts, Az.Compute -Scope CurrentUser
  ```

- Authenticated to Azure

  ```powershell
  Connect-AzAccount
  ```

#### Step-by-step Instructions

1. **Download the script**: Download the [Enable-BasicVMBackup.ps1](./Enable-BasicVMBackup.ps1) script from this repository.

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

> **Note**: The frequency and retention will not be editabled by customers. Please let us know if you have any concerns over this in our [feedback form](https://aka.ms/VMBasicProtectionFeedback).

- Please complete the steps below after verifying that restore points are being created at the expected intervals and cleaned up to avoid incurring additional costs.
  - Please clean up the restore points created in your subscription.
  - To turn off the feature please use the PowerShell script or PATCH API and set it to false so as not to incur cost.

## Restore Existing VM from Restore Point

We provide a PowerShell orchestration script that automates the complete VM restore process from a restore point. This script handles all the manual steps required to restore disks and attach them to your VM in a single execution.

### Prerequisites

- Azure PowerShell module (Az.Accounts, Az.Compute) installed

  ```powershell
  Install-Module -Name Az.Accounts, Az.Compute -Scope CurrentUser
  ```

- Authenticated to Azure

  ```powershell
  Connect-AzAccount
  ```

- VM must have at least one restore point created (allow 3-6 hours after enabling Basic data protection)

### Step-by-step Instructions

1. **Download the script**: Download the [Restore-VMFromRestorePoint.ps1](./Restore-VMFromRestorePoint.ps1) script from this repository.

2. **Run the script to restore VM from latest restore point**

   ```powershell
   .\Restore-VMFromRestorePoint.ps1 `
       -SubscriptionId "your-subscription-id" `
       -ResourceGroupName "your-resource-group" `
       -VMName "your-vm-name"
   ```

   This will:
   - Automatically discover the restore point collection
   - Select the latest restore point
   - Restore all disks (OS and data disks) with "-restored" suffix
   - Deallocate the VM
   - Detach existing data disks
   - Attach restored data disks
   - Swap OS disk with restored OS disk
   - Start the VM

3. **Restore from a specific restore point**

   ```powershell
   .\Restore-VMFromRestorePoint.ps1 `
       -SubscriptionId "your-subscription-id" `
       -ResourceGroupName "your-resource-group" `
       -VMName "your-vm-name" `
       -RestorePointName "your-restore-point-name"
   ```

4. **Keep original disks after restore**

   ```powershell
   .\Restore-VMFromRestorePoint.ps1 `
       -SubscriptionId "your-subscription-id" `
       -ResourceGroupName "your-resource-group" `
       -VMName "your-vm-name" `
       -KeepOriginalDisks
   ```

5. **Preview changes without executing (WhatIf)**

   ```powershell
   .\Restore-VMFromRestorePoint.ps1 `
       -SubscriptionId "your-subscription-id" `
       -ResourceGroupName "your-resource-group" `
       -VMName "your-vm-name" `
       -WhatIf
   ```

### Script Parameters

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| SubscriptionId | Yes | Azure subscription ID | - |
| ResourceGroupName | Yes | Resource group containing the VM | - |
| VMName | Yes | Virtual machine name | - |
| RestorePointCollectionName | No | Restore point collection name (auto-discovered if not specified) | Auto-detected |
| RestorePointName | No | Specific restore point to use (uses latest if not specified) | Latest restore point |
| RestoredDiskSuffix | No | Suffix to append to restored disk names | "-restored" |
| KeepOriginalDisks | No | Keep original disks after restore (otherwise manual cleanup required) | $false |
| WhatIf | No | Show what would happen without making changes | - |

### Validation After Restore

After the script completes successfully, perform the following validation steps:

1. **Verify VM is running**

   ```powershell
   Get-AzVM -ResourceGroupName "your-resource-group" -Name "your-vm-name" -Status
   ```

   Check that the VM status is "VM running"

2. **Verify connectivity**

   - RDP (Windows) or SSH (Linux) to the VM
   - Ensure you can log in successfully

3. **Verify application functionality**

   - Test your applications running on the VM
   - Verify services are running as expected

4. **Verify data integrity**

   - Check that all required data is present
   - Verify database connections and data access
   - Test file system access on data disks

5. **Verify disk configuration**

   Check that all disks are attached correctly:

   ```powershell
   $vm = Get-AzVM -ResourceGroupName "your-resource-group" -Name "your-vm-name"
   
   # Check OS disk
   Write-Host "OS Disk: $($vm.StorageProfile.OsDisk.Name)"
   
   # Check data disks
   Write-Host "`nData Disks:"
   foreach ($disk in $vm.StorageProfile.DataDisks) {
       Write-Host "  LUN $($disk.Lun): $($disk.Name) - Caching: $($disk.Caching)"
   }
   ```

6. **Clean up original disks (if needed)**

   If the restore was successful and you didn't use `-KeepOriginalDisks`, you can delete the original disks to free up storage:

   ```powershell
   # List disks in the resource group
   Get-AzDisk -ResourceGroupName "your-resource-group" | 
       Where-Object { $_.Name -notlike "*-restored" } | 
       Select-Object Name, DiskSizeGB, DiskState
   
   # Delete a specific disk (only if not attached to any VM)
   Remove-AzDisk -ResourceGroupName "your-resource-group" -DiskName "original-disk-name" -Force
   ```

### Important Notes

- **Downtime**: The VM will experience downtime during the restore process (typically 5-15 minutes)
- **Zone Support**: The script automatically handles VMs in availability zones
- **Backup Original Disks**: Original disks are not automatically deleted. Clean them up manually after verifying the restore
- **Testing**: Always test the restore process in a non-production environment first
- **Snapshots**: Consider creating snapshots of current disks before performing a restore if you want an additional safety net

### Troubleshooting

**Issue**: Script cannot find restore point collection

**Solution**: Ensure Basic data protection is enabled and at least one restore point has been created (3-6 hours after enabling)

---

**Issue**: Disk attachment fails due to availability zone mismatch

**Solution**: The script automatically detects and applies the VM's availability zone. Ensure you're using the latest version of the script.

---

**Issue**: VM fails to start after restore

**Solution**: Check Azure Portal for specific error messages. Common issues include:
- Disk encryption settings mismatch
- Boot diagnostics configuration
- Network configuration issues

---

**Issue**: Original disks cannot be deleted

**Solution**: Ensure the disks are fully detached from the VM and no snapshots or other resources are using them.

## Feedback

Please fill up this [feedback form](https://aka.ms/VMBasicProtectionFeedback) as you try out the preview. Your feedback is crucial to help us improve our product.

## Comparison between Azure Backup policies and Basic data protection

Feature | Basic data protection | Azure Backup
-|-|-
Use case    |    Data resiliency    | Data + Infra + Cyber resiliency
Pricing    |    Snapshot (~$0.05/GB/mo), **40% cheaper than enterprise-grade backup solutions**    |    Vault license + Vault storage + Snapshot
Recovery point objective (RPO)    |    24 hours.    |    4 - 24 hours, multiple backups per day.
Retention    |    5 days.    |    7 days to 99 years.
Consistency    |    Crash-consistent only.    |    App & Crash consistent
Restore granularity    |    Disk-level restore    |    File / Disk / VM-level restore.
Supported resources    |    VM only    | VM, Azure Kubernetes (AKS), File storage, database.
Target workloads    | Workloads requiring basic backup with minimal cost and complexity    |    Workloads requiring enterprise-grade backup features

## Upgrade from Basic data protection to Azure Backup

As your protection requirements expand, you can seamlessly upgrade from Basic Data Protection to [Azure Backup](http://aka.ms/AzureBackup) for advanced capabilities:

**Enhanced Recovery Options**
- Multiple recovery points per day for lower RPO requirements
- Longer retention policies and lifecycle management aligned with compliance standards
- Application-consistent backups alongside crash-consistent snapshots

**Enterprise-Grade Security & Compliance**
- Integrated threat detection through Microsoft Defender for Cloud
- Malware and ransomware detection
- Cross-region restore capabilities for disaster recovery
- Compliance with industry-specific retention and governance policies

**Operational Flexibility**
- Support for multiple resource types (VMs, databases, file storage, Kubernetes)
- Granular file and application-level restore options
- Policy-driven backup management at scale

This approach allows infrastructure and backup administrators to start with cost-effective basic protection and expand to enterprise-grade solutions without reconfiguring their workloads, ensuring continuity as your infrastructure grows.
