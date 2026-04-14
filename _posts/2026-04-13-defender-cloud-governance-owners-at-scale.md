---
title: Defender for Cloud - Managing Recommendation Owners at Scale
author: pit
date: 2026-04-13
categories: [Blogging]
tags: [azure, defender, defender cloud, mdc, governance, powershell, security, arg]
render_with_liquid: false
---

Governance rules in `Defender for Cloud` are a great way to drive remediation accountability - but when owners go stale (people leave, addresses change), cleaning them up through the portal quickly becomes a manual chore. Here's how to handle it at scale using Azure Resource Graph and a couple of PowerShell functions.

## What Are Governance Rules?

Governance rules are a feature in Microsoft Defender for Cloud designed to push remediation responsibility down to the right teams. Instead of a central security team owning every open recommendation, you define rules that automatically assign owners to specific recommendations based on criteria like subscription, resource type, or severity.

Each assignment attaches an owner (an email address) to a recommendation with an optional due date and grace period. The idea is simple: security findings should belong to the person or team responsible for the affected resource, not to whoever happens to be looking at the Defender dashboard.

> More details on how governance rules work: <https://learn.microsoft.com/en-us/azure/defender-for-cloud/governance-rules>
{: .prompt-info}

## The Problem: Orphaned Owners at Scale

The concept is solid, but over time governance assignments accumulate stale owners - people who have left the organisation, distribution lists that no longer exist, or addresses that were set during a pilot and never revisited. At that point, the assignments are noise: they show up as assigned but nobody is actually acting on them. This is as even when owners on resources change, the old assignments don't automatically update or remove themselves. They just linger until someone manually cleans them up.

The natural instinct is to fix this through the portal. As far as I can tell, there's no bulk management view that lets you select and remove owners across hundreds of assignments in one go. Thus the API is the way to go.

> ⚠️ The approach below uses `DELETE` to remove the governance assignment entirely. If you want to reassign to a new owner instead of removing, swap the method to `PATCH` and include the updated owner in the request body. Same approach, different HTTP verb.
{: .prompt-warning}

## The Fix: Resource Graph + Invoke-AzRest

Governance assignments are surfaced in Azure Resource Graph under the `securityresources` table as type `microsoft.security/assessments/governanceassignments`. That means you can enumerate every assignment across your entire tenant with a single ARG query - then loop over the results and hit the REST API to delete each one.

Two functions do the job. The first is a general-purpose paged ARG query helper (ARG caps results at 1000 rows per call, so pagination matters at scale). The second does the actual work to delete the assignments.

```powershell
function Invoke-AzResourceGraphQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$query
    )

    $assignments = @()
    $skipToken   = $null

    do {
        $argParams = @{ Query = $query; First = 1000 }
        if ($skipToken) { $argParams["SkipToken"] = $skipToken }

        $page      = Search-AzGraph @argParams
        $assignments += $page.Data ?? $page
        $skipToken  = $page.SkipToken
    } while ($skipToken)

    return $page
}

function Remove-DefenderCloudRecommendationOwnersAtScale {
    param(
        [string]$Method     = "DELETE",
        [string]$apiVersion = "2025-05-04"
    )

    $query = 'securityresources | where type == "microsoft.security/assessments/governanceassignments" | project id'
    $assignments = Invoke-AzResourceGraphQuery -query $query

    $assignments | ForEach-Object {
        try {
            $response = Invoke-AzRest -Method $Method -Path $($_.ResourceId + "?api-version=" + $apiVersion)
            Write-Host $($response.RequestUri) -ForegroundColor Green
        }
        catch {
            Write-Error $_.Exception.Message
        }
    }
}
```

> You'll need the `Az.ResourceGraph` module for `Search-AzGraph` and the `Az` module for `Invoke-AzRest`. Make sure you're connected with `Connect-AzAccount` and have sufficient permissions on the subscriptions you're targeting.
{: .prompt-tip}

Once connected, running `Remove-DefenderCloudRecommendationOwnersAtScale` will enumerate all governance assignments in scope and delete them one by one, printing each request URI to the console as it goes.

## Conclusion

Governance rules are worth using - automatic owner assignment at scale is genuinely useful when your Defender estate spans many subscriptions. The weak point is lifecycle management: the portal doesn't give you a clean way to bulk-remove or reassign stale owners, so a small scripted wrapper around the REST API fills that gap nicely.

The same pattern extends beyond just deleting owners. Swap `DELETE` for `PATCH` with an updated owner payload and you have a bulk reassignment tool. The `securityresources` table in ARG is the common thread - it's a reliable source of truth for everything governance-related across your tenant.
