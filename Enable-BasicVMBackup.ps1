<#
    .NOTES
	============================================================================================================
	Copyright (c) Microsoft Corporation. All rights reserved.
	File:		Enable-BasicVMBackup.ps1
	Purpose:	Enable or disable basic backup protection for Azure VMs via Azure Management API
	Pre-Reqs:	Windows PowerShell version 7.2+ and Azure PowerShell Module version 12.2+ 
	Version: 	1.0.0
	============================================================================================================

	DISCLAIMER
	============================================================================================================
	This script is not supported under any Microsoft standard support program or service.

	This script is provided AS IS without warranty of any kind.
	Microsoft further disclaims all implied warranties including, without limitation, any
	implied warranties of merchantability or of fitness for a particular purpose.

	The entire risk arising out of the use or performance of the script
	and documentation remains with you. In no event shall Microsoft, its authors,
	or anyone else involved in the creation, production, or delivery of the
	script be liable for any damages whatsoever (including, without limitation,
	damages for loss of business profits, business interruption, loss of business
	information, or other pecuniary loss) arising out of the use of or inability
	to use the sample scripts or documentation, even if Microsoft has been
	advised of the possibility of such damages.
    ============================================================================================================

.SYNOPSIS
    Enable or disable basic backup protection for Azure Virtual Machines.

.DESCRIPTION
    This script enables or disables periodic restore points (basic backup) for Azure VMs
    using the Azure Management API version 2025-04-01.

.PARAMETER SubscriptionId
    The Azure subscription ID where the VM is located.

.PARAMETER ResourceGroupName
    The name of the resource group containing the VM.

.PARAMETER VMName
    The name of the virtual machine.

.PARAMETER Enable
    Boolean parameter. If $true, enables basic backup protection. If $false, disables it.

.EXAMPLE
    .\Enable-BasicVMBackup.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "myRG" -VMName "myVM" -Enable $true
    Enables basic backup protection for the specified VM.

.EXAMPLE
    .\Enable-BasicVMBackup.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "myRG" -VMName "myVM" -Enable $false
    Disables basic backup protection for the specified VM.

.NOTES
    - Requires Azure PowerShell modules (Az.Accounts, Az.Compute)
    - User must be authenticated to Azure before running this script
    - API Version: 2025-04-01
    - VM size must support Premium Storage
    - First restore point can be created 3-6 hours after enabling
    - Retention: max 10 restore points, frequency: 24 hours
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure subscription ID")]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true, HelpMessage = "Resource group name")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = "Virtual machine name")]
    [ValidateNotNullOrEmpty()]
    [string]$VMName,

    [Parameter(Mandatory = $true, HelpMessage = "Enable basic backup protection: true to enable, false to disable")]
    [bool]$Enable
)

# Set API version
$apiVersion = "2025-04-01"

# Check if required modules are available
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error "Az.Accounts module is not installed. Please install it using: Install-Module -Name Az.Accounts"
    exit 1
}

if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    Write-Error "Az.Compute module is not installed. Please install it using: Install-Module -Name Az.Compute"
    exit 1
}

# Import the modules
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop

# Check if user is logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged in to Azure. Please log in..." -ForegroundColor Yellow
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "Current subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
    
    # Set the context to the specified subscription
    if ($context.Subscription.Id -ne $SubscriptionId) {
        Write-Host "`nSwitching to subscription: $SubscriptionId" -ForegroundColor Yellow
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        $context = Get-AzContext
        Write-Host "Switched to subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to authenticate to Azure: $_"
    exit 1
}

# Get VM details and derive location
Write-Host "`nRetrieving VM information..." -ForegroundColor Yellow
try {
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
    $location = $vm.Location
    
    Write-Host "VM Name: $VMName" -ForegroundColor Gray
    Write-Host "VM Size: $($vm.HardwareProfile.VmSize)" -ForegroundColor Gray
    Write-Host "VM Location: $location" -ForegroundColor Gray
    Write-Host "✓ VM found" -ForegroundColor Green
} catch {
    Write-Error "Failed to retrieve VM details: $_"
    exit 1
}

# Validate supported region
$supportedRegions = @("eastasia", "uksouth", "northeurope", "westcentralus")
if ($location -notin $supportedRegions) {
    Write-Error "VM location '$location' is not supported. Supported regions: $($supportedRegions -join ', ')"
    Write-Host "`nPlease use a VM in one of the supported regions." -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ VM is in a supported region" -ForegroundColor Green

# Validate VM configuration when enabling
if ($Enable) {
    Write-Host "`nValidating VM configuration..." -ForegroundColor Yellow
    
    $validationErrors = @()
    
    # Check 1: VM size supports Premium Storage
    try {
        $capabilities = (Get-AzComputeResourceSku -Location $location | Where-Object { 
            $_.ResourceType -eq 'virtualMachines' -and $_.Name -eq $vm.HardwareProfile.VmSize 
        }).Capabilities
        
        $premiumIOSupported = ($capabilities | Where-Object { $_.Name -eq 'PremiumIO' }).Value
        
        if ($premiumIOSupported -ne 'True') {
            $validationErrors += "VM size '$($vm.HardwareProfile.VmSize)' does not support Premium Storage"
        } else {
            Write-Host "✓ VM size supports Premium Storage" -ForegroundColor Green
        }
    } catch {
        $validationErrors += "Failed to check Premium Storage support: $_"
    }
    
    # Check 2: Ephemeral OS disk
    if ($vm.StorageProfile.OsDisk.DiffDiskSettings -and $vm.StorageProfile.OsDisk.DiffDiskSettings.Option -eq 'Local') {
        $validationErrors += "VM is using Ephemeral OS disk (not supported)"
    } else {
        Write-Host "✓ VM is not using Ephemeral OS disk" -ForegroundColor Green
    }
    
    # Check 3: Write Accelerator on any disk
    $writeAccelEnabled = $false
    if ($vm.StorageProfile.OsDisk.WriteAcceleratorEnabled) {
        $writeAccelEnabled = $true
    }
    foreach ($dataDisk in $vm.StorageProfile.DataDisks) {
        if ($dataDisk.WriteAcceleratorEnabled) {
            $writeAccelEnabled = $true
            break
        }
    }
    if ($writeAccelEnabled) {
        $validationErrors += "VM is using Write Accelerator (not supported)"
    } else {
        Write-Host "✓ VM is not using Write Accelerator" -ForegroundColor Green
    }
    
    # Check 4: Shared disks
    $hasSharedDisks = $false
    foreach ($dataDisk in $vm.StorageProfile.DataDisks) {
        if ($dataDisk.ManagedDisk) {
            $diskDetails = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $dataDisk.Name -ErrorAction SilentlyContinue
            if ($diskDetails -and $diskDetails.MaxShares -gt 1) {
                $hasSharedDisks = $true
                break
            }
        }
    }
    if ($hasSharedDisks) {
        $validationErrors += "VM is using shared disks (not supported)"
    } else {
        Write-Host "✓ VM is not using shared disks" -ForegroundColor Green
    }
    
    # Check 5: Premium SSD v2 or Ultra disks
    $hasUnsupportedDiskTypes = $false
    $unsupportedDiskType = ""
    
    foreach ($dataDisk in $vm.StorageProfile.DataDisks) {
        if ($dataDisk.ManagedDisk) {
            $diskDetails = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $dataDisk.Name -ErrorAction SilentlyContinue
            if ($diskDetails) {
                if ($diskDetails.Sku.Name -eq 'PremiumV2_LRS') {
                    $hasUnsupportedDiskTypes = $true
                    $unsupportedDiskType = "Premium SSD v2"
                    break
                }
                if ($diskDetails.Sku.Name -like 'Ultra*') {
                    $hasUnsupportedDiskTypes = $true
                    $unsupportedDiskType = "Ultra disk"
                    break
                }
            }
        }
    }
    
    if ($hasUnsupportedDiskTypes) {
        $validationErrors += "VM is using $unsupportedDiskType (not supported - will be supported in public preview)"
    } else {
        Write-Host "✓ VM is not using Premium SSD v2 or Ultra disks" -ForegroundColor Green
    }
    
    # Check 6: VMSS association
    if ($vm.VirtualMachineScaleSet) {
        $validationErrors += "VM is part of a Virtual Machine Scale Set (not supported - Flex orchestration will be supported in public preview)"
    } else {
        Write-Host "✓ VM is not part of a VMSS" -ForegroundColor Green
    }
    
    # Report validation errors
    if ($validationErrors.Count -gt 0) {
        Write-Host "`n✗ Validation Failed" -ForegroundColor Red
        Write-Host "`nThe following configuration issues were found:" -ForegroundColor Red
        foreach ($singleError in $validationErrors) {
            Write-Host "  - $singleError" -ForegroundColor Red
        }
        Write-Host "`nPlease review the unsupported configurations in the documentation." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "`n✓ All validation checks passed" -ForegroundColor Green
}

# Build the API endpoint URL
$uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$VMName`?api-version=$apiVersion"

# Prepare the request body
$body = @{
    location = $location
    properties = @{
        resiliencyProfile = @{
            periodicRestorePoints = @{
                isEnabled = $Enable
            }
        }
    }
} | ConvertTo-Json -Depth 10

# Get access token
try {
    $token = Get-AzAccessToken -ResourceUrl "https://management.azure.com"
    
    # Handle both string and SecureString token types
    if ($token.Token -is [System.Security.SecureString]) {
        # Convert SecureString to plain text
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token.Token)
        $accessToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    } else {
        $accessToken = $token.Token
    }
} catch {
    Write-Error "Failed to get access token: $_"
    exit 1
}

# Prepare headers
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type" = "application/json"
}

# Display action
$action = if ($Enable) { "Enabling" } else { "Disabling" }
Write-Host "`n$action basic backup protection for VM: $VMName" -ForegroundColor Cyan
Write-Host "Subscription ID: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroupName"
Write-Host "Location: $location"
Write-Host "`nRequest Body:"
Write-Host $body -ForegroundColor Gray

# Execute the API call
if ($PSCmdlet.ShouldProcess($VMName, "$action basic backup protection")) {
    try {
        Write-Host "`nSending PATCH request to Azure Management API..." -ForegroundColor Yellow
        
        $response = Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $body -ContentType "application/json"
        
        Write-Host "`nSuccess!" -ForegroundColor Green
        Write-Host "Basic backup protection has been $(if ($Enable) { 'enabled' } else { 'disabled' }) for VM: $VMName" -ForegroundColor Green
        
        if ($Enable) {
            Write-Host "`nImportant Notes:" -ForegroundColor Yellow
            Write-Host "- The first restore point can be created 3-6 hours after enabling"
            Write-Host "- Retention: max 10 restore points, frequency: 24 hours"
            Write-Host "- Restore points are stored in your subscription"
            Write-Host "- Pricing: ~`$0.05/GB per month (snapshot cost)"
            Write-Host "- Remember to disable the feature when done testing to avoid costs"
        } else {
            Write-Host "`nImportant Notes:" -ForegroundColor Yellow
            Write-Host "- Please clean up existing restore points to avoid incurring additional costs"
        }
        
        Write-Host "`nResponse:"
        $response | ConvertTo-Json -Depth 10
        
    } catch {
        Write-Error "Failed to update VM configuration: $_"
        if ($_.ErrorDetails.Message) {
            Write-Host "`nError Details:" -ForegroundColor Red
            Write-Host $_.ErrorDetails.Message
        }
        exit 1
    }
}

Write-Host "`nOperation completed." -ForegroundColor Green
