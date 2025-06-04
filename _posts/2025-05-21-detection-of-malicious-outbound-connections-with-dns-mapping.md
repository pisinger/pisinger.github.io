---
title: VNet Flow Logs - Detection of Malicious Outbound Connections with DNS Mapping
author: pit
date: 2025-05-21
categories: [Blogging, Tutorial]
tags: [sentinel, dns, detection, serverless, flow logs, aks, threat intel, cti, networking, hunting, vnet, azure]
render_with_liquid: false
---

## Introduction

> Full KQL query can be found in my [GitHub repository](https://github.com/pisinger/hunting/blob/main/sentinel-malicious-connections-with-dns-and-bytes.kql). Similar query which makes use of ThreatIntelIndicators table instead of NTA built-in malicious flows to then also allow the mapping against your own IoCs is available at [GitHub repository](https://github.com/pisinger/hunting/blob/main/sentinel-malicious-connections-with-dns-and-bytes-ti-map.kql)
{: .prompt-tip}

In this post, I’ll walk through a Kusto query I developed to improve visibility into general outbound network activity using `VNet Flow Logs`. The goal is to correlate outbound connections with DNS resolution and traffic volume (bytes in/out) to malicious remote ips — all in one place.

> The query does also cover VNet integration scenarios when using serverless resources like Azure App Services or Container Instances.
{: .prompt-info}

This solution combines data from `VNet Flow Logs` (Network Traffic Analytics) and `DNS query logs` (Azure DNS Security Policy) to:

- Identify outbound connections either directly from VMs (inlcuding AKS) or through VNet integration (forwarding, serverless)
- Identify outbound connections from serverless resources like Azure App Services and Container Instances
- Map IPs to their corresponding DNS names for better readability and detection capabilities
- Highlight traffic to known malicious destinations using built-in capabilities from Network Traffic Analytics

> Potential Duplicate Connection Logs in Centralized Egress Setups: In centralized egress configurations, packet forwarding and routing can result in duplicate connection entries. You might see these duplicates for inbound traffic to the egress VNet and again for outbound traffic after SNAT. This duplication occurs if outbound flows from the NAT egress machine are not excluded. However, excluding these outbound flows to avoid duplication means losing visibility into connections initiated directly by the egress machine itself, not just the forwarded traffic. This trade-off should be considered based on your specific monitoring and visibility needs. Additionally, it's important to note that we cannot retrieve the received bytes from the response in this scenario, as the response is tracked as a separate flow, preventing it from merging with the corresponding outbound requests. To retrieve the RecvBytes from response flows in such cases, use the filter with DestPort == -1.
{: .prompt-warning}

Requirements:

- Azure VNet Flow Logs with traffic analytics enabled [Manage VNet flow logs (learn.microsoft.com)](https://learn.microsoft.com/en-us/azure/network-watcher/vnet-flow-logs-manage)
- Azue DNS Security Policy with diagnostics logging configured [Azure DNS security policy (learn.microsoft.com)](https://learn.microsoft.com/en-us/azure/dns/dns-security-policy)
- Tables: NTANetAnalytics, NTAIpDetails, DNSQueryLogs

See below for example results

![img-description](/assets/img/posts/detection-of-malicious-outbound-connections-with-dns-mapping/example-apps.png)
serverless app connections when using vnet integration (egress routing)

![img-description](/assets/img/posts/detection-of-malicious-outbound-connections-with-dns-mapping/example-vms.png)
vm connections when using vnet integration (egress routing)

![img-description](/assets/img/posts/detection-of-malicious-outbound-connections-with-dns-mapping/example-aks.png)
aks connections using direct egress routing through aks vnet

## Detailed Description of the Kusto Query

The first step is to filter the data based on the time range, the type of flow you want to analyze and extracting basic fields from VNet Flow Logs.

> If you are interested in all flows, you can comment the line that filters for `FlowType == "MaliciousFlow"` as shown below.
{: .prompt-tip}

```shell
let dt_lookBack = 1d;
NTANetAnalytics
| where TimeGenerated >= ago(dt_lookBack)
| where SubType == 'FlowLog' and FaSchemaVersion == '3' and FlowType != "IntraVNet"
//| where FlowType == "MaliciousFlow"
//---------------
| extend 
    Region = iff(FlowDirection == "Inbound", DestRegion, SrcRegion),
    Subscription = tostring(split(TargetResourceId,"/")[0]),
    HostVm = case(
        FlowDirection == "Inbound" and IsFlowCapturedAtUdrHop == "true" and not(isempty(SrcVm)), SrcVm,    // vnet integration
        FlowDirection == "Inbound" and IsFlowCapturedAtUdrHop == "true" and isempty(coalesce(SrcVm,DestVm)), TargetResourceId,    // vnet integration
        FlowDirection == "Inbound" and IsFlowCapturedAtUdrHop == "false" and not(isempty(DestVm)), DestVm,    // direct
        SrcVm
    )
```

This `extend` logic is especially important for the `HostVm` field to handle situations where SrcVm or DestVm fields are not populated and as well where vnet egress routing is used such as in vnet integration or hub spoke scenarios. In these cases, the VM metadata may not be available, but the TargetResourceId still provides a reliable fallback to identify the resource involved in the flow.

## 🌐 Identify egress routing of serverless resources

The next step is to identify routing through VNet egresses (NVA, Azure Firewall, etc.) what then is specified in a custom `RouteType` field. This allows us to better handle traffic from serverless resources, like `Azure Container Apps` or `Azure Container Instances` when having those configured with VNet integration, or traffic from a "classic" VM using a centralized egress. For this we are using `case` to set the `RouteType` based on the following conditions:

- `IsFlowCapturedAtUdrHop` indicates whether the flow went direct or through a UDR hop
- `unknown-vm` in source or destination fields
- empty `SrcVm` or `DestVm` fields
- `unknown flow types`
- `TargetResourceId !has "/mc_"` to exclude managed AKS cluster for being flagged

If these conditions are met, it either labels the RouteType as `VNET_INTEGRATION_APPS` or `VNET_INTEGRATION_VM` — making it easier to later track and analyze traffic from `serverless` workloads, or `forwarded` traffic in general.

> There might be more conditions to check for VNet integration depending on resource types. The following snippet is a good starting point, but we may have to adjust to handle more scenarios.
{: .prompt-warning}

```shell
// identify egress routing for vm and serverless resources (vnet integration)
| extend RouteType = case(
    TargetResourceId !has "/mc_" and IsFlowCapturedAtUdrHop == "true" and (
        (FlowDirection == "Outbound" and DestVm has "unknown-vm") or (FlowDirection == "Inbound" and SrcVm has "unknown-vm") or
        (FlowDirection == "Outbound" and isempty(DestVm) and FlowType startswith "Unknown") or (FlowDirection == "Inbound" and isempty(SrcVm) and FlowType startswith "Unknown")
    ), "VNET_INTEGRATION_APPS", 
    IsFlowCapturedAtUdrHop == "true" and FlowDirection == "Inbound" and TargetResourceId !has "/mc_", "VNET_INTEGRATION_VM",
    IsFlowCapturedAtUdrHop == "true" and FlowDirection == "Outbound" and TargetResourceId !has "/mc_", "VNET_INTEGRATION_VM",
    "DIRECT"
)
```

## 🧹 Filtering Out Irrelevant Outbound Responses due to Egress hub VNet Routing

To focus on meaningful outbound traffic from VNet-integrated workloads, this snippet removes irrelevant flows:

- The `AclRule platformrule` condition filters out platform-generated responses/answers to the requesting source
- `IsFlowCapturedAtUdrHop` is used to make sure we only exclude answers from egress based scenarios

> Update: Doing so would also prevent us from retrieving RecvBytes from the response as in vnet integration scenarios the response is tracked as a separate flow, which prevents merging with the corresponding outbound requests. Consequently, the received bytes are not included in the outbound request records. To address this, a workaround has been implemented that allows checking for received bytes without mapping them to the specific outbound request. This can be queried by filtering for DestPort == -1.
{: .prompt-info}

Together, these filters may help clean up the data by removing noise, making it easier to focus on actual outbound connections from serverless resources using VNet integration, and of course the other VM-based resources.

```shell
// exclude inbound answers in vnet integration scenarios
| where not(AclRule == "platformrule" and IsFlowCapturedAtUdrHop == "true" and FlowDirection == "Outbound")
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

We also need to correctly manage forwarding scenarios where the FlowDirection does not align with the actual traffic direction due to the way the flow is captured at the UDR hop. This then leads to having having the Source and Destination "mixed up". This is also important to properly extract the sent/recv bytes from the flow tuple in the next section further below.

```shell
// extract ips from single line tuples
| mv-expand SrcPublicIps_s = split(SrcPublicIps, " ")
| mv-expand DestPublicIps_s = split(DestPublicIps, " ")
| extend
    SrcPublicIps_s = split(SrcPublicIps_s,"|")[0],
    DestPublicIps_s = split(DestPublicIps_s,"|")[0],
    BytesDestToSrc = todecimal(iff(FlowDirection == "Outbound" and DestPublicIps_s has "|", split(DestPublicIps_s, "|")[-1], BytesDestToSrc) ),
    BytesSrcToDest = todecimal(case(
        FlowDirection == "Inbound" and IsFlowCapturedAtUdrHop == true and DestPublicIps_s has "|", split(DestPublicIps_s,"|")[-2],    // vnet integeration outbound request
        FlowDirection == "Outbound" and IsFlowCapturedAtUdrHop == true and SrcPublicIps_s has "|", split(SrcPublicIps_s, "|")[-2],    // vnet integration dedicated response
        FlowDirection == "Inbound" and DestPublicIps_s has "|", split(DestPublicIps_s,"|")[-2],
        FlowDirection == "Outbound" and DestPublicIps_s has "|", split(DestPublicIps_s, "|")[-2],
        BytesSrcToDest
    ))
| extend
    SrcIp = tostring(iff(isempty(SrcIp), SrcPublicIps_s, SrcIp)),
    DestIp = tostring(iff(isempty(DestIp), DestPublicIps_s, DestIp)),
    AclGroup = tostring(split(AclGroup, "/")[-1])
```

## ↔️ Correcting Flow Direction for Egress Routing (VNet Integration)

As mentioned above, when it comes to VNet integration amd egress routing, the flow direction can sometimes be misleading. For example, outbound traffic from a VNet-integrated serverless resource is logged as inbound on the defined UDR hop (NVA, Azure Firewall, etc.) from the egress VNet due to the nature of packet forwarding and NAT, what then can create confusion when doing analysis of inbound/outbound flows.

> The same is true for "classic" VM resources using a centralized egress in a commmon hub-spoke network topology.
{: .prompt-info}

The following snippet corrects the FlowDirection for traffic from VNet-integrated resources where outbound flows are recorded as inbound. It also re-maps the source and destination, including the sent/received bytes.

- The traffic originates from RouteType startswith `VNET_INTEGRATION` - to cover serverless and VM-based resources

> We do not adjust the AclRule, so this will still reflect the applied inbound rule from the egress vnet while the traffic is actually outbound from source/app perspective while the hop sees the same flow as inbound.
{: .prompt-info}

```shell
// revert direction and source/destination columns including bytes sent/recv in case of vnet based egress (SNAT)
| extend 
    FlowDirection = iff(RouteType startswith "VNET_INTEGRATION" and IsFlowCapturedAtUdrHop == "true" and FlowDirection == "Inbound", "Outbound", FlowDirection),
    DestIp = iff(RouteType startswith "VNET_INTEGRATION" and IsFlowCapturedAtUdrHop == "true" and FlowDirection == "Outbound", SrcIp, DestIp),
    SrcIp = iff(RouteType startswith "VNET_INTEGRATION" and IsFlowCapturedAtUdrHop == "true" and FlowDirection == "Outbound", DestIp, SrcIp),
    BytesSrcToDest = iff(RouteType startswith "VNET_INTEGRATION" and IsFlowCapturedAtUdrHop == "true" and FlowDirection == "Outbound", BytesDestToSrc, BytesSrcToDest),
    BytesDestToSrc = iff(RouteType startswith "VNET_INTEGRATION" and IsFlowCapturedAtUdrHop == "true" and FlowDirection == "Outbound", BytesSrcToDest, BytesDestToSrc),
    DestPort = iff(RouteType startswith "VNET_INTEGRATION" and IsFlowCapturedAtUdrHop == "true" and FlowDirection == "Outbound", -1, DestPort)
```

When these conditions are met, the flow direction is flipped to `Outbound` including re-mapping the source and destination to more accurately reflect the true nature of the traffic egress from a serverless workload.

## ✨ Enhancing Readability with Unicode Symbols

To make the output more intuitive and visually scannable, this step uses Unicode symbols to represent flow status and type. This makes it much easier to spot risky or interesting flows at a glance, especially in dashboards or exported reports.

- `Action` shows a ✅ for allowed flows and ⛔ for denied ones.
- `Type` categorizes flows as:
  - 🌐 Public (if either IP is public)
  - 🏠 Internal (if both are private)
  - ⚠️ Malicious (if flagged as such)

```shell
| extend Action = iff(FlowStatus == "Allowed", "✅", "⛔")
| extend FlowTypeUni = case(
    FlowType == "MaliciousFlow" and (not(ipv4_is_private(SrcIp)) or not(ipv4_is_private(DestIp))), "🌐 Public ⚠️ Malicious",
    FlowType == "MaliciousFlow", "🏠 Internal ⚠️ Malicious", 
    not(ipv4_is_private(SrcIp)) or not(ipv4_is_private(DestIp)), "🌐 Public", 
    "🏠 Internal"
)
```

## 🔍 Filtering for Flows based on Scenario

This step is about filtering the data to focus on outbound flows that are relevant for your analysis. The goal is to narrow down the dataset to only those flows that are of interest, such as outbound connections from serverless resources or VNet-integrated workloads. This is also where you can apply any additional filters based on your specific use case, for expample to filter for `AKS` flows only, or to only focus on serverless resources by going with RouteType of `VNET_INTEGRATION_APPS`.

Please note the `DestPort != -1` filter, which is used to exclude responses from VNet integration scenarios. This exclusion is necessary because the response is captured as a separate flow, preventing the merging of request and response flows. To retrieve the RecvBytes from the response flows in such scenarios, use the filter with ==.

```shell
// early filters
| where FlowDirection == "Outbound"
//| where not(ipv4_is_private(DestIp))
//| where FlowTypeUni !endswith "Internal"
//| where RouteType startswith "DIRECT"    // VNET_ or DIRECT
//| where HostVm has "aks"       // include/exclude aks
//| where AclGroup has "spoke"
| where DestPort != -1
```

## 📊 Aggregating Traffic Data for Analysis

This step summarizes/aggregates the flow data by key dimensions and calculates total bytes sent and received in megabytes. The idea is to have a clear overview of the traffic patterns, which can be useful for identifying anomalies or high-volume flows.

- `BytesSentMb/BytesRecvMb` converts byte counts to megabytes and rounds to 3 decimal places
- finally `group by` key attributes like host, region, IPs, ports, protocol, and flow classification

```shell
| summarize 
    BytesSentMb = round(sum(BytesSrcToDest/1024./1024.),3), BytesRecvMb = round(sum(BytesDestToSrc/1024./1024.),3),
    count() by bin(TimeGenerated, dt_binTime), HostVm, RouteType, IsFlowCapturedAtUdrHop, AclGroup, AclRule, Region, FlowDirection, Action, FlowStatus, FlowTypeUni, L4Protocol, SrcIp, DestIp, DestPort, FlowType
```

## 🌍 Enriching with geo IP information

To better understand where outbound traffic is going and why, this step enriches flow data with `Geo IP` metadata:

- `NTAIpDetails`: A reference table providing geolocation, ISP, and service-related info for IPs
- `arg_max(TimeGenerated, *)` ensures the most recent enrichment data is used per IP
- `leftouter join` retains all flow records, even if no enrichment is available

By joining this enrichment data, you gain valuable context about each destination IP — whether it's identifying the geographic location, the ISP, or the service category (e.g., Azure Monitor). This makes it much easier to interpret the purpose and legitimacy of outbound connections.

```shell
// join with location info
| join kind=leftouter(
    NTAIpDetails 
    | summarize arg_max(TimeGenerated, *) by Ip 
    | project Ip, Location, PublicIpDetails
) on $left.DestIp == $right.Ip
```

## 🌐 Enriching VNet Flow Logs with DNS Data

When analyzing outbound connections in Azure using VNet flow logs, you're typically working with raw IP addresses. While this provides a foundational view of network activity, it lacks the context needed to fully understand where your traffic is going and why. This is where DNS query logs come into play. The below snippet enriches the flow data with `DNS information`, allowing you to map IPs to domain names to then provide:

- More readable: Domains are easier to interpret than raw IPs
- More insightful: Helps detect threats tied to suspicious domains
- Easier to troubleshoot: Quickly identify which services are being accessed
- Better for reporting: Enables clearer dashboards and audits

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

```shell
| summarize QueryName = make_set(QueryName) by TimeGenerated, HostVm, RouteType, IsFlowCapturedAtUdrHop, AclGroup, AclRule, FlowDirection, Action, FlowStatus, FlowTypeUni, L4Protocol, SrcIp, DestIp, DestPort, PublicIpDetails, BytesSentMb, BytesRecvMb, Location, Region, FlowType, count_
| extend QueryNameSingle = QueryName[0]    // extract first entry from array to use this as entity in sentinel
| extend Client = toupper(tostring(split(HostVm,"/")[1]))
| project TimeGenerated, Client, HostVm, RouteType, IsFlowCapturedAtUdrHop, AclGroup, AclRule, FlowDirection, Action, FlowStatus, FlowTypeUni, L4Protocol, SrcIp, QueryNameSingle, QueryName, DestIp, DestPort, PublicIpDetails, BytesSentMb, BytesRecvMb, Location, Region, FlowType, count_
```
