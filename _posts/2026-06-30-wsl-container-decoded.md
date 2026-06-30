---
title: "The New WSL Container: Running native Linux Containers on Windows"
author: pit
date: 2026-06-30
categories: [blogging, tutorial]
tags: [wsl, wsl-containers, wslc, docker, docker-desktop, linux-containers, powershell]
render_with_liquid: false
---

Running a Linux container on Windows usually starts with the same instruction: install Docker Desktop. That works well, but it also means adding another desktop application, another update channel and another layer of management before the first container even starts.

Microsoft is now adding a different path directly to WSL. The new **WSL Container** public preview brings a built-in container CLI called `wslc.exe` and an API that allows native Windows applications to run Linux containers. The CLI feels surprisingly familiar - but the API is the real game changer. A Windows application can now treat a Linux-backed service, database or processing engine as part of its own application architecture without using Docker Desktop as the vehicle to deploy and operate it.

> WSL Container is currently available in the WSL pre-release channel. Microsoft is aiming for general availability in autumn 2026, so I would treat everything below as lab and evaluation material for now.
{: .prompt-warning}

> The official announcement and documentation are available here: <https://devblogs.microsoft.com/commandline/wsl-container-is-now-available-for-public-preview/> and <https://learn.microsoft.com/en-us/windows/wsl/wsl-container>
{: .prompt-info}

## What WSL Container actually adds

There are two parts to the feature:

- `wslc.exe`, with `container.exe` as an alias, handles the usual image, container, volume and networking operations.
- The `Microsoft.WSL.Containers` API lets C, C++ and C# applications pull images, create containers, mount folders, publish ports and interact with container processes directly.

The flow looks like this:

```text
  ┌─────────────────────────────┐
  │ PowerShell / Windows app    │
  └──────────────┬──────────────┘
                 │
          ┌──────┴──────┐
          │             │
     ┌────▼─────┐  ┌────▼─────────────────┐
     │ wslc.exe │  │ Microsoft.WSL.       │
     │ CLI      │  │ Containers API       │
     └────┬─────┘  └────┬─────────────────┘
          └──────┬──────┘
                 │
       ┌──────────▼──────────┐
       │ WSL container       │
       │ session / utility VM│
       └──────────┬──────────┘
                 │
       ┌─────────▼──────────┐
       │ Linux containers   │
       └────────────────────┘
```

This is not Linux containers without virtualisation. WSL still provides the Linux kernel inside a managed utility VM. A WSL Container session owns that VM, its resources and its persistent container storage. Multiple containers in the same session share the session's Linux kernel; each container is not a separate micro-VM.

Looking at the current open-source implementation also removes some of the mystery: a session starts `containerd` and then `dockerd`, with Docker using the external containerd socket. It is therefore no accident that the CLI and image behaviour look like Docker.

> The current implementation can be followed in the [WSLCSession source](https://github.com/microsoft/WSL/blob/master/src/windows/wslcsession/WSLCSession.cpp). The public API is organised as `Session → Container → Process`: <https://wsl.dev/api-reference/>
{: .prompt-tip}

## The real game changer: Linux components inside Windows applications

`wslc.exe` is convenient, but Windows already had several ways to run Linux containers. Docker Desktop, Podman Desktop and Docker Engine inside a WSL distribution all solved that problem in one form or another.

What is genuinely new is the first-party application interface. Through the `Microsoft.WSL.Containers` NuGet package, native applications written in C, C++ or C# can create a WSL-backed session, pull an image, configure storage and networking, start a container and interact with its processes. The application owns that lifecycle without telling the user to install Ubuntu, open a Linux shell or manage Docker Desktop separately.

That opens up some interesting application patterns:

| Windows application | Linux-backed component |
|---|---|
| Desktop business application | PostgreSQL, Redis or another containerised data service |
| AI application | Linux inference runtime with GPU access |
| Security or administration tool | Existing Linux-only scanner or analysis engine |
| Developer tool | Local version of a cloud-hosted Linux service |
| Media or engineering application | Linux-specific processing pipeline or native dependency |

A Windows frontend could, for example, start a private PostgreSQL container during application initialisation, connect to it over a locally published port and stop it again during shutdown. The user sees a normal Windows application. The Linux backend becomes an implementation detail.

This is a much cleaner option than using Docker as the delivery vehicle for an otherwise native Windows product. Docker Desktop no longer needs to become a separate product dependency, and the user does not need to understand distributions, daemons or container contexts merely to run one part of the application.

The current preview is not a completely new container engine independent of the Docker/Moby stack. Microsoft's WSL source shows that each managed session starts `containerd` and `dockerd`, while image builds currently invoke `docker build` inside the utility VM. “Without Docker” therefore means that you do not need Docker Desktop as a product dependency or a Docker Engine that you install and operate yourself. WSL packages and manages those open-source runtime components behind `wslc.exe` and the Windows API. As this is still preview, that internal implementation could change before general availability.

The API also integrates with MSBuild and CMake, which means container build and deployment steps can become part of the application's normal build process rather than a separate set of manual instructions.

> ⚠️ This application API is still preview and may introduce breaking changes. Microsoft's API guidance is to use it now to evaluate feasibility and wait for general availability before deploying production-grade integrations. That matters even more for embedded databases and other stateful backends where upgrades, recovery, backup and data migration need a stable lifecycle contract: <https://wsl.dev/api-reference/>
{: .prompt-warning}

## Running it as background process?

Yes. Background execution itself is not new.

WSL added support for background tasks and daemons back in Windows Insider Build 17046. You could start `sshd`, `httpd`, `tmux` or another long-running process, close the final console window and leave that process running inside the distribution. The same principle made it possible to install Docker Engine inside Ubuntu, start `dockerd`, run a detached container and close the WSL shell.

Docker Desktop already hid most of that work behind its own WSL backend. Without Docker Desktop, however, you still had to own the Linux side yourself:

- Install and maintain a WSL distribution.
- Install Docker Engine or another container runtime inside it.
- Configure and start the daemon.
- Handle storage, networking, updates and daemon failures.
- Add a Windows startup task if the environment needed to return after a reboot or sign-in.

> Microsoft documented WSL background-task support in 2017: <https://devblogs.microsoft.com/commandline/background-task-support-in-wsl/>. WSL instances are still tied to the Windows user lifecycle and are terminated when that user logs off: <https://learn.microsoft.com/en-us/windows/wsl/release-notes#build-20211>
{: .prompt-info}

None of those steps is difficult on its own, but together they are real, ongoing work that you carry for the lifetime of the environment - and it is exactly the part WSL Container takes off your hands.

This is where `wslc` is better for this particular use case. It does not merely leave a process running in a general-purpose Linux distribution. The WSL service creates a purpose-built, persistent container session and exposes it directly to Windows. You can start a detached container from PowerShell, close the terminal and return later without keeping Ubuntu open - or even installing a user distribution in the first place.

The practical difference is ownership. With the older approach, *you* operate a Linux distribution and a container daemon. With `wslc`, Windows and WSL operate the container host while you manage the containers.

| Background-container concern | Docker Engine inside a WSL distro | WSL Container |
|---|---|---|
| Linux distribution | Installed and maintained by you | No user distribution required |
| Container daemon | Installed and operated inside the distro | Created and managed by WSL |
| Windows entry point | Enter WSL or target the daemon remotely | Native `wslc.exe` from any Windows terminal |
| Closing the terminal | Works once the daemon/background process is running | Expected detached-container workflow |
| Windows application integration | Docker socket or CLI integration | Native C, C++ and C# API |
| Enterprise control | Depends on the selected engine/product | WSL policy, registry allowlist and planned Intune integration |

This does not mean `wslc` is an always-on server. A reboot, user logoff or explicit termination of its session/runtime can still stop the underlying environment. The current preview should also not be assumed to restart every container automatically after Windows starts.

## How different is it from Docker?

From the command line, not very different. Microsoft deliberately adopted the familiar container vocabulary, and the current command surface is already broad:

```text
container  Manage containers.
image      Manage images.
network    Manage networks.
registry   Manage registry credentials.
settings   Open the settings file in the default editor.
system     System-level commands
volume     Manage volumes.
attach     Attach to a container.
build      Build an image from a Dockerfile.
create     Create a container.
exec       Execute a command in a running container.
export     Export a container's filesystem as a tar archive.
images     List images.
import     Import an image from a tarball.
inspect    Inspect objects.
kill       Kill containers.
list       List containers.
load       Load images.
login      Log in to a registry.
logout     Log out from a registry.
logs       View container logs.
pull       Pull images.
push       Upload an image to a registry.
remove     Remove containers.
rmi        Remove images.
run        Run a container.
save       Save images.
start      Start a container.
stats      Display container resource usage statistics.
stop       Stop containers.
tag        Tag an image.
version    Show version information.
```

For many everyday workflows, replacing `docker` with `wslc` gets you remarkably close:

| Task | Docker | WSL Container |
|---|---|---|
| Run a container | `docker run` | `wslc run` |
| List containers | `docker ps` | `wslc list` or `wslc container list` |
| Execute a command | `docker exec` | `wslc exec` |
| View logs | `docker logs` | `wslc logs` or `wslc container logs` |
| Build an image | `docker build` | `wslc build` |
| Pull and push images | `docker pull` / `docker push` | `wslc pull` / `wslc push` |
| Save and load images | `docker save` / `docker load` | `wslc save` / `wslc load` |
| Manage volumes | `docker volume` | `wslc volume` |

Environment variables, published ports, named volumes, interactive terminals and GPU access also use recognisable options. There is much less muscle memory to relearn than the new binary name suggests.

The difference is mostly around the product boundary:

| Area | Docker Desktop | WSL Container preview |
|---|---|---|
| Installation | Separate product | Included with WSL |
| Main interface | CLI plus desktop UI | Windows CLI and API |
| Linux backend | WSL 2 or Hyper-V | WSL-managed utility VM |
| Windows application API | Primarily Docker Engine API/socket | Native C, C++ and C# API |
| Enterprise controls | Docker-specific administration | WSL GPO/Intune controls and registry allowlist |
| Maturity | Established product | Public preview |
| Broader tooling | Compose, Kubernetes and extensions | Not documented as part of the current preview |

So I would not call it a feature-for-feature Docker Desktop replacement yet. If your workflow depends on Compose, a bundled Kubernetes cluster, the Docker Desktop UI, restart policies or its extension ecosystem, check those requirements carefully. Those capabilities are not represented in the current `wslc` command surface. For running and building individual Linux containers from Windows, however, WSL Container covers a useful amount of ground without another desktop product or a manually maintained Linux container host.

## Defender visibility for WSL containers

The enterprise angle is also worth watching. Microsoft Defender for Endpoint already has a plugin for monitoring activity inside WSL distributions. Microsoft is extending that plugin so it also understands Linux container events generated through WSL Container.

According to Microsoft, the goal is parity: a Linux workload should generate the same endpoint telemetry whether it runs in a normal WSL distribution or inside a WSL container. This is important for organisations that do not want `wslc` to become a separate Linux execution path outside their existing endpoint visibility.

It also makes the native application scenario more realistic. If a Windows application quietly starts a Linux database, processing engine or security tool behind its frontend, the security team still needs visibility into what happens inside that container. Extending the existing MDE integration is the logical place to provide it.

> ⚠️ MDE awareness of WSL container events is currently a **private preview**. It should not be described as generally available coverage yet, and I have not validated its telemetry in my own environment. Microsoft provides a [private-preview signup form](https://forms.office.com/r/KFeDkeMpvS) from the announcement: <https://devblogs.microsoft.com/commandline/wsl-container-is-now-available-for-public-preview/>
{: .prompt-warning}

## Installing the preview

Open PowerShell and update WSL from the pre-release channel:

```powershell
wsl --update --pre-release
wslc version
```

The second command should return the installed WSL Container version. You can also inspect the available commands before continuing:

```powershell
wslc --help
wslc run --help
```

> Updating with `--pre-release` moves WSL onto preview bits, not only the container CLI. I would use a test device or a disposable lab until the feature reaches general availability. The commands below follow the current preview documentation and source, so check `wslc --help` if a later preview changes the CLI.
{: .prompt-warning}

## Configuring the managed session with settings.yaml

WSL Container has its own per-user configuration file at `%LOCALAPPDATA%\wslc\settings.yaml`. This is separate from `%USERPROFILE%\.wslconfig`: `.wslconfig` controls regular WSL 2 virtual-machine behaviour, while `settings.yaml` provides defaults for the managed session used by the `wslc` CLI.

Run the following command to create the default template, if it does not exist yet, and open it in the default editor:

```powershell
wslc settings
```

The generated file documents the currently supported user-facing settings:

```yaml
# wslc user settings
# https://aka.ms/wslc-settings
# All settings support string value "default" which uses built-in defaults.

session:
  # Number of virtual CPUs allocated to the session (e.g. 4 default: all available CPUs)
  # cpuCount: default

  # Memory limit for the session (e.g. 2GB default: half of available memory)
  # memorySize: default

  # Maximum disk image size (e.g. 500GB default: 1TB)
  # maxStorageSize: default

  # Default host address that published ports bind to when 'container run -p' is
  # used without an explicit address (default: 127.0.0.1)
  # defaultBindingAddress: default

# Credential storage backend: "wincred" or "file" (default: wincred)
# credentialStore: wincred
```

| Setting | Built-in default | What it controls |
|---|---|---|
| `session.cpuCount` | All available logical processors | Virtual CPUs assigned to the managed session. The value must be greater than zero. |
| `session.memorySize` | Half of the computer's physical memory | Session memory limit. Size suffixes such as `MB` and `GB` are supported. The current implementation also creates the session's swap disk with the same virtual capacity. |
| `session.maxStorageSize` | `1TB` | Maximum virtual capacity used when creating `storage.vhdx`. The VHDX remains dynamically expanding, so this does not immediately reserve that amount of space. Changing it does not resize an existing disk. |
| `session.defaultBindingAddress` | `127.0.0.1` | IPv4 address used for a `-p` mapping that does not specify a host address. An explicit address in the command takes precedence. |
| `credentialStore` | `wincred` | Stores registry logins either in Windows Credential Manager or in a DPAPI-encrypted file. |

For this PostgreSQL lab, a reasonable explicit configuration would be:

```yaml
session:
  cpuCount: 4
  memorySize: 4GB
  maxStorageSize: 30GB
  defaultBindingAddress: 127.0.0.1

credentialStore: wincred
```

Keeping `defaultBindingAddress` on `127.0.0.1` means the later `-p 5432:5432` example is reachable from Windows but is not published on every host interface by default. If remote systems genuinely need access, I would make that decision visible on the individual container with `-p 0.0.0.0:5432:5432` and then apply an appropriate Windows Firewall rule, rather than changing the global default. Binding to `0.0.0.0` does not itself create or replace firewall policy.

CPU and memory values are read when a new managed session is created. Stop running containers and terminate the existing session before expecting those changes to apply:

```powershell
wslc system session terminate
```

The next `wslc` command creates the session again with the updated defaults while retaining `storage.vhdx`. Port-binding changes apply to newly created mappings; existing containers keep the mappings with which they were created.

The default `wincred` backend creates generic Windows credentials with names beginning `wslc-credential/`. Selecting `file` instead stores registry credentials in `%LOCALAPPDATA%\wslc\registry-credentials.json`, with secrets protected through Windows DPAPI. Switching the setting does not migrate existing logins, so run `wslc login` again for the registries you need. `wslc settings reset` restores the commented template and overwrites custom settings, but it does not delete the separate credential store.

> When you run `wslc login` against a container registry, the credentials are not kept inside the Linux session - they are written to the **Windows Credential Manager** by default (the `wincred` backend). You can confirm this from Windows itself: open *Credential Manager → Windows Credentials* and look for generic entries named `wslc-credential/...`, or run `cmdkey /list:wslc-credential/*` in PowerShell. This means registry logins follow the Windows user's credential vault and DPAPI protection rather than living in a distro or a Docker `config.json`, which is worth knowing when you reason about where secrets actually reside.
{: .prompt-info}

Invalid values, unknown keys and malformed YAML produce warnings and fall back to built-in defaults. The behaviour above is based on the current preview's [settings parser and defaults](https://github.com/microsoft/WSL/blob/master/src/windows/common/WSLCUserSettings.cpp), [managed-session creation](https://github.com/microsoft/WSL/blob/master/src/windows/service/exe/WSLCSessionManager.cpp), [port-binding implementation](https://github.com/microsoft/WSL/blob/master/src/windows/wslc/services/ContainerService.cpp) and [credential backends](https://github.com/microsoft/WSL/tree/master/src/windows/wslc/services). As with the other implementation details in this post, they may change before general availability.

## Where WSL Container stores its state

After using `wslc`, I found a user-specific session directory below `%LOCALAPPDATA%`:

```powershell
Get-ChildItem -Recurse "$env:LOCALAPPDATA\wslc\sessions"
```

```text
Directory: C:\Users\pit\AppData\Local\wslc\sessions\wslc-cli-pit

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a---          30/06/2026    09:23      616562688 storage.vhdx
-a---          30/06/2026    09:14       37748736 swap.vhdx
```

These files belong to the managed WSL Container session. The default session name is `wslc-cli-<username>`; an elevated session uses a separate `wslc-cli-admin-<username>` name.

| File | Purpose |
|---|---|
| `storage.vhdx` | The persistent, dynamically expanding ext4 disk mounted at `/var/lib/docker` inside the managed utility VM. It holds pulled image layers, container state and normal named volumes. The current preview gives it a default maximum size of 1 TB, configurable through `session.maxStorageSize`. |
| `swap.vhdx` | An ephemeral, dynamically expanding disk used as Linux swap for the utility VM. Its virtual capacity follows the configured session memory size. WSL Container recreates it when the session starts and removes it when the session terminates. It does not hold persistent container data. |

The `Length` values shown by PowerShell are the VHDX files' current on-disk allocation, not their configured virtual capacity. That explains why `swap.vhdx` can appear to be only a few dozen megabytes even when the session has substantially more swap available.

### storage.vhdx is simply a Docker data-root

It is worth being precise about what `storage.vhdx` actually is, because it answers the earlier "without Docker" question directly. This disk is nothing exotic: it is a plain Docker Engine data-root mounted at `/var/lib/docker`. Looking inside it shows the standard `dockerd` layout, not a custom or containerd-only store:

```text
drwx--x--x  4 root root  4096 buildkit
drwx------  3 root root  4096 containerd
drwx--x---  4 root root  4096 containers
-rw-------  1 root root    36 engine-id
drwx------  3 root root  4096 image
drwx------  2 root root 16384 lost+found
drwxr-x---  3 root root  4096 network
drwx--x--- 17 root root  4096 overlay2
drwx------  4 root root  4096 plugins
drwx------  2 root root  4096 runtimes
drwx------  2 root root  4096 swarm
drwx------  2 root root  4096 tmp
drwx-----x  3 root root  4096 volumes
```

Several of these directories only exist because a real Docker Engine is running. `engine-id`, `swarm`, `network`, `image`, `overlay2`, `buildkit` and `volumes` are all Docker Engine constructs - a pure containerd installation uses a completely different layout under `/var/lib/containerd` (for example `io.containerd.content.v1.content` and `io.containerd.snapshotter.v1.overlayfs`). The `containerd` folder you can see here is simply the embedded containerd that `dockerd` manages underneath itself, rooted at `/var/lib/docker/containerd`, which matches the `--containerd /run/containerd/containerd.sock` wiring in the WSL source.

This is the on-disk confirmation of what the earlier sections described: the session really does run `containerd` *and* `dockerd`, and your pulled images, named volumes and `wslc build` artefacts all live in this one Docker data-root. So `storage.vhdx` is best understood as "the Docker mount" for the session - the writable disk attached to an otherwise read-only utility VM whose operating system and daemon binaries ship separately with WSL.

This also connects directly to the PostgreSQL example below: a regular `wslc volume create pgdata` volume is stored inside `storage.vhdx`. Removing and recreating the PostgreSQL container does not remove that volume, but deleting or corrupting `storage.vhdx` would remove the session's images, containers and normal named volumes. Do not manually edit, mount or delete either VHDX while the session is active. Use targeted `wslc container`, `wslc image` and `wslc volume` remove or prune commands instead—and remember that pruning unused volumes deletes their data.

These details come from the current preview implementation in Microsoft's WSL source: [session naming and storage-path creation](https://github.com/microsoft/WSL/blob/master/src/windows/service/exe/WSLCSessionManager.cpp), [VHD creation, mounting and swap lifecycle](https://github.com/microsoft/WSL/blob/master/src/windows/wslcsession/WSLCSession.cpp), and [the session storage-size setting](https://github.com/microsoft/WSL/blob/master/src/windows/common/WSLCUserSettings.h). They are implementation details and may change before general availability.

## Running PostgreSQL with persistent storage

Rather than stopping at `hello-world`, let's run something with state. The following example starts PostgreSQL, publishes it to Windows, writes data, removes the container and then proves that the data survived in a named volume.

First create the volume:

```powershell
wslc volume create pgdata
```

Now start PostgreSQL. I am pinning the example to `postgres:17-alpine` rather than using `latest`, which keeps the result more predictable when the upstream image changes.

```powershell
wslc run -d `
    --name cpostgres `
    -e POSTGRES_PASSWORD="ChangeMe-ForTheLab" `
    -e POSTGRES_DB="wslcdemo" `
    -p 5432:5432 `
    -v pgdata:/var/lib/postgresql/data `
    postgres:17-alpine
```

There is quite a bit happening in one command:

- `-d` runs the database in the background.
- `-e` supplies the initial database settings.
- `-p 5432:5432` exposes PostgreSQL on Windows at `localhost:5432`.
- `-v` stores the database files outside the container's writable layer.

Once `wslc run -d` returns, the terminal is no longer part of the container lifecycle. Close it, open a fresh PowerShell window and `wslc container list` will reconnect to the persistent WSL Container session. No WSL distribution shell needs to remain open.

Check the container and follow its startup log:

```powershell
wslc container list
wslc container logs cpostgres
```

Wait until PostgreSQL reports that it is ready to accept connections. Then create a small table and add a row by running `psql` inside the container:

```powershell
wslc exec cpostgres psql -U postgres -d wslcdemo -c `
    "CREATE TABLE release_notes (id integer, feature text);"

wslc exec cpostgres psql -U postgres -d wslcdemo -c `
    "INSERT INTO release_notes VALUES (1, 'WSL Container');"

wslc exec cpostgres psql -U postgres -d wslcdemo -c `
    "SELECT * FROM release_notes;"
```

The final command should return something similar to:

```text
 id |    feature
----+---------------
  1 | WSL Container
(1 row)
```

At this point, any Windows PostgreSQL client can also connect to `localhost:5432` using the same database and credentials. The Linux workload is running inside WSL, but the published port is available directly from Windows.

## Proving that the data is persistent

Stopping a database is easy. The more relevant test is whether its state survives when the container itself is deleted.

```powershell
wslc container stop cpostgres
wslc container remove cpostgres
```

Create a fresh container and attach the same `pgdata` volume:

```powershell
wslc run -d `
    --name cpostgres `
    -e POSTGRES_PASSWORD="ChangeMe-ForTheLab" `
    -e POSTGRES_DB="wslcdemo" `
    -p 5432:5432 `
    -v pgdata:/var/lib/postgresql/data `
    postgres:17-alpine
```

Once PostgreSQL is ready, query the table again:

```powershell
wslc exec cpostgres psql -U postgres -d wslcdemo -c `
    "SELECT * FROM release_notes;"
```

The original row should still be present. The container was replaceable; the volume held the state. That is the kind of behaviour that matters when evaluating whether a new container tool fits an existing development workflow.

When finished, remove the lab resources:

```powershell
wslc container stop cpostgres
wslc container remove cpostgres
wslc volume remove pgdata
```

> Removing `pgdata` permanently deletes the PostgreSQL files used in this example. Leave the volume in place if you want to reuse the database.
{: .prompt-danger}

## Where this appears to be going

Microsoft is also using WSL Container to introduce lower-level improvements such as VirtioFS for faster Windows file access, Consomme networking for better compatibility with Windows VPN, proxy and security controls, and improved memory reclamation. These changes are initially scoped to WSL Container, with the intention of bringing them to regular WSL later. Docker Desktop, Podman Desktop and Rancher Desktop should benefit from those platform improvements as well.

That makes the direction broader than replacing Docker Desktop. WSL is becoming the Windows-managed substrate for Linux development, container tooling and applications that quietly need a Linux component behind a native Windows experience. The CLI makes that substrate accessible to developers; the API makes it part of the Windows application platform.

## Conclusion

For the basic PostgreSQL workflow, the look and feel is very close to Docker: pull an image, publish a port, attach a volume, inspect logs and use `exec`. Closing the terminal was already possible with background processes in traditional WSL, but `wslc` removes the manually operated distribution and daemon from that design. The main change is who owns the platform underneath it - WSL and Windows rather than you or a separate desktop container product.

More importantly, Windows applications can now own that Linux component directly through a native API. It is still too early to make this a production dependency, but it is great to see this capability become part of Windows without requiring Docker Desktop as the application delivery mechanism. For now, the sensible path is to validate the architecture, pressure-test state and recovery behaviour, and wait for the API contract to reach general availability.
