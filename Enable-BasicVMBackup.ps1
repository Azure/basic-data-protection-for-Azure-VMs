<#
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

.PARAMETER Location
    The Azure region where the VM is located (e.g., eastus2euap, eastasia, uksouth, northeurope, westcentralus).

.PARAMETER Enable
    Boolean parameter. If $true, enables basic backup protection. If $false, disables it.

.EXAMPLE
    .\Enable-BasicVMBackup.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "myRG" -VMName "myVM" -Location "eastus2euap" -Enable $true
    Enables basic backup protection for the specified VM.

.EXAMPLE
    .\Enable-BasicVMBackup.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "myRG" -VMName "myVM" -Location "eastus2euap" -Enable $false
    Disables basic backup protection for the specified VM.

.NOTES
    - Requires Azure PowerShell module (Az.Accounts)
    - User must be authenticated to Azure before running this script
    - API Version: 2025-04-01
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

    [Parameter(Mandatory = $true, HelpMessage = "Azure region (supported: eastasia, uksouth, northeurope, westcentralus)")]
    [ValidateSet("eastasia", "uksouth", "northeurope", "uswestcentral")]
    [string]$Location,

    [Parameter(Mandatory = $true, HelpMessage = "Enable basic backup protection: true to enable, false to disable")]
    [bool]$Enable
)

# Set API version
$apiVersion = "2025-04-01"

# Check if Az.Accounts module is available
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error "Az.Accounts module is not installed. Please install it using: Install-Module -Name Az.Accounts"
    exit 1
}

# Import the module
Import-Module Az.Accounts -ErrorAction Stop

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
} catch {
    Write-Error "Failed to authenticate to Azure: $_"
    exit 1
}

# Build the API endpoint URL
$uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$VMName`?api-version=$apiVersion"

# Prepare the request body
$body = @{
    location = $Location
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
    $accessToken = $token.Token
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
Write-Host "Location: $Location"
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
