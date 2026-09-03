---
title: Foundry Hosted Agents - You're Just Shipping an Image
author: pit
date: 2026-09-03
categories: [blogging]
tags: [azure, foundry, ai-agents, hosted-agents, mcp, toolbox, containers, skills, soar, logic-apps]
render_with_liquid: false
---

Hey there 🖖

I was reading through the Foundry hosted agents docs, half-expecting another "new platform, new mental model, go learn fifteen concepts" experience - and then I hit this line: *"You package your agent as a container image and push it to Azure Container Registry."*

That's it. That's the thing. As someone who has spent years thinking in images, registries and rollouts, this clicked instantly. For the deployment model I use today, the runtime is literally a container image. I control the code, framework and dependencies; Foundry handles the session compute, identity, endpoint and observability.

The product has already grown beyond that single deployment path, but the image is still the mental model that makes Hosted Agents feel familiar to me. So let me walk through why, where Toolbox fits, and the versioning trap that cost me an evening.

![Foundry hosted agent deployment flow](/assets/img/posts/foundry-hosted-agents-youre-just-shipping-an-image/foundry-hosted-agents-youre-just-shipping-an-image.svg)

> **Updated 3 September 2026:** Hosted Agents and Toolboxes are now generally available. Container deployment remains, but Python and .NET can also deploy directly from source. Configuration has moved to a unified `azure.yaml`, while Skills, Memory, Tool Search and Routines remain preview. The current runtime does not support traffic splitting between agent versions. See the [GA announcement](https://azure.microsoft.com/en-us/blog/gpt-5-6-now-available-in-microsoft-foundry/) and the [Hosted Agents overview](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents).
{: .prompt-info}

## 📦 What a hosted agent actually is

Prompt agents let Foundry own most of the agent definition. **Hosted agents** are different: they run your code and orchestration inside Microsoft-managed infrastructure. The direct source-deployment path currently targets Python and .NET. With a container, the framework choice is broader: Microsoft lists Agent Framework, LangGraph, Semantic Kernel, the OpenAI Agents SDK, the Anthropic Agent SDK, the GitHub Copilot SDK and custom code. As long as the runtime fulfils the protocol contract, Foundry does not need to own the agent loop.

If you have ever stood up an agent from scratch with an open-source framework, you know where the time disappears. The agent loop itself is rarely the whole job. You still need a server, authentication, persistent state, instrumentation, scaling and a rollback plan. Hosted Agents take a good chunk of that operational pile and leave the part I actually want to own: the agent logic and its boundaries.

Each agent gets a dedicated Microsoft Entra identity and endpoint. Each session runs in its own **microVM** - the VM-isolated sandbox described in the hosted-agent documentation - with a persistent `$HOME` and `/files`. When the session idles, compute is deprovisioned and the filesystem is restored when the session resumes.

That persistence has boundaries worth remembering:

- The idle timeout defaults to 15 minutes and can currently be set from 5 to 60 minutes.
- A session is deleted after 30 days of inactivity.
- Conversations and sessions are different. A session represents compute and filesystem state; conversation history depends on the protocol you use.

The platform also injects the Application Insights connection string. If you use the protocol libraries, OpenTelemetry traces are emitted by default.

> The platform operates the runtime, not your agent architecture. Planning, approvals, recovery logic and domain-specific orchestration are still your responsibility.
{: .prompt-warning}

## 🚀 The container mental model still holds

Here is the part my container-brain likes. Build the agent into an image, push it to ACR and deploy it. The operational shape is familiar:

- **Immutable versions.** A version snapshots the image or source configuration, resources, environment variables and protocols.
- **Per-session scaling.** CPU and memory apply to one session, not the whole agent. Cost therefore grows with active concurrency.
- **Scale to zero.** Compute is released after the idle timeout, while session files are persisted.
- **Stable endpoint.** The agent endpoint routes 100% of traffic to one version. You can follow the latest version or pin a specific one.

That last point matters: **traffic splitting is not currently supported**. Canary or blue-green rollout needs to happen above the agent endpoint, for example through separate agents or an API gateway.

There is a neat twist on the metaphor, though. You ship an ordinary container image, but Foundry does not run sessions as ordinary shared containers. Each session gets its own microVM. You author the workload like a container; underneath, the platform gives every session a much stronger isolation boundary and its own persistent filesystem. That was the detail I did not expect, and it is the part I ended up appreciating most.

If you choose container deployment, the Dockerfile remains ordinary:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 8088
CMD ["python", "main.py"]
```

Foundry expects your application to implement one or more supported invocation protocols. The protocol library can provide the server, health checks and tracing bridge; your image carries the code and exact dependencies.

Billing is based on CPU and memory consumed by active sessions. There is no warm replica count to manage, but remember that compute stays active until the idle timeout expires. For the bursty workloads I keep reaching for - a SOAR playbook that fires a few times a day or a scheduled sweep - that model feels right. I would start with the smallest representative allocation and measure it in Application Insights before sizing up.

> Private ACR support changed after the original draft. Foundry projects created after **25 June 2026** can use a private, network-secured Azure Container Registry. Older projects still require the registry's public endpoint, even when the Foundry environment itself is network-isolated.
{: .prompt-warning}

## 🛠️ Deployment now starts from `azure.yaml`

The current Azure Developer CLI flow uses one `azure.yaml` as the source of truth. It replaces the earlier split between `agent.manifest.yaml` and `agent.yaml` and can describe the project, model deployments, connections, agents, toolboxes, skills and routines.

The hosted-agent service block now looks like this (with the Foundry project declared elsewhere in the same file):

```yaml
name: my-agent-project

services:
  my-agent:
    host: azure.ai.agent
    kind: hosted
    name: my-agent
    project: src/my-agent
    language: docker
    uses:
      - ai-project
    protocols:
      - protocol: responses
        version: 2.0.0
    container:
      resources:
        cpu: "0.5"
        memory: 1Gi
```

The command path stays short:

```bash
azd ext install microsoft.foundry
azd ai agent init -m <sample-azure-yaml-url>
azd provision
azd ai agent run
azd deploy
```

That short path is what really sells the image idea to me. I do not need to hand-crank `docker build`, push tags with `az acr`, wire an endpoint and then invent my own deployment lifecycle around it. `azd deploy` builds or packages the runtime, creates a new immutable agent version and rolls it out.

The `microsoft.foundry` extension meta-package installs the providers needed when the project includes agents plus resources such as toolboxes, skills or routines. For agent-only projects, the underlying provider is `azure.ai.agents`.

There are now three practical delivery paths:

- Build an image from your Dockerfile.
- Deploy a prebuilt image from ACR.
- Upload Python or .NET source as a ZIP and let Foundry perform the remote build.

The source-based Python/.NET path is still on my backlog. For now, shipping a container image is completely fine for me: it gives me the exact runtime control I want and maps cleanly to the delivery practices I already use. The newer source path looks convenient for a quicker inner loop, but I have not kicked its tyres yet. It is an option, not a reason for me to abandon the container model.

There is also a migration boundary now. Agents deployed before April 2026 with the initial-preview hosting packages were not moved automatically, and support for that backend ended on **20 August 2026**. Those deployments need to be rebuilt against the current protocol libraries and redeployed: <https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate-hosted-agent-preview>.

> Current `azure.yaml` reference and deployment modes: <https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/azure-yaml-reference>
{: .prompt-info}

> Full step-by-step walkthrough: [Deploying a Foundry Hosted Agent with azd](/posts/deploying-a-foundry-hosted-agent-with-azd/)
{: .prompt-tip}

## 🧰 Skills can live in two places

This is the bit that made the whole thing feel *not new* at all. When I build an agent locally, I drop file-based skills into the runtime - small folders of instructions and capability the agent can reach for. With a container-backed Hosted Agent, those folders simply travel inside the image beside the code. Build it, push it, ship it.

The container model therefore makes file-based skills straightforward: the exact set travels with that agent version. This is useful when the skills are tightly coupled to the harness or need local files and dependencies.

Foundry has since added **project-scoped Skills in preview**. These are versioned resources that you attach to a toolbox and expose through MCP Resources. That gives you a second design:

- Bake a skill into the image when it belongs to that runtime and must change with the code.
- Publish it as a Foundry Skill when several agents should discover and reuse it independently.

The MCP client or framework must support MCP Resources to discover toolbox-hosted skills. Skills also remain project-scoped; cross-project references are not currently supported.

A project I am a big fan of is [`SCStelz/security-investigator`](https://github.com/SCStelz/security-investigator): modular Agent Skills for Microsoft security investigations wired to Sentinel, Defender and Graph over MCP. Today it fits the interactive editor workflow very well. The idea I keep coming back to is taking that kind of skill library, packaging it with a hosted runtime and putting the same investigation capability behind an endpoint.

With Foundry Skills now available, the interesting design question is no longer simply whether to bake the whole library into an image. Which capabilities belong to this exact runtime, and which should be versioned centrally for several agents? I expect I will end up using both patterns.

Memory is separate again. Foundry Memory remains a preview service for context that should survive beyond one sandbox or conversation. It is a managed memory store, not the same thing as the session filesystem. You are billed for the underlying chat and embedding models, and Memory stores do not currently support VNet integration. That keeps it firmly in the "evaluate before production" bucket for me: <https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/what-is-memory>.

## 🔌 Toolbox separates runtime from tools

A toolbox is a curated collection of tools and skills behind one MCP-compatible endpoint. It centralises authentication, version management, guardrails and observability, while your agent code stays pointed at the same endpoint.

That separation is the part I like most. Skills that belong to the runtime can travel with the image; tools that should evolve independently sit behind Toolbox. The image can remain stable while the tool surface changes. Adding an MCP server or swapping a connection becomes a toolbox release rather than an agent rebuild.

I did not fully appreciate this until I was hands-on. Without Toolbox, changing the available integrations easily turns into rebuild, push and another agent version. With it, I can keep the runtime still and change the tool surface as configuration. That is a small architectural split with a very practical payoff.

There is one security detail the runtime must not delegate away: for MCP tools marked `require_approval: always`, the Toolbox returns approval metadata, but **your agent runtime is responsible for asking the user and enforcing the decision**. The MCP endpoint itself does not block the subsequent tool call.

> Toolbox concepts and current limits: <https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/toolbox-overview>
{: .prompt-info}

## ⚠️ The toolbox version trap

I learned the version behaviour the annoying way. I added a new tool, created another Toolbox version and waited for the agent to use it. Nothing happened. I checked the agent configuration, the connection and the prompt, and the agent kept behaving as if the tool did not exist.

The missing step was promotion. Toolbox versions are immutable. The first version becomes the default; later versions do not become active merely because you created them.

There are two endpoint shapes:

- The unversioned **consumer endpoint** follows `default_version`.
- The version-specific **developer endpoint** addresses one immutable toolbox version.

My new tool was sitting safely in the new version while the consumer endpoint continued serving the old default. The intended release flow is to create a version, test its version-specific endpoint, then promote it when ready. Every agent using the consumer endpoint picks up the promoted default without a redeploy.

My first container-shaped reaction was to treat `default_version` like `:latest` and pin everything. Looking at the current endpoint model, that comparison is too harsh: the default only moves when someone explicitly promotes it. It is closer to a controlled release channel. For centrally managed tools, that behaviour is useful. If an agent must have an immutable tool dependency, give it the version-specific endpoint and accept that changing the Toolbox version now requires configuration rollout on the agent side.

> Added a tool and the agent cannot see it? Check the endpoint first. A new toolbox version changes nothing for consumers until you promote it to `default_version`.
{: .prompt-warning}

## 🔍 Tool search keeps the context lean

A toolbox can grow quickly, and sending every tool schema to the model on every turn costs tokens and makes selection noisier. **Tool search**, currently in preview, replaces the full tool list with two meta-tools:

- `tool_search` discovers tools from a natural-language description.
- `call_tool` invokes a discovered tool.

The current configuration type is `toolbox_search`:

```json
{"type": "toolbox_search"}
```

You can still pin critical tools so they are always visible. Foundry's own guidance suggests considering tool search once a toolbox grows beyond roughly 10-15 tools.

> Tell the model in its instructions to call `tool_search` when the capability it needs is not already visible. Otherwise it may conclude that the tool does not exist.
{: .prompt-tip}

## 🧭 Where I see this fitting

This is where my SOAR and automation hat takes over.

Years ago, when a Logic App needed to do something genuinely complex - a transformation or bit of logic the connectors could not express cleanly - the natural move was to offload that part to an Azure Function. The Logic App stayed the orchestrator; the Function did the heavy lifting.

A Hosted Agent feels like the next rung on that ladder. Now the offloaded part can reason rather than only execute deterministic code. A SOAR playbook can invoke an agent endpoint, pass investigation context and receive a structured result. The same endpoint can be called from an application, pipeline or another agent, subject to its Entra authorisation and network boundary.

Foundry **Routines**, currently in preview, add project-native timer, recurring and limited event triggers. They are intentionally small: one trigger invokes one prompt or hosted agent. If you need branching, multiple actions, human approval or several agents, Microsoft recommends a workflow instead.

What made that pattern concrete for me was seeing how far the low-risk action envelope already goes. With prompt agents and the right MCP tooling, I have used the agent's findings to handle tasks such as:

- Triggering an AV scan on a device that looks suspicious.
- Tagging a device based on the investigation.
- Pushing an indicator to block.
- Writing findings and context back to the incident.

These are not bet-the-farm actions, and that is exactly why they are interesting. They are repetitive tasks where an agent can give the analyst a head start without being handed unlimited authority.

One distinction matters: those hands-on actions were performed with **prompt agents** and MCP tooling, not with my own harness deployed as a Hosted Agent. The endpoint pattern carries across, but the hosted implementation - including the Python/.NET source path - is still on my backlog. I am excited about the runway here, not reporting from the finish line.

For security automation, I would keep the boundary conservative: let the agent gather context, tag devices, add incident comments or propose an indicator action; put high-blast-radius operations behind explicit approval. The runtime gives the agent somewhere secure to execute. It does not decide your authorization model for you.

> Routines are useful for lightweight schedules and triggers, but remain preview: <https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/routines>
{: .prompt-info}

## 📝 Conclusion

Hosted Agents make the operational side of running your own agent pleasantly boring if you already think in containers. Today I am happy shipping an image; the direct Python/.NET source path can wait until I have a reason to trade that control for a simpler build. Either way, Foundry provides a dedicated microVM per session, persistent files, identity, observability, scale-to-zero and a stable endpoint.

The practical boundaries are now clearer than when I started this draft: one agent version receives all endpoint traffic, `azure.yaml` is the deployment source of truth, private ACR support depends on when the project was created, and tool approvals still belong to the harness. Less magic, clearer ownership - that is a trade I am comfortable with.

Same principles I already know, pointed at a new kind of workload. That is why this one clicked.
