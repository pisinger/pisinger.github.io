---
title: Defender for Cloud - Built-in Azure Roles and Permissions
author: pit
date: 2026-07-03
categories: [blogging]
tags: [azure, defender, defender-for-cloud, rbac, built-in-roles, permissions, security]
render_with_liquid: false
---

Defender for Cloud uses several built-in Azure roles behind the scenes. Finding the role names is easy enough, but understanding the exact control-plane and data-plane permissions assigned to each role usually means opening every role definition separately.

I flattened those definitions into one reference. Each section below keeps the role name, role ID, and description together with every `Action`, `NotAction`, and `DataAction` from the source data.

Microsoft's Azure RBAC documentation is still the official starting point for understanding role assignments and built-in roles. Its built-in-role reference covers the broader Azure catalogue and links to individual permission definitions, but it does not bring every Defender-specific service role from this snapshot together in one Defender for Cloud view. That gap is the reason I created this consolidated list instead. 

The source snapshot contains 34 Defender for Cloud-related built-in roles and 372 individual permission entries.

> Official Azure RBAC documentation: <https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles>
{: .prompt-info}

## Roles at a Glance

| Role Name | Description |
|---|---|
| `Defender Agentless VM Scan` | Role that provides access to disk snapshot for security analysis. |
| `Defender AI` | Service role that provides permissions for Microsoft Defender for AI |
| `Defender API Security` | Grants Microsoft Defender for Cloud access to computes to provide API security |
| `Defender Azure Cosmos DB` | Microsoft Defender for Azure Cosmos DB role. Grant permissions for enablement. |
| `Defender Azure SQL Databases` | Microsoft Defender for Azure SQL Databases role. Grant permissions for enablement. |
| `Defender Cloud Secrets Posture` | Service role that provides permissions for Microsoft Defender Cloud Secrets Posture |
| `Defender Containers Sensor` | Grants Microsoft Defender for Cloud access to Azure Kubernetes Services |
| `Defender CSPM` | Grants permissions for Microsoft Defender for Cloud CSPM base plan features |
| `Defender CSPM Storage Scanner Operator` | Lets you enable and configure Microsoft Defender CSPM's sensitive data discovery feature on your storage accounts. Includes an ABAC condition to limit role assignments. |
| `Defender Databricks Operator` | Grants permissions for Microsoft Defender for Cloud feature on Databricks. |
| `Defender For Container Registries Operator` | Grants Microsoft Defender for Cloud access to Azure Container Registries |
| `Defender for Storage Data Scanner` | Grants access to read blobs and update index tags. This role is used by the data scanner of Defender for Storage. |
| `Defender for Storage Scanner Operator` | Lets you enable and configure Microsoft Defender for Storage's malware scanning and sensitive data discovery features on your storage accounts. Includes an ABAC condition to limit role assignments. |
| `Defender for Storage Threat Protection` | Microsoft Defender for Storage Threat Protection role - grants the permissions needed to enable/disable Defender for Storage Advanced Threat Protection at resource level. |
| `Defender Kubernetes Agent Operator` | Grants Microsoft Defender for Cloud permissions to provision the Kubernetes defender security agent |
| `Defender Kubernetes API Access` | Grants Microsoft Defender for Cloud access to Azure Kubernetes Services |
| `Defender Open Source Relational Databases` | Microsoft Defender for Open Source Relational Databases role. Grant permissions for enablement. |
| `Defender Registry Access` | Grants Microsoft Defender for Cloud access to Azure Container Registry for security assessment of container images |
| `Defender Sensitive Data Discovery` | Grants permissions for Microsoft Defender for Cloud Sensitive Data Discovery plan features |
| `Defender Serverless Scanner` | Grants access to Serverless resources and thier connections |
| `Defender Servers P1` | Defender Servers P1 |
| `Defender Servers P2` | Defender Servers P2 |
| `Defender Settings Contributor` | Grants Microsoft Defender for Cloud access to Defender Settings |
| `Defender SQL Servers On Machines` | Microsoft Defender for SQL Servers On Machines role. Grant permissions for enablement. |
| `Defender Storage Automated Malware Remediation` | Grants additional permissions for Microsoft Defender for Storage automated remediation operations including soft-delete management and blob deletion. |
| `Defender Storage Malware Data Scanner` | Grants data plane permissions for Microsoft Defender for Storage scanning operations — blob/file read, index tag updates. |
| `Defender Storage Malware Operator` | Grants permissions for Microsoft Defender for Storage malware scanning operations including blob/file read, index tag updates, EventGrid management, and network bypass. |
| `Defender Unified RBAC Authorization Manager` | Defender Unified RBAC Authorization Manager. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements. |
| `Defender Unified RBAC Authorization Reader` | Defender Unified RBAC Authorization Reader. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements. |
| `Defender Unified RBAC Contributor and Responder` | Defender Unified RBAC Contributor and Responder. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements. |
| `Defender Unified RBAC Data Manager` | Defender Unified RBAC Data Manager. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements. |
| `Defender Unified RBAC Reader` | Defender Unified RBAC Reader. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements. |
| `Defender Unified RBAC Responder` | Defender Unified RBAC Responder. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements. |
| `Defender Unified RBAC Scoped Reader` | Defender Unified RBAC Scoped Reader. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements. |

> Azure role definitions can change, so treat it as a point-in-time snapshot and check the current definition before using it for access reviews or custom-role design.
{: .prompt-warning}

Below the PowerShell command to extract the role definitions and permissions from your Azure subscription. It outputs a table with the role name, ID, description, and all permission types.

```shell 
Get-AzRoleDefinition | ForEach-Object {
	$role = $_
	$perm = $role.Permissions[0]
	
    [PSCustomObject]@{
		Name           = $role.Name
		Id             = $role.Id
		Description    = $role.Description
		IsCustom       = $role.IsCustom
		Actions        = ($perm.Actions -join ';')
		NotActions     = ($perm.NotActions -join ';')
		DataActions    = ($perm.DataActions -join ';')
		NotDataActions = ($perm.NotDataActions -join ';')
    }
}
```

## Reading the Permission Tables

Azure role definitions separate permissions by how they apply:

- `Action` is an individual management or control-plane operation against an Azure resource provider. Operations such as `Microsoft.Compute/virtualMachines/start/action`, `read`, and `write` manage the resource through Azure Resource Manager.
- `NotAction` subtracts an operation from the set granted by `Actions`. The effective control-plane permissions are therefore `Actions - NotActions`.
- `DataAction` is an individual data-plane operation against data held inside a resource. For example, `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read` reads blob content, while a control-plane action manages the container resource itself.
- `NotDataAction` subtracts an operation from the set granted by `DataActions`, following the same model as `NotActions`. The source definitions used here contain no `NotDataActions`, so none appear in the role tables below.

In the role definition JSON, these fields are the plural arrays `Actions`, `NotActions`, `DataActions`, and `NotDataActions`. The tables use the singular form because each row represents one operation string from an array.

The complete evaluation logic is:

- Allowed control-plane operations: `Actions - NotActions`
- Allowed data-plane operations: `DataActions - NotDataActions`
- Deny assignments, when present, override both

> A `NotAction` is not a deny. It only removes an operation from this role definition's grant. Another role assignment can still grant the same operation.
{: .prompt-warning}

> Wildcard entries such as `Microsoft.Security/*/read` are retained exactly as defined. They can cover new matching operations added by the resource provider later.
{: .prompt-info}

## Defender Agentless VM Scan

Role that provides access to disk snapshot for security analysis.

**Role ID:** `d24ecba3-c1f4-40fa-a7bb-4588a071e8fd`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Compute/disks/read` |
| `Action` | `Microsoft.Compute/disks/beginGetAccess/action` |
| `Action` | `Microsoft.Compute/diskEncryptionSets/read` |
| `Action` | `Microsoft.Compute/virtualMachines/instanceView/read` |
| `Action` | `Microsoft.Compute/virtualMachines/read` |
| `Action` | `Microsoft.Compute/virtualMachineScaleSets/instanceView/read` |
| `Action` | `Microsoft.Compute/virtualMachineScaleSets/read` |
| `Action` | `Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read` |
| `Action` | `Microsoft.Compute/virtualMachineScaleSets/virtualMachines/instanceView/read` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |

## Defender Kubernetes API Access

Grants Microsoft Defender for Cloud access to Azure Kubernetes Services

**Role ID:** `d5a2ae44-610b-4500-93be-660a0c5f5ca6`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.ContainerService/managedClusters/trustedAccessRoleBindings/write` |
| `Action` | `Microsoft.ContainerService/managedClusters/trustedAccessRoleBindings/read` |
| `Action` | `Microsoft.ContainerService/managedClusters/trustedAccessRoleBindings/delete` |
| `Action` | `Microsoft.ContainerService/managedClusters/read` |
| `Action` | `Microsoft.Features/features/read` |
| `Action` | `Microsoft.Features/providers/features/read` |
| `Action` | `Microsoft.Features/providers/features/register/action` |
| `Action` | `Microsoft.Security/pricings/securityoperators/read` |
| `Action` | `Microsoft.Security/securityOperators/read` |
| `Action` | `Microsoft.Authorization/policyAssignments/read` |
| `Action` | `Microsoft.Authorization/policySetDefinitions/read` |

## Defender Registry Access

Grants Microsoft Defender for Cloud access to Azure Container Registry for security assessment of container images

**Role ID:** `96062cf7-95ca-4f89-9b9d-2a2aa47356af`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.ContainerRegistry/registries/pull/read` |
| `Action` | `Microsoft.ContainerRegistry/registries/push/write` |
| `Action` | `Microsoft.ContainerRegistry/registries/artifacts/delete` |
| `DataAction` | `Microsoft.ContainerRegistry/registries/repositories/metadata/read` |
| `DataAction` | `Microsoft.ContainerRegistry/registries/repositories/content/read` |
| `DataAction` | `Microsoft.ContainerRegistry/registries/repositories/metadata/write` |
| `DataAction` | `Microsoft.ContainerRegistry/registries/repositories/content/write` |
| `DataAction` | `Microsoft.ContainerRegistry/registries/repositories/metadata/delete` |
| `DataAction` | `Microsoft.ContainerRegistry/registries/repositories/content/delete` |

## Defender for Storage Data Scanner

Grants access to read blobs and update index tags. This role is used by the data scanner of Defender for Storage.

**Role ID:** `1e7ca9b1-60d1-4db8-a914-f2ca1ff27c40`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Storage/storageAccounts/blobServices/containers/read` |
| `Action` | `Microsoft.Storage/storageAccounts/blobServices/read` |
| `Action` | `Microsoft.Storage/storageAccounts/fileServices/shares/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write` |
| `DataAction` | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete` |
| `DataAction` | `Microsoft.Storage/storageAccounts/fileServices/fileshares/files/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/fileServices/readFileBackupSemantics/action` |

## Defender for Storage Scanner Operator

Lets you enable and configure Microsoft Defender for Storage's malware scanning and sensitive data discovery features on your storage accounts. Includes an ABAC condition to limit role assignments.

**Role ID:** `0f641de8-0b88-4198-bdef-bd8b45ceba96`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Authorization/roleAssignments/write` |
| `Action` | `Microsoft.Authorization/roleAssignments/delete` |
| `Action` | `Microsoft.Authorization/*/read` |
| `Action` | `Microsoft.Resources/deployments/*` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| `Action` | `Microsoft.Resources/subscriptions/read` |
| `Action` | `Microsoft.Management/managementGroups/read` |
| `Action` | `Microsoft.Resources/deployments/*` |
| `Action` | `Microsoft.Support/*` |
| `Action` | `Microsoft.Security/defenderforstoragesettings/read` |
| `Action` | `Microsoft.Security/defenderforstoragesettings/write` |
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/read` |
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/write` |
| `Action` | `Microsoft.Security/datascanners/read` |
| `Action` | `Microsoft.Security/datascanners/write` |
| `Action` | `Microsoft.Security/dataScanners/delete` |
| `Action` | `Microsoft.Storage/storageAccounts/write` |
| `Action` | `Microsoft.Storage/storageAccounts/read` |
| `Action` | `Microsoft.EventGrid/topics/read` |
| `Action` | `Microsoft.EventGrid/eventSubscriptions/read` |
| `Action` | `Microsoft.EventGrid/eventSubscriptions/write` |
| `Action` | `Microsoft.EventGrid/eventSubscriptions/delete` |
| `Action` | `Microsoft.Storage/storageAccounts/blobServices/read` |
| `Action` | `Microsoft.Storage/storageAccounts/blobServices/write` |

## Defender Kubernetes Agent Operator

Grants Microsoft Defender for Cloud permissions to provision the Kubernetes defender security agent

**Role ID:** `8bb6f106-b146-4ee6-a3f9-b9c5a96e0ae5`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Authorization/*/read` |
| `Action` | `Microsoft.Insights/alertRules/*` |
| `Action` | `Microsoft.Resources/deployments/*` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/write` |
| `Action` | `Microsoft.Resources/subscriptions/operationresults/read` |
| `Action` | `Microsoft.Resources/subscriptions/read` |
| `Action` | `Microsoft.KubernetesConfiguration/extensions/write` |
| `Action` | `Microsoft.KubernetesConfiguration/extensions/read` |
| `Action` | `Microsoft.KubernetesConfiguration/extensions/delete` |
| `Action` | `Microsoft.KubernetesConfiguration/extensions/operations/read` |
| `Action` | `Microsoft.Kubernetes/connectedClusters/Write` |
| `Action` | `Microsoft.Kubernetes/connectedClusters/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/write` |
| `Action` | `Microsoft.OperationalInsights/workspaces/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/listKeys/action` |
| `Action` | `Microsoft.OperationalInsights/workspaces/sharedkeys/action` |
| `Action` | `Microsoft.Kubernetes/register/action` |
| `Action` | `Microsoft.KubernetesConfiguration/register/action` |

## Defender CSPM Storage Scanner Operator

Lets you enable and configure Microsoft Defender CSPM's sensitive data discovery feature on your storage accounts. Includes an ABAC condition to limit role assignments.

**Role ID:** `8480c0f0-4509-4229-9339-7c10018cb8c4`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Storage/storageAccounts/write` |
| `Action` | `Microsoft.Storage/storageAccounts/read` |
| `Action` | `Microsoft.Authorization/*/read` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| `Action` | `Microsoft.Resources/subscriptions/read` |
| `Action` | `Microsoft.Management/managementGroups/read` |
| `Action` | `Microsoft.Resources/deployments/*` |
| `Action` | `Microsoft.Support/*` |
| `Action` | `Microsoft.Security/datascanners/read` |
| `Action` | `Microsoft.Security/datascanners/write` |
| `Action` | `Microsoft.Security/dataScanners/delete` |

## Defender Containers Sensor

Grants Microsoft Defender for Cloud access to Azure Kubernetes Services

**Role ID:** `5e93ba01-8f92-4c7a-b12a-801e3df23824`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Authorization/*/read` |
| `Action` | `Microsoft.Insights/alertRules/*` |
| `Action` | `Microsoft.Resources/deployments/*` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/write` |
| `Action` | `Microsoft.Resources/subscriptions/operationresults/read` |
| `Action` | `Microsoft.Resources/subscriptions/read` |
| `Action` | `Microsoft.ContainerService/managedClusters/read` |
| `Action` | `Microsoft.ContainerService/managedClusters/trustedAccessRoleBindings/delete` |
| `Action` | `Microsoft.ContainerService/managedClusters/trustedAccessRoleBindings/read` |
| `Action` | `Microsoft.ContainerService/managedClusters/trustedAccessRoleBindings/write` |
| `Action` | `Microsoft.ContainerService/managedClusters/write` |
| `Action` | `Microsoft.Security/pricings/securityoperators/read` |
| `Action` | `Microsoft.Security/securityOperators/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/write` |
| `Action` | `Microsoft.OperationalInsights/workspaces/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/listKeys/action` |
| `Action` | `Microsoft.OperationalInsights/workspaces/sharedkeys/action` |
| `Action` | `Microsoft.OperationalInsights/workspaces/sharedkeys/read` |

## Defender Sensitive Data Discovery

Grants permissions for Microsoft Defender for Cloud Sensitive Data Discovery plan features

**Role ID:** `0b6ca2e8-2cdc-4bd6-b896-aa3d8c21fc35`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Security/defenderforstoragesettings/read` |
| `Action` | `Microsoft.Security/defenderforstoragesettings/write` |
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/read` |
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/write` |
| `Action` | `Microsoft.Security/securityOperators/read` |
| `Action` | `Microsoft.Storage/storageAccounts/write` |
| `Action` | `Microsoft.Storage/storageAccounts/read` |
| `Action` | `Microsoft.Storage/storageAccounts/blobServices/containers/read` |
| `Action` | `Microsoft.Storage/storageAccounts/fileServices/shares/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/fileServices/fileshares/files/read` |

## Defender Serverless Scanner

Grants access to Serverless resources and thier connections

**Role ID:** `68ac31b4-936a-4046-a6d2-ba6f8a757bf6`

| Permission Type | Permission |
|---|---|
| `Action` | `microsoft.web/sites/publish/action` |
| `Action` | `Microsoft.Web/sites/sitecontainers/read` |
| `Action` | `microsoft.web/sites/slots/publish/action` |
| `Action` | `microsoft.web/sites/config/list/action` |
| `Action` | `microsoft.web/sites/slots/config/list/action` |

## Defender For Container Registries Operator

Grants Microsoft Defender for Cloud access to Azure Container Registries

**Role ID:** `c5c82243-e78e-43f9-8428-793bba85b28e`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.ContainerRegistry/registries/pull/read` |
| `Action` | `Microsoft.ContainerRegistry/registries/metadata/read` |
| `Action` | `Microsoft.ContainerRegistry/registries/read` |
| `DataAction` | `Microsoft.ContainerRegistry/registries/repositories/content/read` |
| `DataAction` | `Microsoft.ContainerRegistry/registries/repositories/metadata/read` |
| `DataAction` | `Microsoft.ContainerRegistry/registries/catalog/read` |

## Defender Unified RBAC Data Manager

Defender Unified RBAC Data Manager. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements.

**Role ID:** `40ead2a5-466e-4039-8a80-325542d9d2dd`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.operationalinsights/workspaces/read` |
| `Action` | `Microsoft.operationalinsights/workspaces/write` |
| `Action` | `Microsoft.operationalinsights/workspaces/query/read` |
| `Action` | `Microsoft.operationalinsights/workspaces/tables/write` |
| `Action` | `Microsoft.operationalinsights/workspaces/tables/delete` |
| `Action` | `Microsoft.operationalinsights/workspaces/sharedkeys/action` |

## Defender Unified RBAC Authorization Reader

Defender Unified RBAC Authorization Reader. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements.

**Role ID:** `ca62263b-07d5-4b48-b437-088803f5c2ff`

No `Actions`, `NotActions`, or `DataActions` are present in the source definition.

## Defender Unified RBAC Authorization Manager

Defender Unified RBAC Authorization Manager. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements.

**Role ID:** `1fd5d8bf-9037-4ede-89bf-680f798e2765`

No `Actions`, `NotActions`, or `DataActions` are present in the source definition.

## Defender Unified RBAC Responder

Defender Unified RBAC Responder. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements.

**Role ID:** `1bacae94-6c0f-4d2d-8dfa-408d5a28e6ec`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.SecurityInsights/*/read` |
| `Action` | `Microsoft.SecurityInsights/dataConnectorsCheckRequirements/action` |
| `Action` | `Microsoft.SecurityInsights/automationRules/*` |
| `Action` | `Microsoft.SecurityInsights/cases/*` |
| `Action` | `Microsoft.SecurityInsights/incidents/*` |
| `Action` | `Microsoft.SecurityInsights/entities/runPlaybook/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/appendTags/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/query/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/bulkTag/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/appendTags/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/replaceTags/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/queryIndicators/action` |
| `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/systems/undoAction/action` |
| `Action` | `Microsoft.OperationalInsights/workspaces/analytics/query/action` |
| `Action` | `Microsoft.OperationalInsights/workspaces/*/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/read` |
| `Action` | `Microsoft.OperationsManagement/solutions/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/query/*/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| `Action` | `Microsoft.OperationalInsights/querypacks/*/read` |
| `Action` | `Microsoft.Resources/deployments/*` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| `Action` | `Microsoft.Insights/workbooks/read` |
| `Action` | `Microsoft.Authorization/*/read` |
| `NotAction` | `Microsoft.SecurityInsights/cases/*/Delete` |
| `NotAction` | `Microsoft.SecurityInsights/incidents/*/Delete` |
| `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |
| `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |

## Defender Unified RBAC Contributor and Responder

Defender Unified RBAC Contributor and Responder. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements.

**Role ID:** `625a1cea-653b-4a19-bd3a-df1d66ab6637`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.OperationalInsights/querypacks/*/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/*/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/analytics/query/action` |
| `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/query/*/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/*` |
| `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/read` |
| `Action` | `Microsoft.OperationsManagement/solutions/read` |
| `Action` | `Microsoft.Resources/deployments/*` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| `Action` | `Microsoft.SecurityInsights/*` |
| `Action` | `Microsoft.SecurityInsights/*/read` |
| `Action` | `Microsoft.SecurityInsights/automationRules/*` |
| `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/systems/undoAction/action` |
| `Action` | `Microsoft.SecurityInsights/cases/*` |
| `Action` | `Microsoft.SecurityInsights/dataConnectorsCheckRequirements/action` |
| `Action` | `Microsoft.SecurityInsights/entities/runPlaybook/action` |
| `Action` | `Microsoft.SecurityInsights/incidents/*` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/bulkTag/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/appendTags/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/query/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/replaceTags/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/queryIndicators/action` |
| `Action` | `Microsoft.Insights/workbooks/*` |
| `Action` | `Microsoft.Authorization/*/read` |
| `NotAction` | `Microsoft.SecurityInsights/cases/*/Delete` |
| `NotAction` | `Microsoft.SecurityInsights/incidents/*/Delete` |
| `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |
| `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |

## Defender Unified RBAC Reader

Defender Unified RBAC Reader. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements.

**Role ID:** `78b7345a-1e1b-483a-ac62-62228c6ea89d`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.SecurityInsights/*/read` |
| `Action` | `Microsoft.SecurityInsights/dataConnectorsCheckRequirements/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/query/action` |
| `Action` | `Microsoft.SecurityInsights/threatIntelligence/queryIndicators/action` |
| `Action` | `Microsoft.OperationalInsights/workspaces/analytics/query/action` |
| `Action` | `Microsoft.OperationalInsights/workspaces/*/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/LinkedServices/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/read` |
| `Action` | `Microsoft.OperationsManagement/solutions/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/query/*/read` |
| `Action` | `Microsoft.OperationalInsights/querypacks/*/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/read` |
| `Action` | `Microsoft.Insights/workbooks/read` |
| `Action` | `Microsoft.Authorization/*/read` |
| `Action` | `Microsoft.Resources/deployments/*` |
| `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |
| `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |
| `DataAction` | `Microsoft.OperationalInsights/workspaces/tables/data/read` |

## Defender Cloud Secrets Posture

Service role that provides permissions for Microsoft Defender Cloud Secrets Posture

**Role ID:** `512ef07a-840c-48d2-9be4-9a30a75a5c70`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.DocumentDB/databaseAccounts/listKeys/action` |
| `Action` | `Microsoft.documentdb/mongoClusters/read` |
| `Action` | `Microsoft.DocumentDB/databaseAccounts/listConnectionStrings/action` |
| `Action` | `Microsoft.CognitiveServices/accounts/listKeys/action` |

## Defender CSPM

Grants permissions for Microsoft Defender for Cloud CSPM base plan features

**Role ID:** `46023a6a-0702-4cbf-956c-d8c3ac27bc2b`

| Permission Type | Permission |
|---|---|
| `DataAction` | `Microsoft.CognitiveServices/accounts/aiservices/agents/read` |
| `DataAction` | `Microsoft.CognitiveServices/accounts/aiservices/assets/read` |

## Defender API Security

Grants Microsoft Defender for Cloud access to computes to provide API security

**Role ID:** `6f91a4f9-10ee-4b95-b8cd-96ee73c5968d`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Security/pricings/read` |
| `Action` | `Microsoft.Security/apiCollections/read` |
| `Action` | `Microsoft.ApiManagement/service/read` |
| `Action` | `Microsoft.ApiManagement/service/apis/read` |
| `Action` | `Microsoft.ApiManagement/service/apis/operations/read` |
| `Action` | `Microsoft.ApiManagement/service/apiVersionSets/read` |
| `Action` | `Microsoft.ApiManagement/service/apis/diagnostics/read` |
| `Action` | `Microsoft.ApiManagement/service/apis/diagnostics/write` |
| `Action` | `Microsoft.ApiManagement/service/apis/diagnostics/delete` |
| `Action` | `Microsoft.ApiManagement/service/apis/policies/read` |
| `Action` | `Microsoft.ApiManagement/service/backends/read` |
| `Action` | `Microsoft.ApiManagement/service/workspaces/read` |
| `Action` | `Microsoft.ApiManagement/service/workspaces/apis/read` |
| `Action` | `Microsoft.ApiManagement/service/workspaces/apis/operations/read` |
| `Action` | `Microsoft.ApiManagement/service/workspaces/apiVersionSets/read` |
| `Action` | `Microsoft.ApiManagement/service/workspaces/apis/diagnostics/read` |
| `Action` | `Microsoft.ApiManagement/service/workspaces/apis/diagnostics/write` |
| `Action` | `Microsoft.ApiManagement/service/workspaces/apis/diagnostics/delete` |
| `Action` | `Microsoft.ApiManagement/service/workspaces/apis/policies/read` |
| `Action` | `Microsoft.ApiManagement/service/workspaces/backends/read` |
| `Action` | `Microsoft.ApiManagement/gateways/configConnections/read` |
| `Action` | `Microsoft.ApiManagement/service/workspaceLinks/read` |

## Defender Settings Contributor

Grants Microsoft Defender for Cloud access to Defender Settings

**Role ID:** `7d0c0268-1199-449b-a52e-75c20879f46b`

| Permission Type | Permission |
|---|---|
| `Action` | `microsoft.security/pricings/read` |
| `Action` | `microsoft.security/pricings/write` |
| `Action` | `microsoft.security/pricings/securityoperators/read` |
| `Action` | `microsoft.security/securityoperators/read` |
| `Action` | `microsoft.security/register/action` |
| `Action` | `microsoft.security/settings/read` |
| `Action` | `microsoft.security/settings/write` |

## Defender Unified RBAC Scoped Reader

Defender Unified RBAC Scoped Reader. This role is managed and assigned automatically by the Defender Unified RBAC system. Manual assignment of this role is not recommended, as the Defender Unified RBAC system may modify or remove it at any time based on system requirements.

**Role ID:** `d56b031f-8d90-4376-9231-b5c94fce88ef`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/read` |
| `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |
| `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |
| `NotAction` | `Microsoft.SecurityInsights/alertRules/read` |
| `DataAction` | `Microsoft.OperationalInsights/workspaces/tables/data/read` |

## Defender Databricks Operator

Grants permissions for Microsoft Defender for Cloud feature on Databricks.

**Role ID:** `0e2ecf2a-0574-4b08-89e2-be133aa6303f`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Databricks/workspaces/read` |
| `Action` | `Microsoft.Databricks/workspaces/assignWorkspaceAdmin/action` |

## Defender Open Source Relational Databases

Microsoft Defender for Open Source Relational Databases role. Grant permissions for enablement.

**Role ID:** `99626c15-0799-47ad-96ab-f298031f69d6`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.DBforMySQL/flexibleServers/advancedThreatProtectionSettings/read` |
| `Action` | `Microsoft.DBforMySQL/flexibleServers/advancedThreatProtectionSettings/write` |
| `Action` | `Microsoft.DBforMySQL/flexibleServers/read` |
| `Action` | `Microsoft.DBforPostgreSQL/flexibleServers/read` |
| `Action` | `Microsoft.DBforPostgreSQL/flexibleServers/advancedThreatProtectionSettings/read` |
| `Action` | `Microsoft.DBforPostgreSQL/flexibleServers/advancedThreatProtectionSettings/write` |

## Defender Azure Cosmos DB

Microsoft Defender for Azure Cosmos DB role. Grant permissions for enablement.

**Role ID:** `d2acaa63-2a62-4c01-998a-cdbe7a00d709`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.DocumentDB/databaseAccounts/read` |
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/read` |
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/write` |

## Defender SQL Servers On Machines

Microsoft Defender for SQL Servers On Machines role. Grant permissions for enablement.

**Role ID:** `d9468a2b-1820-47e1-a40e-d2b7fba1879a`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Compute/virtualMachines/extensions/delete` |
| `Action` | `Microsoft.Compute/virtualMachines/extensions/read` |
| `Action` | `Microsoft.Compute/virtualMachines/extensions/write` |
| `Action` | `Microsoft.Compute/virtualMachines/instanceView/read` |
| `Action` | `Microsoft.Compute/virtualMachines/read` |
| `Action` | `Microsoft.HybridCompute/machines/read` |
| `Action` | `Microsoft.HybridCompute/machines/extensions/write` |
| `Action` | `Microsoft.HybridCompute/machines/extensions/delete` |
| `Action` | `Microsoft.HybridCompute/machines/extensions/read` |
| `Action` | `Microsoft.Compute/virtualMachines/write` |

## Defender for Storage Threat Protection

Microsoft Defender for Storage Threat Protection role - grants the permissions needed to enable/disable Defender for Storage Advanced Threat Protection at resource level.

**Role ID:** `a366d631-94bf-46bf-b4af-b38f28c80774`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/read` |
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/write` |
| `Action` | `Microsoft.Security/defenderForStorageSettings/read` |
| `Action` | `Microsoft.Security/defenderForStorageSettings/write` |
| `Action` | `Microsoft.Storage/storageAccounts/read` |

## Defender Servers P1

Defender Servers P1

**Role ID:** `78b19ac9-582c-44d8-9e11-733ae424ad83`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.OperationalInsights/workspaces/read` |
| `Action` | `Microsoft.OperationsManagement/solutions/read` |
| `Action` | `Microsoft.Compute/virtualMachines/read` |
| `Action` | `Microsoft.HybridCompute/machines/read` |
| `Action` | `Microsoft.Compute/virtualMachines/extensions/read` |
| `Action` | `Microsoft.Compute/virtualMachines/extensions/write` |
| `Action` | `Microsoft.HybridCompute/machines/extensions/write` |
| `Action` | `Microsoft.HybridCompute/machines/extensions/delete` |
| `Action` | `Microsoft.HybridCompute/machines/extensions/read` |
| `Action` | `Microsoft.Compute/virtualMachines/extensions/delete` |

## Defender Servers P2

Defender Servers P2

**Role ID:** `1dc24dd8-b00e-4344-837c-58b193cd23c7`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Compute/virtualMachines/read` |
| `Action` | `Microsoft.Network/loadBalancers/read` |
| `Action` | `Microsoft.Network/networkSecurityGroups/read` |
| `Action` | `Microsoft.Network/networkSecurityGroups/write` |
| `Action` | `Microsoft.Network/azureFirewalls/read` |
| `Action` | `Microsoft.Network/azureFirewalls/write` |
| `Action` | `Microsoft.Network/virtualNetworks/read` |
| `Action` | `Microsoft.Network/networkInterfaces/read` |
| `Action` | `Microsoft.Network/publicIPAddresses/read` |
| `Action` | `Microsoft.Network/routeTables/read` |
| `Action` | `Microsoft.HybridCompute/machines/read` |
| `Action` | `Microsoft.OperationalInsights/workspaces/read` |
| `Action` | `Microsoft.OperationsManagement/solutions/read` |
| `Action` | `Microsoft.Compute/virtualMachines/extensions/read` |
| `Action` | `Microsoft.Compute/virtualMachines/extensions/write` |
| `Action` | `Microsoft.HybridCompute/machines/extensions/write` |
| `Action` | `Microsoft.HybridCompute/machines/extensions/delete` |
| `Action` | `Microsoft.HybridCompute/machines/extensions/read` |
| `Action` | `Microsoft.Compute/virtualMachines/extensions/delete` |

## Defender AI

Service role that provides permissions for Microsoft Defender for AI

**Role ID:** `6fe711ec-654d-4ef7-8e32-eb7de3d94774`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.CognitiveServices/accounts/read` |
| `Action` | `Microsoft.CognitiveServices/accounts/defenderForAISettings/read` |
| `Action` | `Microsoft.CognitiveServices/accounts/defenderForAISettings/write` |
| `Action` | `Microsoft.CognitiveServices/accounts/defenderForAISettings/delete` |
| `Action` | `Microsoft.CognitiveServices/raiPolicy/read` |
| `Action` | `Microsoft.CognitiveServices/raiPolicy/write` |
| `Action` | `Microsoft.Search/searchServices/knowledgeBases/read` |

## Defender Storage Malware Data Scanner

Grants data plane permissions for Microsoft Defender for Storage scanning operations — blob/file read, index tag updates.

**Role ID:** `cd50fd1f-0421-46f2-8cce-afc587dbcc77`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Storage/storageAccounts/blobServices/containers/read` |
| `Action` | `Microsoft.Storage/storageAccounts/fileServices/shares/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write` |
| `DataAction` | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/fileServices/fileshares/files/read` |
| `DataAction` | `Microsoft.Storage/storageAccounts/fileServices/readFileBackupSemantics/action` |
| `DataAction` | `Microsoft.EventGrid/events/send/action` |

## Defender Azure SQL Databases

Microsoft Defender for Azure SQL Databases role. Grant permissions for enablement.

**Role ID:** `eef9d654-743f-4e2c-ad0f-9ed243177663`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Sql/managedInstances/read` |
| `Action` | `Microsoft.Sql/managedInstances/securityAlertPolicies/read` |
| `Action` | `Microsoft.Sql/managedInstances/securityAlertPolicies/write` |
| `Action` | `Microsoft.Sql/servers/read` |
| `Action` | `Microsoft.Sql/servers/securityAlertPolicies/read` |
| `Action` | `Microsoft.Sql/servers/securityAlertPolicies/write` |
| `Action` | `Microsoft.Sql/servers/sqlVulnerabilityAssessments/read` |
| `Action` | `Microsoft.Sql/servers/sqlVulnerabilityAssessments/write` |
| `Action` | `Microsoft.Synapse/workspaces/read` |
| `Action` | `Microsoft.Synapse/workspaces/securityAlertPolicies/read` |
| `Action` | `Microsoft.Synapse/workspaces/securityAlertPolicies/write` |
| `Action` | `Microsoft.Sql/servers/vulnerabilityAssessments/read` |
| `Action` | `Microsoft.Synapse/workspaces/vulnerabilityAssessments/read` |
| `Action` | `Microsoft.Sql/managedInstances/vulnerabilityAssessments/read` |
| `Action` | `Microsoft.Sql/servers/sqlVulnerabilityAssessments/delete` |
| `Action` | `Microsoft.Sql/servers/advancedThreatProtectionSettings/read` |
| `Action` | `Microsoft.Sql/servers/advancedThreatProtectionSettings/write` |
| `Action` | `Microsoft.Sql/managedInstances/advancedThreatProtectionSettings/write` |
| `Action` | `Microsoft.Sql/managedInstances/advancedThreatProtectionSettings/read` |
| `Action` | `Microsoft.Sql/managedInstances/vulnerabilityAssessments/write` |
| `Action` | `Microsoft.Sql/managedInstances/vulnerabilityAssessments/delete` |
| `Action` | `Microsoft.Security/SqlVulnerabilityAssessments/read` |
| `Action` | `Microsoft.Security/SqlVulnerabilityAssessments/write` |

## Defender Storage Malware Operator

Grants permissions for Microsoft Defender for Storage malware scanning operations including blob/file read, index tag updates, EventGrid management, and network bypass.

**Role ID:** `971cce9f-2680-4357-9678-c947847a9425`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Security/defenderforstoragesettings/read` |
| `Action` | `Microsoft.Security/defenderforstoragesettings/write` |
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/read` |
| `Action` | `Microsoft.Security/advancedThreatProtectionSettings/write` |
| `Action` | `Microsoft.Security/securityOperators/read` |
| `Action` | `Microsoft.Storage/storageAccounts/write` |
| `Action` | `Microsoft.Storage/storageAccounts/read` |
| `Action` | `Microsoft.EventGrid/topics/read` |
| `Action` | `Microsoft.EventGrid/register/action` |
| `Action` | `Microsoft.EventGrid/eventSubscriptions/read` |
| `Action` | `Microsoft.EventGrid/eventSubscriptions/write` |
| `Action` | `Microsoft.EventGrid/eventSubscriptions/delete` |
| `Action` | `Microsoft.Storage/storageAccounts/blobServices/containers/read` |
| `Action` | `Microsoft.Storage/storageAccounts/fileServices/shares/read` |

## Defender Storage Automated Malware Remediation

Grants additional permissions for Microsoft Defender for Storage automated remediation operations including soft-delete management and blob deletion.

**Role ID:** `c6c9b2d8-9a5e-4122-85e1-81612a046ab2`

| Permission Type | Permission |
|---|---|
| `Action` | `Microsoft.Storage/storageAccounts/blobServices/read` |
| `Action` | `Microsoft.Storage/storageAccounts/blobServices/write` |
| `DataAction` | `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete` |
