---
title: VNet Flow Logs: Detection of Malicious Outbound Connections with DNS Mapping
author: pit
date: 2025-05-21
categories: [Blogging, Tutorial]
tags: [sentinel, dns, detection, serverless, flow logs, threat intel, cti, networking, hunting, vnet, azure]
render_with_liquid: false
---

## Introduction

In this post, I’ll walk through a Kusto query I developed to improve visibility into general outbound network activity using `VNet Flow Logs`. The goal is to correlate outbound connections with DNS resolution, traffic volume (bytes in/out), and threat intelligence — all in one place. The query does also cover VNet integration scenarios when using serverless resources like Azure App Services or Container Instances.

This solution combines data from `VNet Flow Logs` (via Network Traffic Analytics) and `DNS query logs` (via Azure DNS Security Policy) to:

- Identify outbound connections from serverless resources like Azure App Services and Container Instances
- Map IPs to their corresponding DNS queries
- Highlight traffic to known malicious destinations using built-in threat detection
- It also includes logic to properly handle VNet integration scenarios, ensuring accurate attribution of traffic and avoiding double counting

> Full KQL query can be found in my [GitHub repository](https://github.com/pisinger/hunting/blob/main/sentinel-malicious-connections-with-dns-and-bytes.kql)
{: .prompt-tip}

## Detailed Description of the Kusto Query

The first step is to filter the data based on the time range, the type of flow you want to analyze and extracting basic fields from VNet Flow Logs.

> If you are only interested in malicious flows, you can uncomment the line that filters for `FlowType == "MaliciousFlow"`.
{: .prompt-tip}

```shell
let dt_lookBack = 1d;
NTANetAnalytics
| where TimeGenerated >= ago(dt_lookBack)
| where SubType == 'FlowLog' and FaSchemaVersion == '3' and FlowType != "IntraVNet"
//| where FlowType == "MaliciousFlow"
extend 
    Region = iff(FlowDirection == "Inbound", DestRegion, SrcRegion),
    Subscription = tostring(split(TargetResourceId,"/")[0]),
    Host = iff(FlowDirection == "Inbound", iff(isempty(DestVm), TargetResourceId, DestVm), iff(isempty(SrcVm), TargetResourceId, SrcVm))
```

This `extend` logic is especially important for the `Host` field to handle scenarios scenarios where SrcVm or DestVm fields are not populated. In these cases, the VM metadata may not be available, but the TargetResourceId still provides a reliable fallback to identify the resource involved in the flow.

## 🌐 Handle egress routing via vnet integration

The next step is to populate the `Host` field in a more dynamic way to better identify traffic from non-VM-based resources, like `Azure Container Apps` or `Azure Container Instances` using VNet integration. For this purpose, we use a case statement to check for specific conditions that indicate the traffic is coming from a VNet-integrated serverless resource.

- `unknown-vm` in source or destination fields
- missing VM information
- `unknown flow types`
- resource isn’t part of a managed AKS cluster

If these conditions are met, it labels the host as `VNET_INTEGRATION` — making it easier to later track and analyze traffic from `serverless` workloads.

> There might be more conditions to check for VNet integration, depending on your specific use case. The following snippet is a good starting point, but you may need to adjust it based on your environment and requirements.
{: .prompt-warning}

```shell
// handle egress routing via vnet integration
| extend Host = case(
    FlowDirection == "Outbound" and DestVm has "unknown-vm" and TargetResourceId !has "/mc_", "VNET_INTEGRATION",
    FlowDirection == "Inbound" and SrcVm has "unknown-vm" and TargetResourceId !has "/mc_", "VNET_INTEGRATION",
    FlowDirection == "Outbound" and isempty(DestVm) and FlowType startswith "Unknown" and TargetResourceId !has "/mc_", "VNET_INTEGRATION",
    FlowDirection == "Inbound" and isempty(SrcVm) and FlowType startswith "Unknown" and TargetResourceId !has "/mc_", "VNET_INTEGRATION",
    Host
)
```

## ↔️ Correcting Flow Direction for VNet Integration

When it comes to VNet integration, the flow direction can sometimes be misleading.

For example, outbound traffic from a VNet-integrated serverless resource is logged as inbound on the defined next hop (NVA, Azure Firewall, etc.), which can create confusion when analyzing the data - the same is true for classic VMs using centralized egress.

The below snippet corrects the FlowDirection for traffic from such VNet-integrated resources where outbound flows appear as inbound by checking for:

- The traffic originates from hosts equal to `VNET_INTEGRATION`
- The flow is marked as `Inbound` but has `ambiguous or unknown` source details

When these conditions are met, the flow direction is flipped to `Outbound` to more accurately reflect the true nature of the traffic egress from a serverless workload.

```shell
// revert direction in case of vnet based egress
| extend FlowDirection = case(
    Host == "VNET_INTEGRATION" and FlowDirection == "Inbound" and FlowType startswith "Unknown", "Outbound",
    Host == "VNET_INTEGRATION" and FlowDirection == "Inbound" and SrcVm == "unknown-rg/unknown-vm", "Outbound",
    FlowDirection
)
```

## 🧹 Filtering Out Irrelevant Inbound Responses in VNet Integration

To focus on meaningful outbound traffic from VNet-integrated workloads, this snippet removes irrelevant flows:

- The `AclRule platformrule` condition filters out platform-generated responses/answers to the requesting source
- `Host != TargetResourceId` is used to exclude VM traffic already logged at the source VNet to avoid double counting.

> If VNet Flow Logs are not enabled on the source VNet, you can safely remove this filter. However, keep in mind that you'll also need to handle the FlowDirection correction discussed earlier to ensure accurate traffic interpretation.
{: .prompt-info}

Together, these filters help clean up the data by removing noise, making it easier to focus on actual outbound connections from serverless resources using VNet integration, and of course the other VM-based resources.

```shell
// exclude inbound answers in vnet integration scenarios
| where not(AclRule == "platformrule" and FlowDirection == "Outbound")
| where Host != TargetResourceId
```

## 🧩 Extracting Accurate Network Tuples (IP + Byte Info)

This is a critical but often overlooked step when working with flow logs or similar telemetry. To accurately analyze network flows — especially for public IPs and byte counts — you need to split and parse multi-value tuples correctly.

> Flow logs often encode multiple tuples (IP, packets, bytes) into a single field. To extract them properly, you’ll need to apply the split() function twice. This ensures each tuple is expanded and parsed into its individual components, enabling accurate analysis.
{: .prompt-info}

- `mv-expand` handles multiple tuples in a single record
- `split(..., "|")` extracts the actual IP and byte counts from the encoded format
- `Fallback logic`: Ensures SrcIp and DestIp are populated even if the original fields are empty
- `AclGroup` extracts just the group name from a full resource path

This step ensures you get clean and accurate tuples of:

- Source IP
- Destination IP
- Bytes sent and received

```shell
| mv-expand SrcPublicIps_s = split(SrcPublicIps, " ")
| mv-expand DestPublicIps_s = split(DestPublicIps, " ")
| extend
    SrcPublicIps_s = split(SrcPublicIps_s,"|")[0],
    DestPublicIps_s = split(DestPublicIps_s,"|")[0],
    BytesDestToSrc = split(DestPublicIps_s,"|")[-1],
    BytesSrcToDest = split(DestPublicIps_s,"|")[-2]
| extend
    SrcIp = tostring(iff(isempty(SrcIp), SrcPublicIps_s, SrcIp)),
    DestIp = tostring(iff(isempty(DestIp), DestPublicIps_s, DestIp)),
    AclGroup = tostring(split(AclGroup, "/")[-1])
```

## ✨ Enhancing Readability with Unicode Symbols

To make the output more intuitive and visually scannable, this step uses Unicode symbols to represent flow status and type. This makes it much easier to spot risky or interesting flows at a glance, especially in dashboards or exported reports.

- `Action` shows a ✅ for allowed flows and ⛔ for denied ones.
- `Type` categorizes flows as:
  - 🌐 Public (if either IP is public)
  - 🏠 Internal (if both are private)
  - ⚠️ Malicious (if flagged as such)

```shell
| extend Action = iff(FlowStatus == "Allowed", "✅", "⛔")
| extend Type = case(
    FlowType == "MaliciousFlow" and (not(ipv4_is_private(SrcIp)) or not(ipv4_is_private(DestIp))), "🌐 Public ⚠️ Malicious",
    FlowType == "MaliciousFlow", "🏠 Internal ⚠️ Malicious", not(ipv4_is_private(SrcIp)) or not(ipv4_is_private(DestIp)), "🌐 Public", 
    "🏠 Internal"
)
```

## 📊 Aggregating Traffic Data for Analysis

This step summarizes/aggregates the flow data by key dimensions and calculates total bytes sent and received in megabytes. The idea is to have a clear overview of the traffic patterns, which can be useful for identifying anomalies or high-volume flows.

- `BytesSentMb/BytesRecvMb` converts byte counts to megabytes and rounds to 3 decimal places
- finally `group by` key attributes like host, region, IPs, ports, protocol, and flow classification

```shell
| summarize 
    BytesSentMb = round(sum(BytesSrcToDest/1024./1024.),3), BytesRecvMb = round(sum(BytesDestToSrc/1024./1024.),3),
    count() by Host, AclGroup, AclRule, Region, FlowDirection, Action, FlowStatus, Type, L4Protocol, SrcIp, DestIp, DestPort, FlowType
```

## 🌍 Enriching with geo IP information

To better understand where outbound traffic is going and why, this step enriches flow data with `Geo IP` metadata:

- `NTAIpDetails`: A reference table providing geolocation, ISP, and service-related info for IPs
- `arg_max(TimeGenerated, *)` ensures the most recent enrichment data is used per IP
- `leftouter join` retains all flow records, even if no enrichment is available
- `project` Selects only the most relevant fields, such as Location and PublicIpDetails

By joining this enrichment data, you gain valuable context about each destination IP — whether it's identifying the geographic location, the ISP, or the service category (e.g., Azure Monitor). This makes it much easier to interpret the purpose and legitimacy of outbound connections.

```shell
// join with location info
| join kind=leftouter(
    NTAIpDetails 
    | summarize arg_max(TimeGenerated, *) by Ip 
    | project Ip, Location, PublicIpDetails
) on $left.DestIp == $right.Ip
```

## 🌐 Enriching VNet Flow Logs with DNS Data: Why It Matters

When analyzing outbound connections in Azure using VNet flow logs, you're typically working with raw IP addresses. While this provides a foundational view of network activity, it lacks the context needed to fully understand where your traffic is going and why. This is where DNS query logs come into play. The below snippet enriches the flow data with `DNS information`, allowing you to map IP addresses to domain names to provide:

- More readable – Domains are easier to interpret than raw IPs
- More insightful – Helps detect threats tied to suspicious domains
- Easier to troubleshoot – Quickly identify which services are being accessed
- Better for reporting – Enables clearer dashboards and audits

This together with the previous steps allows you to create a more comprehensive view of your network activity, making it easier to spot anomalies or potential security threats.

```shell
| join kind=leftouter (
    DNSQueryLogs
    | where TimeGenerated >= ago(dt_lookBack + 1h)
    | extend Answer = iif(Answer == "[]", '["NXDOMAIN"]', Answer)
    | extend Answer = todynamic(Answer)
    | mv-expand Answer
    | extend parsed = parse_json(Answer)
    | extend RData = parsed.RData
    | extend RType = tostring(parsed.Type)
    // removing the trailing dot
    | extend QueryName = tolower(trim_end("\\.", QueryName))
    | where RType in ("A","AAAA")
    | distinct Answers = tostring(RData), QueryName, RType
) on $left.DestIp == $right.Answers
```

## 🧩 Final Step: Bringing It All Together

The final steps is about proper aggregation and shaping of the data to make it useful for analysis. This is where you summarize the flow data, extract the first domain name, and project the final output by trying to keep the most relevant fields. The goal is to create a clean, easy-to-read dataset that can be used for further analysis or reporting.

- `summarize make_set(QueryName)` collects all domain names (from DNS logs) associated with each unique IP flow. This gives you visibility into all possible destinations for a given connection
- `extend QueryNameSingle = QueryName[0]` extracts the first domain name from the queryNameSet to may use it as dns entity in `Sentinel`
- `extend Client` normalizes the client name, making it easier to identify the source (such as VNET integration)
- `project` selects and shapes the final output, including

  - Client and host identifiers
  - Flow metadata (IP, ports, protocol, region)
  - DNS info (QueryName, QueryNameSingle)
  - Traffic volume (BytesSentMb, BytesRecvMb)

```shell
| summarize QueryName = make_set(QueryName) by Host, AclGroup, AclRule, FlowDirection, Action, FlowStatus, Type, L4Protocol, SrcIp, DestIp, DestPort, PublicIpDetails, BytesSentMb, BytesRecvMb, Location, Region, FlowType, count_
| extend QueryNameSingle = QueryName[0]    // extract first entry from array to use this as entity in sentinel
| extend Client = iff(Host startswith "VNET_INTEGRATION", Host, toupper(tostring(split(Host,"/")[1])))
| project Client, Host, AclGroup, AclRule, FlowDirection, Action, FlowStatus, Type, L4Protocol, SrcIp, QueryNameSingle, QueryName, DestIp, DestPort, PublicIpDetails, BytesSentMb, BytesRecvMb, Location, Region, FlowType, count_
```
