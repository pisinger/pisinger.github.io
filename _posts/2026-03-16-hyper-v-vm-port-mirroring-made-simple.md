---
title: Capturing VM Traffic on Hyper-V External vSwitches with Port Mirroring
author: pit
date: 2026-03-16
categories: [Blogging, Tutorial]
tags: [hyper-v, networking, port-mirroring, span, wireshark, capture, edge]
render_with_liquid: false
---

If you run VMs on Hyper-V using the default NAT switch, capturing their network traffic is trivial - just open Wireshark on the host and you're done. Switch to an **external vSwitch** backed by a dedicated NIC, and that convenience disappears. This post shows the quickest path back to visibility. 🔍

## The background

I came across this in a specific edge scenario: a Windows 11 machine with multiple NICs running several Linux VMs on Hyper-V, all connected to an external switch rather than the default NAT setup. The location was served by a single consumer-grade router, which makes network visibility limited to begin with - so running `tcpdump` on each VM individually wasn't going to cut it. I needed something central and visual.

On Linux with Open vSwitch, port mirroring is something I would reach for immediately - but I hadn't had much reason to do it on Hyper-V before. Then I remembered that when using **Defender for IoT** on Hyper-V we also have to mirror to feed traffic to the virtualized sensor. Turns out it works just as well for general-purpose capture 😊

## 🔄 Why external switches behave differently

With a NAT switch, Hyper-V routes all VM traffic through the host's network stack, so Wireshark sees it naturally. An external switch bypasses that - it maps directly to a physical NIC and bridges traffic at Layer 2, which means the host's packet capture layer never sees it.

The solution is **port mirroring**: Hyper-V can duplicate traffic from a source adapter on a VM and forward it to a destination adapter of your choice, where it becomes capturable again.

> This is the same mechanism Microsoft uses for Defender for IoT sensor deployments on Hyper-V as mentioned above: <https://learn.microsoft.com/en-us/azure/defender-for-iot/organizations/traffic-mirroring/configure-mirror-hyper-v>
{: .prompt-info}

## ✅ Pre-requisites

- Hyper-V on Windows 10/11 or Windows Server
- At least one VM attached to an external vSwitch
- Wireshark on the host (or on a dedicated capture VM)
- A PowerShell session with the Hyper-V module loaded

## 🛠️ Setting it up

Port mirroring in Hyper-V has two sides: a **Source** (the VM whose traffic you want to see) and a **Destination** (where the copy lands). You configure both through `Set-VMNetworkAdapter`.

**Set the VM you want to monitor as source:**

If the VM has a single adapter or you want to mirror all of them at once:

```powershell
Set-VMNetworkAdapter -VMName "MyLinuxVM" -PortMirroring Source
```

If the VM has multiple adapters and you only want to mirror a specific one, target it by name:

```powershell
Set-VMNetworkAdapter -VMName "MyLinuxVM" -Name "Ethernet1" -PortMirroring Source
```

> Not sure what adapters a VM has? `Get-VMNetworkAdapter -VMName "MyLinuxVM"` will list them with their names and current mirroring state.
{: .prompt-tip}

**Set the destination** - two options depending on where you want to capture:

*Option A - Capture directly on the host* using the management adapter of the switch:

```powershell
Set-VMNetworkAdapter -ManagementOS -Name "ExternalSwitch" -PortMirroring Destination
```

*Option B - Capture inside another VM* by adding a dedicated span adapter:

```powershell
Add-VMNetworkAdapter -VMName "CaptureVM" -Name "iface-span-port" -SwitchName "ExternalSwitch1"
Get-VMNetworkAdapter -VMName "CaptureVM" | Where-Object Name -eq "iface-span-port" | Set-VMNetworkAdapter -PortMirroring Destination
```

Open Wireshark on the destination, select the mirrored interface, and traffic from `MyLinuxVM` will start flowing through.

> When capturing, filter out the host's own MAC address in Wireshark to keep the view focused on VM traffic only.
{: .prompt-tip}

**When you're done, clean up:**

```powershell
Set-VMNetworkAdapter -VMName "MyLinuxVM" -PortMirroring None
```

If you used Option B, also remove the span adapter from the capture VM to keep your setup clean.

> Avoid leaving port mirroring permanently enabled - it adds overhead to the vSwitch and is easy to forget. Treat it as an on-demand diagnostic tool as long as you not interested in some SPAN mirror setup for network analysis or similar.
{: .prompt-warning}

## Conclusion

Port mirroring turns an otherwise invisible traffic path into something you can inspect with any standard packet analyzer. It takes under a minute to enable, works with your existing tooling, and is trivial to undo. Next time you need to debug networking on a Hyper-V VM that isn't on the NAT switch, this is the first thing to reach for. 🤞

Full cmdlet reference: <https://learn.microsoft.com/en-us/powershell/module/hyper-v/set-vmnetworkadapter?view=windowsserver2025-ps>
