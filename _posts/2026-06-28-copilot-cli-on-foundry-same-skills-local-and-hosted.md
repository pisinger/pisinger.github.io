---
title: Copilot CLI on Foundry - Same Skills Local and Hosted
author: pit
date: 2026-06-28
categories: [Blogging]
tags: [azure, foundry, ai-agents, copilot-sdk, copilot-cli, hosted-agents, skills, mcp, toolbox, byok, azd]
render_with_liquid: false
---

Hi there!

I am a big fan of [SCStelz/security-investigator](https://github.com/SCStelz/security-investigator). It combines GitHub Copilot, MCP, reusable KQL, and specialized SOC skills—and shows how much domain knowledge can live in `.github/copilot-instructions.md` and `SKILL.md` instead of application code.

My hosted example derives its skills and instructions from that MIT-licensed project, then narrows the runtime: Sentinel Data Exploration is primary, direct Graph calls are disabled, and missing Triage tools fall back to Data Lake KQL.

I already use those skills heavily in VS Code and, more recently, in the GitHub Copilot app. The next question was how to make the same capability available as a **standalone agent**—with its own identity and endpoint, ready for automation, other applications, or Teams as a new SOC team member.

This operationalizes rather than replaces the interactive experience. Copying skills is not enough: they describe behavior, but provide no production endpoint, identity, isolation, scaling, or observability. The complete agent must become a container image on an agent platform.

This is where [Foundry hosted agents](/posts/foundry-hosted-agents-youre-just-shipping-an-image/) fit. I push the image; Foundry provides deployment, sessions, identity, stable invocation, scale-to-zero, and monitoring. The container only implements the Responses protocol, so its reasoning harness remains my choice.

The [GitHub Copilot SDK](https://github.com/github/copilot-sdk) runs the Copilot loop inside that container, while Foundry supplies hosting, identity, sessions, and the toolbox endpoint. The same `.github` folder is used in both places:

> **What you will get:** the same Copilot skills locally and hosted, a managed Foundry endpoint and identity, an independently versioned toolbox, and a repeatable `.env`-driven deployment.
{: .prompt-info}

```text
Microsoft Foundry managed runtime
├─ stable Responses endpoint
├─ managed identity, sessions, scaling, monitoring
└─ hosted container image
   │
   └─ ResponsesAgentServerHost
      │
      └─ GitHub Copilot SDK harness
         ├─ Azure OpenAI model (BYOK)
         ├─ .github/copilot-instructions.md
         ├─ .github/skills/
         │  ├─ incident-investigation/SKILL.md
         │  ├─ threat-pulse/SKILL.md
         │  └─ ...
         └─ MCP client
            │
            └─ Foundry Toolbox consumer endpoint
               └─ default_version → toolbox version x
                  ├─ Microsoft Learn MCP
                  ├─ Sentinel Data Exploration MCP
                  └─ optional compatible Triage/custom MCP
```

For local iteration, run `copilot` from `agent/`. For hosted execution, build that directory into the image and make it the SDK working directory. There is no second prompt or skill format to keep synchronized.

## 🧩 Bring your own harness

A Foundry hosted container only needs to implement the OpenAI **Responses protocol**. Microsoft Agent Framework is the natural Microsoft-native choice, but Foundry also supports **bring your own harness**: keep the hosting contract and replace the agent loop inside the image.

Since I already use GitHub Copilot locally, the obvious harness is its SDK. `azure-ai-agentserver-responses` owns the HTTP contract—port binding, health checks, request models, and streaming—while the Copilot SDK owns reasoning and tool calling.

The relevant session configuration is small:

```python
async with await client.create_session(
    model=model_deployment,
    provider=azure_openai_provider,
    mcp_servers=toolbox_servers,
    streaming=True,
    enable_skills=True,
    enable_config_discovery=True,
    on_permission_request=PermissionHandler.approve_all,
) as session:
    await session.send(prompt)
```

`enable_skills=True` enables skills, and `enable_config_discovery=True` discovers `.github/skills/` relative to the configured working directory. `.github/copilot-instructions.md` is loaded as additive Copilot instructions, so the CLI's built-in agent behavior remains intact.

The response handler is only an adapter. It forwards Copilot text deltas as Responses `output_text.delta` events and completes the normal `created → in_progress → completed` lifecycle. The business logic remains in the Copilot instructions, skills, model, and tools.

> **Teaser: Microsoft Agent Framework works just as well.** I built a [sibling implementation](https://github.com/pisinger/dev-private-demo/tree/main/foundry/agent-security-investigator-azd-greenfield) with `agent_framework.Agent`, `FoundryChatClient`, `ResponsesHostServer`, and `SkillsProvider`. It keeps the same skills and toolbox but uses the Foundry project endpoint, avoiding the Copilot BYOK account-level role. This article stays with Copilot because local-to-hosted runtime parity is the experiment I wanted to explore.
{: .prompt-info}

## 🧰 Keep the agent stable - change its tools independently

This is the most useful operational detail in the design.

The hosted agent is configured with the **toolbox consumer endpoint**:

```text
https://<account>.services.ai.azure.com/api/projects/<project>/toolboxes/<toolbox>/mcp?api-version=v1
```

Notice that it contains no version. This endpoint always resolves to the toolbox's `default_version`. A version-specific endpoint exists for testing:

```text
https://<account>.services.ai.azure.com/api/projects/<project>/toolboxes/<toolbox>/versions/<version>/mcp?api-version=v1
```

That gives us a clean release flow:

1. Create toolbox version `x` with the new set of attached tools.
2. Test version `x` through its version-specific endpoint.
3. Promote version `x` to the toolbox default.
4. Existing agents immediately consume the new default through the unchanged consumer endpoint.

With the current `azd` Foundry extension, promotion is:

```bash
azd ai toolbox publish <toolbox-name> <version>
```

The underlying operation simply updates `default_version` on the toolbox:

```http
PATCH {project_endpoint}/toolboxes/{toolbox_name}?api-version=v1
Content-Type: application/json

{"default_version":"<version>"}
```

This separates two release cadences. Change Python code or local skills and redeploy the hosted agent. Add, remove, or reconfigure centrally managed tools and publish a new toolbox default—**without rebuilding or redeploying the agent**. Rollback is also just promoting the previous toolbox version again.

> 👉 Point production agents at the versionless endpoint, validate a version-specific endpoint, and only then promote it. The agent deployment remains untouched.
{: .prompt-tip}

Microsoft's [toolbox documentation](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox) covers the consumer and version-specific endpoints, version creation, validation, and promotion.

> The toolbox API is currently preview functionality. MCP requests must include `Foundry-Features: Toolboxes=V1Preview` and use an Entra token for `https://ai.azure.com/.default`.
{: .prompt-warning}

The Copilot SDK registration looks like this:

```python
mcp_servers = {
    "sentinel-tools": {
        "type": "http",
        "url": toolbox_consumer_endpoint,
        "tools": ["*"],
        "headers": {
            "Authorization": f"Bearer {toolbox_token}",
            "Foundry-Features": "Toolboxes=V1Preview",
        },
    }
}
```

> ⚠️ Do not omit `tools`. The server can connect successfully while exposing zero tools to Copilot. Use `["*"]` for everything in the curated toolbox or an explicit allow-list. In my tests, toolbox sources also behaved atomically: one source that failed tool enumeration caused the complete toolbox to surface zero tools. Treat that as an observed preview behavior, not a guaranteed platform contract. When discovery returns nothing, call `tools/list` against the toolbox endpoint before debugging the agent.
{: .prompt-warning}

## 🔐 My intentionally small MCP scope

The original security-investigator project can use a broad set of MCP servers and APIs. For this hosted version, I deliberately reduced the initial data-access surface. It currently relies on the [Microsoft Sentinel Data Exploration MCP collection](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-mcp-overview) and does not make direct Microsoft Graph API calls.

I slightly modified `.github/copilot-instructions.md` for that environment. Every session enumerates the toolbox tools first. Sentinel Data Exploration is the baseline; Defender/Sentinel Triage capabilities are treated as optional. If a skill expects a Triage or Advanced Hunting tool that is not available, the agent must not stop the investigation. It instead translates the investigative question into Data Lake KQL, discovers the relevant table and schema, runs the query through `query_lake`, and reports any remaining telemetry gap as degraded enrichment rather than a failed investigation.

> ⚠️ **Sentinel Triage MCP did not work through Toolbox in my setup.** The collection is available in preview, but I could not get its tools to enumerate reliably, so this example does not depend on it. One practical alternative is your own MCP implementation backed by the Defender and Microsoft Graph APIs. Mirror the official Triage MCP tool names and input contracts—effectively a compatible Triage MCP—and attach that server to the toolbox. This worked in my tests and lets the existing security-investigator skills use richer incident, alert, entity, and Advanced Hunting capabilities without rewriting their tool references.
{: .prompt-warning}

Direct Graph access is also intentionally disabled. Signals that can be obtained from `SigninLogs`, `AuditLogs`, `IdentityInfo`, `DeviceInfo`, `SecurityIncident`, `SecurityAlert`, and other available lake tables are retrieved there instead. This keeps the hosted identity and credential model small and gives the example one well-understood security-data path.

This is a design choice, not a harness limitation. The custom MCP owns API authentication, permissions, and the tool contract, while the hosted agent continues to consume one governed toolbox endpoint.

### 🛠️ One manual toolbox step

On a new environment, `agent/deploy.sh` creates the initial toolbox with the public **Microsoft Learn MCP** connection attached. A toolbox version must contain at least one source, and Learn provides a useful, credential-free placeholder plus documentation grounding.

The script does not currently attach the Sentinel collection automatically. After the first deployment, open the toolbox in the Foundry UI, add **Microsoft Sentinel – Data exploration**, configure access to the intended Sentinel workspace, create the new toolbox version, and promote it to default. The hosted agent already points to the versionless consumer endpoint, so it picks up that default version without an agent redeployment. Microsoft's [Foundry integration guide](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-mcp-use-tool-azure-ai-foundry) documents the current preview UI flow for adding Sentinel MCP collections.

> 👉 Microsoft Learn creates a valid initial toolbox but provides no security data. Attach Sentinel Data Exploration before running the SOC skills.
{: .prompt-tip}

## 🚀 Deploy the example

The [example deployment](https://github.com/pisinger/dev-private-demo/tree/main/foundry/agent-security-investigator-copilot-azd-greenfield) wraps provisioning and deployment in `agent/deploy.sh`. You need Azure CLI, Python 3.10+, and the [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd).

After installing `azd`, clone the repository and work from the example root:

```bash
az login
azd auth login
azd env new <environment-name>
./agent/deploy.sh
```

That is the complete command path. The script installs the `azure.ai.agents` extension if needed, provisions missing infrastructure, builds the image remotely in ACR, deploys the agent, and applies the runtime role assignments.

Configuration lives in `agent/.env`. Do not maintain a parallel collection of `azd env set` commands or shell exports: the script loads this file and synchronizes its values into the selected `azd` environment on every run. A compact starting point is:

```dotenv
AZURE_TENANT_ID=<tenant-id>
AZURE_SUBSCRIPTION_ID=<subscription-id>
AZURE_LOCATION=swedencentral
AZURE_RESOURCE_GROUP=<resource-group>

# Model deployment: adjust these four together when changing model
AZURE_AI_MODEL_DEPLOYMENT_NAME=gpt-5.4-mini
AZURE_AI_MODEL_NAME=gpt-5.4-mini
AZURE_AI_MODEL_FORMAT=OpenAI
AZURE_AI_MODEL_DEPLOYMENT_VERSION=2026-03-17

# Optional model quota/capacity
AZURE_AI_MODEL_DEPLOYMENT_CAPACITY=1000

TOOLBOX_MCP_NAME=<toolbox-name>

AGENT_CPU=2
AGENT_MEMORY=4Gi
```

> ⚠️ These model values are examples from my test environment. Model names, formats, versions, regions, and available capacity change over time and depend on your subscription quota. Confirm the currently available catalog version and quota in your target region before deploying.
{: .prompt-warning}

> 👉 Edit `agent/.env`, select an `azd` environment, and run the script. The file overrides stale shell exports and is synchronized into `azd`.
{: .prompt-tip}

Changing the model is therefore an environment change, not a manual YAML edit. Set these four values together:

| Variable | What it controls in `azure.yaml` |
|---|---|
| `AZURE_AI_MODEL_DEPLOYMENT_NAME` | Deployment alias used by the hosted agent and model calls |
| `AZURE_AI_MODEL_NAME` | Catalog model under `deployments[].model.name` |
| `AZURE_AI_MODEL_FORMAT` | Model provider/format, for example `OpenAI`, `Microsoft`, or `DeepSeek` |
| `AZURE_AI_MODEL_DEPLOYMENT_VERSION` | Exact catalog model version |

`AZURE_AI_MODEL_DEPLOYMENT_CAPACITY` is an optional fifth override for `sku.capacity`. Before provisioning, `deploy.sh` validates these values and rewrites the matching deployment block in `azure.yaml`. If that deployment does not yet exist on the selected Foundry account, provisioning creates it from the updated YAML. Run the regular `./agent/deploy.sh` after changing models; `--no-provision` is only for code-only updates after the required model deployment already exists.

The same precedence applies to other useful settings:

| `.env` setting | What `deploy.sh` does with it |
|---|---|
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`, `AZURE_RESOURCE_GROUP` | Selects and synchronizes the Azure deployment context into the active `azd` environment |
| `AZURE_AI_ACCOUNT_NAME`, `AZURE_AI_PROJECT_NAME` | Selects named resources when reusing an existing Foundry deployment in the target resource group |
| `AZURE_CONTAINER_REGISTRY_NAME` | Reuses or creates that ACR inside the target resource group and wires the project connection/RBAC |
| `TOOLBOX_MCP_NAME` | Selects the toolbox; its consumer endpoint is derived from the resolved project |
| `ENABLE_MONITORING`, `APPLICATIONINSIGHTS_NAME` | Enables/disables monitoring or selects an existing Application Insights component |
| `AGENT_CPU`, `AGENT_MEMORY` | Rewrites the container resources in both `agent/agent.yaml` and `azure.yaml` before deployment |
| `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_VERSION` | Optionally overrides the Copilot BYOK model endpoint/API version; the endpoint is normally derived |
| `COPILOT_WIRE_API`, `COPILOT_LOG_LEVEL` | Controls Copilot SDK transport and logging behavior |

> ℹ️ The script intentionally mutates `azure.yaml` and `agent/agent.yaml` on disk so the files handed to `azd` match `.env`. Seeing those YAML files change after a deployment is expected; `.env` remains the configuration source of truth.
{: .prompt-info}

The **resource group is the deployment source of truth**. The script searches only that group and then follows a simple rule for each dependency: reuse it when it exists there; otherwise create it there. It resolves the Foundry account and project, ACR, Application Insights, model deployment, project endpoint, OpenAI endpoint, toolbox endpoint, and RBAC scopes from that target.

This matters when switching environments. A stale project or toolbox endpoint from another resource group must not silently redirect part of the deployment. The script rejects or replaces those values with endpoints derived from the selected resource group.

If the group already contains one unambiguous Foundry project, it is reused. If no project exists, the regular deployment provisions one. Once infrastructure exists, use the faster code-only path:

```bash
./agent/deploy.sh --no-provision
```

Then verify the result:

```bash
azd ai agent show
azd ai agent invoke "Run a threat pulse for the last 7 days"
azd ai agent monitor
```

## 🔑 Two identity audiences - and one easy-to-miss role

The agent calls two Azure data planes with different tokens:

- The Copilot SDK's Azure OpenAI provider uses `https://cognitiveservices.azure.com/.default`.
- The Foundry toolbox uses `https://ai.azure.com/.default`.

The distinction explains a confusing deployment symptom. Foundry grants the per-agent managed identity access at project scope, which covers the toolbox, but the Copilot SDK's BYOK Azure provider calls the Azure OpenAI account endpoint directly. That identity therefore also needs `Cognitive Services OpenAI User` on the account.

The identity is created during agent deployment, so the role cannot be assigned beforehand. `deploy.sh` resolves the new identity after `azd deploy` and applies the account-scoped role idempotently. A toolbox call working while the model returns `401 Authentication failed with provider` usually means this account-level role or token audience is wrong—not that the toolbox or model deployment is missing.

> ⚠️ A working toolbox does not prove model authentication works. If only the model returns `401`, check `Cognitive Services OpenAI User` on the Azure OpenAI account first.
{: .prompt-warning}

The implementation also starts the Copilot runtime lazily on the first request. The HTTP server binds first, allowing Foundry readiness checks to pass before the SDK and remote services initialize.

## 🕵️ Where this becomes useful in a SOC

Publishing gives the investigator a stable endpoint for interactive and event-driven workflows.

**Alert or incident enrichment from a Logic App.** A Sentinel automation rule can pass an incident and its entities to the agent, then write the evidence summary and next steps back. Keep containment behind explicit policy and human approval.

```text
Sentinel incident
    → automation rule
    → Logic App
    → hosted agent endpoint
    → Toolbox tools
    → incident comment / analyst approval
```

**Direct invocation from existing SOC systems.** A case platform, SOC portal, notebook, or CLI can call the Responses endpoint and use the agent as a backend capability.

**Scheduled hunting and posture reports.** A Logic App, Function timer, or pipeline can run a threat pulse, exposure review, or posture assessment and send the result to Sentinel, a ticket, email, or Teams.

**An agentic investigation stage.** A coordinator can delegate identity investigation, endpoint analysis, or KQL generation to this specialist and combine its result with other agents.

**Teams and Microsoft 365 Copilot.** Publish the agent where analysts collaborate while API callers keep using its stable endpoint. Foundry handles the channel and Azure Bot Service flow; see [publish hosted agents to Teams and Microsoft 365 Copilot](https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot).

> A published agent application receives its own managed identity. Reapply the toolbox and Azure OpenAI role assignments to that identity; permissions from the development/project identity do not automatically transfer.
{: .prompt-warning}

## ✅ The resulting workflow

The split is simple:

- Edit instructions and skills in `.github/`, test them locally with `copilot`, and deploy the same files.
- Let Foundry operate the container, managed identity, sessions, and endpoint.
- Connect the agent once to the toolbox consumer endpoint.
- Evolve tools as immutable toolbox versions, validate a pinned version, and promote it to default without redeploying the agent.
- Treat `agent/.env` as deployment configuration and `AZURE_RESOURCE_GROUP` as the authoritative resource boundary.

That gives me local-to-hosted parity without coupling tool updates to agent releases—the two properties I wanted from the start.
