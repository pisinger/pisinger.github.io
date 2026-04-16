---
title: Seeding a Sentinel PoC Workspace with Dummy Security Logs
author: pit
date: 2026-04-14
categories: [Blogging]
tags: [azure, sentinel, log analytics, powershell, defender, logs ingestion api, dce, dcr, poc, vibe coding]
render_with_liquid: false
---

An empty `Microsoft Sentinel` workspace is a bit of a blank canvas problem - great if you're starting fresh, less useful when you're trying to demonstrate detection logic, run a CTF, or help an analyst get familiar with the environment before real data flows in. Here's a mostly `vibe-coded` script that provisions the full ingestion stack and starts pumping synthetic security logs from day one.

You find the script on [GitHub](https://github.com/pisinger/scripts-lib/blob/main/powershell/ingest-dummy-data-into-sentinel.ps1)

## The Problem With Empty Workspaces

When you spin up a new Sentinel workspace for a PoC or a training exercise, the first thing you hit is silence. No data, no events, no alerts - which makes demoing analytics rules or walking someone through KQL feel pretty abstract. You could wait for connectors to warm up, or you could just inject something useful right now.

That said, the quickest legitimate path to real data is often already in reach: onboarding a machine to `Microsoft Defender for Endpoint` immediately starts flowing `DeviceEvents`, `DeviceNetworkEvents`, `DeviceProcessEvents` and the rest of the MDE tables into the workspace. Similarly, enabling `Azure Monitor Agent` on a VM and wiring up a Data Collection Rule brings in Windows Event Logs or Syslog with minimal effort. And if you're running Azure resources, flipping on diagnostic settings for things like Key Vault, NSGs, or Entra ID sign-in logs costs almost nothing and fills the workspace with genuinely useful telemetry fast. So before reaching for synthetic data, it's worth checking what's already there or one toggle away. The script below is for the cases where that's not practical - air-gapped PoC environments, clean-room training setups, or when you just need data *right now* without standing up any additional infrastructure.

The script below takes a different approach: it builds the entire ingestion pipeline from scratch and immediately populates five custom log tables with realistic-looking (but entirely synthetic) security events from common vendors. One run and you have something to work with.

> ⚠️ The generated data won't match the exact schema of the real vendor tables (e.g. `CommonSecurityLog`). These are custom `_CL` tables with a flat structure. The goal is to get *something* into the workspace quickly - not to reproduce a production-accurate data model.
{: .prompt-info}

## What the Script Builds

On first run, the script provisions three things before it ingests a single record:

- **Data Collection Endpoint (DCE)** — the HTTPS endpoint the Logs Ingestion API posts to
- **Custom `_CL` tables** — one per vendor, created directly in the Log Analytics Workspace
- **Data Collection Rule (DCR)** — wires the DCE to the tables with per-vendor streams

Once that infrastructure exists, subsequent runs skip straight to generating and pushing logs. The `-SkipInfraSetup` switch handles this cleanly.

> ⚠️ NOTE: This script has been validated on Linux environments. On Windows clients, execution may be blocked by Defender’s AMSI engine, which can flag the script as suspicious and report it as `'Trojan:PowerShell/FakeCaptcha.Y!MTB' launched by pwsh.exe`.
{: .prompt-warning}



Five tables get created by default:

| Table | Simulated Source |
|---|---|
| `SampleEndpointVendor1_CL` | endpoint protection events |
| `SampleEndpointVendor2_CL` | endpoint protection events |
| `SampleFwVendor1_CL` | network and firewall events |
| `SampleFwVendor2_CL` | network and firewall events |
| `SampleKubernetes_CL` | Kubernetes audit / runtime events |

Each record has four columns: `TimeGenerated` (with a small random offset to avoid all events landing at exactly the same second), `RawData` (the full vendor JSON payload), `SourceVendor`, and `FileName` (a synthetic source shard identifier). The intent is to keep the schema simple and parse at query time - same pattern you'd use with a real flat log ingestion pipeline.

## Running It

The only hard requirements are `az` CLI and `jq` in your PATH. Auth is handled through Managed Identity, so it runs cleanly from an Azure VM or an Azure Function without storing credentials anywhere as long as you have proper role assignments.

```powershell
# First run - provisions DCE, DCR, tables, then ingests
./Invoke-SecurityLogIngestion.ps1 `
    -ResourceGroup "my-rg-security" `
    -WorkspaceName "my-law-001"

# Subsequent runs - skip infra, just generate and push logs
./Invoke-SecurityLogIngestion.ps1 `
    -ResourceGroup "my-rg-security" `
    -WorkspaceName "my-law-001" `
    -RecordsPerVendor 30 `
    -SkipInfraSetup
```

The `RecordsPerVendor` parameter controls how many log records get generated per vendor per run (default 15, so 75 events total per execution). Crank it up if you want a denser dataset faster.

> You'll need the Managed Identity on the VM or Function to have **Monitoring Metrics Publisher** on the DCR or higher level and sufficient permissions to create the infra. If you're running locally, `az login` with a user that has the same rights works just as well.
{: .prompt-tip}

The stable device and user inventories baked into the script mean that repeated runs generate correlated data - the same hostnames, IPs, and user accounts show up across events, which makes analytics rules and investigation workflows feel more realistic than purely random noise.

## Easter Eggs

Each run has a 30% chance of injecting something extra - for this the script simply goes for random between 1 and 100 and if lower 30, then synthetic attack events are ingested. If the dice roll is favourable, the script quietly appends a synthetic multi-stage attack chain — codenamed *Operation Borrowed Time* — spread across all five vendor tables. You won't see a banner in normal output unless you're watching the console closely; the events land in the same tables as the regular noise.

The attack chain records are tagged with `AttackChain=true` in the `RawData` JSON payload, so you can surface them with a simple KQL filter across your custom tables:

```shell
SampleFwVendor2_CL
| where RawData has "AttackChain=true"
```

That makes it a decent starting point for a detection exercise — analysts get a workspace that looks like background noise with a real signal buried inside, and they need to find and correlate it across vendor sources. Whether they stumble on it or not partly depends on the run, which adds a bit of unpredictability to repeat sessions.

Below also some other queries you could then run to investigate the data.

```shell
// All vendors — record counts
union SampleFwVendor2_CL, SampleEndpointVendor1_CL, SampleEndpointVendor2_CL, SampleFwVendor1_CL, SampleKubernetes_CL
| summarize arg_max(TimeGenerated,*), Count=count() by SourceVendor, FileName
| order by Count desc

// High/Critical events across all tables (parse from RawData)
union SampleFwVendor2_CL, SampleEndpointVendor1_CL, SampleEndpointVendor2_CL, SampleFwVendor1_CL, SampleKubernetes_CL
| extend raw = parse_json(RawData)
| where toint(raw.SeverityNum) >= 8
| project TimeGenerated, SourceVendor, Severity=tostring(raw.Severity),
          DeviceName=tostring(raw.DeviceName), DeviceIP=tostring(raw.DeviceIP),
          UserName=tostring(raw.UserName), Action=tostring(raw.Action),
          EventId=tostring(raw.EventId), SourceIP=tostring(raw.SourceIP), DestIP=tostring(raw.DestIP)

// EndpointVendor2 — MITRE ATT&CK mapping
SampleEndpointVendor2_CL
| extend raw = parse_json(RawData)
| project TimeGenerated, DeviceName=tostring(raw.DeviceName), UserName=tostring(raw.UserName),
          Tactic=tostring(raw.MitreTactic), Technique=tostring(raw.MitreTechnique),
          AttackId=tostring(raw.MitreAttackId), CommandLine=tostring(raw.CommandLine),
          DetectionType=tostring(raw.DetectionType), CaseName=tostring(raw.CaseName)

// Kubernetes — policy violations
SampleKubernetes_CL
| extend raw = parse_json(RawData)
| where isnotempty(tostring(raw.PolicyViolation))
| project TimeGenerated, Node=tostring(raw.DeviceName), UserName=tostring(raw.UserName),
          Namespace=tostring(raw.Namespace), Workload=tostring(raw.WorkloadName),
          Violation=tostring(raw.PolicyViolation), Engine=tostring(raw.PolicyEngine),
          Severity=tostring(raw.Severity)

// Per-user activity aggregated across all vendors (stable UserName for correlation)
union SampleFwVendor2_CL, SampleEndpointVendor1_CL, SampleEndpointVendor2_CL, SampleFwVendor1_CL, SampleKubernetes_CL
| extend raw = parse_json(RawData)
| summarize Events=count(), Vendors=make_set(SourceVendor), MaxSev=max(toint(raw.SeverityNum))
  by UserId=tostring(raw.UserId), UserName=tostring(raw.UserName), Dept=tostring(raw.UserDept)
| order by Events desc

// ── Operation Borrowed Time — full attack chain reconstruction ──────────────
// Find all chain events by CorrelationId and reconstruct the timeline
union SampleFwVendor2_CL, SampleEndpointVendor1_CL, SampleEndpointVendor2_CL, SampleFwVendor1_CL, SampleKubernetes_CL
| extend raw = parse_json(RawData)
| where tobool(raw.AttackChain) == true
| project TimeGenerated, SourceVendor,
          Step=tostring(raw.ChainStep),
          CorrelationId=tostring(raw.CorrelationId),
          CaseId=tostring(raw.CaseId),
          Action=tostring(raw.Action),
          Severity=tostring(raw.Severity),
          UserName=tostring(raw.UserName),
          SourceIP=tostring(raw.SourceIP),
          DestIP=tostring(raw.DestIP),
          Note=tostring(raw.Note)
| order by TimeGenerated asc

// Pivot on a specific CorrelationId (paste from above result)
// let cid = "<paste CorrelationId here>";
// union SampleFwVendor2_CL, SampleEndpointVendor1_CL, SampleEndpointVendor2_CL, SampleFwVendor1_CL, SampleKubernetes_CL
// | extend raw = parse_json(RawData)
// | where tostring(raw.CorrelationId) == cid
// | project TimeGenerated, SourceVendor, Step=tostring(raw.ChainStep), Action=tostring(raw.Action), Note=tostring(raw.Note)
// | order by TimeGenerated asc

// Blind spots — accepted/allowed events that are part of the attack chain
union SampleFwVendor2_CL, SampleFwVendor1_CL, SampleEndpointVendor1_CL
| extend raw = parse_json(RawData)
| where tobool(raw.AttackChain) == true
| where tostring(raw.Action) in ("Accept","allow","Left alone")
| project TimeGenerated, SourceVendor, Step=tostring(raw.ChainStep),
          Action=tostring(raw.Action), Rule=tostring(raw.RuleName),
          Note=tostring(raw.Note)
| order by TimeGenerated asc

// Kubernetes privilege escalation — service account secret enumeration
SampleKubernetes_CL
| extend raw = parse_json(RawData)
| where tobool(raw.AttackChain) == true
| project TimeGenerated,
          Step=tostring(raw.ChainStep),
          ServiceAccount=tostring(raw.ServiceAccount),
          AuditVerb=tostring(raw.AuditVerb),
          Namespace=tostring(raw.Namespace),
          Resource=tostring(raw.ResourceKind),
          PolicyViolation=tostring(raw.PolicyViolation),
          SecretsEnumerated=toint(raw.SecretsEnumerated),
          Note=tostring(raw.Note)
| order by TimeGenerated asc
```

## Where to Take It Next

The script works as-is, but the structure is intentionally modular. A few directions worth exploring:

**Scheduled ingestion via Azure Functions** — package the script as a PowerShell Function App and trigger it on a cron schedule. A workspace that gets 75 new events every 15 minutes starts to feel like a live environment surprisingly quickly, and you can layer analytics rules and playbooks on top without waiting for real connectors.

**Capture the Flag scenarios** — the synthetic data may also include known-bad IPs (Tor exit nodes, simulated C2 addresses) you define upfront and suspicious user behaviour patterns mixed in with the benign baseline. With a bit of curation you could define specific "flags" - an analyst finds the lateral movement sequence, correlates the C2 beaconing, traces the compromised account - and turn it into a structured exercise.

**New vendor data sources** — adding a new table is a matter of defining the DCR stream and writing a generator function. The pattern is consistent enough that you could make `SourceVendor` a parameter and drive the whole thing from a config file, letting you swap in or out whatever log sources fit the scenario you're running.

**Detection engineering** — with a steady stream of synthetic data, you can test and fine tune analytics rules in a more dynamic environment.

**Integration of LLMs for dynamic content** — instead of static templates, you could use an LLM to generate more varied and contextually rich log entries on the fly, making the dataset feel less synthetic over time.

**More modularity and extensibility** — abstracting the log generation and ingestion logic into separate modules or classes would make it easier to maintain and extend.

## Conclusion

An empty workspace is a usability problem more than a technical one - the tooling works, there's just nothing to work with. This script is a quick way past that: one first run builds the infrastructure, every subsequent run adds a fresh batch of realistic-ish events across five vendor tables. Good enough for a PoC demo, an analyst onboarding session, or a CTF where you want security events to already be there when someone opens Sentinel for the first time.
