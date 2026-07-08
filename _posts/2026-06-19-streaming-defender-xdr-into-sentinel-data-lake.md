---
title: Streaming Defender XDR into the Sentinel Data Lake - Event Hub and DCR, Made Reusable
author: pit
date: 2026-06-19
categories: [Blogging, Tutorial]
tags: [azure, event hub, sentinel, dcr, azure monitor, log analytics, data lake, ingestion, data collection, powershell]
render_with_liquid: false
---

In my previous post, [Ingestion into Sentinel via Event Hub made simple](/posts/ingestion-into-sentinel-via-event-hub-made-simple/), I walked through the Azure Monitor preview feature that allows a Data Collection Rule (DCR) to consume directly from Event Hub and land the data in a Log Analytics custom table.

Since then I have improved the deployment script quite a bit. The original version was intentionally simple and showed the moving parts one by one. The updated version is more reusable, easier to extend across multiple sources, and better suited for running repeatedly without breaking on resources that already exist.

> The updated script is available here: <https://github.com/pisinger/scripts-lib/blob/main/defender/ingestion-into-sentinel-via-event-hub-and-dcr/ingestion-into-sentinel-via-event-hub-and-dcr.ps1>
{: .prompt-tip}


## 🎯 My Use Case

My current use case is Microsoft Defender XDR data that I want to make available in Sentinel, especially tables that cannot yet be enabled directly for Data Lake.

One example is `CloudProcessEvents`. Defender XDR can stream this table into Event Hub, and from there the updated script can create the matching Event Hub to DCR to Sentinel ingestion path.

I would also like to use the same pattern for `CloudDnsEvents`, but as of writing this blog post, that table is not covered by the Defender streaming API at all. That is why you will see it in the backup example data map, but not in the active `$dataMap` used by the script.

The whole flow, from [Defender XDR streaming api](https://learn.microsoft.com/en-us/defender-xdr/streaming-api) all the way into the Sentinel data lake, looks like this:

```text
  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐
  │ Defender XDR │ ──► │  Event Hub   │ ──► │   DCR/DCE    │ ──► │ Sentinel         │
  │  streaming   │     │  namespace   │     │  (+ DCRA)    │     │ Data Lake (Aux)  │
  └──────────────┘     └──────────────┘     └──────────────┘     └──────────────────┘

  what the script does:
  #  1 - create event hubs within namespace if not exist  
  #  2 - create custom table of type aux, basic or analytics   -> make sure DCE is linked to workspace
  #  3 - create DCR to send data into above custom table       -> deploy custom template
  #  4 - associate the DCR with the event hub (DCRA)           -> deploy custom template
  #  5 - assign event hub receiver permission to DCR identity  -> role assignment
```

## 🔄 What Changed?

The overall architecture stays the same:

>- Event Hub receives the source data.
>- A Data Collection Rule uses the special Event Hub data import stream.
>- The DCR sends the data to a custom table in the Sentinel workspace.
>- The DCR managed identity receives `Azure Event Hubs Data Receiver` on the Event Hub.
>- A Data Collection Rule Association (DCRA) links the Event Hub to the DCR.
{: .prompt-info}

The improvement is mostly in how the script models and deploys this pipeline.

Instead of hard-coding a single set of JSON templates and replacing placeholder strings everywhere, the script now uses a proper PowerShell `param(...)` block, a structured data map, dynamic table schemas, dynamic DCR stream declarations, and existence checks around the Azure resources.

That makes it much easier to onboard one more data source without rewriting the deployment logic.

## ⚙️ Parameterized Inputs

The script now starts with the key Azure resource IDs as parameters:

```shell
param(
    # needs to match DCE location
    $location = "westeurope",
    $workspaceId = "/subscriptions/<sub_id>/resourcegroups/<resource_group>/providers/microsoft.operationalinsights/workspaces/<workspace_name>",
    $dce_id = "/subscriptions/<sub_id>/resourceGroups/<resource_group>/providers/Microsoft.Insights/dataCollectionEndpoints/<data_collection_endpoint_name>",
    $eventHubNamespaceId = "/subscriptions/<sub_id>/resourceGroups/<resource_group>/providers/Microsoft.EventHub/namespaces/<event_hub_namespace>"
)
```

You now keep the deployment logic intact and only pass the environment-specific values when running the script. Everything else (namespace name, resource groups, and so on) is derived from these IDs, so the Event Hub namespace and Sentinel workspace can live in different resource groups.

## 🗺️ A Better Data Map

The biggest improvement is the new `$dataMap` structure. Each source now defines the Sentinel table name, Event Hub name, partition count, table plan, retention, and table columns in one place.

```shell
$dataMap = @{
    "CloudProcessEvents" = @{
        name = "CloudProcessEvents";
        # use this eh name so we can simply re-use the auto created event hubs from XDR
        eh_name = "insights-logs-advancedhunting-cloudprocessevents"
        partitions = 10;
        # aux = data lake
        plan = "Auxiliary";
        totalRetentionInDays = 180;
        columns = @(
            @{ name = "TimeGenerated"; type = "datetime"; description = "The time at which the data was ingested." },
            @{ name = "RawData"; type = "string"; description = "Body of the event." }
        )
    }
}
```

The important part is the split between `name` and `eh_name`.

`name` controls the Log Analytics custom table and DCR naming. `eh_name` controls the actual Event Hub resource name. This allows the script to reuse Event Hubs that were created by another service, for example Microsoft Defender XDR streaming.

In the example above, the source is modeled as `CloudProcessEvents`, while the Event Hub itself uses the Defender streaming naming convention:

```shell
insights-logs-advancedhunting-cloudprocessevents
```

That is cleaner than forcing your Sentinel table names to match the Event Hub naming exactly.

## 🔁 Idempotent Event Hub Creation

The original walkthrough created Event Hubs straight from the source map. The updated script first checks whether the Event Hub already exists, and only creates it if it does not:

```shell
if (-not $(Get-AzEventHub ... -Name $item.eh_name -ErrorAction SilentlyContinue)) {
    New-AzEventHub ... -Name $item.eh_name -PartitionCount $item.partitions
}
```

This makes the script safer to rerun. If the Event Hub already exists, the script moves on instead of failing or trying to recreate it.

## 🧱 Dynamic Custom Table Schema

The custom table payload is also generated from the data map now. This means each source can define its own columns without maintaining separate JSON templates.

```shell
$columnsJson = $item.columns | ForEach-Object {
    @{
        name = $_.name;
        type = $_.type;
        description = $_.description
    }
}

$tableParams = @{
    properties = @{
        plan = $item.plan;
        totalRetentionInDays = $item.totalRetentionInDays;
        schema = @{
            name = $($item.name + "_CL");
            columns = $columnsJson
        }
    }
}

$jsonPayload = $tableParams | ConvertTo-Json -Depth 5
```

For raw Event Hub ingestion, the minimal schema is still usually enough:

- `TimeGenerated`
- `RawData`

## 🌊 Dynamic DCR Stream Declarations

> The DCR still uses the special Event Hub stream: `Custom-MyEventHubStream`
{: .prompt-tip}

That part has not changed. What changed is how the stream declaration is created. The script now builds the stream declaration from the same column definitions used for the custom table:

```shell
$columns = $item.columns | ForEach-Object {
    @{
        name = $_.name;
        type = $_.type
    }
}

$streamDeclarations = @{
    "Custom-MyEventHubStream" = @{
        columns = $columns
    }
}

$templateObject = $dcrTemplate | ConvertFrom-Json
$templateObject.resources[0].properties.streamDeclarations = $streamDeclarations
```

This keeps the table schema and DCR input stream aligned. If you add a column to the data map, the custom table and the DCR declaration both pick it up.

The data flow remains the key part of the DCR:

```json
"dataFlows": [
  {
    "streams": [ "Custom-MyEventHubStream" ],
    "destinations": [ "MyDestinationWorkspace" ],
    "transformKql": "source",
    "outputStream": "[concat('Custom-', parameters('tableName'))]"
  }
]
```

For a table named `CloudProcessEvents_CL`, the output stream becomes:

```txt
Custom-CloudProcessEvents_CL
```

## 🔐 Role Assignment and DCRA Checks

The updated script applies the same idempotent pattern to the last two steps: it assigns the `Azure Event Hubs Data Receiver` role to the DCR managed identity only if it is missing, and it checks for an existing Data Collection Rule Association before creating one. Both use the real Event Hub name from `eh_name`, which matters when the logical source name and the Event Hub resource name differ.

This is another practical improvement for reruns and iterative testing.

## 💡 Why This Matters

The first version was great for explaining the feature. The improved version is closer to something you can keep using:

- The source configuration lives in one data map.
- Event Hub names can differ from Sentinel table names.
- Custom table schemas are generated per source.
- DCR stream declarations are generated from the same schema.
- Existing Event Hubs, role assignments, and DCR associations are handled more gracefully.
- Event Hub and workspace resource groups can be different.

That last point is easy to overlook. In real environments, Event Hub namespaces often sit in a shared integration resource group, while Sentinel and Log Analytics live somewhere else. The updated script handles that pattern much better.

When rerunning the script against an already configured source, the output should look similar to this:

```shell
✅ Event hub already exists: CloudProcessEvents --> insights-logs-advancedhunting-cloudprocessevents
ℹ️ Update existing workspace table: CloudProcessEvents -> 202
✅ Creating DCR for event hub: CloudProcessEvents  -> Succeeded
✅ Role assignment already exists for event hub: CloudProcessEvents
✅ Associating DCR already done for event hub: CloudProcessEvents
```

That is the behavior I want from this kind of deployment helper: update what can be updated, skip what is already in place, and make the state visible while it runs.

## 📌 Quick Reminder

The core Azure Monitor requirements from the first post still apply:

>- The Log Analytics workspace must use a supported SKU for Event Hub data imports.
>- The Data Collection Endpoint must already exist.
>- The DCR uses `Custom-MyEventHubStream` for Event Hub data import.
>- The DCR managed identity needs `Azure Event Hubs Data Receiver` on the Event Hub.
>- The DCRA must be created at the Event Hub scope.
>- If Event Hub public access is disabled, make sure the relevant trusted Microsoft services path is allowed.
{: .prompt-warning}

Also keep the region requirements in mind. The DCRA is scoped to the Event Hub, while your workspace, DCE, and DCR may be in a different place depending on your design and supported regions.

## 🧾 Conclusion

This follow-up is less about a new Azure feature and more about making the deployment pattern easier to reuse.

The Event Hub to Sentinel ingestion path is still very powerful: Event Hub handles high-volume streaming, Azure Monitor handles the pull into Log Analytics, and Sentinel can query the resulting custom tables without a custom consumer service in the middle. 

> Note: From what I see this feature is still in preview. So check the latest documentation and announcements for any changes or updates to the capabilities and requirements.
{: .prompt-warning}

With the updated script, onboarding another source mostly becomes a data map change instead of a full copy-paste deployment exercise. That is exactly where this pattern becomes useful at scale.
