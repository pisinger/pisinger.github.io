---
title: Defender Endpoint SenseIR Events - AIR and Live Response Under the Hood
author: pit
date: 2026-07-10
categories: [blogging]
tags: [windows, defender, mde, automated-investigation, live-response, senseir, powershell, eventlog]
render_with_liquid: false
---

Sometimes the interesting part of Defender for Endpoint is not only what you see in the Defender portal, but what the endpoint quietly records while the cloud service is doing its work.

I came across this again while looking at Automated Investigation and Response, usually shortened to **AIR**. The portal gives you the investigation story, verdicts, evidence, and remediation state. Locally, the interesting part is that AIR and operator-driven Live Response both use the same Defender incident-response module: `SenseIR.exe`. Its actions leave a small but useful trail in the `Microsoft-Windows-SenseIR` event provider.

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

## 📡 The Local SenseIR Module

The local Defender module/binary behind these actions is:

```text
C:\Program Files\Windows Defender Advanced Threat Protection\SenseIR.exe
```

Its corresponding Windows event provider is:

```text
Microsoft-Windows-SenseIR
```

The name already hints at the purpose: Sense incident response. The important point is not merely that AIR and Live Response write to the same local event provider. Both use `SenseIR.exe` as the local Defender module to perform their requested incident-response actions. `Microsoft-Windows-SenseIR` then exposes the execution and result-upload trail from that module.

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

## 🖥️ Live Response Uses the Same Local Module

I later compared this with a Live Response session. The actions were initiated interactively from Live Response, but the endpoint-side completion and upload events still appeared under `Microsoft-Windows-SenseIR` as event `11`:

```text
TimeCreated          Id LevelDisplayName Message
-----------          -- ---------------- -------
23/06/2026 18:26:18  11 Information      Finished uploading results of action PersistenceCheckAction. Action ID: c829585f-f72f-40ce-9f9f-e8422210bb19, upload result code: 0x0
23/06/2026 18:25:43  11 Information      Finished uploading results of action ReadFileAction. Action ID: 7a74b6d8-3ced-4f9f-be29-4d68e801f7a5, upload result code: 0x0
23/06/2026 18:25:40  11 Information      Finished uploading results of action GetFileInformationAction. Action ID: be0fce3d-7913-4a88-b8b4-926912c6d22a, upload result code: 0x0
23/06/2026 18:24:53  11 Information      Finished uploading results of action EnumerateFilesAndFoldersAction. Action ID: 9af2d12d-55ea-440d-aef5-41ee079c0570, upload result code: 0x0
23/06/2026 18:24:43  11 Information      Finished uploading results of action FileExistsAction. Action ID: b8be0fef-a3d3-4020-87fc-fd56ac61c893, upload result code: 0x0
23/06/2026 18:24:10  11 Information      Finished uploading results of action GetTcpConnectionListAction. Action ID: f58a771a-441b-4a4d-8f2e-60a05966d162, upload result code: 0x0
23/06/2026 18:23:31  11 Information      Finished uploading results of action GetFileInformationAction. Action ID: c8fcc68e-c341-4af1-bdd1-bd0f37922a9b, upload result code: 0x0
23/06/2026 18:22:38  11 Information      Finished uploading results of action PersistenceCheckAction. Action ID: 7b22cbaf-d10b-4b24-aeca-d8d746300373, upload result code: 0x0
23/06/2026 18:21:56  11 Information      Finished uploading results of action EnumerateFilesAndFoldersAction. Action ID: 06a6e948-460f-4ec8-ae20-6aa65f2a0a9b, upload result code: 0x0
23/06/2026 18:21:14  11 Information      Finished uploading results of action GetFileInformationAction. Action ID: 4667d2e3-dae4-4ba1-a4e8-4d2513fcfa68, upload result code: 0x0
23/06/2026 18:21:07  11 Information      Finished uploading results of action GetFileInformationAction. Action ID: fce4e7f7-162e-47cf-a8e2-7d869515b8c6, upload result code: 0x0
23/06/2026 18:20:50  11 Information      Finished uploading results of action GetFileInformationAction. Action ID: 3f65f8de-68ab-4a4b-8ff3-c92515e5547b, upload result code: 0x0
23/06/2026 18:20:32  11 Information      Finished uploading results of action FindFilesAction. Action ID: a00c10c1-58b8-4fcd-a272-e5233097a8ed, upload result code: 0x0
23/06/2026 18:14:23  11 Information      Finished uploading results of action PersistenceCheckAction. Action ID: b8482811-9316-403a-8a02-58dfad6a7292, upload result code: 0x0
23/06/2026 18:14:02  11 Information      Finished uploading results of action GetTcpConnectionListAction. Action ID: 3028901e-6fd5-4df9-9bef-9443b5012db0, upload result code: 0x0
23/06/2026 18:13:07  11 Information      Finished uploading results of action EnumerateFilesAndFoldersAction. Action ID: 0d4d495a-0cc8-4c31-a3b9-8caa1c62fed3, upload result code: 0x0
23/06/2026 18:12:51  11 Information      Finished uploading results of action PersistenceCheckAction. Action ID: b8a7af0b-842e-4412-823e-24cd10c2b732, upload result code: 0x0
23/06/2026 18:12:39  11 Information      Finished uploading results of action GetServiceListAction. Action ID: 18e29434-68af-45f9-8dd1-5e56f644d3d7, upload result code: 0x0
23/06/2026 18:12:25  11 Information      Finished uploading results of action GetProcessListAction. Action ID: 6350af59-d86a-452d-b8ff-ace03831ddd8, upload result code: 0x0
23/06/2026 18:11:59  11 Information      Finished uploading results of action GetDriverListAction. Action ID: 936dd2bf-3f5c-4844-9790-bc60b27dfb9c, upload result code: 0x0
```

This is the useful finding. Although the work was requested through a remote Live Response session, the same local `SenseIR.exe` module used for AIR performed the individual actions. `Microsoft-Windows-SenseIR` is the event trail showing their result uploads; the shared provider is a consequence of the shared local module, not the main point by itself.

> This observation confirms that AIR and Live Response both rely on the `SenseIR.exe` module.
{: .prompt-info}

> Live Response examples: <https://learn.microsoft.com/en-us/defender-endpoint/live-response-command-examples>
{: .prompt-tip}

## 🔍 Reading the Action Names

The action names are the useful part. They map nicely to the type of triage an analyst would normally perform manually:

| Action | What it suggests `SenseIR.exe` collected |
|---|---|
| `GetTcpConnectionListAction` | Active or recent TCP connection state |
| `GetDriverListAction` | Loaded driver inventory |
| `GetServiceListAction` | Service inventory |
| `GetProcessListAction` | Running process inventory |
| `GetFileInformationAction` | Metadata for files of interest |
| `ReadFileAction` | Content read from a selected file |
| `FileExistsAction` | Check whether a specified file or path exists |
| `FindFilesAction` | Search for files matching supplied criteria |
| `EnumerateFilesAndFoldersAction` | Directory and file enumeration for a selected path |
| `ReadProcessMemoryAction` | Memory content from selected processes |
| `PersistenceCheckAction` | Autoruns and other persistence locations |
| `GetRecentlyExecutedFilesAction` | Recently executed file evidence |
| `GetFilesFromDownloadLocationsAction` | Files from common download paths |
| `GetRecentlyCreatedOrModifiedExecutableFileListAction` | New or modified executable content |

That list is not the full internal playbook, and it may change over time. Still, it is enough to understand the shape of the investigation. AIR is not just "scan the box". It performs targeted evidence collection, uploads the results, and lets the service-side investigation engine reason over that evidence.

## 🛠️ PowerShell Helper

Below is the combined helper I use for this. The first function reads `Microsoft-Windows-SenseIR` and keeps only a few practical filters. The second function wraps it for the AIR and Live Response action events I usually care about.

```powershell
function Get-DefenderEventsSenseIR {
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

function Get-DefenderEventsSenseAutomatedInvestigation {
    param (
        [switch]$ActionReportOnly
    )

    $ids = 7, 11
    $events = Get-DefenderEventsSenseIR | Where-Object Id -in $ids

    if ($ActionReportOnly) {
        $events = $events | Where-Object Id -eq 11
    }

    return $events
}
```

The `Get-DefenderEventsSenseAutomatedInvestigation` wrapper focuses on two event IDs:

| Event ID | Why I look at it |
|---:|---|
| `7` | AIRS client registration request |
| `11` | Finished upload for an investigation action |

For Live Response, I keep `1`, `3`, `11`, and `14` in the wrapper. Event `11` is still the most useful report-style signal because it records that results for an action were uploaded.

## ⚡ Quick Usage

To list AIR-related local events:

```powershell
Get-DefenderEventsSenseAutomatedInvestigation |
    Select-Object TimeCreated, Id, LevelDisplayName, Message
```

To only show action upload reports:

```powershell
Get-DefenderEventsSenseAutomatedInvestigation -ActionReportOnly |
    Select-Object TimeCreated, Id, Message
```

To quickly extract the action names from event `11`:

```shell
Get-DefenderEventsSenseAutomatedInvestigation -ActionReportOnly |
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

`SenseIR.exe` is the common local Defender incident-response module behind both AIR and Live Response in these observations. `Microsoft-Windows-SenseIR` is the useful window into that module: it shows when the endpoint registered as an incident response client and, more importantly, which locally executed actions finished and uploaded their results.

For anyone interested in how Defender investigation and response works under the hood, this is a simple place to start. You will not get the cloud-side verdict logic or an unambiguous source label from the local event log, but you can see the evidence collection rhythm - processes, services, drivers, connections, autoruns, memory reads, file metadata, and recent execution history. That makes both AIR and operator-driven Live Response a bit less of a black box.
