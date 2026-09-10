---
title: Leveraging Sentinel MCP and Entity Analysis: Logic Apps as a Common Playground
author: pit
date: 2026-09-10
categories: [blogging, tutorial]
tags: [azure, sentinel, mcp, entity-analyzer, soar, logic-apps, security-copilot, scu, incident-response]
render_with_liquid: false
---

An incident usually arrives with more than one interesting object attached to it - a user, a URL, a device, perhaps an IP address as well. The useful question is rarely just “what alert fired?” It is “what do we already know about each entity, and what should the analyst do next?”

There is nothing fundamentally new about enriching an incident with this kind of information. We have been checking threat intelligence, IoCs, sign-in activity, and other identity-related queries for years to build a better evidence package. The interesting question for me is whether existing Sentinel and Logic Apps actions can make that workflow simpler, while moving part of the summarization into an agentic pattern.

My first instinct was to add one incident comment after every entity analysis. That works, but an incident with several accounts and URLs quickly turns into a comment stream that is hard to read. The current workflow instead runs Microsoft Sentinel's Entity Analyzer for the accounts, URLs, and DNS entities linked to an incident, collects the findings, lets the built-in Logic Apps Agent summarize them, and writes one consolidated update.

For more complex orchestration, I could move this work into a Foundry agent and gain much more flexibility around tools, planning, and branching. That is not the goal here. I want to stay within the Logic Apps boundary and show what the new Microsoft Sentinel MCP integration can do with its built-in Entity Analyzer action and the native Agent capability already available in the workflow.

The awkward parts are devices and IP addresses. The same entity-analyzer action is not available for devices, and the service rejects IP addresses. Devices are still perfectly reasonable investigation targets, but they need a different path - for example, a blast-radius or graph query, or a deterministic KQL workflow over device telemetry.

There is one more design detail worth making explicit before adding this to SOAR: **the entity analyzer consumes Security Compute Units (SCUs)**. That usage is attached to the analyzer operation, not to the user interface where somebody happens to invoke it.

> Microsoft Sentinel's MCP Entity Analyzer is powered by the Security Copilot platform behind the scenes and consumes SCUs as part of the Entity Analyzer capability itself. That applies regardless of whether the tool is invoked from a Logic App, GitHub Copilot, Visual Studio Code, or another agent. Existing Security Copilot entitlements may cover the usage; overages are charged according to the applicable terms.
{: .prompt-warning}

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fpisinger%2Fscripts-lib%2Fmain%2Fdefender%2Fplaybook-sentinel-entity-analyzer%2Fsentinel-entity-analyzer-agent-summary.template.json)

Use the button to deploy the [public ARM template](https://github.com/pisinger/scripts-lib/tree/main/defender/playbook-sentinel-entity-analyzer) directly to Azure. The template deploys the Logic App and its connections; the required Sentinel roles and data-lake prerequisites still need to be in place before the playbook can analyze entities.

> Microsoft reference: <https://learn.microsoft.com/en-us/azure/sentinel/datalake/sentinel-mcp-logic-apps>
{: .prompt-info}

## 🧭 What the entity analyzer actually does

The Microsoft Sentinel data exploration collection exposes three relevant operations for entity analysis:

1. `analyze_user_entity` starts an analysis for a Microsoft Entra user.
2. `analyze_url_entity` starts an analysis for a URL.
3. `get_entity_analysis` retrieves the result using the analysis identifier returned by the first operation.

The analysis reasons over security data in the Microsoft Sentinel data lake and produces a verdict with supporting context. For a user, that can include authentication patterns, anomalous behavior, alerts, suspicious IP addresses, user agents, and remediation recommendations. For a URL, the analysis can combine the organization's activity with threat-intelligence and prevalence context. The capability announcement lists entity analyzer as generally available from April 1, 2026, with SCU charging starting on that date. The Logic Apps integration page is still labeled preview, and the template pins a preview API version, so I would describe the analyzer capability as GA while treating this particular Logic Apps deployment surface as subject to preview changes.

This is different from asking an MCP client to run one KQL query. The analyzer is a packaged reasoning workflow which combines multiple data points and returns an assessment. The data exploration collection can also search tables and run KQL, but those are separate operations with a different billing description.

## 📡 Data requirements and analysis limits

The analyzer is only as useful as the data available in the Sentinel data lake. Microsoft documents the following tables and limits in the [Additional information section of the data exploration tool documentation](https://learn.microsoft.com/en-us/azure/sentinel/datalake/sentinel-mcp-data-exploration-tool#additional-information).

For `analyze_user_entity`, the following tables are required:

- `AlertEvidence`
- `SigninLogs`
- `CloudAppEvents`
- `IdentityInfo`

All four tables are required to ensure an accurate analysis. If one is missing, the tool returns an error listing the missing tables and links to onboarding documentation.

The following tables are recommended for user analysis. The analyzer continues to work and assess risk if they are unavailable:

- `AADNonInteractiveUserSignInLogs`
- `BehaviorAnalytics`

The following tables are recommended for `analyze_url_entity`. The analyzer continues to work and assess risk if they are unavailable, but the response includes a disclaimer listing missing tables and onboarding links:

- `EmailUrlInfo`
- `UrlClickEvents`
- `ThreatIntelIndicators`
- `Watchlist`
- `DeviceNetworkEvents`

Microsoft's [`IdentityInfo` schema documentation](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-identityinfo-table) says the table is available only to tenants with Microsoft Defender for Identity, Microsoft Defender for Cloud Apps, or Microsoft Defender for Endpoint Plan 2 licensing. Because the Entity Analyzer also lists `IdentityInfo` as required for user analysis, this is both a licensing and data-onboarding dependency - not merely an optional enrichment table. The license does not by itself guarantee successful analysis; the relevant product must be onboarded and the table must be present in the Sentinel data lake.

There are two other limits I would make visible in the playbook design:

- `analyze_user_entity` supports a maximum analysis window of seven days.
- Users must have a Microsoft Entra object ID. On-premises Active Directory-only users aren't supported for user analysis.

The Logic Apps connector documentation shows a UPN as an accepted user input, but the analyzer's additional-information guidance specifically calls out the Microsoft Entra object ID requirement. I would pass the object ID whenever possible and treat UPN handling as something to validate in the target tenant.

> If an incident-triggered playbook sends many entities at once, start with a maximum of five concurrent analyses. Multiple analyzer instances can increase latency and cause timeouts; tune the degree of parallelism only after checking the workflow's incident volume and service limits.
{: .prompt-warning}

> The official documentation describes the analyzer as a user and URL capability. A device appearing as an entity in a Sentinel incident does not make it a supported input to `analyze_user_entity` or `analyze_url_entity`.
{: .prompt-info}

For the detailed tool description, see [Explore Microsoft Sentinel data lake with data exploration collection](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-mcp-data-exploration-tool).

## 🛠️ The practical SOAR pattern

My Logic App follows a simple incident-enrichment loop:

```text
Manual run from the incident in Microsoft Defender / Sentinel
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│ Incident-triggered Logic App playbook                        │
└───────────────────────────────────────────────────────────────┘
        │
        ├─ Read the incident entities
        │
        ├─ Read entities linked through the incident's alerts
        │
        └─ Normalize and classify entities
                │
                ▼
        ┌─────────────────────────────────────┐
        │ Analyze users, URLs, and DNS domains │
        │ Report IPs as skipped                │
        └─────────────────────────────────────┘
             │
             └─ For each entity
                  ├─ Start the appropriate analysis
                  ├─ Parse verdict, evidence, and sources
                  └─ Append one normalized finding
                                │
                                ▼
        ┌──────────────────────────────────────┐
        │ One no-tools Agent action summarizes  │
        │ the findings into one HTML fragment   │
        └──────────────────────────────────────┘
                         │
                         ▼
        Add one summary or fallback comment
```

![High-level Entity Analyzer Agent summary workflow](/assets/img/posts/microsoft-sentinel-mcp-entity-analyzer-soar-scu-billing/entity-analyzer-agent-summary-blog.svg)
High-level flow with the permissions used by each workflow stage

The implementation choice I care about most is keeping the entity types separate. The workflow extracts related entities from the incident, normalizes `Account` and `User` to a user analysis, `Url` to a URL analysis, and `DnsResolution`/`Dns` to a URL analysis using the domain value. Each filtered entity produces one normalized finding, including skipped and failed items, so the final counts remain visible.

IP entities are deliberately retained as `skipped` findings when `reportIpEntities` is enabled. That makes the comment say “this IP was present but not analyzed” instead of silently changing the incident counts. They are never sent to the analyzer: the service returns `InvalidField` for IP addresses.

For users and URLs, the connector action accepts the entity properties, a Microsoft Sentinel data lake workspace ID, and a look-back period. The equivalent JSON shape from the Microsoft documentation is small enough to show the idea:

```json
{
  "entityType": "Url",
  "url": "https://example.invalid/login"
}
```

For a user, the connector documentation shows a Microsoft Entra object ID or UPN as input. I would prefer the object ID where it is available, because the analyzer guidance specifically calls out Microsoft Entra-backed users:

```json
{
  "entityType": "User",
  "userId": "00000000-0000-0000-0000-000000000000"
}
```

The underlying analyzer is asynchronous: the MCP tool can start an analysis and retrieve it with `get_entity_analysis`. The Logic Apps Entity Analyzer action wraps those two phases into one connector action - it starts the analysis and takes care of retrieving the result. This template therefore needs no separate `get_entity_analysis` action: it calls Entity Analyzer once, waits for the connector result, parses the returned status, classification, analysis text, recommendation, disclaimer, and data-source list, and appends a normalized object to the run-scoped `findings` array.

The resulting comment should help the analyst without becoming a second incident report. I send the normalized findings to one native Logic Apps `Agent` action with no tools. It returns an HTML fragment containing an overall verdict, one block per entity, up to four evidence lines, and one action; the workflow adds the risk key and run counts around it.

This is the main difference from the usual “analyze and comment” pattern. I deliberately do not add a Sentinel comment inside the `For each` loop. Each iteration appends one finding object to the `findings` array, including the entity label, normalized entity type, status, classification, analysis, recommendation, data sources, disclaimer, and a workflow-derived risk emoji. The loop only collects results.

After the loop completes, the workflow creates a smaller agent payload from that array. It trims long analysis text, keeps the entity identity and verdict visible, and preserves skipped or failed entities as status records. The built-in Logic Apps Agent then receives the incident context and the complete findings payload in one call. I instruct it to emit an overall paragraph followed by one compact block for each entity, in the same order as the input.

Only after that summarization step does the playbook call the Sentinel `Add comment` action. The final comment contains the worst-case traffic light, the agent-generated entity blocks, a risk key, and counts showing how many entities were analyzed, skipped, or returned no usable verdict. This gives the analyst one readable incident update instead of a sequence of partially duplicated comments that has to be pieced together manually.

The workflow also checks the extracted summary length before posting it. If it is over `28000` characters, `Summary_first_part` sends the first 28,000 characters as the first incident update, `Delay_before_second_comment` waits 10 seconds, and `Add_summary_comment_part_2` posts the remainder. That leaves some headroom for the incident-comment wrapper, risk key, and workflow metadata. The normal path still creates one comment. The split is deliberately simple and character-based, so a very long response can break in the middle of an HTML element; the better control is to keep the Agent concise and treat the two-comment path as a size-limit safeguard.

If the Agent action fails, times out, or returns empty content, the workflow joins pre-rendered HTML blocks from the same `findings` array and posts those as one unsummarized comment. The model improves readability; it is not the system of record for the analyzer output.

The template also trims each entity's analysis to `maxAnalysisCharsPerEntity` before it enters the agent prompt. The default is `4000` characters. This keeps incidents with many entities from turning into an unnecessarily large model request, while the original analyzer fields remain available in the workflow run.

The normal success path posts one comment per playbook run; runs with nothing reportable post no comment, while runs with no usable verdict post a short diagnostic comment. A traffic-light emoji is calculated from the worst finding in the workflow, not by the model. The per-entity emoji, entity type, and friendly label are passed to the agent as values to copy verbatim.

> The template is [playbook-entity-analyzer-agent-summary.template.json](playbook-entity-analyzer-agent-summary.template.json). Deploy it disabled first, run it manually against a representative incident, and inspect both the `Summarize_with_agent` output and the final comment before enabling automation.
{: .prompt-tip}

## 🤖 The no-tools summarization agent

The Agent action is not a Security Copilot connector call. It is a native Consumption Logic Apps autonomous agent action with an Azure OpenAI model selected by the Logic App service in the workflow region. There is no model connection, `deploymentId`, or `modelConfigurations` block in this template, and the agent has an empty `tools` object.

That boundary is intentional. Entity analysis is the SCU-backed security operation. The agent only formats the already-collected findings into an incident comment. It is not allowed to look up more data, run KQL, or take response actions. This gives the model a narrow job and leaves the evidence-gathering path deterministic.

The ARM shape has an important constraint: the `Agent` action sits at the top level of the workflow definition. Putting it inside a `Condition` is rejected by ARM with an unsupported-action error. The comment actions remain conditional, but the agent action itself is reached after the findings payload has been prepared. If the incident contains only skipped entities, the later conditions prevent a comment and the agent is still invoked with an empty reportable payload - an operational cost worth knowing before enabling it.

The template uses ARM parameters for `agentModelType`, `agentMaxHistoryTokens`, and `agentIterationLimit`. Those values are substituted at deployment time. They must be literal values in the stored workflow definition; runtime `@parameters(...)` expressions in those Agent settings can leave deployment hanging or surface later as an internal server error. Runtime expressions are used for the findings message, where they are supported.

The action's response property is not documented clearly enough to hard-code confidently. `Agent_summary_text` therefore tries `lastAssistantMessage.content`, `content`, `output`, and `text` with null-safe property access. If none matches, the normal comment uses the deterministic raw rendering. I would read one real run and replace this defensive coalesce with the actual output path once the tenant confirms it.

> The model is responsible for wording, not risk classification. The workflow computes the header traffic light and supplies the per-entity emoji. If the model changes an emoji, the body can disagree with the header - verify the first real comments and tighten the prompt if needed.
{: .prompt-warning}

## 🎯 Targeted user playbooks in Defender XDR

There is a second entry point that fits a different investigation workflow. In the Microsoft Defender portal, you can run a playbook from a user entity in an incident, from the investigation graph, or from the entity behavior view. The playbook must use the **Microsoft Sentinel Entity** Logic Apps trigger configured for the user entity type.

That makes it possible to create a small, targeted playbook whose only input is the selected user. Instead of extracting every user and URL from an incident, the playbook can receive one user entity and run the entity analyzer for that user only. This is useful when an analyst has already identified the account they want to validate, or when rerunning the check for one entity is preferable to replaying the entire incident enrichment.

The distinction is therefore:

| Entry point | Scope | Good fit |
| --- | --- | --- |
| Incident-triggered playbook | All linked users, URLs, and DNS domains | Consistent enrichment when an incident opens |
| User-entity playbook | One selected user | On-demand validation or a focused re-check |

The user-entity option is a targeted, on-demand action from the Defender experience. It does not replace the incident-triggered workflow when the requirement is to enrich every linked entity automatically.

> Microsoft documents this as an entity-trigger playbook using the **Microsoft Sentinel Entity** trigger. The playbook list shown for a selected user is filtered to playbooks configured for that entity type.
{: .prompt-info}

See [Run a playbook on an entity](https://learn.microsoft.com/azure/sentinel/automation/run-playbooks#run-a-playbook-manually,-on-demand) and [Create and manage Microsoft Sentinel playbooks](https://learn.microsoft.com/azure/sentinel/automation/create-playbooks#create-a-playbook) for the current Defender portal flow.

## 🔗 Use cases beyond an agentic SOC

The entity analyzer does not need an agent in the middle. The Logic App connector is already enough to call it from a deterministic workflow, which is useful when the desired behavior is known in advance and should be easy to audit.

Here are a few practical patterns beyond the incident-enrichment flow described above and beyond “let an agent investigate this incident”:

**Focused analyst recheck** — Use the Defender XDR user-entity playbook when an analyst wants to validate one account again after new evidence arrives. The input is one selected user, the workflow runs one `analyze_user_entity` operation, and the result can be written to the incident or investigation notes. This avoids rerunning all enrichment for the incident and gives the analyst a clean before-and-after checkpoint. It is also a useful manual fallback when the original result has expired and a fresh assessment is justified; if an analysis is still processing, the workflow should retrieve the existing analysis rather than start another one.

**URL triage from email or web detections** — A URL-triggered playbook can analyze a URL from a phishing alert, a user-reported message, or a web-proxy detection. The workflow can preserve the original alert ID, message ID, sender, and affected user next to the analyzer result, then route the case for review if the verdict or supporting evidence meets the organization's escalation criteria. I would keep blocking or deleting the message in a separate action branch, because the analysis provides context and recommendations rather than being the control that authorizes the response.

**Privileged-user review** — A scheduled workflow can analyze a selected set of privileged or sensitive users and create a review task with the verdict, evidence, recommendations, and analysis timestamp. The input list could come from a maintained privileged-account inventory rather than from every user in the tenant. That makes the cost and scope predictable, and lets an identity or access team review accounts that are important even when no new Sentinel incident exists. I would use this as a review queue, not as an automatic replacement for Conditional Access or account-disablement policy.

**Identity-risk case routing** — A risk-detection workflow can analyze selected users from an identity-risk queue and create or update a ticket with the result. The workflow can use the analyzer output to add context to the existing identity signal, assign the case to the right team, and avoid opening duplicate work for the same user and time window. This is useful when the identity signal and the deeper entity assessment are owned by different teams. The workflow should still preserve the original risk event and should not treat the analyzer verdict as a replacement for the source detection.

**Post-incident evidence pack** — At the end of an investigation, a workflow can run a final analysis for the key user and URL entities and attach the returned evidence, recommendations, source list, look-back window, and analysis timestamp to the case record. This gives the review process a repeatable enrichment step and records exactly when the assessment was produced. Because analyzer results are available for only one hour, the workflow should store the relevant output when the case is closed rather than relying on a later rerun to reproduce the same result.

The common design principle is to keep the trigger and scope explicit:

| Workflow | Trigger | Scope | Agent required? |
| --- | --- | --- | --- |
| Targeted user check | User entity action in Defender XDR | One user | No |
| URL triage | Phishing, proxy, or user-report workflow | One or more URLs | No |
| Privileged-user review | Schedule | Selected privileged users | No |
| Identity-risk routing | Risk queue | Selected users | No |
| Post-incident evidence | Case closure or review | Key users and URLs | No |
| Investigation assistant | Analyst prompt or agent task | Depends on the prompt | Optional |

For all of these, the analyzer remains an enrichment and decision-support step. I would keep destructive actions such as disabling an account, blocking a URL, or isolating a device behind a separate policy and approval branch. A verdict and its evidence can inform that decision, but should not silently become the authorization to take it.

## 🎯 Handling devices without pretending they are supported

Devices are where the design becomes more interesting. The fact that the analyzer covers users and URLs does not mean the device is unimportant; it means the enrichment method has to match the question.

This is a potential enhancement to my playbook, not part of the current implementation. The [Microsoft Sentinel MCP Logic Apps guidance](https://learn.microsoft.com/en-us/azure/sentinel/datalake/sentinel-mcp-logic-apps) currently documents the Entity Analyzer action for `User` and `Url` properties only. I cannot find a documented `Device` variant in the connector. If Microsoft adds one, the playbook could extend its entity-type split with a third loop and send each device through that action.

Until then, I would keep the device branch separate from the SCU-backed entity-analyzer loop. A graph, blast-radius, or device-timeline action could be added as an independent enrichment step, but I would first confirm that the required action is available in the Logic Apps connector or expose it through another approved integration.

> The current connector documentation shows `entityType: "User"` and `entityType: "Url"`; it does not document `entityType: "Device"`. Treat device analysis as a future connector capability or a separate integration, not as a supported input to the current Entity Analyzer action.
{: .prompt-warning}

For a device, I would split the decision into two tracks:

**Blast radius and relationships** — If the question is “what could this device reach?” or “what paths lead from this device to important assets?”, the Sentinel graph tooling and blast-radius style analysis are a natural fit. This is a relationship problem rather than an entity-verdict problem.

**Device activity and timeline** — If the question is “what did this device do around the alert?”, use a bounded KQL query over the available device tables, such as process, network, logon, and alert-evidence data. This produces a deterministic evidence package that can be attached to the incident.

That would give a future version of the playbook a deliberately mixed model:

| Entity | Enrichment path | Result |
| --- | --- | --- |
| User | Sentinel MCP entity analyzer | Verdict, evidence, and recommendations |
| URL | Sentinel MCP entity analyzer | Verdict, prevalence, and supporting context |
| Device | Graph or blast-radius analysis | Relationships and reachable assets |
| Device | KQL timeline query | Processes, connections, logons, and alerts |

I prefer this split to forcing all entities through a generic AI step. The user and URL analyzer is already a productized workflow. For devices, a clear KQL or graph contract makes the output easier to test, compare, and govern.

## 🔐 The SCU boundary

This is the part I would put directly into the design documentation. Microsoft Sentinel MCP is a hosted interface, so there is no MCP server for the Logic App team to deploy and maintain. That does not make every tool in the interface cost-neutral.

Microsoft documents the data exploration MCP interface as having no additional interface charge, while queries that retrieve data from the Sentinel data lake are billed according to the data-lake model. The entity analyzer has a separate cost path: you pay for the KQL work it performs and the SCUs required to produce the reasoned entity-risk analysis. The current [Sentinel billing guidance](https://learn.microsoft.com/en-us/azure/sentinel/billing) is the page I would use for the entitlement and overage details.

From my own runs, I have seen usage around `0.1 SCU` per analyzed entity. I would treat that as an observation, not a pricing formula. The actual consumption can vary with tenant size, the amount and type of data available, and the analysis being performed. It is useful for rough capacity planning, but the tenant's SCU usage is the number to trust.

The look-back window is another cost and scope control. User analysis supports a maximum of seven days, so the template defaults to `lookBackDays: 7` and constrains the parameter accordingly. A longer retrospective should use separate data-lake queries or another investigation workflow rather than passing a larger value to Entity Analyzer.

That means these calls belong in the same cost conversation:

```text
Logic App connector ─────────────┐
GitHub Copilot + Sentinel MCP ───┼─> Entity Analyzer ─> SCU usage
VS Code + Sentinel MCP ──────────┤
Hosted or custom agent ──────────┘
```

The client changes. The analyzer operation does not.

This matters for manual investigation as well. An analyst can run an analysis from GitHub Copilot or VS Code and experience it as “just another MCP tool call”. Operationally, it is still invoking the same Sentinel entity-analysis capability and should be included in usage monitoring, access reviews, and cost controls.

The documentation also distinguishes the role used to run entity analysis from the optional owner role used to view and monitor SCU usage. I would validate the effective permissions in the target tenant rather than assuming that the interactive user's permissions transfer to the managed identity.

## 🧩 What deployment needs to get right

The template is tenant-agnostic, but it is not dependency-free. The workspace must be onboarded both to the Defender portal and to the Microsoft Sentinel data lake, and the Sentinel SOAR Essentials solution must be installed. The Azure Security Insights service account also needs `Microsoft Sentinel Automation Contributor` on the resource group so an automation rule can run the playbook.

The workflow has a system-assigned managed identity. It uses the Sentinel connection to add the incident comment and the `sentinelmcp` connection to call Entity Analyzer. The template sets both connection authentication types to `ManagedServiceIdentity`, and the MCP connection uses the connector's `managedIdentityAuth` parameter set. That connection shape should still be checked in the portal after deployment - the connection status is the useful confirmation.

The permissions are split across two control planes. For Entity Analyzer, the identity needs `Security Reader` for Sentinel data access and `Security Copilot Contributor` because the tool uses the Security Copilot platform for its reasoned analysis. The identity that writes the incident update needs `Microsoft Sentinel Responder` on the workspace. `Security Copilot Contributor` is not an Azure RBAC role or a Microsoft Entra role; Microsoft documents it as a Security Copilot role assigned from the Security Copilot settings under `Role assignment`.

I have not found a supported public API for assigning the Security Copilot role to the Logic App's managed identity. The [Security Copilot authentication guidance](https://learn.microsoft.com/en-us/copilot/security/authentication) documents the portal assignment flow, not an API-based assignment. In practice, I would treat this as a portal configuration step after the Logic App identity exists, then verify that the Entity Analyzer action succeeds. Granting `Security Reader` alone is not enough if the tenant has not also granted the identity access to the Security Copilot platform.

For a quick proof of concept, you can authenticate the connector with your own user account and get the flow working first. That is useful for separating workflow problems from identity-configuration problems. I would switch to the system-assigned managed identity before using the playbook in production, so the workflow has a stable, reviewable identity instead of depending on a person's account, permissions, or lifecycle.

I would deploy the workflow as `Disabled` initially. The first manual run should confirm four things: the trigger paths match the incident payload in the target tenant, `Account` identifiers resolve to an object ID or usable UPN, the managed identity can read the data lake, and the Agent output property is the one selected by `Agent_summary_text`.

There are two Logic Apps details in the template that are easy to lose during later edits:

- `Render_raw_blocks` uses one expression per `Select` item to produce HTML paragraphs. Mixing literal text and interpolation in the scalar map can make the designer try to parse the value as JSON.
- The raw renderer uses `slice()` to cap strings. A guarded `substring()` is unsafe here because Logic Apps evaluates both branches of `if()` and `substring()` can fail at its boundary.

> The current template pins the Entity Analyzer API version to `2025-08-01-preview`, and the `sentinelmcp` connector is not available in Azure Government, Azure China, or DoD regions. Treat both as deployment prerequisites to re-check before promoting the template to a public repository or production tenant.
{: .prompt-warning}

The parameters I would change for a first deployment are intentionally small:

```json
{
  "workspaceId": "00000000-0000-0000-0000-000000000000",
  "entityConcurrency": 1,
  "workflowState": "Disabled",
  "reportIpEntities": true,
  "maxAnalysisCharsPerEntity": 4000
}
```

The workspace value is the Sentinel workspace customer ID, not the full Azure resource ID. I would leave the agent instructions and risk emoji map at their defaults until the first comment has been reviewed.

One failure mode is intentionally biased toward preserving evidence: if the primary incident-comment action fails after its retries, the fallback path can produce a duplicate comment if the service accepted the first request but returned an error. I prefer that trade for an enrichment playbook, but it belongs in the operational notes before someone treats comment count as an idempotency guarantee.

## ⚡ Controlling playbook concurrency

An incident can contain several users and URLs, and several incidents can trigger at the same time. A `For each` loop that launches every analyzer operation concurrently is a quick way to increase latency and run into tenant limits.

Microsoft's Logic Apps guidance recommends enabling concurrency control on the loop and starting with a degree of parallelism of `5`. The service limits documented for the entity analyzer include 200 runs per hour, 500 runs per day, and approximately 15 concurrent runs every five minutes, subject to service capacity. Results are available for one hour.

I would therefore make the following settings explicit in the playbook:

- **Concurrency:** start at `5`, then tune from measured incident volume.
- **Look-back:** keep it within the supported seven-day maximum for user analysis.
- **Retries:** retry result retrieval separately from starting a new analysis.
- **Idempotency:** avoid launching a second analysis for the same entity and incident unless the first result expired or failed.
- **Comments:** label the entity type and analysis timestamp so stale enrichment is visible.

> Do not confuse a failed result retrieval with a failed analysis. `get_entity_analysis` may need to be called again if the analysis is still running, while the result itself expires after one hour.
{: .prompt-tip}

The seven-day limit is especially relevant when an incident playbook is reused for retrospective investigations. A long investigation window may need to be divided into separate queries or handled through another data-exploration workflow.

## 🔍 A useful boundary for agentic use

The same design applies when the MCP client is an agent rather than a Logic App. I would give the agent permission to use the entity analyzer for users and URLs, but keep device enrichment behind named tools or saved queries with a clear scope.

For example, an agent instruction can say:

```text
For each linked user and URL, run the Microsoft Sentinel entity analyzer
within the incident look-back window. For devices, do not call the entity
analyzer. Use the approved device timeline query and the approved graph or
blast-radius operation, then cite which path produced each finding.
```

That instruction does two useful things. It reflects the actual product boundary, and it prevents an agent from repeatedly attempting an unsupported device analysis while the incident is waiting for a result.

The agent can still use the Sentinel MCP data exploration tools to discover tables or run a focused KQL query in a different workflow. I would treat those as investigation tools, not as a substitute for the user/URL entity analyzer and not as an excuse to hide SCU-backed actions inside a broad prompt.

## 📝 Conclusion

The Sentinel MCP entity analyzer is a good SOAR enrichment action for users and URLs. It turns a collection of linked entities into concise, evidence-backed context that can be placed directly into the incident, while avoiding a large hand-built enrichment workflow.

Devices need a separate branch today. That is not a reason to drop the pattern - it is a reason to make the boundary visible and pair the analyzer with graph or KQL-based device investigation.

The cost boundary belongs in that same design. Whether the call originates from a Logic App, GitHub Copilot, VS Code, or an agent, the entity analyzer consumes SCUs. The client is different; the meter is not.
