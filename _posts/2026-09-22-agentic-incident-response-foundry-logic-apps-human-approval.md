---
title: Agentic Incident Response with Foundry and Logic Apps - Human Approval Without Custom MCP Code
author: pit
date: 2026-09-22
categories: [blogging, tutorial]
tags: [azure, foundry, logic-apps, mcp, sentinel, defender, incident-response, human-in-the-loop, agentic-soc]
render_with_liquid: false
---

If you work with Microsoft Sentinel and Defender, you probably already have response playbooks: Teams cards, approval emails, incident updates. When I started giving a Foundry agent response tools, I wondered why I would build a custom MCP server for each action when Logic Apps could expose the workflows I already use.

The setup itself was super straightforward and much more simpler than you may expect. The use case I see is an **autonomous agent** started by a Foundry routine, an external scheduler, or a SOAR playbook. I attached the Microsoft Sentinel data exploration MCP server and 2 Logic App MCP servers to the same agent. Sentinel handles investigation; Logic Apps handles response and human approval.

![Autonomous Foundry agent connected to Sentinel and two Logic App MCP servers](/assets/img/posts/agentic-incident-response-foundry-logic-apps-human-approval/agentic-incident-response-foundry-logic-apps-linkedin.png)
*The full path: an autonomous agent investigates through Sentinel MCP and calls response workflows through Logic Apps MCP.*

```text
Routine / external trigger / SOAR playbook 
─────────────────┴──► Foundry agent
                        ├──► Sentinel data exploration MCP
                        ├──► sentinelResponse MCP ────────┐
                        └──► defenderDeviceResponse MCP ──┤
                                                          ▼
                                               One Standard Logic App
```

That is still **one Standard Logic App**. It can host multiple workflows as usual, expose them as MCP tools, and group those tools into several MCP servers. In my lab, the incident and device servers share one Logic App resource. Microsoft documents [multiple MCP server groups in one Standard Logic App](https://learn.microsoft.com/en-us/azure/logic-apps/create-model-context-protocol-server-standard).

![Two MCP servers and their workflow tools in one Standard Logic App](/assets/img/posts/agentic-incident-response-foundry-logic-apps-human-approval/logic-app-mcp-servers.png)
*My Standard Logic App hosts both `defenderDeviceResponse` and `sentinelResponse`.*

> Microsoft currently documents the Standard Logic Apps MCP server feature as **preview**. I would recheck the setup requirements before promoting this workflow into a production response path. <https://learn.microsoft.com/en-us/azure/logic-apps/create-model-context-protocol-server-standard>
{: .prompt-info}

## ⏰ How the autonomous agent starts

I prefer to trigger this agent from Sentinel automation or a SOAR playbook, so the incident context is already available when the investigation starts. Foundry also provides native [agent routines](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/routines): a routine has **one trigger and one action**, and Foundry invokes one prompt or hosted agent when that trigger fires. No one needs to open a chat. Whichever entry point I use, I pass enough context into the response path for the approver to make an informed decision: incident severity and link, device name and ID, requested action, rationale, expiry, and a correlation ID. That context needs to be planned in the agent's instructions, tool schemas, and skills.

The portal itself offers 4 trigger choices. Underneath, these are three types: recurring schedule, one-time timer, and external event.

| Portal choice | What it does |
| --- | --- |
| Recurring (`schedule`) | Runs on a five-field cron expression, with a minimum interval of five minutes. Set `time_zone` explicitly, for example `Europe/Berlin`; Foundry accepts IANA or Windows time zones. |
| One-time (`timer`) | Runs once at a future time. The routine guide also describes a duration from now, although its current API examples use an explicit future timestamp. |
| GitHub issue (`github_issue`) | Runs when an issue opens or closes in a watched repository. |
| Teams channel message (`custom` with `teams` provider) | Runs when a new message lands in a watched channel. |

For GitHub and Teams, the path is **source event → connector connection → Foundry routine → agent**. Foundry's [connector namespace](https://learn.microsoft.com/en-us/azure/connector-namespace/connector-namespace-overview) handles authentication and delivery, using a webhook or polling according to the connector. The [routine guide](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/use-routines#event-based-triggers) does not say which one these two triggers use. The `custom` trigger here means the Teams provider; it is not an arbitrary HTTP webhook for SOC events. I would use a SOAR playbook to invoke the agent for those.

## 🧩 Reuse the response layer you already have

In Sentinel automation, human approval often means a Logic App with a Teams adaptive card or approval email. I kept that familiar step. The agent decides *when* to call the workflow; the workflow still decides whether the action runs. So this offloads the approval gate to existing paradigms.

The Sentinel data exploration collection supplies investigation context, including an incident ARM ID or device name. The Logic App MCP servers supply response actions: 

- comment on an incident
- update incident
- isolate a device
- unisolate a device

The Sentinel data exploration MCP is read-only. The response actions have separate permissions and may need explicit human approval.

> The Sentinel data exploration collection is a way to retrieve and analyze data; it does not grant the agent permission to perform response actions. See the [collection's tool list](https://learn.microsoft.com/en-us/azure/sentinel/datalake/sentinel-mcp-graph-tool) and the [Logic Apps MCP guide](https://learn.microsoft.com/en-us/azure/logic-apps/create-model-context-protocol-server-standard).
{: .prompt-info}

There are **two different approvals** here. Foundry can pause before an MCP tool call, but an autonomous run has no analyst in a chat window to answer it. An external process would need to collect that decision and [resume the Foundry response](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol#use-the-mcp-tool-with-the-rest-api).

My agent already has an `allowed_tools` list. For the Logic App MCP tools, I configure Foundry's [`require_approval`](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol#set-up-the-mcp-connection) as a per-tool `{"never": ["tool_name"]}` list so the autonomous run does not pause for Foundry's developer approval. Setting it to `"never"` without a list disables Foundry approval for every tool in that MCP definition; the default is `"always"`. This is not the response approval: Logic Apps still enforces the human decision before an approval-gated action runs.

For an interactive agent, I could put a human approval step in a Foundry workflow. Its visual builder includes a [**Human in the loop** pattern](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/workflow) that asks the user and waits for an answer. Foundry also documents a [long-running hosted-agent HITL pattern in preview](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/add-human-in-the-loop).

> **Foundry workflow change:** After December 1, 2026, the visual designer and in-portal workflow execution will no longer be supported. Workflow patterns, including human-in-the-loop steps, remain available through code and configuration; Foundry can still run YAML-based workflow definitions deployed as hosted agents. For new work, Microsoft recommends [Agent Framework](https://learn.microsoft.com/en-us/agent-framework/workflows/human-in-the-loop). See the [Foundry migration guide](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/workflow#migration-guide) for the supported paths.
{: .prompt-warning}

The [migration guide](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/workflow#migration-guide) recommends **Agent Framework** for code-first or YAML orchestration deployed as a hosted agent. It also points to **Azure Logic Apps** for visual orchestration that can call Foundry agents, and **A2A** for a simple agent-to-agent handoff. Logic Apps fits this SOC flow because the approval and response connectors are already there and we do not have to re-invent the wheel.

My autonomous agent may be started by a routine or SOAR playbook, and **unisolate** is a disruptive action. I want the approval next to the Defender action, inside the Logic App. A prompt can tell the agent to ask first, but the workflow condition is what actually stops an unapproved action. 

> Note: Device isolation should be part of existing automations, and those playbooks usually follow a "fire first, ask later" logic for workstations.
{: .prompt-info}

## 🛠️ Putting it together

I grouped the workflows in that app into two MCP servers: `sentinelResponse` and `defenderDeviceResponse`. In the Azure portal, open the Logic App and go to **Agents > MCP servers**. You can register existing qualifying workflows or choose connector actions and let the portal create a workflow for each tool. For this workflow design, I used Microsoft Sentinel actions such as **Add comment to incident** and **Update incident**, plus Microsoft Defender for Endpoint actions to get a machine and isolate or unisolate it. You can add a **Create incident** tool the same way if your process calls for one. 

Optionally, you can attach the Defender for Endpoint connector as an MCP tool directly from Foundry. Behind the scenes, this still creates a Standard Logic App, but without letting you choose its name, and you still configure the connection, actions and permissions yourself. So I would recommend creating it through the Standard Logic App interface or via IaC instead.

The [Standard Logic Apps MCP guide](https://learn.microsoft.com/en-us/azure/logic-apps/create-model-context-protocol-server-standard) gives you two paths for creating tools and two for authenticating the server:

- **Reuse an existing workflow** that starts with *When an HTTP request is received* and ends with a *Response* action: create an MCP server from existing workflows.
- **Turn connector actions into new workflow tools:** create new workflows while registering the MCP server.
- **Authenticate with Microsoft Entra ID:** configure OAuth with Easy Auth on the Standard Logic App, then set the Foundry MCP connection to use the chosen agent or project identity.
- **Authenticate with an API key:** generate an MCP API key and send it in the `X-API-Key` header.

![Registering a Sentinel response MCP server with connector actions](/assets/img/posts/agentic-incident-response-foundry-logic-apps-human-approval/logic-app-mcp-server-overview-sentinel-responses.png)
*The registration screen lets me select Sentinel connector actions and describe the tools exposed to the agent.*

The basic path is short:

1. Create a **new-model agent** in Microsoft Foundry and attach the Sentinel data exploration MCP collection for investigation. New agents receive their own agent identity and stable endpoint without a separate publish step. For autonomous operation, start it from a Foundry routine or external scheduler, or have a SOAR playbook invoke it.
2. Create a Standard Logic App. Under **Agents > MCP servers**, register the Sentinel and Defender response tools you want the agent to call.
3. For an existing playbook, make it callable with **When an HTTP request is received**, a useful request schema, and a **Response** action. Give the trigger and its inputs clear descriptions; these become the tool contract the agent sees.
4. Secure the MCP server, copy its endpoint from the Logic App, and add it to the Foundry agent as a custom MCP tool.
5. Allow list the MCP tools this agent may call, configure Foundry approval for those tool calls, and give the agent instructions for when a Logic App approval is required and what it must report afterward. Then test each tool with a harmless incident or lab device before trying an end-to-end prompt.

![Foundry agent showing Sentinel exploration and both Logic App MCP tools](/assets/img/posts/agentic-incident-response-foundry-logic-apps-human-approval/foundry-agent-retrieve-logic-app-tools.png)
*The same agent can discover Sentinel data exploration tools and both Logic App response tool groups.*

The MCP endpoints may look like below:

```text
https://sentinel-incident-response-demo.swedencentral-01.azurewebsites.net/api/mcpservers/sentinelResponse/mcp
https://sentinel-incident-response-demo.swedencentral-01.azurewebsites.net/api/mcpservers/defenderDeviceResponse/mcp
```

Copy the actual URL from **MCP servers > Copy URL** in your Logic App and attach it to your Foundry agent as a custom MCP tool. The workflow's own HTTP trigger URL is a different endpoint.

Key-based authentication is fine for a quick lab setup: generate an MCP API key in the Logic App and configure the Foundry connection to send it in the `X-API-Key` header. For this autonomous response agent, I would use **Easy Auth with Microsoft Entra ID** on the Standard Logic App. Then I would choose which Foundry identity the MCP connection uses. There is no interactive caller whose identity needs to pass through.

- **Agent identity** (`agentic-identity`): use it when a particular agent needs its own access to the response MCP server. This is my choice when different autonomous agents should have different permissions and audit identities. The MCP server and its underlying service must support agent identity authentication, and that agent identity needs the required role assignments.
- **Project managed identity** (`project-managed-identity`): use it when all agents in the Foundry project should share the same access to that MCP server, or when the server requires a managed identity rather than an agent identity. The project's managed identity needs the required roles on the MCP server's underlying service.

These are [two distinct Microsoft Entra authentication options in Foundry](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/mcp-authentication#microsoft-entra-authentication). The routine's dispatch identity controls how the routine invokes the agent; the MCP connection's authentication setting controls which identity calls the Logic App tool. Set that connection's audience to the application ID URI accepted by the Logic App's Easy Auth configuration, including the trailing slash shown in the [Logic Apps MCP guide](https://learn.microsoft.com/en-us/azure/logic-apps/create-model-context-protocol-server-standard#set-up-easy-auth-for-your-mcp-server). Authorize whichever identity you chose: add its object ID to Easy Auth's allowed identities if you restrict callers, and grant any app role or underlying service access your MCP server requires.

I keep three identities separate in the design: the Foundry agent identity authenticates to the MCP endpoint, the Logic App's system-assigned managed identity performs the Sentinel and Defender response actions, and the human approver identity supplies the HITL decision. Enable the Logic App identity and configure the Microsoft Sentinel connector to use **Connect with managed identity**, then assign the `Microsoft Sentinel Responder` role on the workspace. For Defender actions, configure the connector or the direct Defender API/Graph call to use that same Logic App identity where the authentication option is supported, and grant only the required Defender application permissions. If a connector cannot use managed identity for a particular operation, use a narrowly scoped API connection or HTTP call and document that exception; do not confuse that connector identity with the Foundry identity calling the MCP server. See Microsoft's [Sentinel playbook authentication guidance](https://learn.microsoft.com/en-us/azure/sentinel/automation/authenticate-playbooks-to-sentinel) and [Logic Apps managed identity guidance](https://learn.microsoft.com/en-us/azure/logic-apps/authenticate-with-managed-identity).

The connection types have not changed with the new agent object model. What changed is how an agent identity is created: a new-model agent gets its own identity immediately, while a legacy agent may still use the shared project identity until you recreate it under the new model. **At the time of writing**, the current MCP authentication page still shows the older before-and-after-publish wording, so use the [migration guidance](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate-agent-applications) to determine which identity your agent actually has.

> **The new agent object model changes this identity story.** A newly created **new-model** agent receives its own Entra agent identity and stable agent endpoint immediately; it does not need to be published first. In the new model, publishing means exposing a selected version through the endpoint or distributing it to Microsoft 365 and Teams. The **project managed identity** remains a shared project identity, but it is now an explicit connection choice rather than the only way to avoid the old unpublished-agent behavior. See Microsoft's [migration guide](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate-agent-applications#before-legacy-model).
{: .prompt-info}

That distinction is exactly what I was missing when I first started working on agentic SOC designs. The new model lets me keep several autonomous agents in one Foundry project and grant each agent identity only the access its Logic App MCP tools require. I no longer need a separate project solely to reduce the blast radius of the old shared unpublished-agent identity.

One date note: Microsoft rolled this out in stages rather than with one clearly named object-model launch. The next-generation Foundry Agent Service reached general availability for the March 2026 release, including the `AIProjectClient.agents.create_version` prompt-agent model and expanded MCP authentication, as described in [Microsoft's March update](https://devblogs.microsoft.com/foundry/whats-new-in-microsoft-foundry-mar-2026/). The new hosted-agent backend followed in the **April 22, 2026** announcement [Introducing the new hosted agents in Foundry Agent Service](https://devblogs.microsoft.com/foundry/introducing-the-new-hosted-agents-in-foundry-agent-service-secure-scalable-compute-built-for-agents/). The migration guidance that names the new agent object model is dated **July 21, 2026**. I would describe this as a staged 2026 transition, rather than claim that one portal release switched every existing agent over.

This applies to **prompt agents as well as hosted agents** when they are created through the new agent object model. The current [agent configuration guidance](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/configure-agent) says every agent has a stable endpoint from creation, and the [prompt-agent quickstart](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/prompt-agent) creates an agent version through the same Agent Service model. Hosted agents have additional runtime and deployment identity details, but the prompt-versus-hosted distinction does not by itself decide whether the agent identity is unique. The key question is whether the agent is new-model or legacy.

That staged rollout is also why the older behavior was easy to encounter. A prompt agent created with the previous portal experience or legacy API could still be a legacy agent using the shared project identity, even after the newer APIs existed. If your testing was around the March 2026 transition, you may have been working across both models without an obvious visual boundary. Check `instance_identity` in the agent object rather than relying on when the project was created.

**Fun fact:** I was confused about this for quite a while. My main workload was around hosted agents, but for quick ad hoc tests I still reached for prompt agents because they were convenient. When I checked my own agents, some of the ones I used most were still backed by the old agent object model, while newer agents already had the new model. At one point I assigned the required permissions to both the per-agent identity and the shared project identity and moved on from the troubleshooting. Not elegant, but it saved me from chasing the wrong identity again. ;-)

There is a transition detail: an agent created under the legacy model still has a `null` instance identity and uses the shared project identity. Microsoft currently says there is no in-place upgrade for that agent; create a new agent from the same definition to receive a unique identity, then reapply the downstream RBAC assignments. The [migration guide](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate-agent-applications) documents the distinction between legacy and new agents. The identity used by those MCP connections is independent of the Logic App identity that performs the response actions.

The portal-created connector workflows already have the HTTP request and response shape. For existing workflows, Microsoft documents the required Request/Response pattern and hosting requirements in the [Standard Logic Apps MCP guide](https://learn.microsoft.com/en-us/azure/logic-apps/create-model-context-protocol-server-standard). The exact tool names and descriptions matter: “update incident” is much more useful to an agent when the input says which incident identifier it expects and what fields it changes.

![Logic App workflow with an HTTP Request trigger and described JSON inputs](/assets/img/posts/agentic-incident-response-foundry-logic-apps-human-approval/logic-app-workflow-with-http-trigger-and-json-schema-to-describe-tools.png)
*The Request schema gives the comment tool an incident ARM ID and message, with descriptions the agent can use.*

With the tools attached, the agent can choose among them based on their descriptions and its instructions. I still verify the selected tool and arguments in the run history; I would not treat tool selection from a prompt as an authorization check.

## ⏳ The approval timeout trap

My first unisolate workflow followed the obvious sequence: HTTP request, approval email, unisolate device, then Response. The responder might take hours, though, and the agent's tool call cannot wait that long.

### The timeouts behind the problem

There is no single timeout for the whole response:

| Layer | Documented limit | Why it matters here |
| --- | --- | --- |
| Foundry MCP tool call | A **non-streaming tool call times out after 100 seconds**. [Foundry MCP limitations](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol#known-limitations) | This is the tighter deadline for the agent waiting on the Logic App MCP tool. |
| Required HTTP Request/Response connection | A **synchronous inbound request to Standard Logic Apps defaults to 225 seconds**. [Logic Apps HTTP request limits](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-limits-and-config#http-request-limits) | This is the deadline for replying to the HTTP caller, not for finishing the workflow. The tighter Foundry MCP deadline still applies to the tool call. |
| Separate Logic App workflow run | A **stateful run defaults to a maximum of 90 days**; a stateless run defaults to **five minutes**. [Logic Apps run duration limits](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-limits-and-config#run-duration-and-history-retention-limits) | After the HTTP reply, the stateful run can continue waiting for approval, subject to this separate run limit and the shorter approval deadline you set. |
| Foundry routine dispatch | The request that invokes the agent has a **30-second timeout per attempt**, with **three total attempts by default**. [Routine retry and timeout defaults](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/use-routines#retry-and-timeout-defaults) | This measures delivery to the agent, not completion of its later MCP call or the approval. Retries are another reason to use a stable `requestId`. |

> **The early reply addresses the MCP/HTTP deadline, not the full Logic App run.** Once the Logic App sends its Response, the tool call ends and the **stateful workflow can continue waiting for approval**. Give that approval its own deadline. [Logic Apps Request/Response behavior](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-http-endpoint#respond-to-requests) · [run-duration limits](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-limits-and-config#run-duration-and-history-retention-limits)
{: .prompt-tip}

I return **pending** well inside the 100-second MCP limit. Foundry documents [background mode for long-running MCP tasks](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol#long-running-operations-preview), but it requires MCP tasks support; I have not verified that capability on a Logic App-generated server.

A [long-running hosted agent](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/long-running-agent-resilience) can continue after its initiating request disconnects when configured for resilient background execution. That does not extend the Logic App's [run duration](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-limits-and-config#run-duration-and-history-retention-limits). I would let a later agent run check the outcome instead of keeping one MCP call open for the whole approval.

In my workflow design, I moved an HTTP **Response** action *before* the approval step. The agent hears that its request was accepted for review, and the workflow continues. An explicit condition must send only **Approve** to the Defender action; a rejection ends without changing the device. Microsoft shows that [condition after an approval email](https://learn.microsoft.com/en-us/azure/logic-apps/tutorial-process-mailing-list-subscriptions-workflow#add-an-action-to-check-approval-response) in its Logic Apps tutorial.

![Unisolate workflow with early response, approval email, and Defender action](/assets/img/posts/agentic-incident-response-foundry-logic-apps-human-approval/logic-app-workflow-unisolate-action-with-HITL.png)
*This screenshot shows the workflow sequence and the input schema. It does not show an approval-result condition; add one before the unisolate action.*

![Early HTTP response telling the agent that unisolate approval is pending](/assets/img/posts/agentic-incident-response-foundry-logic-apps-human-approval/logic-app-workflow-immediate-response-back-to-agent-in-HITL-scenarios.png)
*The first Response returns “awaiting approval” immediately, while the Logic App continues to the human review.*

```text
Foundry agent ──MCP call──► Logic App: defenderDeviceResponse
       ▲                              │
       │                              ▼
       └── "approval pending" ◄── Request → Response action
                                      │
                                      ▼ workflow continues
                              Send approval request
                                      │
                            Approved? ├── No ──► No device action
                                      │
                                     Yes
                                      │
                                      ▼
                              Unisolate device
```

> ⚠️ **“Approval pending” is not “action completed.”** Once the early response has gone back, the agent cannot infer the later approval outcome from that tool call. Check the Logic App run history or use a separate status lookup or notification if you need the agent or analyst to learn the final result. Microsoft says a [Response action can appear before the end of a workflow](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-http-endpoint#respond-to-requests), while its [MCP setup guide](https://learn.microsoft.com/en-us/azure/logic-apps/create-model-context-protocol-server-standard) describes workflows ending with a Response action. I kept the generated trailing Response in my workflow design and verified tool discovery and the early reply; test this behavior in your own environment before depending on it.
{: .prompt-warning}

That placement change let the agent report **approval requested** and finish its turn. I would use the same idea for other actions that wait on a person; an incident comment can return synchronously.

## 🔄 Who needs the final result?

### Let Logic Apps own the follow-up

For this autonomous agent, I would keep the contract small: **the agent requests the gated action, receives “approval requested,” and finishes.** If its next decision does not depend on the result, it need not wake up for the responder's answer. Logic Apps owns the approval, Defender call, and follow-up. I would still use a stable `requestId` so a retry cannot create a second approval.

I would monitor the Standard Logic App with [Azure Monitor workflow metrics](https://learn.microsoft.com/en-us/azure/logic-apps/view-workflow-metrics) and [run history or Application Insights](https://learn.microsoft.com/en-us/azure/logic-apps/enable-enhanced-telemetry-standard-workflows). Alert on failed or timed-out runs and on approvals that exceed the SOC's deadline. The approval branches should record or notify **approved**, **rejected**, and **expired** outcomes so an analyst can see what happened. A run marked `Succeeded` only means its workflow path completed: the rejection branch can succeed too. If I need proof that unisolation finished, the workflow or a checker should inspect the returned [Defender machine action status](https://learn.microsoft.com/en-us/defender-endpoint/api/machineaction), not just the connector call's success.

This is the simplest production contract I see for my use case. The agent starts the process; Logic Apps and SOC monitoring own the result. I would add an agent-facing status tool only when a later decision or report needs that result.

### If the agent needs the outcome

The tradeoff: after an early Response, that agent run cannot see whether the responder approved or whether Defender finished the action. My lab test covered the early reply and the continued approval workflow. I have **not** built the status layer below; this is how I would add it if a later agent run needs the result.

I would create a `ResponseOperations` table in Azure Table Storage and connect it through the [Standard Logic Apps Table connector](https://learn.microsoft.com/en-us/azure/logic-apps/connectors/built-in/reference/azuretables/) using the Logic App's managed identity. Give that identity **Storage Table Data Contributor** on the table or storage account. This identity is separate from the Foundry identity calling the MCP endpoint.

The response tool's Request schema would require a stable `requestId`, the requested `action`, a Defender `machineId`, and an `incidentId`. A SOAR playbook can supply its event ID; a routine needs an ID derived from a durable source event, because a fresh agent run will not remember a generated ID. Describe these inputs in the Request schema so they appear clearly in the [MCP tool contract](https://learn.microsoft.com/en-us/azure/logic-apps/create-model-context-protocol-server-standard#considerations-for-workflows-as-tools).

For a small lab, use `PartitionKey = response` and `RowKey = requestId`. Store `state`, action, target, incident ID, `updatedAt`, and [`workflow().run.name`](https://learn.microsoft.com/en-us/azure/logic-apps/expression-functions-reference#workflow). Before replying, look up that key and create the row as `pending_approval` only if it does not exist. The Table connector's **Fail if entity exists** option helps prevent two calls from creating the same operation. On a retry, return the existing state if the action and target match; reject an ID reused for a different request. Treat storage errors as errors, not as a missing row.

```text
MCP request → check requestId → save pending_approval → Response(requestId, state)
                                                          ↓ workflow continues
                                             approval → Defender action → update state
```

Only send the approval after the status write succeeds. Add a short dispatch deadline and a checker for records stranded at `pending_approval` if the workflow fails after replying. Configure the approval branch to write `rejected` or `approval_timed_out`; on approval, submit the Defender action and save its returned machine action ID with `action_sent`. Use [Scopes and Configure run after](https://learn.microsoft.com/en-us/azure/logic-apps/error-exception-handling) to record `approval_failed` and `action_failed`. Set an actual SOC approval deadline rather than relying on the workflow's maximum run duration.

A scheduled workflow in the **same Standard Logic App** can check rows in `action_sent` with the Defender connector's **Actions - Get single machine action**. [Defender machine actions](https://learn.microsoft.com/en-us/defender-endpoint/api/machineaction) have their own statuses; mark the record `confirmed` only after Defender reports `Succeeded`, or check the resulting device state if that level of proof matters. A successful connector submission alone is not completion.

To let the agent ask, add a read-only `getResponseStatus` workflow to `defenderDeviceResponse`: **Request → Get Entity → Response** for a known `requestId`. For a new routine run that does not know the ID, also expose a bounded query for recent operations. Table Storage [indexes partition and row keys](https://learn.microsoft.com/en-us/azure/storage/tables/table-storage-design-for-query), so a time-filtered list in one large partition needs a better partition or index design at scale. Add this tool to the agent's allow list and tell the routine to report terminal states while describing `pending_approval` as still in progress.

I would still monitor the Logic App run and correlate its run name with the status record. The [Workflow Runs API](https://learn.microsoft.com/en-us/rest/api/appservice/workflow-runs/get?view=rest-appservice-2026-07-15) or run history can reveal a failed or timed-out run whose record is still pending. If the SOC needs an immediate agent follow-up, the workflow can invoke a SOAR playbook when the operation reaches a terminal state. A [Service Bus queue and second workflow](https://learn.microsoft.com/en-us/azure/logic-apps/connectors/built-in/reference/servicebus/) is another option if I need the MCP-facing workflow to end at Response, as the MCP setup guide describes.

## 🔐 Where I would draw the line

Not every action needs the same gate. For an active compromise, isolating a device may be an “act now, review immediately after” decision in your playbook. Unisolate is different: I would normally require approval before reconnecting a device. Incident comments and read actions can usually run without that pause. Those are response-policy choices, not something the agent should invent from the incident narrative.

The tool result should say what happened: an incident update can return success or failure, while an approval-gated action returns **pending approval** with a traceable identifier. On a retry, check whether the workflow already started before sending another approval.

## 🔗 The gap between incident comments and case activity

One thing I noticed in my tests: when the agent used the Microsoft Sentinel connector to **Add comment to incident**, that comment did not appear in the **Activities** timeline of the corresponding Defender case. The tool call succeeded, but the analyst looking at the case would miss that note. I would verify where each comment lands before treating either timeline as the complete response record.

I could not find a native Logic Apps action for adding a comment to a Defender case. Microsoft now documents a [Defender SOC connector (preview)](https://learn.microsoft.com/en-us/connectors/defendersoc/), but it currently lists exactly **two triggers** — one for alerts and one for cases — and **no actions**. So it can start a workflow from a case event, but it cannot add a comment to a case. I am looking forward to either an updated Sentinel connector that handles this case activity or a dedicated Defender case action connector. I would prefer that over maintaining my own API call.

There is an API route if you need the flexibility now: [Microsoft Graph case management can create a comment activity](https://learn.microsoft.com/en-us/graph/api/security-casemanagement-case-post-activities?view=graph-rest-beta) with `POST /beta/security/caseManagement/cases/{caseId}/activities`. That takes a **case ID**, not the Sentinel incident ARM ID used by the connector. It is also a **beta API**, and Microsoft says beta APIs are not supported for production applications. I would treat a Graph-backed Logic App tool as a lab or carefully evaluated option until that support boundary changes.

## 📝 Conclusion

Logic Apps gave my Foundry agent a practical response layer without a pile of custom MCP code. I could reuse the Sentinel and Defender connectors, keep human approval in the workflow, and let an autonomous agent focus on investigation and choosing the right tool. The small but crucial design detail was returning **approval pending** before waiting for a human — and treating the final action result as a separate event.
