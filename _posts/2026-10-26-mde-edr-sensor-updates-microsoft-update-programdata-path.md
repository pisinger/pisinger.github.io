---
title: MDE EDR Sensor Updates via Microsoft Update - MsSense Moves to ProgramData
author: pit
date: 2026-10-26
categories: [blogging]
tags: [defender, mde, defender-for-endpoint, edr, mssense, microsoft-update, windows, detection, powershell, kql]
render_with_liquid: false
---

For years the Defender for Endpoint EDR sensor (`MsSense.exe`) rode along with the monthly Windows cumulative update. A sensor fix had to wait for Patch Tuesday, and the binaries lived in a fixed folder under Program Files. That is changing.

Back in June, message center post **MC1381119** said EDR updates were moving from the monthly Windows CU to Microsoft Update, starting with Windows 10 and following on Windows 11 in the fall. Since October 15 I've seen it land on a much wider set of devices across the tenants I work with.

> This has been a long time coming. The July 2025 platform release (10.8798) already called itself "the first step toward enabling EDR updates through Microsoft Update". The actual switch only followed with MC1381119 this June, and it's rolling out to Windows 11 now: <https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-endpoint-releases#windows--july-2025--platform-108798>
{: .prompt-info}

## 🧭 What changed

The sensor now gets the same treatment Defender Antivirus has had for years: it updates independently of the Windows CU, installs into versioned folders, and can roll back to N-1. The install path changes with it:

```text
Old: C:\Program Files\Windows Defender Advanced Threat Protection\
New: C:\ProgramData\Microsoft\Windows Defender Advanced Threat Protection\Platform\Versions\<ver>\
```

I like this change. Sensor fixes no longer wait for the OS servicing calendar, and the versioned layout means a bad build can be rolled back without touching the OS. If you already handle `C:\ProgramData\Microsoft\Windows Defender\Platform\<ver>\` for the AV platform, the new layout will look familiar.

The update itself seems to be driven by a new component. On devices that have switched, I see a new Windows service, `DefenderUpdateSvc`, which runs `DefenderUpdateService.exe` from its own versioned folder:

```text
C:\ProgramData\Microsoft\Microsoft Defender\Defender Update\Platform\10.8839.26080.2008-0\DefenderUpdateService.exe
```

Microsoft hasn't documented that service yet as far as I can find, so treat this as what I observed on devices rather than confirmed architecture. It's still worth knowing about: it's one more Defender binary in a version-numbered folder under ProgramData, and the exclusion point below applies to it too.

Side note: right before the new EDR version shipped, I also spotted `DefenderBootstrapper.exe` (it identifies itself as `xpdBootstrapper`) running from the Office Click-to-Run folder:

```text
C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OnlineInteraction\73b2aa4f-faa6-4702-8d25-444947072c82_2797f362b9a8005f5fc69004eaedff3d\DefenderBootstrapper.exe
```

The timing looked suspicious, but this one isn't new. Users have reported the same binary in the same `ClickToRun\OnlineInteraction` folder since at least 2023, usually after a firewall prompt, and Microsoft doesn't document it. Given the Click-to-Run location, I read it as part of the Microsoft 365 / Office side rather than the EDR sensor change, so I wouldn't tie the two together: <https://learn.microsoft.com/en-us/answers/questions/4157079/anyone-know-what-defenderbootstrapper-exe-do>

> ⚠️ Some docs still describe the old model. The streamlined connectivity page, for example, still says EDR sensor updates "always come as part of regular Windows update release cadence". Trust what your devices report over that sentence until the docs catch up.
{: .prompt-warning}

## 🔍 Check your own device

The quickest way to see which model a device runs is to read the `Sense` service image path:

```powershell
(Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\Sense).ImagePath
```

If the path points into `ProgramData\...\Platform\Versions\<ver>\`, the device has switched. If it still points to Program Files, it is still on the CU-delivered sensor.

To see the update service as well:

```powershell
Get-CimInstance Win32_Service -Filter "Name='DefenderUpdateSvc'" | Select-Object Name, State, StartMode, PathName
```

For the fleet view, count devices by the path `MsSense.exe` last ran from in Advanced Hunting:

```shell
DeviceProcessEvents
| where Timestamp > ago(30d)
| extend SensePath = case(
    FileName =~ "MsSense.exe", FolderPath,
    InitiatingProcessFileName =~ "MsSense.exe", InitiatingProcessFolderPath,
    "")
| where isnotempty(SensePath)
| summarize arg_max(Timestamp, SensePath) by DeviceId
| extend SenseLocation = case(
    SensePath has @"\programdata\microsoft\windows defender advanced threat protection\platform\versions\", "New (ProgramData)",
    SensePath has @"\program files\windows defender advanced threat protection\", "Old (Program Files)",
    "Other")
| summarize Devices = dcount(DeviceId) by SenseLocation
```

Any device under "Other" is worth a closer look, since `MsSense.exe` shouldn't run from anywhere else.

To see how far the rollout has got per OS, the same logic split by `OSPlatform` from `DeviceInfo`:

```shell
DeviceProcessEvents
| where Timestamp > ago(30d)
| extend SensePath = case(
    FileName =~ "MsSense.exe", FolderPath,
    InitiatingProcessFileName =~ "MsSense.exe", InitiatingProcessFolderPath,
    "")
| where isnotempty(SensePath)
| summarize arg_max(Timestamp, SensePath) by DeviceId
| extend SenseLocation = case(
    SensePath has @"\programdata\microsoft\windows defender advanced threat protection\platform\versions\", "New (ProgramData)",
    SensePath has @"\program files\windows defender advanced threat protection\", "Old (Program Files)",
    "Other")
| join kind=leftouter (
    DeviceInfo
    | where Timestamp > ago(30d)
    | summarize arg_max(Timestamp, OSPlatform) by DeviceId
) on DeviceId
| summarize Devices = dcount(DeviceId) by OSPlatform, SenseLocation
| order by OSPlatform asc, SenseLocation asc
```

> `MsSense.exe` is long-running, so its own start event may be older than the lookback window. Matching on the processes it launches as well catches most devices. A device that hasn't started or launched anything Sense-related in 30 days won't show up.
{: .prompt-info}

## ⚠️ What to check next

A path change sounds cosmetic until something depends on the old path. These are the two things I'd go through.

**Third-party AV/EDR exclusions.** If you run another security product alongside MDE, its exclusions for the Sense binaries probably name the old Program Files folder. Add the new location with a wildcard for the version segment, `...\Windows Defender Advanced Threat Protection\Platform\Versions\*`, or every sensor update will create a new path that isn't covered. The same goes for the updater under `...\Microsoft Defender\Defender Update\Platform\*`.

**Detections and allow-lists keyed on the old path.** Custom detections, SIEM correlation rules, or allow-lists that match `MsSense.exe` by its full Program Files path will either miss the new binary or start flagging it. I'd move these to signer plus path pattern instead of one hardcoded folder. The version folder is going to change on every update, so a hardcoded path will keep breaking.

> Pin the logic to who signed the file and which folder pattern it runs from, not a specific version folder. That holds up across sensor updates and N-1 rollbacks.
{: .prompt-tip}

## 📝 Conclusion

The EDR sensor now updates the way Defender AV has for years: outside the Windows CU, with versioned folders and rollback. That's good news for fix velocity. The cost is a one-time cleanup: update third-party exclusions, and rebase any detection or allow-list that hardcodes the old `MsSense` path.

Run the fleet queries first to see how far the rollout has got per OS. Where devices have already switched, now is the time to fix whatever still points at Program Files.
