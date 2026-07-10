---
title: Defender Endpoint AIR Under the Hood - What SenseIR Events Reveal
author: pit
date: 2026-07-10
categories: [blogging]
tags: [windows, defender, mde, air, automated-investigation, senseir, powershell, eventlog, incident-response]
render_with_liquid: false
---

Sometimes the interesting part of Defender for Endpoint is not only what you see in the Defender portal, but what the endpoint quietly records while the cloud service is doing its work.

I came across this again while looking at Automated Investigation and Response, usually shortened to **AIR**. The portal gives you the investigation story, verdicts, evidence, and remediation state. The local machine, however, also leaves a small but useful trail in the Windows event log. If you want to understand what AIR actually asked the endpoint to collect, `Microsoft-Windows-SenseIR` is worth a look.

> This is not a replacement for the Defender portal investigation view. Treat it as endpoint-side visibility: useful for learning, troubleshooting, and correlating what happened locally while AIR was running.
{: .prompt-info}

## 🧭 What AIR Does

Automated Investigation and Response is the Defender for Endpoint capability that starts investigations from alerts or operator action, examines evidence, assigns verdicts, and can trigger remediation actions depending on the automation level and approvals in your tenant.

Microsoft's own overview is here:

> <https://learn.microsoft.com/en-us/defender-endpoint/automated-investigations>
{: .prompt-info}

One detail is worth calling out, because it affects how long this exact workflow stays relevant:

> ⚠️ As of September 1, 2026, Automated Investigation and Response (AIR) will no longer run as a separate investigation experience or be available for manual triggering in Microsoft Defender.
>
> AIR detection and response capabilities are already included in Microsoft Defender's default antivirus protection stack and run automatically. For on-demand investigations, run a full antivirus scan as needed.
{: .prompt-warning}

So why look at it now? Because the local event trail is still a good way to understand the type of collection and inspection actions Defender performs on an endpoint.

## 📡 The Local Provider

The provider I am using here is:

```text
Microsoft-Windows-SenseIR
```

The name already hints at the purpose: Sense incident response. On a device where AIR activity has happened, it records entries such as client registration and finished uploads for individual actions.

The beginning of an investigation may show a registration event:

```text
ProviderName: Microsoft-Windows-SenseIR

TimeCreated          Id LevelDisplayName Message
-----------          -- ---------------- -------
21/06/2026 21:22:47   7 Information      Windows Defender Advanced Threat Protection Incident Response requested registration as an AIRS client. Result code: 0x0
```

After that, the more interesting rows are usually event `11`, where results for individual actions were uploaded successfully:

```text
TimeCreated                     Id LevelDisplayName Message
-----------                     -- ---------------- -------
21/06/2026 21:35:30    11 Information    Finished uploading results of action GetFileInformationAction. Action ID: iaid_3350_get_files_info__107_1783625674, upload result code: 0x0
21/06/2026 21:34:04    11 Information    Finished uploading results of action GetRecentlyCreatedOrModifiedExecutableFileListAction. Action ID: iaid_3349_get_recently_created_or_modified_executables__107_1783625634, upload result code: 0x0
21/06/2026 21:33:57    11 Information    Finished uploading results of action GetRecentlyExecutedFilesAction. Action ID: iaid_3346_get_recently_executed_files__107_1783625632, upload result code: 0x0
21/06/2026 21:33:56    11 Information    Finished uploading results of action GetFilesFromDownloadLocationsAction. Action ID: iaid_3348_get_files_from_download_locations__107_1783625633, upload result code: 0x0
21/06/2026 21:33:56    11 Information    Finished uploading results of action PersistenceCheckAction. Action ID: iaid_3347_get_autoruns__107_1783625632, upload result code: 0x0
21/06/2026 21:27:18    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3312_read_memory_content__107_1783625113, upload result code: 0x0
21/06/2026 21:27:17    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3314_read_memory_content__107_1783625055, upload result code: 0x0
21/06/2026 21:27:17    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3315_read_memory_content__107_1783625055, upload result code: 0x0
21/06/2026 21:26:43    11 Information    Finished uploading results of action GetFileInformationAction. Action ID: iaid_3313_get_files_info__107_1783625055, upload result code: 0x0
21/06/2026 21:26:17    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3301_read_memory_content__107_1783625054, upload result code: 0x0
21/06/2026 21:26:17    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3292_read_memory_content__107_1783625054, upload result code: 0x0
21/06/2026 21:26:16    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3300_read_memory_content__107_1783625054, upload result code: 0x0
21/06/2026 21:26:16    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3310_read_memory_content__107_1783625052, upload result code: 0x0
21/06/2026 21:26:15    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3298_read_memory_content__107_1783625052, upload result code: 0x0
21/06/2026 21:25:16    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3305_read_memory_content__107_1783625052, upload result code: 0x0
21/06/2026 21:25:15    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3311_read_memory_content__107_1783625052, upload result code: 0x0
21/06/2026 21:25:15    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3299_read_memory_content__107_1783625052, upload result code: 0x0
21/06/2026 21:25:15    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3303_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:25:15    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3307_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:25:14    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3306_read_memory_content__107_1783625052, upload result code: 0x0
21/06/2026 21:25:14    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3309_read_memory_content__107_1783625052, upload result code: 0x0
21/06/2026 21:24:15    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3296_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:24:14    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3304_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:24:14    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3302_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:24:14    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3308_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:24:14    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3297_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:24:14    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3291_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:24:14    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3290_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:24:13    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3295_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:24:13    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3293_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:24:12    11 Information    Finished uploading results of action ReadProcessMemoryAction. Action ID: iaid_3294_read_memory_content__107_1783625051, upload result code: 0x0
21/06/2026 21:23:43    11 Information    Finished uploading results of action GetProcessListAction. Action ID: iaid_3286_get_process_list__107_1783624973, upload result code: 0x0
21/06/2026 21:23:05    11 Information    Finished uploading results of action GetFileInformationAction. Action ID: iaid_3288_get_files_info__107_1783624982, upload result code: 0x0
21/06/2026 21:22:58    11 Information    Finished uploading results of action GetServiceListAction. Action ID: iaid_3287_get_service_list__107_1783624975, upload result code: 0x0
21/06/2026 21:22:56    11 Information    Finished uploading results of action GetDriverListAction. Action ID: iaid_3285_list_drivers__107_1783624973, upload result code: 0x0
21/06/2026 21:22:55    11 Information    Finished uploading results of action GetTcpConnectionListAction. Action ID: iaid_3284_get_connection_list__107_1783624973, upload result code: 0x0
```

This gives you a compact, local view of the collection sequence. In my sample, AIR collected network connections, drivers, services, processes, file information, process memory content, autoruns, recently executed files, and recently created or modified executables.

> The event tells you that the endpoint finished and uploaded the result for an action. It does not show the full uploaded payload in the local event message, and it should not be treated as proof that a malicious verdict was reached.
{: .prompt-warning}

## 🔍 Reading the Action Names

The action names are the useful part. They map nicely to the type of triage an analyst would normally perform manually:

| Action | What it suggests AIR collected |
|---|---|
| `GetTcpConnectionListAction` | Active or recent TCP connection state |
| `GetDriverListAction` | Loaded driver inventory |
| `GetServiceListAction` | Service inventory |
| `GetProcessListAction` | Running process inventory |
| `GetFileInformationAction` | Metadata for files of interest |
| `ReadProcessMemoryAction` | Memory content from selected processes |
| `PersistenceCheckAction` | Autoruns and other persistence locations |
| `GetRecentlyExecutedFilesAction` | Recently executed file evidence |
| `GetFilesFromDownloadLocationsAction` | Files from common download paths |
| `GetRecentlyCreatedOrModifiedExecutableFileListAction` | New or modified executable content |

That list is not the full internal playbook, and it may change over time. Still, it is enough to understand the shape of the investigation. AIR is not just "scan the box". It performs targeted evidence collection, uploads the results, and lets the service-side investigation engine reason over that evidence.

## 🛠️ PowerShell Helper

Below is the combined helper I use for this. The first function reads `Microsoft-Windows-SenseIR` and keeps only a few practical filters. The second function wraps it for the AIR and Live Response action events I usually care about.

```powershell
function Get-SxDefenderEventsSenseIR {
    param (
        [string]$Pattern,
        [switch]$Filtered
    )

    $ids = 1..5

    $events = Get-WinEvent -ErrorAction SilentlyContinue -FilterHashTable @{
        ProviderName = "Microsoft-Windows-SenseIR"
    }

    if ($Filtered) {
        $events = $events | Where-Object Id -notin $ids
    }

    if ($Pattern) {
        $events = $events | Where-Object Message -like "*$Pattern*"
    }

    return $events
}

function Get-SxDefenderEventsSenseAutomatedInvestigation {
    param (
        [switch]$ActionReportOnly
    )

    $ids = 7, 11
    $events = Get-SxDefenderEventsSenseIR | Where-Object Id -in $ids

    if ($ActionReportOnly) {
        $events = $events | Where-Object Id -eq 11
    }

    return $events
}
```

The `Get-SxDefenderEventsSenseAutomatedInvestigation` wrapper focuses on two event IDs:

| Event ID | Why I look at it |
|---:|---|
| `7` | AIRS client registration request |
| `11` | Finished upload for an investigation action |

For Live Response, I keep `1`, `3`, `11`, and `14` in the wrapper. Event `11` is still the most useful report-style signal because it records that results for an action were uploaded.

> Live Response can also trigger activity that later shows up in related Defender event streams. When I am trying to separate operator-driven activity from automated investigation activity, I usually start with `Microsoft-Windows-SenseIR` and then correlate with the Defender portal timeline.
{: .prompt-tip}

## ⚡ Quick Usage

To list AIR-related local events:

```powershell
Get-SxDefenderEventsSenseAutomatedInvestigation |
    Select-Object TimeCreated, Id, LevelDisplayName, Message
```

To only show action upload reports:

```powershell
Get-SxDefenderEventsSenseAutomatedInvestigation -ActionReportOnly |
    Select-Object TimeCreated, Id, Message
```

To quickly extract the action names from event `11`:

```powershell
Get-SxDefenderEventsSenseAutomatedInvestigation -ActionReportOnly |
    ForEach-Object {
        [pscustomobject]@{
            TimeCreated = $_.TimeCreated
            Action      = [regex]::Match($_.Message, "action (?<action>[^.]+)\.").Groups["action"].Value
            ActionId    = [regex]::Match($_.Message, "Action ID: (?<id>[^,]+)").Groups["id"].Value
            ResultCode  = [regex]::Match($_.Message, "upload result code: (?<code>\S+)").Groups["code"].Value
        }
    } |
    Sort-Object TimeCreated
```

That produces a much cleaner sequence:

```text
TimeCreated          Action                                             ResultCode
-----------          ------                                             ----------
21/06/2026 21:22:55  GetTcpConnectionListAction                         0x0
21/06/2026 21:22:56  GetDriverListAction                                0x0
21/06/2026 21:22:58  GetServiceListAction                               0x0
21/06/2026 21:23:43  GetProcessListAction                               0x0
21/06/2026 21:24:12  ReadProcessMemoryAction                            0x0
21/06/2026 21:33:56  PersistenceCheckAction                             0x0
21/06/2026 21:33:57  GetRecentlyExecutedFilesAction                     0x0
21/06/2026 21:34:04  GetRecentlyCreatedOrModifiedExecutableFileListAction 0x0
```

## 💡 Why This Is Useful

For me, this is mainly useful in three situations.

**Learning how AIR behaves.** Seeing the action names in order makes the investigation less abstract. You get a feeling for the evidence classes Defender collects.

**Troubleshooting local execution.** If the portal shows an investigation but the endpoint has no matching `Microsoft-Windows-SenseIR` activity, that is a useful clue. It does not automatically identify the root cause, but it tells you where to look next.

There are also a few limits to keep in mind:

- The local event log does not contain the full investigation result.
- Action names and IDs are internal implementation details and can change.
- Retention depends on the local event log configuration.
- Some activity may be easier to understand from the Defender portal timeline or Advanced Hunting.

That last point matters. Local logs are a supporting signal, not the source of truth for investigation outcome.

## ✅ Conclusion

`Microsoft-Windows-SenseIR` is a neat local window into Defender for Endpoint AIR activity. It shows when the endpoint registered as an incident response client and, more importantly, which investigation actions finished and uploaded their results.

For anyone interested in how AIR works under the hood, this is a simple place to start. You will not get the cloud-side verdict logic from the local event log, but you can see the evidence collection rhythm - processes, services, drivers, connections, autoruns, memory reads, file metadata, and recent execution history. That alone makes AIR a bit less of a black box.
