
# Basic backup protection for Azure Virtual machines Private preview

We are introducing **basic policy** capability which will allow VM to be backed up once every day achieving an RPO of approximately 24 hours.
The restore points created will be multi-disks crash consistent restore points.
> Note: Restore points created in your subscription. Pricing: ~$ 0.05/GB per month. This dependent on snapshot cost in the region. Please check pricing [here](https://azure.microsoft.com/en-us/pricing/details/managed-disks/).

## Sign up for preview
Sign-up for the preview via this [form](https://forms.office.com/r/8Y0zNYU3Pu). You will receive an email notification once you are enrolled for the preview. It usually takes 5 business days.

## Feedback
Please fill up this feedback [form](https://forms.office.com/r/XHgDNb8zi1) as you try out the preview. Your feedback is crucial to help us improve our product.

## Supported configurations
- VMs using SKUs that support premium storage
- Single instance Virtual machines

## Unsupported configurations
- VMs using Ephemeral OS disks
- VMs using write accelerated
- VMs using shared disks
- VMSS with Uniform orchestration
- VMs using Premium SSD v2 disks (To be supported from public preview)
- VMs using Ultra disks (To be supported from public preview)
- Single instance VM within VMSS flex orchestration (To be supported from public preview)

## Get started
In this preview customers will be able to enable a basic backup policy on existing/new virtual machine that meet the supported configurations.

## Prerequisites
- **Regions supported:** East Asia, UK South, North Europe and West Central US (Rest by Feb 2025)
- Subscription must be allowlisted as mentioned above

## Existing VM steps
Use API version **2025-04-01**

```http
PATCH https://management.azure.com/.../api-version=2025-04-01
{
  "location": "eastus2euap",
  "properties": {
    "resiliencyProfile": {
      "periodicRestorePoints": { "isEnabled": true }
    }
  }
}
```

- The first RP can be created 3–6 hours once enabled.
- Retention max = 10 (will be 5 in public preview), frequency = 24 hours. The frequency and retention will not be editabled by customers. Please let us know if you have any concerns over this in our feedback [form](https://forms.office.com/r/XHgDNb8zi1) .


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
