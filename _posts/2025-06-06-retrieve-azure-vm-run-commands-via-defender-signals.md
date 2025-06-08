---
title: Retrieve Azure VM Run Commands through Defender AH tables (PoC)
author: pit
date: 2025-06-06
categories: [Blogging, Tutorial, PoC]
tags: [defender, detection, hunting, azure, RunCommands]
render_with_liquid: false
---

Hi there! I was recently asked whether it's possible to retrieve details about the actual commands executed via Azure VM Run Command when working with **Microsoft Defender** and **Sentinel**. Although there's no direct integration and Azure doesn't log these actions with such granularity by default in central manner, I decided to dig deeper into the topic.

> The most obvious option would be to use PowerShell Transcription logging on Windows together with **Azure Monitor** to ingest the logs. However, I wanted to investigate whether we could leverage Defender Endpoint telemetry instead to retrieve Run Command activity.
{: .prompt-info}
> Full KQL query can be found in my [GitHub repo](https://github.com/pisinger/hunting/blob/main/defender-azure-vm-run-commands-hunting.kql).
{: .prompt-tip}

See below example result when running above query in Defender Advanced Hunting:

![img-description](/assets/img/posts/retrieve-azure-vm-run-commands-via-defender/example-run-command-query.png)
Run Command activity on Azure VM via Defender AH

## ▶️Azure VM Run Command

Azure VM Run Command provides a convenient way to execute scripts or commands on Azure Virtual Machines without requiring direct login access. It's especially handy for administrative tasks, troubleshooting, and automation scenarios. However, capturing the exact content of the commands executed through this feature - especially in a flexible or auditable way - can be somewhat challenging.

General information about using Run Commands can be found in the [Azure documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/run-command-overview).

## Azure Activity

Azure Activity Logs — specifically the AzureActivity table — can be queried to identify when Run Command actions were executed on Azure Virtual Machines. However, these logs only capture the occurrence of the action, not the actual content of the commands that were run. And that’s precisely the detail we’re after — especially for threat hunting scenarios or when enriching incidents with deeper context.

To check for executed Run Commands in Azure Activity Logs, you can use the following query:

```shell
AzureActivity
| where OperationNameValue =~ "MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMAND/ACTION"
```

## 🛠️Off topic - repair Run Command extension

Before diving into how to retrieve Run Command data, I want to briefly touch on a related issue — repairing the Run Command extension on Azure VMs. This can be helpful if you run into problems with the extension itself.

> Why bring this up? Because I ran into this exact issue in my own lab. After experimenting with various configurations — removing downloaded scripts, resetting the extension, and more — I somehow broke the Run Command extension. Attempts to fix it manualy only made things worse. Eventually, I found a way to reinstall the extension using PowerShell, which I’ll share below.
{: .prompt-tip}

```shell
Invoke-AzVMRunCommand -ResourceGroupName "myResourceGroup" -Name "myMachine" -CommandId "RemoveRunCommandWindowsExtension"
```

To reinstall the extension, you can simply trigger a new Run Command execution — this will automatically re-provision the extension if it's missing or broken. It’s worth noting that the Run Command extension isn’t pre-installed on Azure VMs and also doesn’t appear under the list of installed extensions in the Azure Portal. Instead, it’s provisioned on demand the first time a Run Command is executed.

## 🔍Where to find the Run Commands logs locally

When you execute Run Commands on Azure Virtual Machines, the commands run within the VM agent context of the VM (System on Windows, Root on Linux). These actions aren’t captured in detail by Azure Activity Logs or Diagnostics Logs. However, the actual command scripts — typically named script1.ps1, script2.ps1 for Windows or script.sh for Linux — are downloaded to the VM and stored locally before execution.

These scripts are placed in a specific directory used by the Run Command extension, from where they are picked up and executed. This local presence can be useful for forensic analysis or troubleshooting, especially when deeper visibility into command content is required.

- **Windows**: `C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.18\Downloads`
- **Linux**: `/var/lib/waagent/run-command/download`

On Linux VMs, the Run Command logs — including stdout and stderr — can be found in the same directory where the script is downloaded and executed. These logs provide insight into the output and any errors generated during execution. On Windows VMs, however, there's a dedicated status folder located at `C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.18\Status`.

## 🎯Retrieve Run Commands activity via Defender Telemetry

Since I wanted to avoid manually ingesting logs from individual VMs, I turned to **Defender Endpoint** and started analyzing its signals using the **Advanced Hunting** tables. While Defender isn’t designed to capture every operational detail, I was curious whether it logs Run Command activity in any meaningful way. And good news — it does! 💡🥳

> Spoiler alert: Based on my investigation, tracking the Run Commands through Defender AH works pretty well on Linux machines, including capturing the full script content. On Windows, the visibility is more limited — it typically logs only certain executions, depending on the security context and Defender’s telemetry focus instead of the full script content.
{: .prompt-info}
> Keep in mind: Defender for Endpoint is a security solution, not a full auditing or monitoring tool. That said, it can still offer valuable insights into Run Command usage on Windows even while not seeing the full script content.
{: .prompt-warning}

To finally identify Run Command executions via Defender, you can use the following KQL query. It searches for relevant events across both Windows and Linux environments. While Windows coverage may be partial, Linux systems often provide full script visibility — at least in the scenarios I tested 🙃.

```shell
let RunCommandsWindows = DeviceFileEvents
    | where InitiatingProcessFileName == "runcommandextension.exe" and FileName contains ".ps1" and isnotempty(FileSize)
    | project Timestamp, DeviceId, DeviceName, FileName, SHA256, FolderPath, InitiatingProcessAccountName, FileSize
;
let RunCommandsWindowsFileName = RunCommandsWindows | summarize make_set(FileName);
let RunCommandsWindowsFileSHA256 = RunCommandsWindows | summarize make_set(SHA256);
//-----------------
let RunCommandsLinux = DeviceFileEvents
    | where FolderPath contains "run-command/download" and FileName contains ".sh"
    | where ActionType == "FileCreated"
    | project Timestamp, DeviceId, DeviceName, FileName, FolderPath, SHA1, SHA256, InitiatingProcessAccountName, FileSize
    //| join kind=inner (DeviceEvents) on SHA256
    //| project Timestamp, FileName, SHA256, parse_json(AdditionalFields).ScriptContent
;
let RunCommandsLinuxFileName = RunCommandsLinux | summarize make_set(FileName);
let RunCommandsLinuxFileSHA256 = RunCommandsLinux | summarize make_set(SHA256);
let Devices = union RunCommandsWindows, RunCommandsLinux | summarize make_set(DeviceId);
//-----------------
// using script FileName or its SHA256 for correlation
union DeviceProcessEvents, DeviceEvents
| where DeviceId has_any (Devices)
| where
    ProcessCommandLine has_any (RunCommandsWindowsFileName) or InitiatingProcessCommandLine has_any (RunCommandsWindowsFileName) 
    or SHA256 has_any (RunCommandsWindowsFileSHA256) or SHA256 has_any(RunCommandsLinuxFileSHA256)
| extend ScriptContent = parse_json(AdditionalFields).ScriptContent
| extend RunCommand = parse_json(AdditionalFields).Command
| extend RunCommand = iff (RunCommand == "" and not(ProcessCommandLine has_any (RunCommandsWindows) or ProcessCommandLine has_any(RunCommandsLinux)), ProcessCommandLine, RunCommand)
| extend RunCommand = coalesce (todynamic(RunCommand), ScriptContent)
| project Timestamp, DeviceId, DeviceName = split(DeviceName,".")[0], ActionType, FileName, FolderPath, InitiatingProcessFolderPath, InitiatingProcessFileName, RunCommand, ScriptContent, ProcessCommandLine, InitiatingProcessCommandLine, AccountName, AccountSid, LogonId, SHA256, ReportId
//-----------------
| project-away ScriptContent, ProcessCommandLine, LogonId, AccountSid, FileName, FolderPath
| where isnotempty(RunCommand) and InitiatingProcessCommandLine !has ("Cpowershell") and RunCommand !has ("Cpowershell") and InitiatingProcessFileName != "csrss.exe"
// exclude non runCommand related processes where any script.sh is run
| where not(ActionType == "ProcessCreated" and InitiatingProcessCommandLine has "script.sh" and InitiatingProcessCommandLine !has ("run-command") and RunCommand has "script.sh")
| sort by Timestamp desc
```

## Final thoughts

While Azure VM Run Command is a powerful tool for remote management and automation, its visibility in standard logging solutions like Azure Activity Logs is limited — especially when it comes to capturing the actual command content. However, by exploring local VM paths and leveraging Defender Endpoint signals, particularly on Linux systems, we can uncover valuable insights that support threat hunting and incident enrichment. With the right combination of tools and queries, it's possible to bridge the visibility gap and enhance your security investigations.
