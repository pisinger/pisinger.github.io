---
title: Sentinel in Defender Unified RBAC - URBAC Roles, Permissions and Row-Level Scoping
author: pit
date: 2026-09-08
categories: [blogging]
tags: [sentinel, defender, defender-xdr, urbac, unified-rbac, rbac, permissions, azure, sentinel-scoping, sentinel-data-lake, security]
render_with_liquid: false
---

While flattening the Defender role definitions for [Defender for Cloud - Built-in Azure Roles and Permissions](/posts/defender-for-cloud-built-in-azure-roles-permissions/), seven roles fell out of `Get-AzRoleDefinition` that had no business sitting in a Defender for Cloud list. They all carry the prefix `Defender Unified RBAC`, and the description Microsoft ships with them is circular to the point of being useless: *"This role is managed and assigned automatically by the Defender Unified RBAC system."*

The permission sets are the giveaway. There is not a single `Microsoft.Security/*` action between them - it is `Microsoft.SecurityInsights/*` and `Microsoft.OperationalInsights/workspaces/*` all the way down. These are Azure-side role definitions supporting Microsoft Sentinel. When you activate a Sentinel workspace in **Microsoft Defender unified RBAC** (URBAC), the Defender portal synchronizes URBAC role assignments into Azure RBAC using these definitions.

That is a different product, a different portal, and a different permission model than Defender for Cloud, so it gets its own post.

> Role mapping reference: <https://learn.microsoft.com/en-us/defender-xdr/compare-rbac-roles#microsoft-sentinel>
{: .prompt-info}

## 🧭 Three Permission Models, One Portal

Sentinel in the Defender portal is governed by three access-control systems at once, and it helps to name them before touching anything:

1. **Azure RBAC** - the classic model. `Microsoft Sentinel Reader`, `Microsoft Sentinel Responder`, `Microsoft Sentinel Contributor`, preferably assigned on the resource group holding the workspace. Direct workspace assignment is supported too, but then the same role must also cover the workspace's SecurityInsights solution resource and, where needed, related resources.
2. **Microsoft Entra ID roles** - `Security Reader`, `Security Operator`, `Security Administrator`, `Global Reader`, `Global Administrator`. Tenant-wide, and they still reach into the Defender portal after URBAC is on.
3. **Defender unified RBAC (URBAC)** - the Defender portal's own model, built from permission groups rather than role definitions, and assignable per Sentinel workspace and per Sentinel scope.

URBAC is not required to onboard a workspace to the Defender portal. Azure RBAC keeps working there without it. What URBAC buys you is one place to delegate across Defender for Endpoint, Defender for Office, Defender for Identity, Defender for Cloud and Sentinel instead of maintaining separate workload permission models.

```text
                        Microsoft Defender portal
                                   │
       ┌───────────────────────────┼───────────────────────────┐
       │                           │                           │
 Entra ID roles             Defender URBAC              Azure RBAC roles
 Security Reader            permission groups           Sentinel Reader
 Security Operator          assigned per workspace      Sentinel Contributor
 Global Admin ...           and per Sentinel scope      Playbook Operator ...
       │                           │                           │
       │                           ▼                           │
       │            ┌──────────────────────────────┐            │
       │            │ MTP Unified RBAC application │            │
       │            │ User Access Administrator    │            │
       │            │ on the activated workspace   │            │
       │            └──────────────┬───────────────┘            │
       │                           │ writes                     │
       │                           ▼                            │
       │          "Defender Unified RBAC *" assignments ─────────►│
       │                                                        │
       └──────────────────────► effective access ◄──────────────┘
                        additive - the broadest grant wins
```

The bottom line of that diagram is the part I would put in front of anyone planning a rollout: access is **additive**, and Sentinel pages in the Defender portal keep honouring ARM permissions alongside URBAC. A user with more rights in Azure RBAC than in URBAC sees more data than their URBAC role suggests. URBAC is the management surface, not a ceiling. Microsoft's own [unified RBAC page](https://learn.microsoft.com/en-us/defender-xdr/manage-rbac) says both things in the same table cell - *"unified RBAC becomes the source of permissions once enabled"* one sentence before it concedes that users with more ARM permissions than URBAC permissions *"may see more data in the Sentinel pages in the Defender portal than configured in their URBAC permissions"*. Plan against the second sentence, not the first.

> ⚠️ Activating URBAC does not revoke anything that Azure RBAC or Entra ID already grants. If you are activating URBAC to *reduce* an analyst's blast radius, you also have to clean up the Azure role assignments and Entra roles they hold - otherwise the tighter URBAC role is decoration.
{: .prompt-warning}

## 🔁 How Sentinel's Azure Roles Map to URBAC

The three Azure RBAC Sentinel roles map onto URBAC roles built from permission groups. Two URBAC roles have no Azure RBAC equivalent at all:

| Azure RBAC Sentinel role | URBAC role | URBAC permissions |
|---|---|---|
| `Microsoft Sentinel Reader` | Defender Unified RBAC Reader | Security operations \ Security data \ Security data basics (read) |
| `Microsoft Sentinel Responder` | Defender Unified RBAC Responder | Security data basics (read), Alerts (manage), Response (manage) |
| `Microsoft Sentinel Contributor` | Defender Unified RBAC Contributor and Responder | Security data basics (read), Alerts (manage), Response (manage), Detection tuning (manage) |
| n/a | Defender Unified RBAC Scoped Reader | Security data basics (read), only for assignments with a Sentinel scope applied |
| n/a | Defender Unified RBAC Data Manager | Data operations \ Data management \ Data (manage) |

Read the `Contributor and Responder` row carefully. In Azure RBAC, `Microsoft Sentinel Contributor` is a broad grant: `Microsoft.SecurityInsights/*`, `Microsoft.Insights/workbooks/*`, `Microsoft.Insights/alertRules/*`, `Microsoft.Resources/deployments/*` and content hub solution installs. Its URBAC counterpart resolves down to responder rights plus one settings permission, `Detection tuning (manage)`, which covers custom detections, alert tuning and threat indicators. Analytics-rule and Sentinel resource management, content hub, workbooks and deployments are not in that mapping and have to come from somewhere else. The synchronized Azure role tells a different story though - it carries `Microsoft.SecurityInsights/*`, `Microsoft.Insights/workbooks/*` and `Microsoft.Resources/deployments/*` (see the [appendix](#-appendix---full-role-definitions)) - so what the ARM assignment permits and what the URBAC groups describe are not the same thing.

Worth being precise about playbooks here: `Microsoft Sentinel Contributor` never ran or authored them in the first place. Manually running playbooks needs `Microsoft Sentinel Playbook Operator`. Creating and editing Consumption playbooks uses `Logic App Contributor`; creating and editing Standard playbooks uses `Logic Apps Standard Developer` or `Logic Apps Standard Contributor`, while `Logic Apps Standard Operator` covers operational actions such as enabling, resubmitting and disabling workflows. None of those permissions exists in URBAC. Workbooks are a similar split - since August 2025 you can create and edit Sentinel workbooks directly in the Defender portal under **Microsoft Sentinel > Threat management > Workbooks** (still preview), but the permission that lets you do it, `Workbook Contributor`, is still an Azure RBAC role assigned in the Azure portal.

That is the detail that would change how I stage a migration: URBAC replaces the analyst roles cleanly, and leaves the engineering roles behind in Azure.

### The roles that never left Azure

Three Sentinel-adjacent roles are explicitly unsupported in URBAC and stay in the Azure portal: `Microsoft Sentinel Playbook Operator`, `Microsoft Sentinel Automation Contributor` and `Workbook Contributor`. In practice you also keep assigning `Logic App Contributor` for Consumption playbooks or the applicable Logic Apps Standard role for Standard playbooks, `Monitoring Contributor` for data collection rules, `Log Analytics Contributor` for the Search feature, and `Template Spec Contributor` for deploying v2.0 content hub solutions.

> ⚠️ Two capabilities are missing from URBAC for Sentinel entirely: you cannot assign Sentinel permissions to a **service principal**, and you cannot assign them to a **GDAP user group**. If your automation authenticates as an app registration - CI/CD that deploys analytics rules, an external SOAR platform, an MSSP tooling stack - or you are a partner operating through GDAP, keep that workspace on Azure RBAC and do not activate it in URBAC yet.
{: .prompt-warning}

> The [governance relationships](https://learn.microsoft.com/en-us/unified-secops/governance-relationships) preview does not lift this restriction either - it is a separate Entra Tenant Governance capability, and Sentinel permissions for the tenants it delegates are still assigned in Azure RBAC.
{: .prompt-info}

## 🔐 The URBAC Permission Groups That Matter for Sentinel

URBAC does not hand you role definitions to copy. You build a custom role by picking permissions out of groups. These are the ones that decide what a Sentinel analyst can do:

| Permission group | Permission | Level | What it covers in Sentinel |
|---|---|---|---|
| Security operations \ Security data | Security data basics | Read | Incidents, alerts, investigations, advanced hunting, reports, data lake data (preview) |
| Security operations \ Security data | Alerts | Manage | Manage alerts, start automated investigations |
| Security operations \ Security data | Response | Manage | Response actions, approve or dismiss pending remediation |
| Authorization and settings | Detection tuning | Manage | Custom detections, alert tuning, threat indicators |
| Authorization and settings | Authorization | Read / Manage | View or manage custom and built-in roles and device groups. The scoping doc names `Security Authorization (Manage)` as what creates Sentinel scopes |
| Data operations \ Data management | Data | Manage | Retention, tier moves, data lake tables, lake connectors |
| Data operations \ Data management | Analytics Jobs Schedule | Read / Manage | Schedule analytics jobs via lake exploration, ADX or notebooks |

The `Data operations` group is in preview and only applies to workspaces onboarded to the Defender portal, plus the Sentinel data lake default workspace. It is also the group behind `Defender Unified RBAC Data Manager`. Its Azure-side definition (in the appendix) reaches further than the name suggests: workspace write, table write and delete, and workspace shared keys.

> In that snapshot, `Data Manager` holds `Microsoft.operationalinsights/workspaces/sharedkeys/action`. Workspace shared keys are a legacy ingestion credential - anything holding that key can write to the workspace. Treat `Data (manage)` as a privileged permission, not a data-hygiene one.
{: .prompt-warning}

## ⚙️ What Activation Actually Does

Activation is per workspace, from **System > Permissions > Microsoft Defender XDR > Roles > Workload settings**, then **View Workspaces**. To do it you need:

- `Security Administrator` in Microsoft Entra ID, **and**
- subscription `Owner`, **or** `User Access Administrator` plus `Microsoft Sentinel Contributor` on the workspace

Under the covers, the platform assigns `User Access Administrator` to the **MTP Unified RBAC** application on the activated workspace. From then on, Sentinel role assignments made in URBAC synchronize into Azure RBAC and are visible there. Microsoft documents that synchronization, but not which of the seven definitions a given activation ends up assigning - `Get-AzRoleAssignment` at workspace scope is the only way to see what your own tenant got.

It is important not to mix up the definitions with their assignments. [`Get-AzRoleDefinition`](https://learn.microsoft.com/en-us/powershell/module/az.resources/get-azroledefinition) lists roles available for assignment and is the right command for inspecting their permission sets:

```shell
# per role - name, ID and each permission bucket
Get-AzRoleDefinition |
    Where-Object Name -Like "Defender Unified RBAC*" |
    ForEach-Object {
        [pscustomobject]@{
            Role           = $_.Name
            Id             = $_.Id
            Actions        = (($_.Permissions.Actions        + $_.Permissions.Action)        | Where-Object { $_ }) -join "; "
            NotActions     = (($_.Permissions.NotActions     + $_.Permissions.NotAction)     | Where-Object { $_ }) -join "; "
            DataActions    = (($_.Permissions.DataActions    + $_.Permissions.DataAction)    | Where-Object { $_ }) -join "; "
            NotDataActions = (($_.Permissions.NotDataActions + $_.Permissions.NotDataAction) | Where-Object { $_ }) -join "; "
        }
    } | Format-List
```

Same data one row per permission, which is the shape the appendix tables are built from:

```shell
Get-AzRoleDefinition |
    Where-Object Name -Like "Defender Unified RBAC*" |
    ForEach-Object {
        $role = $_
        foreach ($set in $role.Permissions) {
            $set.PSObject.Properties |
                Where-Object Name -Match '^(Not)?(Data)?Actions?$' |
                ForEach-Object {
                    $type = $_.Name -replace 's$'
                    foreach ($permission in $_.Value) {
                        [pscustomobject]@{
                            Role       = $role.Name
                            Id         = $role.Id
                            Type       = $type
                            Permission = $permission
                        }
                    }
                }
        }
    } | Sort-Object Role, Type, Permission | Format-Table -AutoSize
```

> The permission arrays hang off the `Permissions` collection on each role definition, not off the role object itself - `Select-Object Name, Id, Actions` comes back empty. Property names inside that collection are singular in the newer generated `Az.Resources` cmdlets (`Action`, `NotAction`) and plural in older ones, so both scripts above cover either shape.
{: .prompt-info}

To do the same for the classic Sentinel roles, run the below:

```shell
# classic azure rbac sentinel roles
Get-AzRoleDefinition | Where-Object Name -Like "Microsoft Sentinel*" |
	ForEach-Object {
		$role = $_
		foreach ($set in $role.Permissions) {
			$set.PSObject.Properties |
				Where-Object Name -Match '^(Not)?(Data)?Actions?$' |
				ForEach-Object {
					$type = $_.Name -replace 's$'
					foreach ($permission in $_.Value) {
						[pscustomobject]@{
							Role       = $role.Name
							Id         = $role.Id
							Type       = $type
							Permission = $permission
						}
					}
				}
		}
	} | Sort-Object Role, Type, Permission | Format-Table -AutoSize
```

Use [`Get-AzRoleAssignment`](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-list-powershell) to find which of them the MTP application has actually assigned on a workspace:

```shell
Get-AzRoleAssignment -Scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.OperationalInsights/workspaces/<workspace>" |
    Where-Object RoleDefinitionName -Like "Defender Unified RBAC*" |
    Select-Object DisplayName, RoleDefinitionName, Scope
```

Mapped back to their purpose, the seven definitions in my 3 September 2026 snapshot look like this. Microsoft Learn documents the first five names and their URBAC mappings, but does not publish this complete ID table or the two Authorization definitions, so treat the IDs and raw actions as observed implementation detail:

| Azure role | Role ID | Backs |
|---|---|---|
| `Defender Unified RBAC Reader` | `78b7345a-1e1b-483a-ac62-62228c6ea89d` | URBAC Reader - Sentinel Reader equivalent |
| `Defender Unified RBAC Responder` | `1bacae94-6c0f-4d2d-8dfa-408d5a28e6ec` | URBAC Responder - Sentinel Responder equivalent |
| `Defender Unified RBAC Contributor and Responder` | `625a1cea-653b-4a19-bd3a-df1d66ab6637` | URBAC Contributor and Responder |
| `Defender Unified RBAC Scoped Reader` | `d56b031f-8d90-4376-9231-b5c94fce88ef` | Row-level scoped read |
| `Defender Unified RBAC Data Manager` | `40ead2a5-466e-4039-8a80-325542d9d2dd` | Data operations \ Data (manage) |
| `Defender Unified RBAC Authorization Reader` | `ca62263b-07d5-4b48-b437-088803f5c2ff` | Authorization plane - no `Actions` in the definition |
| `Defender Unified RBAC Authorization Manager` | `1fd5d8bf-9037-4ede-89bf-680f798e2765` | Authorization plane - no `Actions` in the definition |

The two Authorization roles carry no `Actions`, `NotActions` or `DataActions` at all in the snapshot I pulled - see the [appendix](#-appendix---full-role-definitions). Microsoft does not document what they are for, and an empty definition grants nothing on its own.

The full permission tables for all seven roles, straight out of the role definitions, are in the [appendix](#-appendix---full-role-definitions) at the end of this post - they were originally captured in the [Defender for Cloud roles post](/posts/defender-for-cloud-built-in-azure-roles-permissions/).

> ⚠️ Once a workspace is active in URBAC, manage its Sentinel permissions **in the Defender portal only**. Changing them in the Azure portal afterwards can produce sync errors; the Defender **Permissions** page then shows a notification telling you how to resolve it. Deactivating a workload silently reverts to the old model - the URBAC roles you built stop taking effect.
{: .prompt-warning}

Two more asymmetries worth knowing before you plan delegation:

- A `Global Administrator` gets no automatic permissions over workspaces in URBAC. What they do get is the right to assign permissions - **including to themselves**. That is a one-step path from directory role to full Sentinel data access, and it belongs in your privileged-access review.
- Sentinel scopes can only be attached to Defender XDR RBAC roles. Azure RBAC permissions on the workspace and Entra global role permissions cannot carry a scope, so a user holding, say, `Global Reader` is simply unrestricted by scoping. Microsoft's own example is a user with `Global Reader` plus a scoped URBAC role on system tables - the Entra role wins and the scope does not apply.

## 🎯 Row-Level RBAC with Sentinel Scoping (Preview)

`Defender Unified RBAC Scoped Reader` is the piece with no Azure RBAC ancestor. Sentinel scoping gives you row-level access control inside a single workspace - the long-standing answer to "do we split the workspace per business unit or per customer". It arrived in **April 2026 and is still in preview**, so treat this section as subject to change.

To configure it you need `Security Authorization (Manage)` in URBAC for the scopes and assignments, `Data Operations (Manage)` plus `Alerts (Manage)` for table management, and either Subscription Owner or `Microsoft.Insights/DataCollectionRules/Write` to create the DCRs.

The mechanics are four steps:

1. Create named scopes under **System > Permissions > Microsoft Defender XDR > Scopes**. Up to 100 per tenant.
2. Assign users or Entra groups to one or more scopes on a custom URBAC role.
3. Tag rows at ingestion time - **Microsoft Sentinel > Configuration > Tables > Scope tag rule**, with a KQL expression such as `Location == 'Spain'`. Saving the rule creates a Data Collection Rule that stamps the scope onto matching rows.
4. Scoped users then see only alerts, incidents, hunting results and lake data derived from their rows.

Behind the toggle sits a plain string column, `SentinelScope_CF`. If you already manage schemas and ingestion-time transformations as code, you can add that column and populate it from your own DCR, then set **Control access with scope tags** to On while leaving **Rule status** Off so the portal does not fight your deployment.

```shell
// scope-aware detection - the scope column must be projected
// or the alerts this rule raises come out unscoped
SigninLogs
| where ResultType != 0
| where Location == "Spain"
| summarize FailedAttempts = count() by UserPrincipalName, SentinelScope_CF
| where FailedAttempts > 25
```

> When you write custom detections or analytics rules that should respect scoping, you **must** project `SentinelScope_CF` in the query. Without it the rule still runs, still fires, and produces alerts that scoped users cannot see - a silent detection gap rather than an error.
{: .prompt-warning}

The constraints are real and worth reading before designing around scoping:

| Constraint | Detail |
|---|---|
| Table support | Only tables that support ingestion-time transformations. `CLv2` custom tables yes, `CLv1` no |
| XDR tables | Not supported, including XDR extended retention into the lake |
| Historical data | Only newly ingested rows get tagged. No retroactive scoping |
| Latency | Up to an hour for a new scope tag rule to take effect |
| Subscription boundary | Transformations must live in the same subscription as the target workspace |
| Alert and incident tables | The Log Analytics `SecurityAlert` and `SecurityIncident` tables do not inherit scope from source tables. The XDR `AlertInfo` and `AlertEvidence` tables do (Microsoft's scoping doc pluralizes all four table names) |
| Custom detections | Detections over `AlertInfo` and `AlertEvidence` ignore scopes and run over all data. A scoped detection on an unscoped table always returns nothing, and scoped detections cannot use custom frequency against XDR tables |
| Notebooks | Experiences that cannot apply row-level RBAC, such as Jupyter notebooks, show scoped users no data for that workspace |
| Playbooks | Playbooks and integrations do not support Sentinel scoping yet. Automation rules do - pick the scope on the **Enhanced rules** tab under **Microsoft Sentinel > Configuration > Automation** |
| Managing resources | Scoped users cannot manage detection rules, playbooks or automation rules unless that permission comes from a separate role assignment |

Two behaviours matter for how an incident looks to a scoped analyst: they can **view** an incident if they have access to at least one of its alerts, but can only **manage** it if they have access to all of them. And unscoped users still see everything in the workspace - scoping restricts, it never expands.

> ⚠️ Scoping is configured in the Defender portal only. Sentinel in the Azure portal has no support for it, and there is no path to it via Azure RBAC.
{: .prompt-warning}

## 📊 The Data Lake Sits Half in Each Model

If the workspace is onboarded to both the Defender portal and the Sentinel data lake, permissions split along a line that is easy to trip over: the **default data lake workspace** and its system tables are governed by URBAC, and every other workspace in the lake is governed by Azure RBAC on that workspace. The URBAC side of the lake has been in preview since it shipped in July 2025, and building custom roles for the lake is preview as well.

| Task | Permission |
|---|---|
| Read system tables in the lake | Custom URBAC role with `security data basics (read)` over the Microsoft Sentinel data collection |
| Update system tables in the lake | Custom URBAC role with `data (manage)` over the Microsoft Sentinel data collection |
| Read every workspace in the lake at once | Entra ID `Global Reader`, `Security Reader`, `Security Operator`, `Security Administrator` or `Global Administrator` - broad, tenant-wide, and unrestricted by Sentinel scoping |
| Write lake tables or analytics-tier tables via KQL jobs and notebooks | Entra ID `Security Operator`, `Security Administrator` or `Global Administrator` |
| Read any other workspace in the lake | Azure RBAC on that workspace - `Log Analytics Reader`, `Microsoft Sentinel Reader`, `Reader` and upwards |
| Write to any other workspace in the lake | Azure RBAC actions `workspaces/write`, `workspaces/tables/write`, `workspaces/tables/delete` |
| Create or manage scheduled lake jobs | Microsoft's [URBAC permission catalog](https://learn.microsoft.com/en-us/defender-xdr/custom-permissions-details#data-operations-preview) lists `Analytics Jobs Schedule` (read/manage), while the [Sentinel roles page](https://learn.microsoft.com/en-us/azure/sentinel/roles#manage-jobs-in-the-microsoft-sentinel-data-lake) still says Entra ID `Security Operator`, `Security Administrator` or `Global Administrator` is required |

That last row is a genuine documentation conflict as of 3 September 2026, and the two answers are a tenant-wide Entra role apart. Test the least-privilege URBAC permission in the target tenant before you plan around it.

### The Sentinel MCP server runs on Entra roles, not URBAC

The [Microsoft Sentinel MCP server](https://learn.microsoft.com/en-us/azure/sentinel/datalake/sentinel-mcp-get-started) gates access on Microsoft Entra ID directory roles, and it does so for **whichever identity calls it** - your own user account under on-behalf-of authentication in VS Code, Security Copilot, Copilot Studio or Foundry, just as much as a managed identity or service principal running an agent unattended. Microsoft's wording covers all three: access is supported for *"users, managed identities, or service principals"* holding at least `Security Reader`. A URBAC role does not satisfy it in any of those cases, and for a service principal there is no URBAC option to begin with.

| Task | Entra ID role on the calling identity |
|---|---|
| List and invoke the Sentinel MCP tool collections | `Security Reader` at minimum, or `Security Operator` / `Security Administrator` |
| List and invoke custom MCP tools | `Security Reader` or `Global Reader` |
| Create, update or delete custom MCP tools | `Security Operator`, `Security Administrator` or `Global Administrator` |
| Reach graph data in the Defender portal | Additionally read-only access in Microsoft Security Exposure Management |

Note what that does to least privilege. `Security Reader` is tenant-wide, and the Sentinel roles page lists it among the roles that read **all** workspaces in the data lake - and scopes cannot rein it in, because they attach only to Defender XDR RBAC roles. The MCP tools do not bypass scoping; you simply cannot onboard a scoped analyst to them without first granting a role their scope was never able to constrain.

The [triage tool collection](https://learn.microsoft.com/en-us/azure/sentinel/datalake/sentinel-mcp-triage-tool) is the one that behaves differently, though not as an exemption from the prerequisite: Microsoft describes it as enforcing existing permissions, so users can only reach data their role already grants.

## ⚠️ Limitations and Open Questions

**Current product behaviour:**

- Sentinel activation in URBAC is per workspace, not tenant-wide.
- Service principals and GDAP assignments aren't currently supported for Sentinel URBAC role assignments. Azure RBAC is still required for those scenarios. [Governance relationships](https://learn.microsoft.com/en-us/unified-secops/governance-relationships) (preview) are a separate Entra Tenant Governance capability, not the Partner Center GDAP relationship. They provide delegated access to Defender XDR across tenants, but don't remove the Azure RBAC dependency for Sentinel scenarios that URBAC doesn't yet support.
- `Playbook Operator`, `Automation Contributor` and `Workbook Contributor` stay in Azure.
- URBAC does not override ARM. Broader ARM permissions still show more data in the Defender portal.
- `Data operations` permissions, the URBAC side of the Sentinel data lake, and custom roles for the lake are all in preview.
- Sentinel scoping is in preview. It requires ingestion-time transformations, tags only new data, and does not cover playbooks or notebooks.
- In multitenant management, *viewing* unified RBAC went GA in August 2025 but *creating and editing* custom roles there is still preview - relevant if you are an MSSP planning to drive this from the MTO portal.

**Open questions, and my own reading:**

- The `Authorization Reader` and `Authorization Manager` roles ship with no permissions. Whether they are placeholders for a future authorization surface or purely internal markers is not documented, and I would not build anything on top of them.
- `Microsoft Sentinel Contributor` maps to responder plus `Detection tuning (manage)` and nothing more, which leaves content hub, workbook and playbook management outside URBAC. With Sentinel in the Azure portal retiring after **31 March 2027**, either those capabilities arrive in URBAC or organisations keep a parallel set of Azure role assignments alongside it. Microsoft has not said which, so plan for the parallel assignments and treat anything better as a bonus.
- Scope inheritance stopping at the Log Analytics `SecurityAlert` and `SecurityIncident` tables is the sharpest edge in scoping. The documented workaround - tag those tables manually - is explicitly not equivalent to inheritance, so a federated-SOC design that relies on them needs testing rather than assumption.
- Nothing in the model reconciles Entra global roles with scopes, and by design nothing can - scopes only attach to Defender XDR RBAC roles. So treat row-level RBAC as a delegation tool rather than a hard data boundary: it restricts the users you scope, but anyone holding a global Entra role still sees past it, which is worth knowing before you lean on scoping in a compliance argument.

## 📝 Conclusion

The seven `Defender Unified RBAC *` definitions visible in your Azure context are not roles you should assign manually, and they are not Defender for Cloud roles. They are Microsoft-managed building blocks used when the Defender portal synchronizes Sentinel URBAC assignments into Azure RBAC. Seeing them in `Get-AzRoleDefinition` proves only that the definitions are available; use `Get-AzRoleAssignment` at the workspace scope to identify the assignments the MTP Unified RBAC application actually created. Leaving those platform-managed assignments alone is the correct response.

For the model itself, the useful mental split is analysts versus engineers. URBAC maps the analyst roles cleanly - reader, responder, contributor - and adds row-level scoping that Azure RBAC never offered. It does not yet cover the engineering surface: playbook and workbook permissions, content hub, data collection rules, service principals. Until it does, a Sentinel deployment in the Defender portal runs on both models at once, and the permissions that actually apply are the union of everything a user holds across all three.

If you are planning this, start by auditing what your analysts already hold in Azure RBAC and Entra ID. Activating URBAC on top of unreviewed assignments changes where you manage permissions without changing what anyone can reach.

## 📎 Appendix - Full Role Definitions

For reference, here are the complete permission sets of all seven `Defender Unified RBAC *` definitions, exactly as they came out of `Get-AzRoleDefinition` in my 3 September 2026 snapshot. The same tables also appear in the [Defender for Cloud roles post](/posts/defender-for-cloud-built-in-azure-roles-permissions/), where they were originally captured.

Two things to read out of them before scrolling the tables:

- The Azure-side definitions are **broader than the URBAC permission-group mapping suggests**, and where the two disagree it is the ARM actions the resource provider enforces.
- Every role except `Data Manager` and the two Authorization roles carries the same pair of `NotActions`: `Microsoft.SecurityInsights/ConfidentialWatchlists/*` and `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*`. Confidential watchlists are excluded from all of them, including `Contributor and Responder`.

> These are the definitions, not the assignments, and they are Microsoft-managed. Reproduced here to make the effective ARM permissions auditable - not as a suggestion to assign them by hand.
{: .prompt-info}

### The seven Defender Unified RBAC definitions

The Microsoft-managed roles the Defender portal writes into Azure RBAC when a workspace is activated in URBAC.

#### Defender Unified RBAC Reader

**Role ID:** `78b7345a-1e1b-483a-ac62-62228c6ea89d`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.SecurityInsights/*/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/dataConnectorsCheckRequirements/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/query/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/queryIndicators/action` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/analytics/query/action` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/LinkedServices/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/read` |
| ✅ `Action` | `Microsoft.OperationsManagement/solutions/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/querypacks/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/read` |
| ✅ `Action` | `Microsoft.Insights/workbooks/read` |
| ✅ `Action` | `Microsoft.Authorization/*/read` |
| ✅ `Action` | `Microsoft.Resources/deployments/*` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |
| ⛔ `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |
| `DataAction` | `Microsoft.OperationalInsights/workspaces/tables/data/read` |

#### Defender Unified RBAC Responder

**Role ID:** `1bacae94-6c0f-4d2d-8dfa-408d5a28e6ec`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.SecurityInsights/*/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/dataConnectorsCheckRequirements/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/automationRules/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/cases/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/incidents/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/entities/runPlaybook/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/appendTags/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/query/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/bulkTag/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/appendTags/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/replaceTags/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/queryIndicators/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/systems/undoAction/action` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/analytics/query/action` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/read` |
| ✅ `Action` | `Microsoft.OperationsManagement/solutions/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/querypacks/*/read` |
| ✅ `Action` | `Microsoft.Resources/deployments/*` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| ✅ `Action` | `Microsoft.Insights/workbooks/read` |
| ✅ `Action` | `Microsoft.Authorization/*/read` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/cases/*/Delete` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/incidents/*/Delete` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |
| ⛔ `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |

#### Defender Unified RBAC Contributor and Responder

**Role ID:** `625a1cea-653b-4a19-bd3a-df1d66ab6637`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.OperationalInsights/querypacks/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/analytics/query/action` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/*` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/read` |
| ✅ `Action` | `Microsoft.OperationsManagement/solutions/read` |
| ✅ `Action` | `Microsoft.Resources/deployments/*` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/*/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/automationRules/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/systems/undoAction/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/cases/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/dataConnectorsCheckRequirements/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/entities/runPlaybook/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/incidents/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/bulkTag/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/appendTags/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/query/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/replaceTags/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/queryIndicators/action` |
| ✅ `Action` | `Microsoft.Insights/workbooks/*` |
| ✅ `Action` | `Microsoft.Authorization/*/read` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/cases/*/Delete` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/incidents/*/Delete` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |
| ⛔ `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |

#### Defender Unified RBAC Scoped Reader

**Role ID:** `d56b031f-8d90-4376-9231-b5c94fce88ef`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/read` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |
| ⛔ `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/alertRules/read` |
| `DataAction` | `Microsoft.OperationalInsights/workspaces/tables/data/read` |

#### Defender Unified RBAC Data Manager

**Role ID:** `40ead2a5-466e-4039-8a80-325542d9d2dd`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.operationalinsights/workspaces/read` |
| ✅ `Action` | `Microsoft.operationalinsights/workspaces/write` |
| ✅ `Action` | `Microsoft.operationalinsights/workspaces/query/read` |
| ✅ `Action` | `Microsoft.operationalinsights/workspaces/tables/write` |
| ✅ `Action` | `Microsoft.operationalinsights/workspaces/tables/delete` |
| ✅ `Action` | `Microsoft.operationalinsights/workspaces/sharedkeys/action` |

#### Defender Unified RBAC Authorization Reader

**Role ID:** `ca62263b-07d5-4b48-b437-088803f5c2ff`

No `Actions`, `NotActions` or `DataActions` are present in the role definition.

#### Defender Unified RBAC Authorization Manager

**Role ID:** `1fd5d8bf-9037-4ede-89bf-680f798e2765`

No `Actions`, `NotActions` or `DataActions` are present in the role definition.

### The classic Microsoft Sentinel Azure RBAC roles

For comparison, the roles you assign yourself in the Azure portal - the ones URBAC maps onto, and the ones that stay behind for playbooks and automation. They are noticeably wider than their URBAC counterparts: `Microsoft Sentinel Contributor` carries `Microsoft.SecurityInsights/*`, `Microsoft.Insights/workbooks/*`, `Microsoft.Insights/alertRules/*` and `Microsoft.Support/*`, none of which has an equivalent in the `Detection tuning (manage)` permission it maps to. `Microsoft Sentinel Business Applications Agent Operator` has no URBAC mapping at all.

#### Microsoft Sentinel Reader

**Role ID:** `8d289c81-5878-46d4-8554-54e1e3d8b5cb`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.Authorization/*/read` |
| ✅ `Action` | `Microsoft.Insights/alertRules/*` |
| ✅ `Action` | `Microsoft.Insights/myworkbooks/read` |
| ✅ `Action` | `Microsoft.Insights/workbooks/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/querypacks/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/analytics/query/action` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/LinkedServices/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/read` |
| ✅ `Action` | `Microsoft.OperationsManagement/solutions/read` |
| ✅ `Action` | `Microsoft.Resources/deployments/*` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| ✅ `Action` | `Microsoft.Resources/templateSpecs/*/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/*/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/dataConnectorsCheckRequirements/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/query/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/queryIndicators/action` |
| ✅ `Action` | `Microsoft.Support/*` |
| ⛔ `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |

#### Microsoft Sentinel Responder

**Role ID:** `3e150937-b8fe-4cfb-8069-0eaf05ecd056`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.Authorization/*/read` |
| ✅ `Action` | `Microsoft.Insights/alertRules/*` |
| ✅ `Action` | `Microsoft.Insights/myworkbooks/read` |
| ✅ `Action` | `Microsoft.Insights/workbooks/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/querypacks/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/analytics/query/action` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/read` |
| ✅ `Action` | `Microsoft.OperationsManagement/solutions/read` |
| ✅ `Action` | `Microsoft.Resources/deployments/*` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/*/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/automationRules/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/systems/undoAction/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/cases/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/dataConnectorsCheckRequirements/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/entities/runPlaybook/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/incidents/*` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/bulkTag/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/appendTags/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/appendTags/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/query/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/indicators/replaceTags/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/threatIntelligence/queryIndicators/action` |
| ✅ `Action` | `Microsoft.Support/*` |
| ⛔ `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/cases/*/Delete` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/incidents/*/Delete` |

#### Microsoft Sentinel Contributor

**Role ID:** `ab8e14d6-4a74-4a29-9ba8-549422addade`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.Authorization/*/read` |
| ✅ `Action` | `Microsoft.Insights/alertRules/*` |
| ✅ `Action` | `Microsoft.Insights/myworkbooks/read` |
| ✅ `Action` | `Microsoft.Insights/workbooks/*` |
| ✅ `Action` | `Microsoft.OperationalInsights/querypacks/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/analytics/query/action` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/dataSources/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/*/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/query/read` |
| ✅ `Action` | `Microsoft.OperationalInsights/workspaces/savedSearches/*` |
| ✅ `Action` | `Microsoft.OperationsManagement/solutions/read` |
| ✅ `Action` | `Microsoft.Resources/deployments/*` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/*` |
| ✅ `Action` | `Microsoft.Support/*` |
| ⛔ `NotAction` | `Microsoft.OperationalInsights/workspaces/query/ConfidentialWatchlist/*` |
| ⛔ `NotAction` | `Microsoft.SecurityInsights/ConfidentialWatchlists/*` |

#### Microsoft Sentinel Playbook Operator

**Role ID:** `51d6186e-6489-4900-b93f-92e23144cca5`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.Logic/workflows/read` |
| ✅ `Action` | `Microsoft.Logic/workflows/triggers/listCallbackUrl/action` |
| ✅ `Action` | `Microsoft.Web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action` |
| ✅ `Action` | `Microsoft.Web/sites/read` |

#### Microsoft Sentinel Automation Contributor

**Role ID:** `f4c81013-99ee-4d62-a7ee-b3f1f648599a`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.Authorization/*/read` |
| ✅ `Action` | `Microsoft.Logic/workflows/runs/read` |
| ✅ `Action` | `Microsoft.Logic/workflows/triggers/listCallbackUrl/action` |
| ✅ `Action` | `Microsoft.Logic/workflows/triggers/read` |
| ✅ `Action` | `Microsoft.Web/sites/hostruntime/webhooks/api/workflows/runs/read` |
| ✅ `Action` | `Microsoft.Web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action` |
| ✅ `Action` | `Microsoft.Web/sites/hostruntime/webhooks/api/workflows/triggers/read` |

#### Microsoft Sentinel Business Applications Agent Operator

**Role ID:** `c18f9900-27b8-47c7-a8f0-5b3b3d4c2bc2`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.Authorization/roleAssignments/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/systems/listActions/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/systems/read` |
| ✅ `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/systems/reportActionStatus/action` |
| ✅ `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/systems/write` |
| ✅ `Action` | `Microsoft.SecurityInsights/businessApplicationAgents/write` |

### The Logic Apps roles behind Sentinel playbooks

Playbooks are Logic Apps resources, and no Sentinel or URBAC role writes to them. `Microsoft Sentinel Playbook Operator` runs a playbook; creating or editing one needs a Logic Apps role, assigned in Azure. Two of them, from the same snapshot:

#### Logic App Contributor

**Role ID:** `87a39d53-fc1b-424a-814c-f7e04687dc9e`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.Authorization/*/read` |
| ✅ `Action` | `Microsoft.ClassicStorage/storageAccounts/listKeys/action` |
| ✅ `Action` | `Microsoft.ClassicStorage/storageAccounts/read` |
| ✅ `Action` | `Microsoft.Insights/alertRules/*` |
| ✅ `Action` | `Microsoft.Insights/diagnosticSettings/*` |
| ✅ `Action` | `Microsoft.Insights/logdefinitions/*` |
| ✅ `Action` | `Microsoft.Insights/metricAlerts/*` |
| ✅ `Action` | `Microsoft.Insights/metricDefinitions/*` |
| ✅ `Action` | `Microsoft.Logic/*` |
| ✅ `Action` | `Microsoft.Resources/deployments/*` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/operationresults/read` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| ✅ `Action` | `Microsoft.Storage/storageAccounts/listkeys/action` |
| ✅ `Action` | `Microsoft.Storage/storageAccounts/read` |
| ✅ `Action` | `Microsoft.Support/*` |
| ✅ `Action` | `Microsoft.Web/connectionGateways/*` |
| ✅ `Action` | `Microsoft.Web/connections/*` |
| ✅ `Action` | `Microsoft.Web/customApis/*` |
| ✅ `Action` | `Microsoft.Web/serverFarms/join/action` |
| ✅ `Action` | `Microsoft.Web/serverFarms/read` |
| ✅ `Action` | `Microsoft.Web/sites/functions/listSecrets/action` |

#### Logic Apps Standard Contributor

**Role ID:** `ad710c24-b039-4e85-a019-deb4a06e8570`

| Permission Type | Permission |
|---|---|
| ✅ `Action` | `Microsoft.Authorization/*/read` |
| ✅ `Action` | `Microsoft.Insights/alertRules/*` |
| ✅ `Action` | `Microsoft.Resources/deployments/operations/read` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/operationresults/read` |
| ✅ `Action` | `Microsoft.Resources/subscriptions/resourceGroups/read` |
| ✅ `Action` | `Microsoft.Support/*` |
| ✅ `Action` | `Microsoft.Web/*/read` |
| ✅ `Action` | `Microsoft.Web/certificates/*` |
| ✅ `Action` | `Microsoft.Web/connectionGateways/*` |
| ✅ `Action` | `Microsoft.Web/connections/*` |
| ✅ `Action` | `Microsoft.Web/customApis/*` |
| ✅ `Action` | `Microsoft.Web/serverFarms/*` |
| ✅ `Action` | `Microsoft.Web/sites/*` |

> `Logic Apps Hybrid Contributor` (`32109304-a0e2-4d64-bd07-b23ac5efbe43`) also shows up in my tenant, but it is not listed in Microsoft's [Azure built-in roles for Integration](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/integration) reference, so I have left its permission set out. The Standard companions - `Logic Apps Standard Developer`, `Logic Apps Standard Operator`, `Logic Apps Standard Reader` and `Logic App Operator` - are documented on that same page.
{: .prompt-info}
