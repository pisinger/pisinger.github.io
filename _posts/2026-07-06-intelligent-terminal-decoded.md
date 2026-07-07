---
title: "Windows Intelligent Terminal - ACP, Autofix and AI Agent Architecture"
author: pit
date: 2026-07-06
categories: [blogging]
tags: [intelligent-terminal, windows-terminal, ai-agents, acp, github-copilot, com]
render_with_liquid: false
---

Intelligent Terminal ships without an AI model of its own. Rather than reinvent the wheel, it leans on the agent CLI you already run: it is an experimental Windows Terminal fork that acts as a local transport, speaking ACP to whatever agent you have installed (Copilot, Claude, Codex or Gemini) and driving the terminal over a private COM interface. That single "be a transport, not a brain" decision shapes the entire architecture below.

> Imagine a capable mechanic next to your car who, every time a warning appears, still needs you to read the dashboard and describe it - they know exactly what to do, but cannot see the warning light or reach the controls. That is roughly how an AI coding agent and your terminal normally relate: the agent runs commands in its own session but knows little about the terminal in front of you - it cannot see the failed command in another pane, pick up its output or open a tab in your window. You carry the context between the two.
{: .prompt-info}

Microsoft's new **Intelligent Terminal** sets out to remove that gap - an experimental fork of Windows Terminal that gives the mechanic an intercom and a controlled set of switches. What pulled me in wasn't the feature list, though. It was one line in the README: Intelligent Terminal is "a local transport layer" that "does not call any cloud APIs itself". That is an odd thing for an AI product to say out loud, and it turns out to be the single decision the rest of the architecture hangs off.

> Intelligent Terminal is an experimental, separate app that installs next to your existing Windows Terminal and can run side by side - it does not replace it. Source and announcement: <https://github.com/microsoft/intelligent-terminal> and <https://devblogs.microsoft.com/commandline/announcing-intelligent-terminal-version-0-1/>
{: .prompt-info}

A caveat up front: most of the architectural detail comes from reading the source, backed by the app's own diagnostic logs.

> Best entry points if you want to follow along: the shipped-architecture overview in [`AGENTS.md`](https://github.com/microsoft/intelligent-terminal/blob/main/AGENTS.md) and the WTA crate walkthrough in [`tools/wta/OVERVIEW.md`](https://github.com/microsoft/intelligent-terminal/blob/main/tools/wta/OVERVIEW.md), backed by the helper+master spec in [`doc/specs/Multi-window-agent-pane.md`](https://github.com/microsoft/intelligent-terminal/blob/main/doc/specs/Multi-window-agent-pane.md).
{: .prompt-tip}

## 🖥️ What using Intelligent Terminal actually looks like

The first launch is deliberately uneventful. Intelligent Terminal detects supported ACP-compatible agent CLIs such as Copilot, Claude, Codex and Gemini, lets you choose one, and handles sign-in inside the agent pane. GitHub Copilot CLI is the default. From there the workflow is built around a few shortcuts:

| Shortcut | What it does |
|---|---|
| `Ctrl+Shift+.` | Toggle the agent pane for the current tab |
| `Ctrl+Shift+I` | Move focus between the shell and agent pane |
| `Ctrl+Shift+/` | Show active agents and previous sessions |
| `Alt+Shift+/` | Open the command palette directly in prompt mode |
| `Ctrl+Alt+.` | Ask agent to handle autofix |
| `Ctrl+Shift+P` | Report a bug (collect logs) |

> The agent pane is only one entry point. Prefix a prompt with `?` in the Command Palette and Intelligent Terminal injects context from the active pane, then starts the work in a background tab so the shell in front of you stays usable. Agent access stays visible throughout: Intelligent Terminal asks before an agent runs a command in your shell, and error detection and automatic suggestions can be controlled separately - a better boundary than treating every detected failure as permission to start changing things.
{: .prompt-tip}

The current preview installs next to Windows Terminal and requires Windows 10 2004 or later. The shortest path is WinGet:

```powershell
winget install --id Microsoft.IntelligentTerminal -e
```

## 🔗 ACP: the common language between clients and agents

The **Agent Client Protocol** (ACP) did not originate with Intelligent Terminal. Zed introduced it in August 2025 while working with Google to bring Gemini CLI into the Zed editor. The problem was straightforward: every editor was building one-off integrations for every coding agent, while every agent needed different code for every editor. ACP puts a common contract between the two sides. If Intelligent Terminal is the intercom, ACP is the language spoken over it - the terminal only needs a common way to start a session, send a request, receive progress and ask for permission. It is often described as the agent equivalent of the Language Server Protocol: an agent implements one protocol and works with multiple clients; a client implements it once and offers several agents.

For a local agent, the client launches it as a subprocess and exchanges JSON-RPC messages over standard input and output. A session roughly follows this lifecycle:

| ACP operation | Purpose |
|---|---|
| `initialize` | Negotiate the protocol version and supported capabilities |
| `session/new` | Create a conversation with its working directory and available services |
| `session/prompt` | Send the user's request and context to the agent |
| `session/update` | Stream text, plans and tool activity back to the client |
| `session/request_permission` | Ask the client to approve an action |

ACP also defines client-side capabilities an agent can call back into, such as terminal creation and file operations, reusing MCP's JSON representations where that makes sense. But the two solve different problems. **MCP connects a model or agent to tools and data; ACP connects an agent to the application hosting its user interface.** An ACP agent can still use MCP servers behind the scenes. This is why ACP fits Intelligent Terminal: Microsoft embeds no Copilot-specific logic into Windows Terminal, and another agent needs no custom terminal plugin. WTA is the ACP client, the selected CLI the ACP agent, and both evolve independently.

- client = the app hosting the UI → that's WTA
- agent = the coding agent being driven → that's the selected CLI

> Zed launched ACP with Gemini CLI in August 2025, and JetBrains joined its development in October 2025. The protocol and schema are open source under Apache 2.0: <https://zed.dev/blog/bring-your-own-agent-to-zed> and <https://agentclientprotocol.com/get-started/introduction>
{: .prompt-info}

## 🧭 The one idea that shapes everything: it is a transport, not a brain

The temptation is to assume Microsoft built an AI model or dedicated agent into the terminal. They did not. Intelligent Terminal ships **no model, no cloud endpoint and no inference of its own** - it speaks to whatever agent CLI you have installed (Copilot by default, or Claude, Gemini, Codex, or any custom command) over the [Agent Client Protocol](https://agentclientprotocol.com/), a JSON-RPC dialect these CLIs already understand. Because the terminal is just a transport, it needs exactly two things:

1. A way to **talk to the agent** - send your prompt and shell context, stream the answer back. This is ACP.
2. A way to **let the agent drive the terminal** - open tabs, split panes, run commands, read scrollback. This is a private COM interface.

Almost every design choice in the repo follows from keeping those two channels clean and separate. The mental model to hold for the rest of this post:

```text
   You  ──prompt──►  Intelligent Terminal  ──ACP──►  Agent CLI (the "brain")
                            ▲                              │
                            │                              │ wants to run a command,
                            │                              │ read a pane, open a tab
                            │                              ▼
                            └──────  COM control  ◄──  wtcli / wta
```

The agent is a separate process the terminal launches and pipes to. Your prompt and recent shell output pass through the terminal in memory; where that content actually *goes* depends on which CLI you picked - Copilot to GitHub, Claude to Anthropic, a custom agent wherever its vendor decides. That does not mean the app writes nothing locally: diagnostic logs may be written, and normal telemetry can be emitted unless disabled. The narrower, more useful claim is that Intelligent Terminal itself does not call the model's cloud API or persist the conversation as its own history.

| Component | What it owns | What it does not own |
|---|---|---|
| Intelligent Terminal | ✅ Windows, tabs, panes, scrollback and terminal events | ⛔ Model inference |
| WTA | ✅ Agent sessions, routing and the chat UI | ⛔ The agent model or shell itself |
| Agent CLI | ✅ Reasoning, responses and tool decisions | ⛔ Windows Terminal's UI |
| `wtcli` | ✅ Commands for reading and controlling terminal panes | ⛔ The conversation with the agent |

## 🧩 WTA: the Rust bridge doing the real work

The C++ Windows Terminal codebase barely knows what an agent is. Nearly all the agent logic lives in a companion Rust binary called **WTA** (Windows Terminal Agent), under `tools/wta/`. WTA speaks ACP to the agent CLI and translates between the agent's intentions and the terminal's capabilities. It never runs as a single tidy process - it runs as a **helper + master** pair, and that split is the key to the whole system.

```text
  WindowsTerminal.exe  (one process, N windows/tabs)
        │
        │ spawns once (SharedWta)         spawns one per agent pane
        ▼                                 ▼
  ┌──────────────┐   named pipe    ┌──────────────────┐
  │  wta-master  │◄──ACP/JSON-RPC─►│   wta-helper     │  (one per pane)
  │ (singleton)  │                 │  ratatui chat UI │
  └──────┬───────┘                 └────────┬─────────┘
         │ ACP over stdio                   │ create_terminal /
         ▼                                  │ permission prompts
   Agent CLI                                ▼
 (copilot / claude /                   wtcli.exe ──► COM ──► Windows Terminal
  gemini / codex)                      (drive tabs, panes, input)
```

- **`wta-master`** is a singleton, spawned once per terminal process. It is headless. Its only job is to own the single connection to the agent CLI subprocess and multiplex it, so the agent CLI is spawned exactly once no matter how many panes you open.
- **`wta-helper`** is spawned once per agent pane. It renders the chat interface (a `ratatui` TUI running inside the pane) and connects back to master over a named pipe. From the helper's point of view, master *is* the agent.

So ACP is actually spoken over **two hops**: helper to master over a named pipe, then master to the agent CLI over stdio. Master plays "client" to the real CLI and "agent" to each helper, forwarding requests down and fanning notifications back up to whichever helper owns each session - the reason one Copilot process can serve five panes at once. The multiplexer lives in [`master/mod.rs`](https://github.com/microsoft/intelligent-terminal/blob/main/tools/wta/src/master/mod.rs), the per-pane helper in [`helper/mod.rs`](https://github.com/microsoft/intelligent-terminal/blob/main/tools/wta/src/helper/mod.rs), and the C++ singleton that spawns master in [`SharedWta.cpp`](https://github.com/microsoft/intelligent-terminal/blob/main/src/cascadia/TerminalApp/SharedWta.cpp). The expensive part is shared; the TUI bound to each tab is not. You can trace a single prompt across both hops in `wta-main_master.log`, and the docs put the debugging rule plainly - "if any step is missing, the failure is at the previous step" - so a hung prompt has a ladder you climb down rather than a black box you restart.

> There is no standalone mode and, notably, **no MCP server**. Earlier iterations had a single-process TUI and a `wta mcp` mode; both were removed. The agent reaches the terminal by shelling out to `wtcli`, not through MCP. Bare `wta` with neither `--master` nor `--connect-master` just exits with an error.
{: .prompt-tip}

## 🔌 Two protocols, cleanly split

The two channels map onto two completely different transports that never blur together. **Agent side - ACP over JSON-RPC:** prompts, streamed responses and session lifecycle are all ACP (`agent-client-protocol`), the standard these CLIs already implement - so Intelligent Terminal gets Copilot, Claude, Gemini and Codex support essentially for free rather than inventing its own protocol. ACP stops at the agent conversation, though: it does not know how Windows Terminal represents a window, identifies a pane or stores scrollback. That needs a Windows-side control channel.

## 🪟 Why COM is used for terminal control

COM - the **Component Object Model** - is Windows' long-established mechanism for one process to call a structured interface implemented by another. It may look old-school, but still widely used. Here both processes remain local: `wtcli.exe` is the caller and the running `WindowsTerminal.exe` is the server - local inter-process communication, not a network service and not a cloud API.

Think of a bank teller. You never walk into the vault and count the cash yourself - you slide a slip across the counter ("balance of account 3", "move money out of account 5", "open a new account"), and the teller acts against the ledger the bank already owns. You only get served if your ID checks out. COM is the teller window, `IProtocolServer` is the fixed set of slips it will accept, and the running `WindowsTerminal.exe` is the bank that actually holds the accounts. That fits a terminal well:

The design point is ownership. Scrollback, pane layout, focus and shell metadata already live inside Windows Terminal. Exposing operations from that process is cleaner than letting WTA inspect Terminal's memory, scrape pixels or maintain a second copy of the same state.

> Microsoft's current COM documentation describes the same client/server, cross-process component model used here: <https://learn.microsoft.com/en-us/windows/win32/com/the-component-object-model>
{: .prompt-info}

**Terminal side - classic local COM.** When the agent wants to *do* something, it goes through `IProtocolServer`, implemented by `WindowsTerminal.exe` itself, defined in [`TerminalProtocol.idl`](https://github.com/microsoft/intelligent-terminal/blob/main/src/cascadia/TerminalProtocol/TerminalProtocol.idl) and served from [`TerminalProtocolComServer.cpp`](https://github.com/microsoft/intelligent-terminal/blob/main/src/cascadia/WindowsTerminal/TerminalProtocolComServer.cpp). The IDL is compact - a handful of queries and mutations:

```text
// Queries
GetActivePane()          ListWindows()         ListTabs(windowId)
ListPanes(win, tab)      ReadPaneOutput(...)   GetProcessStatus(sessionId)

// Mutations
CreateTab(...)           SplitPane(...)        ClosePane(sessionId)
SendInput(sessionId, text)                     FocusPane(sessionId)

// Events (push-based via callback)
Subscribe(callback)      Unsubscribe()         SendEvent(eventJson)
```

What comes back is deliberately rich. The `PaneInfo` struct is worth reading - note the last two fields:

```text
struct PaneInfo {
    Guid    SessionId;      // panes are addressed by an opaque GUID
    UInt32  TabId;
    ...
    Boolean IsAgentPane;
    String  Cwd;            // working dir, from OSC 9;9 shell integration
    String  Shell;          // "pwsh", "bash", "wsl:Ubuntu", … (OSC 9001;ShellType)
    String  ShellVersion;
};
```

So the agent gets not just the pane but its working directory and shell identity, harvested from shell-integration escape sequences. Hold onto that `Shell` field - it's why the WSL story works out cleanly later.

How a caller *finds* the running terminal is neat: there is no hardcoded CLSID. At startup Windows Terminal registers its COM server and drops the class ID into an environment variable, `WT_COM_CLSID`. Because every process launched inside a terminal pane inherits that environment, any child - a shell, a script, the agent CLI, `wta`, `wtcli` - just sees it and calls `CoCreateInstance(CLSCTX_LOCAL_SERVER)` to reach the terminal that launched it. The environment variable *is* the discovery mechanism.

WTA could call COM itself, but wrapping it in `wtcli` keeps the Rust agent layer independent from the Windows COM ABI and proxy implementation, and leaves a command-line control surface for other agents and scripts. In the source, WTA's Rust [`CliChannel`](https://github.com/microsoft/intelligent-terminal/blob/main/tools/wta/src/shell/wt_channel/cli_channel.rs) launches `wtcli.exe`; `wtcli` is the COM client, while [`TerminalProtocolComServer.cpp`](https://github.com/microsoft/intelligent-terminal/blob/main/src/cascadia/WindowsTerminal/TerminalProtocolComServer.cpp) registers the classic local server. So **WTA uses COM indirectly through `wtcli`**, not directly.

## 🔀 Could this have used something other than COM?

Yes. COM is not the only IPC option on Windows - and there is no single modern replacement that fits every application.

| Alternative | Where it would fit | What Intelligent Terminal would need to add |
|---|---|---|
| Named pipe | Fast local client/server communication | Its own request schema, versioning, discovery and event contract |
| Unix domain socket | Cross-platform local IPC | Windows application activation and package-aware access control |
| JSON-RPC over stdio | A parent process talking to a child | A managed process relationship with Terminal as the parent or child |
| HTTP, WebSocket or gRPC | Local and potentially remote APIs | Endpoint management, authentication and additional network surface |
| Shared memory | Very high-volume data exchange | Synchronisation, signalling and a separate control protocol |

A named pipe would be the most obvious local alternative - and Intelligent Terminal already uses one between each `wta-helper` and `wta-master`, carrying ACP/JSON-RPC between processes whose lifetime WTA controls. The Terminal boundary is different: WTA must discover and call into an independently running packaged Windows application that already owns the windows, panes, scrollback and UI thread. The team could have designed another JSON protocol over another pipe, with its own ACLs, activation, version negotiation, callbacks and object identifiers - but COM already provides the Windows-specific component boundary and proxy/stub machinery, and the IDL gives both sides an explicit contract. It is not automatically better than a pipe; it simply avoids rebuilding the local Windows integration around one. Each transport is used at the boundary it matches: COM would be a poor fit for the cross-platform agent protocol, just as ACP would add unnecessary machinery to every low-level Terminal method.

## 🕹️ wtcli: a tmux-style control surface for agents

One distinction worth fixing in your head before the commands: `wta` and `wtcli` are two different things, easy to conflate because they ship together. Think of it as:

- **`wta`** - the brain-facing side (ACP, the agent, the chat UI)
- **`wtcli`** - the terminal-facing side (COM, driving panes)

`wta` is the long-lived bridge; `wtcli` is the short-lived command you can actually type. The agent doesn't call COM directly - it shells out to **`wtcli`** (source: [`src/tools/wtcli/main.cpp`](https://github.com/microsoft/intelligent-terminal/blob/main/src/tools/wtcli/main.cpp), full reference in [`doc/wtcli-commands.md`](https://github.com/microsoft/intelligent-terminal/blob/main/doc/wtcli-commands.md)), which wraps `IProtocolServer` in a command surface that looks a lot like `tmux`:

```bash
wtcli --json list-panes                      # what panes exist
wtcli --json capture-pane                    # read a pane's scrollback
wtcli --json capture-pane --last-prompt      # read a pane's last command output
wtcli --json new-tab -c "pwsh" -n "build"    # open a tab
wtcli split-pane -t 3 -d right -s 0.4 -c "tail -f log"
wtcli send-keys -t 3 "cargo test"            # type into a pane
wtcli listen --event "agent.*"               # stream events
```

There is a real design decision in `capture-pane`. Its `--last-prompt` flag returns only the most recent completed command's output, not a blind line-count grab of scrollback. That works because Windows Terminal understands **OSC 133 shell-integration marks** - the invisible escape sequences a configured shell emits to say "a prompt starts here, a command starts here, it exited with code N here". With those marks the terminal knows exactly where one command's output begins and ends, so the agent gets *this command failed* rather than *here are the last 50 lines, good luck*. When marks aren't available it falls back to a line-count read and flags it (`HasMarks: false`), so the agent can judge how trustworthy its context is. That OSC 133 dependency turns out to be load-bearing for the headline feature.

> **OSC 133 in one breath.** `OSC` (Operating System Command) is a class of invisible terminal escape sequence. A shell with integration enabled wraps every command in four `133` marks: `A` (prompt starts), `B` (command input starts), `C` (output starts) and `D;<exit_code>` (command finished, with its exit code). That last one is the important bit here - `OSC 133;D;1` is literally how the shell announces "I failed with code 1," which is what powers both `--last-prompt` capture and autofix. No marks, no signal.
{: .prompt-info}

## 📤 How terminal output reaches the agent

This is easiest to explain with the WSL case I care about most. I'm in an Ubuntu pane and `sudo apt upgrade` fails with `E: Could not get lock /var/lib/dpkg/lock-frontend`. I open the agent pane and ask "What does this error mean?" - without pasting either the command or its output.

The path is short. Windows Terminal is already rendering that text and keeping it in the pane scrollback. WTA resolves the active pane and its `SessionId`, calls `wtcli capture-pane` (→ COM `ReadPaneOutput`), and OSC 133 marks isolate the latest command and its output. WTA combines my question with that context and sends it as `session/prompt` over the existing ACP session; master forwards it over stdio to the selected CLI, which reasons over both pieces.

The important WSL detail: `apt` runs inside Linux, but its visible output already flows through the conpty hosted by Windows Terminal. WTA does not enter the distribution, scrape a Linux log or ask `apt` to repeat itself - it reads the same terminal buffer I am looking at. With OSC 133 marks present, `ReadPaneOutput` returns the latest completed prompt as one unit - command, output and completion boundary - keeping an older `git status` result from joining the question; without them, `capture-pane` falls back to a bounded slice of recent scrollback. Either way the terminal performs the capture, but the agent vendor controls the next hop.

Rather than take that on trust from the source, I asked the running agent to check my homework - *"explain this and tell me how you fetched the terminal output"* - after leaving an `ipconfig` result on screen. It was blunt about the direction of travel: it hadn't fetched anything.

> I **didn't fetch it.** The Windows Terminal Agent runtime **injected it** directly into my context as part of the Terminal Context JSON. [...] WTA pushes this JSON to me at startup, not the other way around. I read it from my runtime context, never by running commands myself.

It even enumerated the shape of that context object - `activeTarget` (the active pane's ID), `cwd` (`C:\temp`), `shell` (`pwsh.exe`), `buffer` (the last N lines of pane output), plus `window_title` and `locale`. That maps cleanly onto the path above and settles a subtlety worth stating plainly: the *terminal* does the capturing through COM, then hands the agent a finished JSON blob. The agent is a passive recipient - it never re-runs `ipconfig` or scrapes the screen to reconstruct what I saw; the `buffer` is already sitting in its prompt the moment the conversation opens (the same `buffer` field the local-files section below turns on). It is a tidy confirmation of the "transport, not a brain" split seen from the inside: the model does the reasoning, the terminal does the seeing.

There's a second confirmation sitting on disk, from the other end of the pipe. WTA's prompt templates live under `%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalState\IntelligentTerminal\prompts\`, and the agent-pane one (`terminal-agent.md`) spells out exactly what gets spliced in and where. It ends with a literal `<!-- WTA_RUNTIME_CONTEXT -->` marker and documents the injected block as *"terminal context JSON (fields: `activeTarget`, `window_title`, `cwd`, `shell`, `locale`, `buffer`)"* - the same six fields the running agent reported back to me, now seen from the template that assembles them rather than the model that receives them. The prompt even instructs the model to trust them over its own guesses: *"The runtime sections below are authoritative for the current pane, supported agents, and terminal state. Use them. Do not guess."*

That folder also settles why autofix and the agent pane feel so different: they are **two separate prompts**. `auto-fix.md` is tightly constrained - it must return exactly one JSON object, either a `fix` (a single-line shell command you apply with one keystroke) or an `explain` - which is why an autofix arrives as a terse card and never a conversation. `terminal-agent.md` is a full mode-router that lets the pane agent chat, recommend a command into your shell, run its own tools, or delegate the job to a new tab. Same injected context, two very different jobs: one resolves a failure in a keystroke, the other holds a conversation.

```shell
Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a---          21/06/2026    11:00           2880 auto-fix.default.md
-a---          21/06/2026    11:00           2880 auto-fix.md
-a---          21/06/2026    10:55          11541 terminal-agent.default.md
-a---          07/07/2026    10:15          11541 terminal-agent.md
```

> Treat terminal context as data disclosure. A pane may contain tokens, connection strings, customer names or command output you did not intend to share. The destination and retention terms follow the selected agent CLI, not Intelligent Terminal itself.
{: .prompt-warning}

## 📚 When shell history and other local files are used

Terminal scrollback and shell history sound similar, but they are separate sources. Scrollback is the in-memory text Windows Terminal owns. PSReadLine history, Bash's `~/.bash_history` and Zsh's `~/.zsh_history` are files the shell maintains so you can recall commands across sessions.

I checked the WTA source for those history paths. Intelligent Terminal does **not** automatically read PSReadLine's history file, `.bash_history` or `.zsh_history` when it builds context for a normal prompt. The runtime context is the active pane, current directory, shell identity and a bounded `buffer` captured from Terminal. That distinction matters: a shell-history file contains previous command *lines*, but not the output needed to explain why the latest `apt upgrade` failed.

| Local data | Used automatically? | Purpose |
|---|---:|---|
| Terminal scrollback | Yes | Current command and output supplied as prompt context |
| OSC 133 marks | Yes, when shell integration is enabled | Identify command boundaries and exit status |
| PSReadLine history | No | PowerShell's own cross-session command recall |
| `~/.bash_history` / `~/.zsh_history` | No | Shell-managed command recall inside Windows or WSL |
| PowerShell profile / `~/.bashrc` | Yes, for setup | Sources the Intelligent Terminal shell-integration script |
| Agent CLI session files | Yes, for session management | Discover, label and resume previous agent conversations |

There is one place Intelligent Terminal deliberately touches local shell configuration: to make autofix reliable, setup drops a small shell-integration script beside your profile and adds a single line to source it. On Windows PowerShell that's:

```text
Documents\PowerShell\Microsoft.PowerShell_profile.ps1   # sources the script below
Documents\PowerShell\shell-integration_v1.ps1           # emits the marks
```

For Linux shells inside WSL, the same pair lives inside the distro:

```text
~/.bashrc                                        # sources the script below
~/.intelligent-terminal/shell-integration_v1.sh  # emits the marks
```

Those scripts emit OSC 133 prompt/command/completion marks plus working-directory metadata; they do not upload the profile or copy history into the prompt. The other local files WTA reads belong to the **agent CLIs**, not the shell - populating the session view and resuming conversations:

```text
~/.copilot/session-state/...
~/.claude/projects/...
~/.codex/sessions/...
~/.gemini/tmp/.../chats/...
```

## 🔧 Autofix: how a failed command reaches the agent by itself

The feature people will notice first is autofix - a command fails, an indicator lights up, and the agent already has the error loaded and a fix ready. The mechanism is a tidy event pipeline riding on those same shell-integration marks. The shell emits `OSC 133;D;<exit_code>` when a command finishes; `TerminalPage` raises `ProtocolVtSequenceReceived`; the COM server forwards it to subscribers; `wta` (subscribed via `wtcli listen --json`) classifies it; and a non-zero exit calls `maybe_trigger_autofix()`, handing the agent the error as context.

Two things are worth pausing on. First, the trigger is genuinely just the exit code arriving as a VT sequence. The shell announces "I finished, exit code 1" through OSC 133, the terminal turns it into an event, and WTA - already subscribed via `wtcli listen` - classifies it and decides whether it's worth bothering the agent. No polling, no screen-scraping for the word "error".

Second, and cleverer: **autofix works on a pane you have never opened**. Every time you create a new tab, Intelligent Terminal quietly spawns a *stashed* agent pane in the background - the helper starts, connects to master and establishes its ACP session, all while hidden. So when a command fails in a tab whose agent pane you never touched, the helper is already connected and can act immediately.

> Autofix needs three things lined up: PowerShell shell integration so OSC 133 marks are emitted, a helper whose ACP session has reached `Connected`, and `wtcli` on `PATH`. Miss the shell integration and the whole pipeline is silent, because the exit code never becomes an event in the first place.
{: .prompt-warning}

## 🐧 Why this all works for WSL too

If you live in WSL like I do, the obvious question is whether any of this cares that half your work happens inside a Linux distro. Mostly it doesn't. The agent drives your terminal through `wtcli` and `IProtocolServer`, addressing every pane by an opaque `SessionId` GUID - nothing in that path knows what shell runs inside. The `PaneInfo` even carries a `Shell` field (`pwsh`, `bash`, `wsl:Ubuntu`), so the agent can *see* it's WSL, but `capture-pane`, `send-keys` and `split-pane` behave identically either way. The agent pane is the same in reverse: the CLI runs on the Windows host, but its working directory can point into the distro over `\\wsl$\...`, and the code already tolerates those UNC paths - so "open Copilot against my WSL project" works with the host CLI and a Linux `cwd`, no agent install inside the distro required.

> The reverse - running the agent CLI *itself* inside the distro by pointing Intelligent Terminal at an agent such as `wsl -d Ubuntu -- codex --acp --stdio` - looks plausible on paper: the terminal-control channel stays host-side in WTA, so the agent only has to speak ACP over stdio, which `wsl.exe` bridges. I have **not tested this**, and there are open questions (Windows→Linux `cwd` translation, the exact per-CLI ACP invocation, and no in-distro hooks for live session status). Treat it as a maybe, not a supported path.
{: .prompt-warning}

## 🔍 Troubleshooting the mechanics with local logs

When you need to see *why* something misbehaved - a hung prompt, a dropped autofix, a helper that never connected - the built-in logs are the place to look. They show the logical protocols flowing through the system: ACP request/response, terminal-control commands, session routing and package-identity failures. Production builds keep them under the package's local cache:

```text
%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Local\IntelligentTerminal\logs\<version>\
```

| Log | What it helps with |
|---|---|
| `wta-main_master.log` | Agent CLI startup, helper connections and session routing |
| `wta-main_helper-<pid>.log` | ACP initialisation, prompts, responses and pane lifecycle |
| `wta-acp-debug.log` | Low-level ACP JSON-RPC traffic |
| `wta-cli.log` | `capture-pane`, `list-panes` and other terminal-control commands |
| `wta-ensure-host.log` | WTA lifecycle, autofix events and package-identity failures |
| `terminal-agent-pane.log` | The C++ Terminal side of the agent pane |
| `hook-trace.log` | Events emitted by the agent hooks |

The cleanest collection path is `Ctrl+Shift+P` → **Report a bug (collect logs)**, which builds a ZIP and opens its location. For a detailed repro, `WTA_LOG=debug` or `WTA_LOG=trace` raises Rust-side logging after a full restart. As with the master log, one prompt can be followed across layers, and a missing step points at the previous boundary.

> Diagnostic bundles and trace logs may contain prompts, terminal output, paths and agent details. Review and redact them before attaching them to a public GitHub issue.
{: .prompt-warning}

## 🔭 What the architecture tells you about where this is going

Step back and the shape is clear. Intelligent Terminal is not trying to be an AI; it is the **substrate** connecting the terminal you already use to the agent you already pay for - two clean protocols (ACP facing the agent, COM facing the terminal) and a Rust bridge multiplexing between them. A few things follow:

- **The agent stays swappable.** Because the contract is ACP, not a Microsoft-specific SDK, any conforming CLI plugs in - including local or custom ones via `custom:<cmd>`. That's a deliberately open door, the opposite of a walled garden.
- **`wtcli` is a public surface, not just an internal one.** Several of its commands (`send-event`, `set-env`, `wait-for`) aren't called anywhere inside the repo - they exist as a documented control surface for external agents and scripts. The terminal is being positioned as something *other* tools automate, not just something Copilot talks to.
- **Data routing follows the selected agent.** Intelligent Terminal does not call the model API itself or keep its own conversation history; the selected CLI receives the prompt and shell context under that vendor's terms, while diagnostic logs and product telemetry remain separate considerations.

> The load-bearing sources behind this walkthrough are the overviews in [`AGENTS.md`](https://github.com/microsoft/intelligent-terminal/blob/main/AGENTS.md) and [`tools/wta/OVERVIEW.md`](https://github.com/microsoft/intelligent-terminal/blob/main/tools/wta/OVERVIEW.md), the helper+master [design specification](https://github.com/microsoft/intelligent-terminal/blob/main/doc/specs/Multi-window-agent-pane.md), the [`TerminalProtocol.idl`](https://github.com/microsoft/intelligent-terminal/blob/main/src/cascadia/TerminalProtocol/TerminalProtocol.idl) COM contract, the [`wtcli` command reference](https://github.com/microsoft/intelligent-terminal/blob/main/doc/wtcli-commands.md), and the [official announcement](https://devblogs.microsoft.com/commandline/announcing-intelligent-terminal-version-0-1/).
{: .prompt-info}

## 🧾 Conclusion

The interesting thing about Intelligent Terminal isn't that it puts AI in your terminal - plenty of tools do a version of that. It's how hard it works to *not* be the AI. Commit to being a local transport and a surprising amount follows: the agent stays swappable, the model connection remains with the selected CLI, and the terminal integration fits in one Rust binary speaking two protocols. The helper-and-master split, shared agent process, stashed panes and OSC 133 autofix pipeline all trace back to that choice. 
