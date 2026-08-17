---
title: Custom Detections vs Analytics Rules - Why I Now Default to Custom Detections
author: pit
date: 2026-08-14
categories: [blogging]
tags: [defender-xdr, microsoft-sentinel, custom-detections, analytics-rules, detection-engineering, advanced-hunting, kql, nrt, detections-as-code, bicep]
render_with_liquid: false
---

For years my reflex when building a detection was to open the analytics rule wizard. Not loyalty - it just had everything. Entity mapping the way I wanted it, alert grouping, suppression, a playbook on the alert trigger, a content hub full of rules to start from. Custom detections were what you used when you couldn't do it properly in Sentinel.

> I've flipped sides. Custom detections are now my default for new rules, and the default I recommend to customers too. I only open the analytics rule wizard when I hit one of a handful of specific gaps.
{: .prompt-tip}

Microsoft isn't being subtle about it either. The MS Learn pages for analytics rules, anomaly rules and detection tuning all carry the same banner: *"Custom detections is now the best way to create new rules across Microsoft Sentinel SIEM + Microsoft Defender XDR"*. In October 2025 they went further and made custom detections the **default** wizard when you create a detection from advanced hunting, with analytics rules moved behind a "create analytics rule" button inside it. And [Sentinel in the Azure portal retires on **31 March 2027**](https://learn.microsoft.com/en-us/azure/sentinel/overview#microsoft-sentinel-in-the-azure-portal-retirement-timeline). Analytics rules don't die with it - they keep running and stay manageable - but once the whole SOC is in one portal, which wizard you open stops being a matter of taste.

What kept me on analytics rules was the feature transfer taking longer than I expected. Custom detections started as an endpoint-shaped feature: run an advanced hunting query on a schedule, raise an alert, maybe isolate a device. Next to a scheduled analytics rule, that felt thin. Most of what changed my mind arrived in the last twelve months.

> Bookmark Microsoft's [feature comparison for analytics rules and custom detections](https://learn.microsoft.com/en-us/azure/sentinel/compare-analytics-rules-custom-detections). It's the only place the remaining gaps are listed honestly, including which ones are `Planned`
{: .prompt-info}

## 📦 What actually landed

Conveniently, this is almost exactly the list of things that used to send me back to the analytics rule wizard.

| When | What arrived |
| --- | --- |
| Aug 2025 | Dynamic alert titles and descriptions, custom details in the alert side panel, custom frequency for Sentinel-only rules, GA of the unified **Detection rules** page |
| Sep 2025 | Run rule on demand, one-click migration of eligible rules to NRT, extended lookback up to 30 days |
| Oct 2025 | Custom detections named the unified experience, and made the *default* wizard in advanced hunting |
| Jan 2026 | Continuous (NRT) frequency on Microsoft Sentinel data |
| Jul 2026 | Detections as code - custom detection rules in Sentinel repositories via the Microsoft Security Bicep extension |

The unified Detection rules page gets less credit than it deserves. Both rule types now sit in one list, same filters, same details pane. Sounds cosmetic - but the day you stop checking two inventories to answer "do we already detect this?", the two-engine split starts feeling like plumbing rather than design.

The two announcements worth reading are the [September 2025 feature drop](https://techcommunity.microsoft.com/blog/microsoftthreatprotectionblog/custom-detection-rules-get-a-boost%E2%80%94explore-what%E2%80%99s-new-in-microsoft-defender/4443602) and the [October 2025 statement of direction](https://techcommunity.microsoft.com/blog/microsoftthreatprotectionblog/custom-detections-are-now-the-unified-experience-for-creating-detections-in-micr/4463875).

> Treat preview status as something to verify, not inherit. Repositories and Bicep support are explicitly public preview, and so is the configurable lookback covered later on. The docs also disagree with each other occasionally - NRT over Sentinel data was flagged as preview in the Defender what's-new in January 2026, while the comparison doc now lists it as plainly supported
{: .prompt-warning}

## ⚖️ Head to head

Most rows in Microsoft's [authoritative comparison](https://learn.microsoft.com/en-us/azure/sentinel/compare-analytics-rules-custom-detections) are parity rows now, and parity rows don't help you choose. So these two tables carry only what decides the question: what custom detections do that analytics rules can't, and what they still can't do. ✅ supported, ⛔ not supported, ⏳ planned, ⚠️ supported with a caveat - and the ⛔ / ⏳ distinction matters, because Microsoft has stated an intention for the planned rows. Limits and NRT query shape come from the [custom detection rules reference](https://learn.microsoft.com/en-us/defender-xdr/custom-detection-rules) and [Sentinel service limits](https://learn.microsoft.com/en-us/azure/sentinel/sentinel-service-limits) rather than the comparison doc.

### Only in custom detections

| Capability | Analytics rules | Custom detections |
| --- | --- | --- |
| Defender XDR data | ⛔ | ✅ |
| Built-in XDR enrichment functions | ⛔ | ✅ |
| Native XDR remediation actions | ⛔ | ✅ |
| Rule scope | no device-group | ✅ all devices or specific device groups, and enforced by RBAC |
| NRT execution model | ⚠️ after ingestion, two minute built-in delay | ✅ streaming, tested as events arrive |
| NRT rule count | 50 enabled, 100 including disabled | no published numeric limit; Microsoft describes real-time detections as unlimited |
| Scheduled rule count | 512 enabled, 1024 total | no published numeric limit |
| Maximum lookback | Up to 48 hours for frequencies above one hour; up to 14 days otherwise | Public-preview parity with analytics rules for Sentinel-only data; up to 30 days depending on source and frequency |
| Run rule on demand | ⛔ | ✅ |
| Entity mapping | manual, 10 mappings per rule | ⚠️ pre-populated for Defender XDR data, no documented limit |
| Group events into one alert | ⛔ | ✅ automatic, not configurable |

### Still missing in custom detections

| Capability | Analytics rules | Custom detections |
| --- | --- | --- |
| Create rules on workspaces onboarded to Defender | ✅ | ⏳ planned |
| Cross-workspace detection with `workspace()` | ✅ | ⏳ planned |
| Sentinel automation rules with incident trigger | ✅ | ⏳ planned |
| Sentinel automation rules with alert trigger | ✅ | ⏳ planned |
| Exclude the correlation | ✅ supported* | ⏳ planned |
| Alert suppression after a run | ✅ | ⛔ |
| Create alerts without incidents | ✅ | ⛔ |
| Customize alert grouping | ✅ | ⛔ |
| Rule simulation in the wizard | ✅ | ⏳ planned |
| Rerun on a previous time window | ✅ | ⏳ planned |
| Determine a rule's first run | ✅ | ⛔ a new rule checks the previous 30 days |
| Rule health logs | ✅ `SentinelHealth` | ⏳ planned, and the API's `lastRunDetails` is deprecated |
| Health and quality workbooks | ✅ | ⏳ planned |
| Rule audit logs in advanced hunting | ✅ `SentinelAudit` | ⚠️ `CloudAppEvents`, Defender for Cloud Apps customers only |
| Multiple MITRE tactics per rule | ✅ | ⏳ planned |
| Content hub rule creation | ✅ | ⏳ planned |
| All alert properties dynamic | ✅ | ⏳ planned |

> The `Planned` incident-trigger row does **not** mean playbooks cannot run on incidents created from custom detections. Custom-detection alerts participate in Defender XDR incidents, and Sentinel automation rules can run incident-triggered playbooks when those incidents are created or updated. What is missing is first-class, rule-specific targeting equivalent to selecting an analytics rule by name. Account for two practical differences: an alert may update an existing correlated incident rather than create one, and synchronization into Sentinel can delay the automation rule. Use both incident-created and incident-updated logic where appropriate.
{: .prompt-info}

The MITRE row reads worse than it is. **MITRE mapping is supported** - the wizard has **Tactic**, **Techniques** and **Sub-techniques** fields, you can link a threat analytics report, and the Bicep schema carries the same nested structure. The difference is singular, literally: **one tactic per rule**. If your detection genuinely spans two tactics, pick the dominant one or split the rule. Behind that sit two smaller gaps: not every technique is selectable yet, and custom detections don't reflect on the MITRE ATT&CK coverage page - so your rules are tagged, your coverage reporting just doesn't count them.

\* The comparison page still labels analytics-rule correlation exclusion as `Planned`, but Microsoft's newer [dedicated correlation documentation](https://learn.microsoft.com/en-us/defender-xdr/exclude-analytics-rules-correlation) documents it as supported. Custom detections still have no equivalent setting.

Two rows carry most of the weight in either direction. Defender XDR data being flatly unavailable to analytics rules is why I stopped reaching for them. Multi-workspace being `Planned` is why I haven't retired them.

## 🔍 The same detection, twice

Two rules I would have argued about a year ago.

### Case 1 - Endpoint only, running continuously

Office application spawning a script host. `DeviceProcessEvents` is a Defender XDR table, and that's the first fork in the road: **an analytics rule cannot query it at all**. To build this as an analytics rule you'd first stream `DeviceProcessEvents` into the analytics tier and pay for it, so a second engine could look at data the first one already holds.

```shell
DeviceProcessEvents
| where InitiatingProcessFileName in~ ("winword.exe", "excel.exe", "powerpnt.exe", "outlook.exe")
| where FileName in~ ("powershell.exe", "pwsh.exe", "wscript.exe", "cscript.exe", "mshta.exe", "regsvr32.exe")
| project Timestamp, ReportId, DeviceId, DeviceName, AccountSid, AccountUpn,
          FileName, ProcessCommandLine, InitiatingProcessFileName, InitiatingProcessCommandLine
```

No time filter, deliberately. The service prefilters on the detection lookback, and MS Learn warns against filtering on `Timestamp` or `TimeGenerated` yourself. If you do need one, use `ingestion_time()` and match it to the lookback. The `project` list earns its keep, and it's the part people get wrong most often - it gets its own section further down.

The rest is wizard, not KQL:

- **Entities** - pre-populated, not automatic. `DeviceId`, `DeviceName`, `AccountSid` and `AccountUpn` are all strong identifiers, so device and account arrive already mapped. Still walk the step - entities drive how alerts group into incidents. Microsoft markets this as "automatic entity mapping"; in practice it saves you the lookup, not the review.
- **Dynamic alert title** - `{{FileName}} launched by {{InitiatingProcessFileName}} on {{DeviceName}}`. Three columns, which is also the hard limit per field. The alert queue stops being a wall of identical rule names.
- **Custom details** - `ProcessCommandLine` in the alert side panel, so it's there during triage without pivoting into hunting. Capped at 20 pairs and 4 KB combined, and blowing the size limit drops the *entire* custom details array rather than truncating it.
- **Response action** - Isolate device, off the `DeviceId` column. No Logic App, no playbook, no automation rule.
- **Frequency** - Continuous (NRT). One table, no join, and `DeviceProcessEvents` is on the supported list.

That last one changed my mind more than anything else. Analytics NRT rules evaluate events *after* ingestion, so they inherit ingestion delay; custom detections at Continuous frequency test events as they stream, with resource impact Microsoft describes as minimal to none.

> Don't guess at NRT eligibility - use **Migrate now** on the custom detection rules page. It lists every existing rule that actually qualifies and converts the ones you pick
{: .prompt-warning}

### Case 2 - Crossing the estates

The second rule is one an analytics rule cannot express at all: endpoint telemetry from Defender XDR joined against perimeter data that only exists in Sentinel.

A device successfully reached a public IP the firewall is denying for everyone else. Either the egress path isn't what the network team thinks it is, or the host has a way around it. Both deserve an alert.

```shell
let FirewallDenies =
    CommonSecurityLog
    | where DeviceAction in~ ("deny", "drop", "reset-both")
    | summarize DenyCount = count(), DeniedFor = dcount(SourceIP) by DestinationIP
    | where DeniedFor > 3;
DeviceNetworkEvents
| where ActionType == "ConnectionSuccess"
| where RemoteIPType == "Public"
| join kind=inner FirewallDenies on $left.RemoteIP == $right.DestinationIP
| project Timestamp, ReportId, DeviceId, DeviceName, AccountSid, RemoteIP, RemoteUrl,
          InitiatingProcessFileName, InitiatingProcessCommandLine, DenyCount, DeniedFor
```

One rule, two estates, no duplication. `CommonSecurityLog` stays in Sentinel, `DeviceNetworkEvents` stays in Defender, and neither gets copied to make the correlation work.

> `DeviceAction` values are vendor-specific. `deny`, `drop` and `reset-both` are Palo Alto shaped - check what your own firewall actually writes into `CommonSecurityLog` before reusing this. Neither of the two queries in this post has been run in anger; treat both as the shape of the thing rather than something to paste
{: .prompt-warning}

The bill for that isn't obvious from the wizard:

- **No NRT.** Two tables and a `join`, either disqualifying on its own - even though both tables appear individually on the supported list. Be precise here though: `summarize` is *not* the problem. Microsoft's own NRT-compatible sample uses `summarize` with `arg_max`, so aggregation is fine as long as you stay inside one table.
- **No custom frequency, no custom lookback.** Both appear only when a rule is built on Sentinel data *only*, and one `DeviceNetworkEvents` reference is enough to lose them. That puts this rule on the fixed ladder, which is why `Window` is `4h` - it matches an hourly rule's lookback.
- **Entity mapping is half pre-filled.** `DeviceId` and `AccountSid` come from the Defender side already mapped. Anything from the Sentinel side you do yourself, so `RemoteIP` as evidence goes in by hand under *Related evidence*.
- **Response actions and XDR enrichment functions still work**, because the rule uses Defender data. Isolate device is available off `DeviceId`, and `FileProfile()`, `SeenBy()`, `DeviceFromIP()` and `AssignedIPAddresses()` are callable from a query that's otherwise driven by Sentinel data. An analytics rule can't do either.

## ⏱️ Frequency and lookback

I initially assumed frequency and lookback were two independent settings. They are not. **Run a rule less often and it looks back further.** You only get to choose both independently when the query is Sentinel-only.

| Frequency | Lookback |
| --- | --- |
| Every 24 hours | Past 30 days |
| Every 12 hours | Past 48 hours |
| Every 3 hours | Past 12 hours |
| Every hour | Past 4 hours |
| Continuous (NRT) | Events as they're collected and processed |
| Custom, 5 minutes to 14 days | Configurable, Sentinel-only queries |

The rule that governs all of it: **custom lookback is only available for queries containing only Microsoft Sentinel data tables.** One Defender XDR table in the query and the ladder above applies, no negotiation.

For Sentinel-only rules the configurable bounds move with the frequency. This part is still public preview:

| Frequency | Configurable lookback |
| --- | --- |
| Run interval shorter than one hour | Under 48 hours |
| Run interval from one hour through one day | Up to 30 days |
| Run interval longer than one day | Up to 14 days |

> Which is where custom detections quietly overtake analytics rules. A 30-day ceiling against 14 gives slow-burn exfiltration, low-and-slow credential spraying and first-seen-in-30-days logic room an analytics rule doesn't have. The comparison doc files this under "parity with analytics rules", which undersells it two-fold.
{: .prompt-tip}

### Tables that support Continuous (NRT)

Query shape isn't the only gate. The table has to be on the supported list, and if it isn't, no amount of rewriting helps.

One thing first, because the wizard muddles it: the frequency picker describes Continuous as checking "events as they are ingested into Microsoft Defender XDR", which reads as XDR-only. It isn't. The supported-table list in Microsoft's [custom detection rules documentation](https://learn.microsoft.com/en-us/defender-xdr/custom-detection-rules) covers both Defender XDR and Microsoft Sentinel data.

Two exclusions to know. `EmailEvents` is supported apart from its `LatestDeliveryLocation` and `LatestDeliveryAction` columns. And across the board only **generally available** columns qualify - a preview column in an otherwise supported table keeps a rule off Continuous.

The Sentinel side is a fixed allowlist, which is the detail that catches people. Arbitrary custom `_CL` tables are not on it, so your own normalised firewall or DNS table cannot run Continuous - a scheduled custom frequency down to 5 minutes is the closest you'll get. Check the documentation before relying on a table, because the list changes as tables reach GA.

> For scheduled custom detections, lookback is evaluated against `ingestion_time()`, not the event timestamp. A late-arriving event can therefore be evaluated even when its `Timestamp` is older than the configured lookback. Continuous (NRT) rules are different: they process events as they are collected rather than applying this scheduled lookback window.
{: .prompt-info}

For scheduled rules, that means alert event times can predate the configured lookback. Where lookback exceeds frequency you get overlap too - which it does at every rung of the first ladder - though custom detections deduplicate events with identical entities, custom details and dynamic details into one alert rather than alerting twice.

## 🧩 The columns you have to project

This is the part I underestimated. Custom detections care what the query returns, and not in a "nice to have" way. Drop the wrong column and you get a working rule with a degraded alert. I find that worse than a query failing outright, because nothing obvious tells you what context went missing.

| Column | Why it matters | Applies to |
| --- | --- | --- |
| `Timestamp` or `TimeGenerated` | Sets the alert's event time. Omit it and first/last event time are derived from the lookback window instead | Everything |
| `DeviceId` or `DeviceName` | Correct device group scope on the alert, and the process tree view renders | Defender for Endpoint tables |
| `Timestamp` **and** `ReportId` from the same event | Lets Defender identify the originating event, which drives correct entity scope and a fully enriched alert timeline | All other Defender tables |
| A strong entity identifier | The wizard pre-populates the impacted asset for you | Everything, if you don't want to map by hand |

The strong identifiers that get pre-populated are worth knowing by heart:

| Entity | Identifiers |
| --- | --- |
| Device | `DeviceId`, `DeviceName`, `RemoteDeviceName` |
| Account | `AccountObjectId`, `AccountSid`, `AccountUpn`, `InitiatingProcessAccountSid`, `InitiatingProcessAccountUpn` |
| Mailbox | `RecipientEmailAddress`, `SenderFromAddress`, `SenderMailFromAddress`, `SenderObjectId`, `RecipientObjectId` |

Simple queries return all of this by accident. The trouble starts when you `summarize`, because neither `ReportId` nor `Timestamp` survives a `summarize ... by DeviceId`. The documented fix is `arg_max`, which carries both back from the most recent event per group:

```shell
DeviceEvents
| where ingestion_time() > ago(1d)
| where ActionType == "AntivirusDetection"
| summarize (Timestamp, ReportId)=arg_max(Timestamp, ReportId), count() by DeviceId
| where count_ > 5
```

That's Microsoft's own sample, and it generalises - any time you aggregate, re-attach `Timestamp` and `ReportId` this way rather than dropping them. As a bonus it's still one table with supported operators, so it stays NRT-eligible.

### When the table has no ReportId

Sentinel tables generally don't have one. `ReportId` is a Defender XDR schema column, and `CommonSecurityLog`, `SigninLogs` and `AzureActivity` carry `TimeGenerated` instead. Nothing to work around: project `TimeGenerated`, map entities manually, and accept a thinner alert timeline. Microsoft's guidance on `ReportId` is scoped to Defender tables, so this isn't you doing it wrong.

Some Defender XDR tables don't have one either - snapshot and inventory-shaped tables more likely than event tables, though that's a hunch rather than something I've enumerated. Don't guess, check with `getschema`. If it isn't there, don't try to manufacture one: `Timestamp` and `ReportId` have to come **from the same event**, and borrowing a `ReportId` through a join points the alert timeline at a different event entirely, which is worse than leaving it empty. Two things that do work - accept the thinner timeline for a rule whose value is the aggregate anyway, or flip the query so an event table drives the detection and the snapshot table joins on for enrichment. The second isn't a workaround, it's the shape the feature expects.

> One more from the same family, easy to miss: if you've configured Microsoft Sentinel scoping, `SentinelScope_CF` has to be projected too. It's not about alert quality - leave it out and scoped analysts can't see the alerts at all.
{: .prompt-info}

## 🛡️ Native response actions, no playbook required

This was probably the most practical reason for my change of mind. An analytics rule detects, but everything that *happens* afterwards is a separate object: an automation rule, then a playbook, then a Logic App with its own identity, permissions, failure modes and bill. Four moving parts before a device gets isolated. A custom detection just does it, configured in the rule wizard.

The mechanism isn't a dropdown of targets - **the projected column is the contract.** You make an action available by returning the right identifier. Get the column wrong and the action isn't offered.

| Target | Actions | Column the action binds to |
| --- | --- | --- |
| Device | Isolate device, Collect investigation package, Run antivirus scan, Initiate investigation, Restrict app execution | `DeviceId` |
| User | Mark user as compromised | `AccountObjectId`, `InitiatingProcessAccountObjectId`, `RecipientObjectId` |
| User | Disable user, Reset user authentication | `AccountSid`, `InitiatingProcessAccountSid`, `RequestAccountSid`, `OnPremSid` |
| File | Quarantine file | `SHA1`, `InitiatingProcessSHA1`, `SHA256`, `InitiatingProcessSHA256` |
| File | Allow / Block | A file ID such as a SHA-1 hash |
| Email | Move to mailbox folder, Delete email (soft or hard) | `NetworkMessageId` **and** `RecipientEmailAddress` |

Three of these do more than the label suggests:

- **Mark user as compromised** sets the user's risk level to high in Microsoft Entra ID, so your existing Identity Protection and Conditional Access policies pick it up and act. You're not writing the response, you're feeding a response engine you already own.
- **Restrict app execution** leaves only Microsoft-signed binaries able to run. A useful middle gear between doing nothing and isolating the machine, and it's one checkbox.
- **Block file** reaches past the alert - other instances of that file are blocked across all devices in the device group you scoped it to.

> `Disable user` and `Reset user authentication` both need a **SID**, and Microsoft Entra identities need `AccountObjectId` for every user action. A query returning only a UPN gets you a nicely enriched alert and no ability to act on it. Project the identifiers even when you think you don't need them
{: .prompt-warning}

Many of the containment actions I normally put into SOC playbooks are now a checkbox on the rule that found the thing. Which raises the obvious objection: a checkbox that isolates machines is a checkbox you want to be careful with.

## 🎯 Scoping to device groups

Device-group scoping is what made me comfortable even considering automatic response actions. It isn't a filter bolted onto the output - the rule queries data only from devices in scope, and takes actions only on those devices. Two things follow, and they're the reason it matters:

- **You can pilot a destructive action.** Point an auto-isolate rule at a canary device group, watch it for a fortnight, then widen the scope. Same rule, no duplicate to keep in sync. Given that rule simulation is still `Planned`, it's the main tool you've got.
- **The scope is enforced by RBAC, not by trust.** You can only create or edit a rule scoped to device groups you have permissions for, and you can't scope to all devices unless you have permissions for all of them. That turns scoping into a delegation model: a regional team can own detections for their own estate without being able to fire an isolate action across the tenant.

Scope only influences rules that check devices, so a rule looking purely at mailboxes or identities is unaffected. And more awkwardly:

> **Custom frequency and device group scoping are mutually exclusive.** Custom frequency is only offered for rules built on Microsoft Sentinel data, and Defender fetches that data from Sentinel - which doesn't support scoping. So a rule on a 15 minute schedule runs unscoped by definition. Pick which one the detection actually needs
{: .prompt-warning}

## 🛠️ Detections as code

The objection I heard most, and made myself, was that custom detections were a portal-only artefact. Two things fixed that, and the second is about four weeks old as I write this.

First, a proper Microsoft Graph API. Custom detection rules are exposed as `microsoft.graph.security.detectionRule` under `/security/rules/detectionRules`, with the usual `GET` / `POST` / `PATCH` / `DELETE` set. The body decomposes into `queryCondition` (the KQL), `schedule` (frequency) and `detectionAction` (the alert template plus automated response). `id` is **client-provided** on create, which gives you a stable identifier for deployments - but it does not turn `POST` into an upsert, so a deployment tool still creates with `POST` and updates with `PATCH`.

Three details there are more useful than they look. Read-only audit metadata comes for free - `createdBy`, `lastModifiedBy` and timestamps - which, given how limited the advanced hunting audit logs are, is currently the best way to answer "who changed this rule and when". `status` has three values, not two: `enabled`, `disabled` and `autoDisabled`, the third being the service switching a rule off on your behalf, which is exactly what you want a nightly script watching for. And `$filter` works on `queryCondition/queryText` with `contains`, turning the API into an inventory tool - "which of my rules still reference a table that's being retired" becomes one call. Permissions are `CustomDetection.Read.All` and `CustomDetection.ReadWrite.All`; on the Defender side, writes map to the `Detection tuning (Manage)` unified RBAC permission.

> The [Graph `detectionRule` API](https://learn.microsoft.com/en-us/graph/api/resources/security-detectionrule?view=graph-rest-beta) is `/beta`, not supported for production applications, and global-service only - no US Gov L4/L5 or 21Vianet. Three properties are deprecated and disappear on **1 October 2026**: `isEnabled` (use `status`), `detectorId`, and `lastRunDetails` - the last being the only place the platform exposes per-rule execution outcomes, and absent from v1.0 entirely
{: .prompt-warning}

Second, [custom detections in Sentinel repositories through Bicep](https://learn.microsoft.com/en-us/azure/sentinel/ci-cd-custom-content#deploy-custom-detection-rules-as-code-preview), announced in **July 2026** and still public preview. This is the one that changes a workflow, because custom detections now sit in repositories next to analytics rules, playbooks, parsers and workbooks instead of being the one content type you had to click in by hand.

They deploy as the `Microsoft.Security/detectionRules` resource type through a dedicated Microsoft Security Bicep extension - a different extension *and* a different resource provider to the rest of the Sentinel content types, which is the first thing to internalise if you already have a repo full of `Microsoft.SecurityInsights` templates. Wire it up with a `bicepconfig.json` in the repository root:

```json
{
  "extensions": {
    "MicrosoftSecurity": "br:mcr.microsoft.com/bicep/extensions/microsoftsecurity:v1.0.1"
  }
}
```

The rule itself looks like this. Note the `extension MicrosoftSecurity` line - without it the resource type won't resolve:

```bicep
extension MicrosoftSecurity

resource detectionRule 'Microsoft.Security/detectionRules@2026-06-01-preview' = {
  id: 'custom-rule-id'
  displayName: 'Custom Rule Display Name'
  status: 'enabled'
  queryCondition: {
    queryText: 'DeviceProcessEvents | take 10 | project DeviceId, Timestamp, FileName'
  }
  schedule: {
    frequency: 'PT1H'
  }
  detectionAction: {
    alertTemplate: {
      title: '<ruleTitle>'
      severity: 'medium'
      tactics: [
        {
          tactic: 'Execution'
          techniques: [ { technique: 'T1059' } ]
        }
      ]
      entityMappings: {
        hosts: [ { id: 'h', deviceIdColumn: 'DeviceId' } ]
      }
    }
  }
}
```

`frequency` is an ISO 8601 duration, so `PT1H` rather than a friendly string. The MITRE mapping is genuinely nested - techniques hang off a tactic - which is schema-level confirmation of the earlier point that tagging works fine and it's only *multiple* tactics that aren't there yet. Entity mappings are expressible too, so the mapping you'd otherwise click through in the wizard becomes reviewable in a pull request.

> Rules are keyed on the `id` in the template, so that ID is the thing you must never regenerate between runs. Awkwardly, this is the opposite of every other Sentinel content type - Bicep files for those **don't** support an `id` property at all, and Microsoft's guidance is to strip it when decompiling exported ARM templates. One repo, two opposite rules
{: .prompt-warning}

From there, two deployment paths: connect the repository under **Microsoft Sentinel** > **Content management** > **Repositories** and tick `Custom Detection Rules`, or skip the sync and run `az deployment group create` from your own pipeline. If you go the repository route, understand what you're signing up for - the repo becomes the **single source of truth**, and syncs overwrite portal changes. Combined with the preview limits below that has a sharp edge, so I'd keep repo-managed and portal-tuned rules in separate populations until the gap closes.

> The [Bicep preview](https://learn.microsoft.com/en-us/azure/sentinel/ci-cd-custom-content#deploy-custom-detection-rules-as-code-preview) bites exactly where this post has been enthusiastic - **custom frequency for Microsoft Sentinel data isn't supported, and neither are custom details**. A rule you tuned in the portal with a 15 minute frequency and a populated alert side panel is not something you can round-trip through Bicep today. Prerequisites are stricter than for other content types too: Microsoft 365 E5 or equivalent, and workspaces already onboarded to the Defender portal
{: .prompt-warning}

Which is why I wouldn't move an existing well-tuned rule into a pipeline yet. For net-new content written with the constraint in mind, it works.

## 🔗 Incident correlation, and opting out of it

This is the gap that has cost me the most argument time, and the one place I'd read the comparison doc against another doc rather than trusting it - it lists correlation exclusion as `Planned` for **both** rule types, yet analytics rules have a shipped feature for exactly this in the [correlation exclusion documentation](https://learn.microsoft.com/en-us/defender-xdr/exclude-analytics-rules-correlation).

The problem it solves is real. In Sentinel, incidents were static: the rule's grouping configuration decided what landed where. In Defender, the correlation engine builds *attack stories*, pulling alerts from different rules and products into one incident on shared entities, artefacts, time frames or a recognisable multistage sequence. Usually what I want. Sometimes absolutely not - a compliance detection that must stay its own ticket, or a downstream system keyed on one rule per incident.

Analytics rules give you three levels of control: a **tenant default** toggle under **System** > **Settings** > **Microsoft Defender XDR** > **Rules** > **Incident correlation** (worth knowing it's **off by default**, so all analytics rules are excluded unless you opt one in), a **per-rule dropdown** on the *Incident settings* tab, and a **tag** - because the toggle is really writing `#DONT_CORR#` or `#INC_CORR#` at the very start of the rule description, settable by hand or through the API.

> Three traps. The tag *is* the state, so manually stripping `#DONT_CORR#` from a description silently re-enables correlation. Correlation state is stamped on an alert when it's created, so changing the rule doesn't retrofit existing alerts. And even on an excluded rule with a dynamic title, the Defender incident title can differ from the Sentinel one - Sentinel uses the first alert's title, Defender falls back to the common MITRE tactic across alerts
{: .prompt-warning}

**Custom detections have none of this.** No toggle, no tag, no per-rule setting. Every alert joins or creates an incident, and the correlation engine decides which. If deterministic one-rule-one-incident behaviour is a requirement, that alone is enough to keep the detection as an analytics rule - it's the cleanest example in this post of a gap you cannot engineer around.

You can influence it at the margins:

- **Map fewer entities.** Correlation works on shared entities and artifacts, so every extra mapping is extra surface to merge on. Map what should drive correlation, not everything you happen to have projected.
- **Enable the device group condition.** Incidents containing devices in different device groups aren't merged - but this condition is **off by default**. If your device groups mirror business units, switching it on is the closest thing to scoped correlation, and it pairs neatly with scoping the rules themselves.
- **Unlink and relink manually.** Every alert must belong to some incident, but you can move an alert to a different or new one after the fact.

None of that gives you the guarantee the analytics rule toggle does. It reduces the odds.

## 💰 About that cost argument

Microsoft leads with "reduce ingestion costs". The saving is real when data would otherwise be ingested *only so a rule could query it*. Retention, historical analysis and correlation with non-Microsoft sources can still justify keeping a copy. Detection alone no longer does. I covered the ingestion side separately in [Streaming Defender XDR into the Sentinel data lake](https://pisinger.github.io/posts/streaming-defender-xdr-into-sentinel-data-lake/).

That separates two decisions: **what to detect on, and what to retain**. In a new environment I would keep the included 30-day XDR copy for hunting and custom detections, rather than stream every high-volume table into Sentinel Analytics just for analytics rules. For longer retention, configure the Sentinel data lake where needed; it is not automatic or free, as Microsoft's [data tier and retention guidance](https://learn.microsoft.com/en-us/azure/sentinel/manage-data-overview) makes clear. I would also convert useful Content Hub rules to custom detections instead of designing ingestion around them.

Both rule types remain **analytics-tier only**: they cannot query Basic, Auxiliary or data lake tables directly. [Summary rules](https://learn.microsoft.com/en-us/azure/sentinel/summary-rules) and [KQL jobs](https://learn.microsoft.com/en-us/azure/sentinel/datalake/kql-jobs) can promote a high-value derivative into the Analytics tier - for example, a small `MaliciousIPDetection` table distilled from noisy firewall data, as in [Detecting suspicious DNS requests](https://pisinger.github.io/posts/detect-suspicious-dns-requests/). The trade-off is manual mapping, a thinner alert timeline and latency equal to the distillation cadence plus the rule frequency. Fine for enrichment; for low-latency containment, keep the source in Analytics or use an analytics rule and playbook.

## 🧭 When I still reach for an analytics rule

The verdict is a default, not an absolute. New detection means custom detection, unless one of these applies - and there are more of them than the marketing suggests. The gaps table above has the full list; these are the ones that actually decide a rule for me.

**Multi-workspace scope.** Cross-workspace with the `workspace()` operator, no workaround. Multi-*tenant* is a different problem and it's fine: the Detection rules list is manageable from the multitenant portal, and custom detections push through MTO content distribution profiles, so an MSSP shipping one rule to fifty tenants has a supported path.

**Existing playbooks usually remain usable.** Custom-detection alerts are correlated into Defender XDR incidents, and Sentinel automation rules with incident-created or incident-updated triggers can run playbooks against those incidents. That covers the usual ticketing, notification, enrichment and third-party integration scenarios. The limitations are in rule-specific and alert-level targeting: you cannot bind an incident automation rule to a custom detection through the analytics-rule-name condition, an alert may update an existing incident instead of creating one, and incident synchronization introduces some delay. Use incident-created and incident-updated conditions.

**Deterministic incident boundaries.** Custom-detection alerts participate in Defender XDR correlation and may be merged with alerts from other rules and products. Custom detections cannot opt out of correlation, suppress alerts after a run, create alerts without incidents, or configure grouping. This does not prevent incident-triggered playbooks from running, but it matters when a downstream workflow assumes exactly one rule or alert per incident. Keep an analytics rule only when that deterministic boundary is a genuine requirement; otherwise, make the playbook correlation-aware and use custom detections.

**Validation and observability.** The gap I'd weigh most heavily after multi-workspace, and the only one currently getting worse: simulation and historical rerun are `Planned`, health logs and workbooks are `Planned`, and the one API surface exposing per-rule failures is deprecated. Run-on-demand helps but runs against the current window rather than one you choose.

**NRT with a complicated query.** This one surprised me. Custom detection NRT is faster but takes a single table with no joins, while an analytics NRT rule can reference multiple tables across workspaces. For a near-real-time detection that genuinely needs a correlation, analytics rules win on capability even while losing on latency.

**Content hub and community content.** The overwhelming majority of community, vendor and Content Hub content ships as analytics rules - ARM templates, Sentinel solutions, everyone's GitHub repo of KQL. That ecosystem won't be ported overnight. But that's an argument for deploying that content as-is, not for authoring new rules the same way. Two separate activities, and people conflate them.

I'm also in no hurry to migrate anything, and neither is Microsoft - their FAQ says no action is currently necessary and that parity is still being worked toward. A working analytics rule keeps working. Move it when there's a reason: it wants XDR data it can't see, or it would benefit from true NRT.

## 📝 Conclusion

The direction was never in question. What I wanted to know was when choosing custom detections would stop costing me something important. For my own environments that point arrived somewhere between dynamic alert details in August 2025 and NRT on Sentinel data in January 2026, and repositories and Bicep in July 2026 removed the last structural objection: a detection built this way can finally be shipped alongside the rest of the estate.

Defender XDR data without duplicating it into Sentinel purely for detection, native remediation scoped to device groups, a 30-day lookback ceiling, and streaming NRT matter more to me than suppression windows and configurable alert grouping. The remaining gaps are real, especially multi-workspace rules, first-class rule-specific and individual-alert automation, historical reruns and health visibility. That's why custom detection is both my greenfield default and the default I recommend to customers, not a migration mandate: in a new environment I'd avoid duplicating XDR device data into Sentinel just to preserve old rule formats, and in a mature one I'd leave working detections alone until cost or capability gives me a real reason to touch them.

## 📚 Sources

Preview status and `Planned` rows move, so check the originals before making a decision.

- [Feature comparison: analytics rules vs custom detections](https://learn.microsoft.com/en-us/azure/sentinel/compare-analytics-rules-custom-detections)
- [Create custom detection rules](https://learn.microsoft.com/en-us/defender-xdr/custom-detection-rules)
- [Manage custom detection rules](https://learn.microsoft.com/en-us/defender-xdr/custom-detection-manage)
- [Manage analytics rule correlation settings](https://learn.microsoft.com/en-us/defender-xdr/exclude-analytics-rules-correlation)
- [Microsoft Sentinel service limits](https://learn.microsoft.com/en-us/azure/sentinel/sentinel-service-limits)
- [Near-real-time analytics rules and their constraints](https://learn.microsoft.com/en-us/azure/sentinel/near-real-time-rules)
- [Microsoft Sentinel data tiers and retention](https://learn.microsoft.com/en-us/azure/sentinel/manage-data-overview)
- [Compare KQL jobs, summary rules, and search jobs](https://learn.microsoft.com/en-us/azure/sentinel/datalake/kql-jobs-summary-rules-search-jobs)
- [Microsoft Graph `detectionRule` resource](https://learn.microsoft.com/en-us/graph/api/resources/security-detectionrule?view=graph-rest-beta)
- [Deploy custom detection rules as code](https://learn.microsoft.com/en-us/azure/sentinel/ci-cd-custom-content#deploy-custom-detection-rules-as-code-preview)
