---
title: Defender for Cloud - Container Security Updates in the Last 6 Months
author: pit
date: 2026-07-02
categories: [blogging]
tags: [defender, defender-for-cloud, containers, kubernetes, aks, eks, gke, cloud-security, advanced-hunting]
render_with_liquid: false
---

Defender for Cloud receives container-related changes throughout its regular release cycle. Looking back from January through July 2026, those updates cover posture management, vulnerability assessment, runtime protection, enforcement, sensor maintenance, private connectivity, and advanced hunting across Azure, AWS, and GCP.

> The list is lifecycle-deduplicated: when a capability moved from preview to general availability during this period, only its latest GA state is shown. Preview entries remain where no later GA announcement exists.
{: .prompt-info}

## Container Updates from January to July 2026

The table covers AKS, EKS, GKE, Azure Arc-enabled Kubernetes, private clusters, serverless containers, image scanning, runtime protection, Defender sensor releases, and container-relevant advanced hunting tables.

Each feature name links to the most specific Microsoft Learn page available.

| Month | Status | Scope | Feature or update | What changed |
|---|---|---|---|---|
| 2026-07 | 🟢 GA | Kubernetes | [Container-level misconfiguration recommendations](https://learn.microsoft.com/en-us/azure/defender-for-cloud/recommendations-reference-container) | Agentless KSPM evaluates individual containers; older cluster-level recommendations are deprecated. |
| 2026-07 | 🟢 GA | AKS | [Upgrade AKS Version recommendation](https://learn.microsoft.com/en-us/azure/defender-for-cloud/kubernetes-nodes-va) | Identifies the minimum upgrade required for vulnerable managed system pods. |
| 2026-07 | 🟢 GA | EKS, GKE | [Runtime-discovered image vulnerability assessment](https://learn.microsoft.com/en-us/azure/defender-for-cloud/view-and-remediate-vulnerabilities-containers) | Extends scanning beyond registry images to images found in running workloads. |
| 2026-07 | 🟢 GA | EKS, GKE | [Kubernetes node vulnerability assessment](https://learn.microsoft.com/en-us/azure/defender-for-cloud/kubernetes-nodes-va) | Adds OS-level node vulnerability assessment equivalent to existing AKS coverage. |
| 2026-07 | 🟢 GA | Container images | [Docker Hardened image scanning](https://learn.microsoft.com/en-us/azure/defender-for-cloud/support-matrix-defender-for-containers#registries-and-images-support-for-vulnerability-assessment) | Adds Defender Vulnerability Management coverage for Docker Hardened images. |
| 2026-07 | 🟢 GA | AKS, Arc, AWS, GCP | [Kubernetes misconfiguration enforcement](https://learn.microsoft.com/en-us/azure/defender-for-cloud/kubernetes-misconfiguration-enforcement) | Adds admission-time audit and blocking through automatic provisioning or Helm. |
| 2026-07 | 🟢 GA | ACA, ACI, ECS Fargate | [Serverless-container discovery and posture](https://learn.microsoft.com/en-us/azure/defender-for-cloud/posture-for-serverless-containers) | Adds inventory, misconfiguration and vulnerability findings, and attack-path analysis. |
| 2026-07 | 🟢 GA | Helm, Arc for Kubernetes | [Defender sensor v0.11 release line](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-sensor-change-log) | Became GA in July 2026 and is supported through July 2027. |
| 2026-06 | 🟢 GA | AWS, GCP | [Expanded multicloud posture coverage](https://learn.microsoft.com/en-us/azure/defender-for-cloud/recommendations-reference-container) | Adds approximately 90 resource types and 200+ recommendations, including containers. |
| 2026-06 | 🔵 Update | Kubernetes, registries | [Expanded container support for cloud scopes](https://learn.microsoft.com/en-us/azure/defender-for-cloud/cloud-scopes-unified-rbac) | Adds K8s namespace, K8s cluster, multicloud registry, and repository scopes. |
| 2026-06 | 🟡 Preview | AWS, GCP | [60+ multicloud recommendations](https://learn.microsoft.com/en-us/azure/defender-for-cloud/security-recommendations) | Adds recommendations spanning containers and other resource categories. |
| 2026-06 | 🟡 Preview | Private EKS, GKE clusters | [Defender sensor v0.11.3](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-sensor-change-log) | Adds Defender sensor support for private EKS and GKE clusters. |
| 2026-06 | 🟢 GA | Multicloud audit activity | [`CloudAuditEvents` advanced hunting table](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-cloudauditevents-table) | Exposes cloud audit activity for control-plane and container investigations. |
| 2026-06 | 🟢 GA | Cloud and container DNS | [`CloudDnsEvents` advanced hunting table](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-clouddnsevents-table) | Exposes DNS activity from cloud infrastructure environments. |
| 2026-06 | 🟢 GA | Multicloud workloads | [`CloudProcessEvents` advanced hunting table](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-cloudprocessevents-table) | Exposes process activity from multicloud hosted workloads. |
| 2026-05 | 🟡 Preview | Private Kubernetes clusters | [Private-cluster sensor protection](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-private-clusters) | Adds gated deployment, binary-drift detection, and malware detection support. |
| 2026-05 | 🟡 Preview | EKS, GKE | [Kubernetes-node malware detection](https://learn.microsoft.com/en-us/azure/defender-for-cloud/kubernetes-nodes-malware) | Extends node malware coverage beyond AKS. |
| 2026-05 | 🟢 GA | AKS, EKS, GKE | [Direct Helm sensor deployment](https://learn.microsoft.com/en-us/azure/defender-for-cloud/deploy-helm) | Replaces installation scripts with environment-specific Helm commands. |
| 2026-05 | 🟢 GA | Containers, container images | [Individual vulnerability recommendations](https://learn.microsoft.com/en-us/azure/defender-for-cloud/transition-grouped-individual-recommendations) | Replaces legacy grouped container and image recommendations. |
| 2026-05 | 🟢 GA | Helm, Arc, AKS | [Sensor v0.10.5, v0.9.58 and v0.8.51](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-sensor-change-log) | Adds Nexus Baremetal compatibility plus dependency security and stability updates. |
| 2026-04 | 🟢 GA | EKS | [Bottlerocket runtime protection](https://learn.microsoft.com/en-us/azure/defender-for-cloud/support-matrix-defender-for-containers#runtime-protection-features) | Adds runtime protection for EKS clusters using Bottlerocket. |
| 2026-04 | 🟢 GA | AKS, EKS, GKE | [Runtime anti-malware detection and blocking](https://learn.microsoft.com/en-us/azure/defender-for-cloud/anti-malware) | Adds configurable alerting and blocking policies for malicious runtime executables. |
| 2026-04 | 🟢 GA | AKS, EKS, GKE | [DNS Detection for Kubernetes](https://learn.microsoft.com/en-us/azure/defender-for-cloud/support-matrix-defender-for-containers#runtime-protection-features) | Detects malicious domains and DNS tunnelling through the Helm-deployed sensor. |
| 2026-04 | 🟢 GA | Azure Government | [Defender for Containers capabilities](https://learn.microsoft.com/en-us/azure/defender-for-cloud/support-matrix-defender-for-containers) | Adds agentless discovery, attack paths, vulnerability assessment, compliance, and runtime protection. |
| 2026-04 | 🟢 GA | Helm, Arc for Kubernetes | [Sensor v0.9 and v0.10 release lines](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-sensor-change-log) | Both became stable in April 2026 and are supported through April 2027. |
| 2026-03 | 🟢 GA | AKS Automatic | [Kubernetes gated deployment](https://learn.microsoft.com/en-us/azure/defender-for-cloud/deploy-helm) | Installs the sensor through Helm in `kube-system`, replacing the AKS add-on deployment. |
| 2026-03 | 🟡 Preview | Container images, CI/CD | [Code-to-runtime enrichment](https://learn.microsoft.com/en-us/azure/defender-for-cloud/code-to-runtime-mapping) | Maps runtime recommendations through registries and pipelines back to source code. |
| 2026-03 | 🟡 Preview | Kubernetes policy enforcement | [`CloudPolicyEnforcementEvents` advanced hunting table](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-cloudpolicyenforcementevents-table) | Exposes policy decisions and metadata for cloud security gating events. |
| 2026-03 | 🟢 GA / 🟡 Preview | Defender sensor | [Sensor security and platform updates](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-sensor-change-log) | Adds Nexus compatibility, secret sanitisation, SELinux improvements, FIPS support, hardened images, and dependency fixes. |
| 2026-02 | 🟡 Preview | Container workloads | [Binary-drift blocking](https://learn.microsoft.com/en-us/azure/defender-for-cloud/binary-drift-detection) | Sensor v0.10.2 can block unauthorised runtime changes to container images. |
| 2026-02 | 🟢 GA | Container images | [Minimus and Photon OS scanning](https://learn.microsoft.com/en-us/azure/defender-for-cloud/support-matrix-defender-for-containers#registries-and-images-support-for-vulnerability-assessment) | Extends image vulnerability scanning to both distributions. |
| 2026-02 | 🟢 GA / 🟡 Preview | Defender sensor | [Sensor performance improvements](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-sensor-change-log) | Delivered through stable v0.8.47 and preview v0.9.50. |
| 2026-01 | 🟡 Preview | Defender for Containers | [Microsoft Security Private Link](https://learn.microsoft.com/en-us/azure/defender-for-cloud/concept-private-links) | Enables private connectivity between Defender for Cloud and protected workloads through private endpoints. |

> Status key: 🟢 generally available, 🟡 preview, and 🔵 functional update. Mixed sensor rows combine changes shipped across stable and preview sensor branches in the same month.
{: .prompt-info}

## What Stands Out

The first clear shift is **multicloud parity**. EKS and GKE now receive runtime image and node vulnerability assessment that was previously associated mainly with AKS. Malware detection is moving in the same direction, although EKS and GKE node coverage is still in preview.

The second is the move from observation towards **enforcement**. Kubernetes misconfiguration enforcement can audit or block resources at admission time, while binary-drift blocking and gated deployment add controls closer to workload execution. I would still start these controls in audit mode and review the impact before blocking production deployments.

The third is better investigation data in Defender XDR. `CloudAuditEvents`, `CloudDnsEvents`, and `CloudProcessEvents` are now GA, while `CloudPolicyEnforcementEvents` remains in preview. These tables matter for container investigations even though their names are broader than Kubernetes - they expose the audit, DNS, process, and policy activity around the workload.

> The table is a release summary, not a support guarantee. Check the linked support matrix before enabling a capability because availability can differ by cloud, Kubernetes distribution, deployment method, and sensor version.
{: .prompt-warning}

## Sources

- <https://learn.microsoft.com/en-us/azure/defender-for-cloud/release-notes>
- <https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-sensor-change-log>
- <https://learn.microsoft.com/en-us/defender-xdr/whats-new>

## Conclusion

Container security in Defender for Cloud changed quite a bit between January and July. The most useful improvements are not limited to another set of recommendations - Microsoft added private connectivity, more multicloud coverage, practical admission and runtime controls, serverless-container posture, and hunting tables that bring the resulting activity into Defender XDR.

The remaining previews are worth tracking, especially private-cluster protection, EKS and GKE malware detection, binary-drift blocking, and `CloudPolicyEnforcementEvents`. Those are the rows most likely to move again in the next release cycle.
