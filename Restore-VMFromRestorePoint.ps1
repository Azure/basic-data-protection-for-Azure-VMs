<#
    .NOTES
	============================================================================================================
	Copyright (c) Microsoft Corporation. All rights reserved.
	File:		Restore-VMFromRestorePoint.ps1
	Purpose:	Restore all disks from a restore point and attach them to a VM
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
    Restore all disks from a VM restore point and attach them to the VM in a single operation.

.DESCRIPTION
    This script automates the complete restore process for Azure VMs from restore points created by
    Basic data protection. It handles:
    - Getting restore point collection and latest restore point
    - Identifying all disks in the restore point
    - Restoring all disks (OS and data disks)
    - De-allocating the VM
    - Detaching existing data disks
    - Attaching restored data disks
    - Swapping OS disk with restored OS disk
    - Starting the VM

.PARAMETER SubscriptionId
    The Azure subscription ID where the VM is located.

.PARAMETER ResourceGroupName
    The name of the resource group containing the VM.

.PARAMETER VMName
    The name of the virtual machine to restore.

.PARAMETER RestorePointCollectionName
    (Optional) The name of the restore point collection. If not provided, will search for collection with VM name.

.PARAMETER RestorePointName
    (Optional) The name of a specific restore point to use. If not provided, will use the latest restore point.

.PARAMETER RestoredDiskSuffix
    (Optional) Suffix to append to restored disk names. Default is "-restored".

.PARAMETER KeepOriginalDisks
    (Optional) If specified, original disks will not be deleted after successful restore.

.PARAMETER WhatIf
    (Optional) Shows what would happen if the script runs without actually making changes.

.EXAMPLE
    .\Restore-VMFromRestorePoint.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "myRG" -VMName "myVM"
    Restores the VM from the latest restore point in the default restore point collection.

.EXAMPLE
    .\Restore-VMFromRestorePoint.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "myRG" -VMName "myVM" -RestorePointName "rp-20250130-120000" -KeepOriginalDisks
    Restores the VM from a specific restore point and keeps the original disks.

.NOTES
    - Requires Azure PowerShell modules (Az.Accounts, Az.Compute)
    - User must be authenticated to Azure before running this script
    - VM will experience downtime during the restore process
    - Ensure you have sufficient permissions to modify VM and disk resources
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

    [Parameter(Mandatory = $false, HelpMessage = "Restore point collection name")]
    [string]$RestorePointCollectionName,

    [Parameter(Mandatory = $false, HelpMessage = "Specific restore point name to use")]
    [string]$RestorePointName,

    [Parameter(Mandatory = $false, HelpMessage = "Suffix to append to restored disk names")]
    [string]$RestoredDiskSuffix = "-restored",

    [Parameter(Mandatory = $false, HelpMessage = "Keep original disks after restore")]
    [switch]$KeepOriginalDisks
)

#region Helper Functions

function Write-StepHeader {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Yellow
}

function Write-Detail {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

#endregion

#region Pre-flight Checks

Write-StepHeader "STEP 0: Pre-flight Checks"

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
Write-Success "Required PowerShell modules loaded"

# Check if user is logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Info "Not logged in to Azure. Please log in..."
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-Success "Connected to Azure as: $($context.Account.Id)"
    Write-Detail "Current subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
    
    # Set the context to the specified subscription
    if ($context.Subscription.Id -ne $SubscriptionId) {
        Write-Info "Switching to subscription: $SubscriptionId"
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        $context = Get-AzContext
        Write-Success "Switched to subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
    }
} catch {
    Write-Error "Failed to authenticate to Azure: $_"
    exit 1
}

# Get VM details
Write-Info "Retrieving VM information..."
try {
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
    $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status -ErrorAction Stop
    $location = $vm.Location
    $vmZones = $vm.Zones
    
    Write-Detail "VM Name: $VMName"
    Write-Detail "VM Size: $($vm.HardwareProfile.VmSize)"
    Write-Detail "VM Location: $location"
    if ($vmZones -and $vmZones.Count -gt 0) {
        Write-Detail "VM Availability Zone: $($vmZones -join ', ')"
    } else {
        Write-Detail "VM Availability Zone: None (Regional)"
    }
    Write-Detail "VM Status: $(($vmStatus.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus)"
    Write-Success "VM found"
} catch {
    Write-Error "Failed to retrieve VM details: $_"
    exit 1
}

#endregion

#region Step 1: Get Restore Point Collection

Write-StepHeader "STEP 1: Get Restore Point Collection"

try {
    # If no collection name provided, discover all collections
    if ([string]::IsNullOrEmpty($RestorePointCollectionName)) {
        Write-Info "Discovering restore point collections in resource group: $ResourceGroupName"
        
        # Get all restore point collections in the resource group using Get-AzResource
        $allCollections = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Compute/restorePointCollections" -ErrorAction SilentlyContinue
        
        if (-not $allCollections -or $allCollections.Count -eq 0) {
            Write-Error "No restore point collections found in resource group: $ResourceGroupName"
            Write-Host "`nPlease ensure Basic data protection is enabled for the VM." -ForegroundColor Yellow
            exit 1
        }
        
        Write-Success "Found $($allCollections.Count) restore point collection(s)"
        
        if ($allCollections.Count -eq 1) {
            # Only one collection found - auto-select it
            $RestorePointCollectionName = $allCollections[0].Name
            $restorePointCollection = Get-AzRestorePointCollection -ResourceGroupName $ResourceGroupName -Name $RestorePointCollectionName -ErrorAction Stop
            Write-Success "Auto-selected the only available collection: $RestorePointCollectionName"
        } else {
            # Multiple collections found - find the one with the latest restore point
            Write-Info "Multiple collections found. Selecting collection with latest restore point..."
            
            $collectionsWithLatestRP = @()
            
            foreach ($collection in $allCollections) {
                Write-Detail "Checking collection: $($collection.Name)"
                
                try {
                    $restorePoints = Get-AzRestorePoint -ResourceGroupName $ResourceGroupName -RestorePointCollectionName $collection.Name -ErrorAction SilentlyContinue
                    
                    if ($restorePoints -and $restorePoints.Count -gt 0) {
                        $latestRP = $restorePoints | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1
                        
                        $collectionsWithLatestRP += [PSCustomObject]@{
                            CollectionName = $collection.Name
                            LatestRestorePoint = $latestRP
                            LatestRestorePointTime = $latestRP.TimeCreated
                            RestorePointCount = $restorePoints.Count
                        }
                        
                        Write-Detail "  Latest restore point: $($latestRP.Name) (Created: $($latestRP.TimeCreated))"
                    } else {
                        Write-Detail "  No restore points found in this collection"
                    }
                } catch {
                    Write-Detail "  Failed to retrieve restore points: $_"
                }
            }
            
            if ($collectionsWithLatestRP.Count -eq 0) {
                Write-Error "No restore points found in any restore point collection in resource group: $ResourceGroupName"
                exit 1
            }
            
            # Select the collection with the most recent restore point
            $selectedCollection = $collectionsWithLatestRP | Sort-Object -Property LatestRestorePointTime -Descending | Select-Object -First 1
            $RestorePointCollectionName = $selectedCollection.CollectionName
            $restorePointCollection = Get-AzRestorePointCollection -ResourceGroupName $ResourceGroupName -Name $RestorePointCollectionName -ErrorAction Stop
            
            Write-Success "Selected collection with latest restore point: $RestorePointCollectionName"
            Write-Detail "Latest restore point: $($selectedCollection.LatestRestorePoint.Name)"
            Write-Detail "Created: $($selectedCollection.LatestRestorePointTime)"
            Write-Detail "Total restore points in collection: $($selectedCollection.RestorePointCount)"
            
            if ($collectionsWithLatestRP.Count -gt 1) {
                Write-Host "`nOther available collections:" -ForegroundColor Yellow
                foreach ($col in ($collectionsWithLatestRP | Where-Object { $_.CollectionName -ne $RestorePointCollectionName })) {
                    Write-Host "  - $($col.CollectionName) (Latest RP: $($col.LatestRestorePointTime))" -ForegroundColor Gray
                }
            }
        }
    } else {
        # Collection name was provided
        $restorePointCollection = Get-AzRestorePointCollection -ResourceGroupName $ResourceGroupName -Name $RestorePointCollectionName -ErrorAction Stop
        Write-Success "Restore point collection found: $RestorePointCollectionName"
    }
    
    Write-Detail "Collection ID: $($restorePointCollection.Id)"
    
} catch {
    Write-Error "Failed to get restore point collection: $_"
    exit 1
}

#endregion

#region Step 2: Get Latest Restore Point

Write-StepHeader "STEP 2: Get Latest Restore Point"

try {
    if ([string]::IsNullOrEmpty($RestorePointName)) {
        Write-Info "Retrieving all restore points from collection: $RestorePointCollectionName"
        
        # Use REST API to get restore point collection with expanded restore points
        $apiVersion = "2024-07-01"
        
        # URL encode the resource group and collection names to handle special characters
        $encodedResourceGroup = [System.Uri]::EscapeDataString($ResourceGroupName)
        $encodedCollectionName = [System.Uri]::EscapeDataString($RestorePointCollectionName)
        
        $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$encodedResourceGroup/providers/Microsoft.Compute/restorePointCollections/$encodedCollectionName`?api-version=$apiVersion&`$expand=restorePoints"
        
        Write-Detail "API URL: $uri"
        
        # Get access token
        $token = Get-AzAccessToken -ResourceUrl "https://management.azure.com"
        
        # Handle both string and SecureString token types
        if ($token.Token -is [System.Security.SecureString]) {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token.Token)
            $accessToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        } else {
            $accessToken = $token.Token
        }
        
        # Prepare headers
        $headers = @{
            "Authorization" = "Bearer $accessToken"
            "Content-Type" = "application/json"
        }
        
        # Call the API
        Write-Detail "Calling REST API to get restore point collection with restore points..."
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ContentType "application/json"
        
        if (-not $response.properties.restorePoints -or $response.properties.restorePoints.Count -eq 0) {
            Write-Error "No restore points found in collection: $RestorePointCollectionName"
            Write-Host "`nPlease ensure restore points have been created for the VM." -ForegroundColor Yellow
            Write-Host "It can take 3-6 hours after enabling Basic data protection for the first restore point to be created." -ForegroundColor Yellow
            exit 1
        }
        
        $restorePointsFromAPI = $response.properties.restorePoints
        Write-Success "Found $($restorePointsFromAPI.Count) restore point(s) in collection"
        
        # Parse restore points and sort by creation time
        $restorePointsInfo = @()
        foreach ($rp in $restorePointsFromAPI) {
            $rpName = $rp.name
            $creationTime = $rp.properties.timeCreated
            
            $restorePointsInfo += [PSCustomObject]@{
                Name = $rpName
                TimeCreated = [DateTime]$creationTime
                ResourceId = $rp.id
                Properties = $rp.properties
            }
            
            Write-Detail "Restore point: $rpName (Created: $creationTime)"
        }
        
        # Sort by creation time and get the latest
        $latestRestorePointInfo = $restorePointsInfo | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1
        $RestorePointName = $latestRestorePointInfo.Name
        
        # Get the full restore point object using PowerShell cmdlet for detailed information
        $latestRestorePoint = Get-AzRestorePoint `
            -ResourceGroupName $ResourceGroupName `
            -RestorePointCollectionName $RestorePointCollectionName `
            -Name $RestorePointName `
            -ErrorAction Stop
        
        Write-Success "Selected latest restore point: $RestorePointName"
        Write-Detail "Created: $($latestRestorePoint.TimeCreated)"
        Write-Detail "Total restore points available: $($restorePointsInfo.Count)"
        
        if ($restorePointsInfo.Count -gt 1) {
            Write-Host "`nOther available restore points (older):" -ForegroundColor Yellow
            $olderRestorePoints = $restorePointsInfo | Sort-Object -Property TimeCreated -Descending | Select-Object -Skip 1 -First 3
            foreach ($rp in $olderRestorePoints) {
                Write-Host "  - $($rp.Name) (Created: $($rp.TimeCreated))" -ForegroundColor Gray
            }
            if ($restorePointsInfo.Count -gt 4) {
                Write-Host "  ... and $($restorePointsInfo.Count - 4) more" -ForegroundColor Gray
            }
        }
    } else {
        # Specific restore point name was provided
        Write-Info "Using specified restore point: $RestorePointName"
        $latestRestorePoint = Get-AzRestorePoint `
            -ResourceGroupName $ResourceGroupName `
            -RestorePointCollectionName $RestorePointCollectionName `
            -Name $RestorePointName `
            -ErrorAction Stop
        Write-Success "Restore point found: $RestorePointName"
        Write-Detail "Created: $($latestRestorePoint.TimeCreated)"
    }
    
} catch {
    Write-Error "Failed to get restore point: $_"
    if ($_.ErrorDetails.Message) {
        Write-Host "`nError Details:" -ForegroundColor Red
        Write-Host $_.ErrorDetails.Message
    }
    exit 1
}

#endregion

#region Step 3: Capture Resource ID of Restore Point

Write-StepHeader "STEP 3: Capture Restore Point Details"

$restorePointId = $latestRestorePoint.Id
Write-Detail "Restore Point Resource ID:"
Write-Detail "$restorePointId"
Write-Success "Restore point ID captured"

#endregion

#region Step 4: Capture Current Disk SKUs

Write-StepHeader "STEP 4: Capture Current Disk SKUs"

try {
    # Get current OS disk SKU
    $currentOSDiskName = $vm.StorageProfile.OsDisk.Name
    $currentOSDisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $currentOSDiskName -ErrorAction Stop
    $osDiskSku = $currentOSDisk.Sku.Name
    
    Write-Success "Current OS Disk SKU captured"
    Write-Detail "OS Disk: $currentOSDiskName"
    Write-Detail "SKU: $osDiskSku"
    
    # Get current data disk SKUs
    $currentDataDiskSkus = @{}
    if ($vm.StorageProfile.DataDisks -and $vm.StorageProfile.DataDisks.Count -gt 0) {
        Write-Info "Capturing data disk SKUs..."
        foreach ($disk in $vm.StorageProfile.DataDisks) {
            $dataDisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $disk.Name -ErrorAction Stop
            $currentDataDiskSkus[$disk.Name] = $dataDisk.Sku.Name
            Write-Detail "Data Disk: $($disk.Name) - SKU: $($dataDisk.Sku.Name)"
        }
        Write-Success "Captured SKUs for $($currentDataDiskSkus.Count) data disk(s)"
    } else {
        Write-Info "No data disks currently attached"
    }
    
} catch {
    Write-Error "Failed to capture current disk SKUs: $_"
    exit 1
}

#endregion

#region Step 5: Identify All Disks in Restore Point

Write-StepHeader "STEP 5: Identify All Disks in Restore Point"

try {
    $diskRestorePoints = @()
    $osDiskRestorePoint = $null
    $dataDiskRestorePoints = @()
    
    if ($latestRestorePoint.SourceMetadata.StorageProfile.OsDisk) {
        $osDiskRestorePoint = $latestRestorePoint.SourceMetadata.StorageProfile.OsDisk
        Write-Success "OS Disk found in restore point"
        Write-Detail "Name: $($osDiskRestorePoint.Name)"
        Write-Detail "Disk Restore Point ID: $($osDiskRestorePoint.DiskRestorePoint.Id)"
    }
    
    if ($latestRestorePoint.SourceMetadata.StorageProfile.DataDisks) {
        $dataDiskRestorePoints = $latestRestorePoint.SourceMetadata.StorageProfile.DataDisks
        Write-Success "Found $($dataDiskRestorePoints.Count) data disk(s) in restore point"
        foreach ($dataDisk in $dataDiskRestorePoints) {
            Write-Detail "Data Disk: $($dataDisk.Name) (LUN: $($dataDisk.Lun))"
            Write-Detail "  Disk Restore Point ID: $($dataDisk.DiskRestorePoint.Id)"
        }
    } else {
        Write-Info "No data disks found in restore point"
    }
    
    $totalDisks = 1 + $dataDiskRestorePoints.Count
    Write-Success "Total disks to restore: $totalDisks"
    
} catch {
    Write-Error "Failed to identify disks in restore point: $_"
    exit 1
}

#endregion

#region Step 6: Restore All Disks

Write-StepHeader "STEP 6: Restore All Disks"

$restoredDisks = @{}
$restoreJobs = @()

try {
    # Prepare disk restore configuration
    Write-Info "Preparing to restore disks..."
    
    # Restore OS Disk
    if ($osDiskRestorePoint) {
        $osDiskName = $osDiskRestorePoint.Name
        $restoredOSDiskName = "$osDiskName$RestoredDiskSuffix"
        
        Write-Info "Restoring OS disk: $osDiskName -> $restoredOSDiskName"
        Write-Detail "Using SKU: $osDiskSku"
        
        $osDiskConfig = New-AzDiskConfig `
            -Location $location `
            -CreateOption Restore `
            -SourceResourceId $osDiskRestorePoint.DiskRestorePoint.Id `
            -SkuName $osDiskSku
        
        # Apply zone if VM is in an availability zone
        if ($vmZones -and $vmZones.Count -gt 0) {
            $osDiskConfig.Zones = $vmZones
            Write-Detail "Applying availability zone: $($vmZones -join ', ')"
        }
        
        if ($PSCmdlet.ShouldProcess($restoredOSDiskName, "Restore OS disk")) {
            $restoredOSDisk = New-AzDisk `
                -ResourceGroupName $ResourceGroupName `
                -DiskName $restoredOSDiskName `
                -Disk $osDiskConfig
            
            $restoredDisks['OSDisk'] = @{
                Name = $restoredOSDiskName
                Id = $restoredOSDisk.Id
                OriginalName = $osDiskName
            }
            
            Write-Success "OS disk restored: $restoredOSDiskName (SKU: $osDiskSku)"
            Write-Detail "Disk ID: $($restoredOSDisk.Id)"
        }
    }
    
    # Restore Data Disks
    if ($dataDiskRestorePoints -and $dataDiskRestorePoints.Count -gt 0) {
        $restoredDisks['DataDisks'] = @()
        
        foreach ($dataDisk in $dataDiskRestorePoints) {
            $dataDiskName = $dataDisk.Name
            $restoredDataDiskName = "$dataDiskName$RestoredDiskSuffix"
            
            # Get the SKU for this data disk
            $dataDiskSku = if ($currentDataDiskSkus.ContainsKey($dataDiskName)) {
                $currentDataDiskSkus[$dataDiskName]
            } else {
                # Fallback to Standard_LRS if we can't find the original disk SKU
                Write-Warning "Could not find SKU for data disk '$dataDiskName', using Standard_LRS as fallback"
                "Standard_LRS"
            }
            
            Write-Info "Restoring data disk: $dataDiskName -> $restoredDataDiskName (LUN: $($dataDisk.Lun))"
            Write-Detail "Using SKU: $dataDiskSku"
            
            $dataDiskConfig = New-AzDiskConfig `
                -Location $location `
                -CreateOption Restore `
                -SourceResourceId $dataDisk.DiskRestorePoint.Id `
                -SkuName $dataDiskSku
            
            # Apply zone if VM is in an availability zone
            if ($vmZones -and $vmZones.Count -gt 0) {
                $dataDiskConfig.Zones = $vmZones
                Write-Detail "Applying availability zone: $($vmZones -join ', ')"
            }
            
            if ($PSCmdlet.ShouldProcess($restoredDataDiskName, "Restore data disk")) {
                $restoredDataDisk = New-AzDisk `
                    -ResourceGroupName $ResourceGroupName `
                    -DiskName $restoredDataDiskName `
                    -Disk $dataDiskConfig
                
                $restoredDisks['DataDisks'] += @{
                    Name = $restoredDataDiskName
                    Id = $restoredDataDisk.Id
                    OriginalName = $dataDiskName
                    Lun = $dataDisk.Lun
                    Caching = $dataDisk.Caching
                    WriteAcceleratorEnabled = $dataDisk.WriteAcceleratorEnabled
                }
                
                Write-Success "Data disk restored: $restoredDataDiskName (SKU: $dataDiskSku)"
                Write-Detail "Disk ID: $($restoredDataDisk.Id)"
            }
        }
    }
    
    Write-Success "All disks restored successfully"
    
} catch {
    Write-Error "Failed to restore disks: $_"
    Write-Host "`nPartially restored disks may need manual cleanup." -ForegroundColor Red
    exit 1
}

#endregion

#region Step 7: De-allocate VM

Write-StepHeader "STEP 7: De-allocate VM"

try {
    $vmStatus = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status).Statuses | 
                Where-Object { $_.Code -like 'PowerState/*' }
    
    if ($vmStatus.Code -eq 'PowerState/deallocated') {
        Write-Info "VM is already deallocated"
    } else {
        Write-Info "Current VM state: $($vmStatus.DisplayStatus)"
        
        if ($PSCmdlet.ShouldProcess($VMName, "Stop and deallocate VM")) {
            Write-Info "Stopping VM: $VMName (this may take a few minutes)..."
            Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force | Out-Null
            Write-Success "VM deallocated successfully"
        }
    }
    
} catch {
    Write-Error "Failed to deallocate VM: $_"
    exit 1
}

#endregion

#region Step 8: Detach Existing Data Disks

Write-StepHeader "STEP 8: Detach Existing Data Disks"

try {
    # Refresh VM object to get current configuration
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
    
    $originalDataDisks = @()
    
    if ($vm.StorageProfile.DataDisks -and $vm.StorageProfile.DataDisks.Count -gt 0) {
        Write-Info "Found $($vm.StorageProfile.DataDisks.Count) data disk(s) attached to VM"
        
        # Store original data disk information
        foreach ($disk in $vm.StorageProfile.DataDisks) {
            $originalDataDisks += @{
                Name = $disk.Name
                Lun = $disk.Lun
                Caching = $disk.Caching
                WriteAcceleratorEnabled = $disk.WriteAcceleratorEnabled
            }
            Write-Detail "Data Disk: $($disk.Name) (LUN: $($disk.Lun))"
        }
        
        if ($PSCmdlet.ShouldProcess($VMName, "Detach all data disks")) {
            # Remove all data disks from VM configuration
            foreach ($disk in $vm.StorageProfile.DataDisks) {
                Write-Info "Detaching data disk: $($disk.Name)"
                Remove-AzVMDataDisk -VM $vm -Name $disk.Name | Out-Null
            }
            
            # Update VM configuration
            Write-Info "Updating VM configuration..."
            Update-AzVM -ResourceGroupName $ResourceGroupName -VM $vm | Out-Null
            Write-Success "All data disks detached successfully"
        }
    } else {
        Write-Info "No data disks attached to VM"
    }
    
} catch {
    Write-Error "Failed to detach data disks: $_"
    exit 1
}

#endregion

#region Step 9: Attach Restored Data Disks

Write-StepHeader "STEP 9: Attach Restored Data Disks"

try {
    # Refresh VM object
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
    
    if ($restoredDisks.ContainsKey('DataDisks') -and $restoredDisks['DataDisks'].Count -gt 0) {
        Write-Info "Attaching $($restoredDisks['DataDisks'].Count) restored data disk(s)..."
        
        foreach ($dataDisk in $restoredDisks['DataDisks']) {
            Write-Info "Attaching data disk: $($dataDisk.Name) at LUN: $($dataDisk.Lun)"
            
            if ($PSCmdlet.ShouldProcess($dataDisk.Name, "Attach restored data disk to VM")) {
                $diskToAttach = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $dataDisk.Name
                
                $vm = Add-AzVMDataDisk `
                    -VM $vm `
                    -Name $dataDisk.Name `
                    -CreateOption Attach `
                    -ManagedDiskId $diskToAttach.Id `
                    -Lun $dataDisk.Lun `
                    -Caching $dataDisk.Caching
                
                Write-Detail "Added disk: $($dataDisk.Name)"
            }
        }
        
        # Update VM configuration
        if ($PSCmdlet.ShouldProcess($VMName, "Update VM with restored data disks")) {
            Write-Info "Updating VM configuration..."
            Update-AzVM -ResourceGroupName $ResourceGroupName -VM $vm | Out-Null
            Write-Success "All restored data disks attached successfully"
        }
    } else {
        Write-Info "No data disks to attach"
    }
    
} catch {
    Write-Error "Failed to attach restored data disks: $_"
    exit 1
}

#endregion

#region Step 10: Swap OS Disk

Write-StepHeader "STEP 10: Swap OS Disk with Restored OS Disk"

try {
    # Refresh VM object
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
    
    $originalOSDiskName = $vm.StorageProfile.OsDisk.Name
    $originalOSDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id
    
    Write-Info "Current OS Disk: $originalOSDiskName"
    Write-Info "New OS Disk: $($restoredDisks['OSDisk'].Name)"
    
    if ($PSCmdlet.ShouldProcess($VMName, "Swap OS disk")) {
        # Get the restored OS disk
        $restoredOSDisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $restoredDisks['OSDisk'].Name
        
        # Update OS disk reference
        Set-AzVMOSDisk -VM $vm -ManagedDiskId $restoredOSDisk.Id -Name $restoredOSDisk.Name | Out-Null
        
        # Update VM configuration
        Write-Info "Updating VM with new OS disk..."
        Update-AzVM -ResourceGroupName $ResourceGroupName -VM $vm | Out-Null
        
        Write-Success "OS disk swapped successfully"
        Write-Detail "Original OS Disk: $originalOSDiskName"
        Write-Detail "New OS Disk: $($restoredDisks['OSDisk'].Name)"
        
        # Store original disk info for cleanup
        $restoredDisks['OSDisk']['OriginalId'] = $originalOSDiskId
    }
    
} catch {
    Write-Error "Failed to swap OS disk: $_"
    exit 1
}

#endregion

#region Step 11: Start VM

Write-StepHeader "STEP 11: Start VM"

try {
    if ($PSCmdlet.ShouldProcess($VMName, "Start VM")) {
        Write-Info "Starting VM: $VMName (this may take a few minutes)..."
        Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName | Out-Null
        Write-Success "VM started successfully"
        
        # Wait a moment and check status
        Start-Sleep -Seconds 5
        $vmStatus = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status).Statuses | 
                    Where-Object { $_.Code -like 'PowerState/*' }
        Write-Detail "VM Status: $($vmStatus.DisplayStatus)"
    }
    
} catch {
    Write-Error "Failed to start VM: $_"
    Write-Host "`nVM may need to be started manually." -ForegroundColor Red
    exit 1
}

#endregion

#region Cleanup Original Disks

if (-not $KeepOriginalDisks) {
    Write-StepHeader "STEP 12: Cleanup Original Disks (Optional)"
    
    Write-Host "`nOriginal disks that can be deleted:" -ForegroundColor Yellow
    Write-Host "  - OS Disk: $originalOSDiskName" -ForegroundColor Gray
    
    foreach ($dataDisk in $originalDataDisks) {
        Write-Host "  - Data Disk: $($dataDisk.Name)" -ForegroundColor Gray
    }
    
    Write-Host "`nTo delete original disks manually, use:" -ForegroundColor Yellow
    Write-Host "  Remove-AzDisk -ResourceGroupName '$ResourceGroupName' -DiskName '<disk-name>' -Force" -ForegroundColor Cyan
    
    Write-Info "Original disks were kept (use -KeepOriginalDisks switch or delete manually)"
} else {
    Write-Info "Original disks were kept as requested"
}

#endregion

#region Summary

Write-StepHeader "RESTORE OPERATION COMPLETED"

Write-Host "`nRestore Summary:" -ForegroundColor Green
Write-Host "  VM Name: $VMName" -ForegroundColor White
Write-Host "  Restore Point: $RestorePointName" -ForegroundColor White
Write-Host "  Restored OS Disk: $($restoredDisks['OSDisk'].Name)" -ForegroundColor White

if ($restoredDisks.ContainsKey('DataDisks') -and $restoredDisks['DataDisks'].Count -gt 0) {
    Write-Host "  Restored Data Disks: $($restoredDisks['DataDisks'].Count)" -ForegroundColor White
    foreach ($dataDisk in $restoredDisks['DataDisks']) {
        Write-Host "    - $($dataDisk.Name) (LUN: $($dataDisk.Lun))" -ForegroundColor Gray
    }
}

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Verify VM is running and accessible" -ForegroundColor White
Write-Host "  2. Test application functionality" -ForegroundColor White
Write-Host "  3. Verify data integrity" -ForegroundColor White
if (-not $KeepOriginalDisks) {
    Write-Host "  4. Delete original disks if no longer needed (see cleanup commands above)" -ForegroundColor White
}

Write-Host "`n✓ All operations completed successfully!" -ForegroundColor Green

#endregion
