---
title: Defender for Containers Gated Deployment - Blocking Vulnerable Images and Kubernetes Misconfigurations
author: pit
date: 2026-08-04
categories: [blogging, tutorial]
tags: [defender-for-cloud, gated-deployment, kubernetes, aks, eks, gke, azure-arc, validatingadmissionpolicy, container-security]
render_with_liquid: false
---

One of the most satisfying moments in a Kubernetes lab is seeing a bad deployment fail at the API server - before a pod starts, before a container pulls more layers, and before somebody has to clean up the mess afterwards.

That sentence can mean two different things. We might want to stop an image because it contains vulnerabilities. Or we might want to stop an otherwise clean image because the workload asks for a privileged container, mounts a service-account token, runs as root, or has no resource limits.

Microsoft Defender for Cloud now covers both cases through gated deployment. The image path evaluates vulnerability findings associated with the image. The misconfiguration path evaluates Kubernetes resources against security rules. The interesting part is that the second path is now Kubernetes-native: it uses `ValidatingAdmissionPolicy` and no longer requires Gatekeeper or Azure Policy to perform the admission-time enforcement.

That distinction matters particularly when the same platform team operates AKS, EKS, GKE and clusters connected through Azure Arc. One policy idea, several clouds, and a decision made at the Kubernetes admission boundary. That is a much more interesting story than another dashboard full of recommendations.

> The commands and observations in this post come from my AKS test cluster. Always check the current support matrix and the public installation documentation before making this a production gate.
{: .prompt-warning}

## 🧭 Enabling the two gates

Both capabilities are part of the **Defender for Containers** plan, but they do not use exactly the same supporting components. This is the part I would verify first, because a policy can be perfectly configured in the portal and still have nothing useful to evaluate in the cluster.

| Capability | Defender plan and components | Where the policy is configured |
|---|---|---|
| Vulnerable-image gated deployment | Defender for Containers with Defender sensor, Security Gating, Registry Access and Security Findings | Defender for Cloud → Environment settings → Security rules → Gated deployment → Vulnerability assessment |
| Kubernetes misconfiguration enforcement | Defender for Containers with Kubernetes API access, or the manual Helm deployment path | Defender for Cloud → Environment settings → Security rules → Gated deployment → Misconfigurations |

For a multi-cloud deployment, enable Defender for Containers for the environment containing the cluster and the environment containing the registry. For example, an EKS cluster using ECR needs the AWS connector and the relevant Defender components enabled; a GKE cluster using Google Artifact Registry needs the equivalent GCP onboarding. The exact onboarding path changes by cloud, but the policy experience is centralised in Defender for Cloud.

### Choosing the deployment method

Microsoft supports automatic provisioning as well as a public Helm-based installation. The [Helm deployment documentation](https://learn.microsoft.com/en-us/azure/defender-for-cloud/deploy-helm?tabs=aks%2Cstandard) covers AKS, EKS and GKE and explains the trade-off: Helm gives you control over the sensor version and upgrade timing, while automatic provisioning follows Microsoft's rollout schedule.

I usually prefer the Helm-based installation even for standard, non-AKS-Automatic clusters. It makes the deployment method explicit, keeps the chart values with the platform configuration, and gives me a deliberate upgrade point. The price is that sensor upgrades become my responsibility.

For standard AKS, EKS and GKE clusters, the public instructions use the `mdc` namespace. AKS Automatic is the special case: gated deployment requires the sensor to be installed with Helm in `kube-system`; the add-on and an `mdc` installation are not supported for that scenario.

When using Helm, do not remediate the automatic-installation recommendations for the same cluster. That can create a second sensor deployment or conflicting resources. Treat Helm as the source of truth for that cluster's sensor lifecycle.

Before starting the manual installation, exclude the cluster from automatic sensor deployment. This is especially important when you want Helm to be the only sensor installation path: without the exclusion, Defender can deploy its own sensor while you are also installing and managing one with Helm.

For an Azure resource, merge the exclusion tag with the cluster resource:

```bash
# Exclude a cluster from automatic sensor deployment
# This disables automatic sensor provisioning for the cluster.
az tag update \
  --resource-id "$AZURE_RESOURCE_ID" \
  --operation merge \
  --tags "ms_defender_container_exclude_sensors=true"
```

> ⚠️ Apply this tag before automatic provisioning deploys the Defender sensor. The tag prevents future automatic deployment; it does not remove a sensor that is already installed. Check the current [Microsoft Learn exclusion guidance](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-exclude-cluster?tabs=aks) for supported cluster types and limitations. Keep in mind that taking ownership of installation and upgrades with Helm also means you are responsible for maintaining the sensor lifecycle.
{: .prompt-warning}

### Image gating setup

For image gating, enable these Defender for Containers capabilities:

- `Defender sensor` with `Security Gating` for the cluster;
- `Registry Access` for the registry; and
- `Security Findings` so vulnerability assessment artifacts are available.

After the prerequisites are met, Defender creates a default audit rule for high or critical vulnerabilities. The rule is configured under **Vulnerability assessment**. Select **Add rule**, choose `Audit` or `Deny`, define the cloud and resource scope, add vulnerability conditions, and optionally configure missing-artifact behaviour, CVE exemptions and resource exemptions.

For AKS configured through the managed cluster API, the gated deployment agent needs read access to the ACRs used by the cluster. The documented pattern is a user-assigned managed identity with `AcrPull` or equivalent read permissions, an AKS Workload Identity federated credential, and the identity referenced in the cluster's security-gating configuration. The federated subject is the Defender admission controller service account:

```text
system:serviceaccount:kube-system:defender-admission-controller-serviceaccount
```

### Misconfiguration setup

For misconfiguration enforcement, first enable Defender for Containers and make sure the cluster supports Kubernetes `ValidatingAdmissionPolicy`. The documentation states that Kubernetes `1.30` and later enable this capability by default. The current software supply-chain support matrix lists the Defender misconfiguration gate as GA for AKS, EKS, GKE and Azure Arc-enabled Kubernetes.

The portal path is **Security rules → Gated deployment → Misconfigurations**. Defender creates **Default K8s misconfiguration rule** in `Audit` mode. You can edit that default policy to enable or disable individual rules, configure supported parameters and change the action to `Block`. Or select **Create new policy** to define a custom policy with its own scope, rules, parameters and action.

For a manually installed sensor, the public [Microsoft Learn documentation](https://learn.microsoft.com/en-us/azure/defender-for-cloud/kubernetes-misconfiguration-enforcement#manually-enable-misconfiguration-enforcement-with-helm) documents the following Helm value for enabling the feature:

```bash
--set defender-admission-controller.enableMisconfigurationPolicies=true
```

After the chart is installed, the policy objects are created in the cluster and the portal policy is translated into Defender policy templates, parameter resources, `ValidatingAdmissionPolicy` objects and bindings. That is the point where the feature stops being only a portal setting and becomes inspectable Kubernetes state.

You need `Security Admin` or higher permissions to create or change the image-gating rules. For misconfiguration enforcement, the documented requirement is `Subscription Owner` or `Security Admin` to enable and manage deployment-time policies. `Security Reader` is sufficient for viewing rules and monitoring information.

> Start both features in audit mode. The image gate can introduce a short deployment delay while the image is evaluated, and misconfiguration blocking can reject workloads that were previously accepted by the cluster. Narrow the scope to a test cluster or namespace before expanding it.
{: .prompt-tip}

## 🚦 Two gates, two different questions

The high-level flow looks like this:

```text
                                      ┌──────────────────────────┐
                                      │ Kubernetes API request   │
                                      └─────────────┬────────────┘
                                                    │
                 ┌──────────────────────────────────┴─────────────────────────────────┐
                 │                                                                    │
                 ▼                                                                    ▼
      ┌──────────────────────┐                                           ┌────────────────────────┐
      │ Container image       │                                           │ Kubernetes object     │
      │ + image digest        │                                           │ + workload settings  │
      └──────────┬───────────┘                                           └───────────┬────────────┘
                 │                                                                   │
                 ▼                                                                   ▼
      ┌──────────────────────┐                                           ┌────────────────────────┐
      │ OCI findings artifact│                                           │ VAP + binding         │
      │ CVEs and signature   │                                           │ misconfiguration rule │
      └──────────┬───────────┘                                           └───────────┬────────────┘
                 │                                                                   │
                 ▼                                                                   ▼
      ┌──────────────────────┐                                           ┌────────────────────────┐
      │ Image gated          │                                           │ Kubernetes             │
      │ deployment check     │                                           │ misconfiguration check│
      └──────────┬───────────┘                                           └───────────┬────────────┘
                 │                                                                   │
                 └──────────────────────────────┬────────────────────────────────────┘
                                                ▼
                              ┌────────────────────────────────┐
                              │ Admission decision              │
                              │ ✅ Allow  ℹ️ Audit  ⛔ Block     │
                              └────────────────────────────────┘
```

The image gate asks:

> Does this image have vulnerability findings that match the rule?

The misconfiguration gate asks:

> Does this Kubernetes object violate one of the enabled security rules?

Both can run in `Audit` mode first and move to `Deny` or `Block` once the impact is understood. They are related operationally, but they are not the same policy engine and should not be debugged in exactly the same way.

## 🛡️ Blocking vulnerable container images

Defender for Containers scans images in supported registries and associates vulnerability findings with the image. When a user or CI/CD pipeline submits a workload, the gated deployment component evaluates the image before Kubernetes admits it.

The decision is based on the configured rule. For example, a rule could audit or deny images with high or critical vulnerabilities, apply only to a particular cluster or namespace, exempt a specific CVE, or block images when no valid findings artifact exists.

There is an uncomfortable reality here: a static rule such as “block every high or critical CVE” is not always safe to apply everywhere. A business-critical service may legitimately depend on an image that currently contains a high-severity vulnerability. Blocking its next deployment could prevent an urgent configuration change, interrupt a recovery action, or stop the business from shipping a required fix.

> Severity is an important signal, but it is not the whole decision. The practical risk depends on factors such as exploitability, whether the vulnerable code path is reachable, internet exposure, the workload's blast radius, the service's business criticality, the availability of a fix and the compensating controls around it. The right question is often not simply “does this image have a high CVE?” but “what risk do we accept by allowing this image to run here, for how long, and under which conditions?”
{: .prompt-warning}

This is why gated deployment supports both resource scoping and exemptions. A rule can be limited to a cluster, namespace or other resource scope, while a narrowly defined exemption can allow a specific vulnerability or resource to proceed. Time-bound exemptions are particularly useful for emergency releases: they make the exception visible and give it an expiry instead of turning a temporary workaround into a permanent hole.

The same trade-off exists in CI/CD image gates. Pipeline enforcement happens earlier, which is excellent for preventing vulnerable images from progressing, but teams sometimes need enough flexibility to push an image while a remediation is in progress. Runtime gating adds another control point close to the cluster. It does not remove the need for judgement; it gives you a second opportunity to apply the decision using the actual deployment scope and business context.

> A useful rollout is usually more precise than “block high and above everywhere”: start with audit, scope the rule to the workloads where the risk reduction is highest, define a documented exemption process, and use expiry dates for temporary exceptions.
{: .prompt-tip}

The last option is worth calling out. A missing scan result is not automatically the same as a clean image. It may mean the image has not been scanned yet, the registry is unsupported, or the Defender findings artifact was not published. You need to choose whether that should be allowed, audited, or blocked in your environment.

The basic deployment-time path is:

1. Defender scans the image in a supported registry.
2. Vulnerability findings are published and associated with the image.
3. A deployment request reaches the Kubernetes API server.
4. The Defender admission component retrieves and validates the findings artifact for the image digest, then evaluates it against the gated deployment rule.
5. The request is allowed, audited, or denied.

> The ordering is important. The admission controller checks the registry-side vulnerability artifact first; it is not waiting for the node to start the container before making the decision. 
{: .prompt-info}

If the artifact is valid and no gated-deployment policy blocks the image, the admission request continues. Kubernetes can then schedule the pod, and the node's container runtime pulls the image layers before starting the container. If the artifact or policy check fails, the request is rejected before that normal node-side image pull and pod start can happen.

In the admission-controller activity, the registry verification call can show a user agent similar to:

```text
ratify+unknown (linux/amd64)
```

That points at **Ratify**, a CNCF- and Microsoft-originated supply-chain verifier. Ratify resolves OCI referrers and validates attached supply-chain information such as Notation or Cosign signatures, SBOMs and vulnerability attestations. In the Defender image-gating flow, this is the bridge between the image digest in the deployment request and the signed findings artifact stored alongside it.

Ratify is also used more broadly as an external data provider behind Gatekeeper in Kubernetes supply-chain scenarios. That should not be confused with the misconfiguration path described later in this post: Defender's newer misconfiguration enforcement uses native `ValidatingAdmissionPolicy` objects, while the image gate has its own admission and artifact-verification flow.

In simplified form:

```text
  API request
      │
      ▼
  Defender admission controller ──► retrieve findings artifact
      │                              evaluate CVEs and policy
      │
      ├── blocked ──► Forbidden; no pod admission
      │
      └── allowed ──► Kubernetes schedules pod
                              │
                              ▼
                       Node pulls image layers
                              │
                              ▼
                       Container starts
```

For AKS, EKS and GKE, the current support matrix lists gated deployment as generally available for Kubernetes version `1.31` and later. The image registry is important as well: the matrix calls out ACR for AKS, ECR for EKS, and Google Artifact Registry for GKE. Azure Arc-enabled Kubernetes clusters are also listed as supported.

The required pieces are the Defender sensor, Security Gating, Security Findings and Registry Access. For AKS, the managed identity and federated identity configuration must also allow the gated deployment agent to read the relevant ACRs. In other words, the admission decision can be perfectly configured and still fail to produce a useful result if the findings artifact cannot be read.

There is also a registry-side step that is easy to miss: Defender needs to publish the vulnerability assessment artifact that the gate evaluates. In the resource configuration, the relevant extension is `ContainerIntegrityContribution`. This is the resource-level equivalent of the `Security Findings` capability in the portal. The extension is enabled by default for Defender for Containers, but it is worth checking on the relevant subscription or registry resource if you are troubleshooting a missing artifact. Below is an example of the extension configuration in a subscription-level pricing resource for Defender for Containers:

```json
  "name": "Containers",
  "type": "Microsoft.Security/pricings",
  "properties": {
    "extensions": [
      {
        "name": "ContainerRegistriesVulnerabilityAssessments",
        "isEnabled": "True"
      },
      {
        "name": "AgentlessDiscoveryForKubernetes",
        "isEnabled": "True"
      },
      {
        "name": "AgentlessVmScanning",
        "isEnabled": "True",
        "additionalExtensionProperties": {
          "ExclusionTags": "[{\"key\":\"agentless scanning\",\"value\":\"exclude\"}]"
        }
      },
      {
        "name": "ContainerSensor",
        "isEnabled": "True",
        "additionalExtensionProperties": {
          "InstallationMethod": "AKSAddon",
          "AutoProvisioning": "true",
          "SecurityGatingEnabled": "True",
          "AntiMalwareEnabled": "True"
        }
      },
      {
        "name": "ContainerIntegrityContribution",
        "isEnabled": "False"
      }
    ],
    "enablementTime": "2025-11-10T14:14:23.4375354Z",
    "pricingTier": "Standard",
    "freeTrialRemainingTime": "PT0S"
```

The artifact is an OCI referrer associated with the image digest. This is why testing only with an image tag can be misleading: the tag may move, while the admission decision and the vulnerability report belong to a specific digest. In the registry, check the image's **Referrers** view and confirm that the vulnerability findings artifact and its signature are present.

Inside the cluster, the applied image policies can also be queried through the Defender resource types:

```bash
kubectl get securityartifactpolicies -o json
kubectl get securityartifactpolicies.defender.microsoft.com -o json
```

> A deployment that happens before the image scan has completed may not be gated. When troubleshooting, check the image digest in the registry and confirm that a signed vulnerability findings artifact exists before investigating the Kubernetes admission path.
{: .prompt-info}

The Defender documentation shows a typical blocked request as an admission error containing the image reference and the number of high-or-higher CVEs. In audit mode, the request is allowed and the scan continues in the background. That is a good rollout pattern: start narrow, collect the events, fix the rule scope and exemptions, and only then introduce blocking.

## 🧩 Kubernetes misconfiguration enforcement

The second gate is different. It does not primarily care whether the image contains a CVE. It evaluates the Kubernetes object itself.

The built-in rule set covers controls such as:

- Audit or block Kubernetes workloads with unsafe security configurations.
- Enforce non-root execution and approved user or group IDs.
- Prevent automatic mounting of Kubernetes API credentials.
- Block workloads from running in the default Kubernetes namespace.
- Prevent containers from sharing sensitive host namespaces, such as PID, IPC, or network.
- Restrict container images to trusted registries or approved patterns.
- Enforce CPU and memory limits.
- Require HTTPS for Kubernetes Ingress resources.
- Block privilege escalation and fully privileged containers.
- Require containers to use a read-only root filesystem.

Defender creates a default K8s misconfiguration rule in `Audit` mode. Custom policies can select rules, configure parameters and narrow the scope to subscriptions, clusters or namespaces. Once a policy is switched to `Block`, a non-compliant object is rejected before it becomes an admitted Kubernetes resource.

The important implementation detail is the enforcement object that appears in the cluster. On a current cluster, the Defender policy templates are translated into native Kubernetes `ValidatingAdmissionPolicy` objects and their associated bindings. Parameterised rules also have Defender custom resources that supply the parameter values.

When I inspected the cluster, the Defender CRDs made this relationship visible. The parameter CRDs had names such as `containercpuandmemorylimitsshouldbeparams.defender.microsoft.com`, `privilegedcontainersshouldbeavoidedparams.defender.microsoft.com` and `runningcontainersasrootusershouldbeparams.defender.microsoft.com`. The policy templates then showed both the built-in default rules and the custom `ps-block-misconfig` rules.

The policy-template list was especially useful because it showed the split between the default audit policy and the custom policies I had enabled for blocking. The generated names are not pretty, but they are useful evidence of what this cluster was actually running. Treat them as inspection output rather than stable names to build automation around.

That means the cluster contains objects which can be inspected with the normal Kubernetes toolchain:

```bash
kubectl get policytemplates.defender.microsoft.com
kubectl get validatingadmissionpolicies
kubectl get validatingadmissionpolicybindings
kubectl describe validatingadmissionpolicy <policy-name>
```

For a manual Helm installation, keep the admission-policy switch explicit. The current public documentation still instructs you to set this value, even if a particular chart version enables it by default.

Before running the command, confirm that Helm is installed, the cluster version and cloud-provider combination are supported, and the identity used by the Defender components has the required permissions and outbound connectivity. The exact values for the subscription, resource group, cluster name and region are environment-specific; the command below is a shape to adapt, not a complete universal installation.

```bash
helm upgrade --install defender-k8s \
  oci://mcr.microsoft.com/azuredefender/microsoft-defender-for-containers \
  --create-namespace \
  --namespace mdc \
  --set defender-admission-controller.enableMisconfigurationPolicies=true \
  --set global.cloudIdentifiers.Azure.subscriptionId="<subscription-id>" \
  --set global.cloudIdentifiers.Azure.resourceGroupName="<resource-group>" \
  --set global.cloudIdentifiers.Azure.clusterName="<cluster-name>" \
  --set global.cloudIdentifiers.Azure.region="<region>"
```

The chart reference and the remaining environment-specific Helm values come from the public [Defender for Containers sensor installation documentation](https://learn.microsoft.com/en-us/azure/defender-for-cloud/deploy-helm?tabs=aks%2Cstandard). Use `mdc` for standard AKS, EKS and GKE clusters, and `kube-system` for AKS Automatic.

The exact generated names are long and can change, but the pattern is useful. The default Defender policies and your custom policies are visible beside other admission policies. You can inspect which rules exist, which bindings are active, and whether a policy is configured for audit or block behaviour.

This also explains a potentially confusing observation. The image vulnerability path still uses the Defender admission component. The misconfiguration path can be represented by native `ValidatingAdmissionPolicy` and binding objects. Seeing both a Defender admission webhook and several Defender VAPs in the same cluster is therefore expected; they protect different things.

## ☁️ Why the multi-cloud angle matters

Historically, enforcing Kubernetes security best practices across AKS, EKS and GKE often meant stitching together Azure Policy, Gatekeeper, policy assignments and cloud-specific onboarding. That can work, but the operational model becomes less attractive as the number of clusters and cloud providers grows.

The cluster is the common denominator. Kubernetes receives the object, evaluates admission rules and decides whether the object is admitted. Using the Kubernetes admission APIs for the enforcement point makes the control easier to reason about across clouds in a more native way. The Defender policy is still configured in the portal, but the enforcement is now a Kubernetes-native construct rather than a Gatekeeper or Azure Policy object.

The current Defender support matrix lists Kubernetes misconfiguration enforcement as generally available for:

| Environment | Gated image deployment | Misconfiguration enforcement |
|---|---|---|
| AKS | GA on `1.31+` | GA |
| EKS | GA on `1.31+` with ECR | GA |
| GKE | GA on `1.31+` with Google Artifact Registry | GA |
| Azure Arc-enabled Kubernetes | GA | GA |

This does not mean Azure Policy or Gatekeeper have disappeared from Kubernetes security. They can still be used separately for governance, compliance reporting or other policy scenarios. The important change is that Defender's deployment-time misconfiguration gate no longer needs either of them to perform the actual admission decision.

> There is one important boundary to keep clear. **Defender for Cloud posture management based on recommendations is a separate capability.** If you want the Azure Policy-based Kubernetes recommendations and workload-hardening controls, you still need the Azure Policy Kubernetes add-on and its Gatekeeper component. The move to native `ValidatingAdmissionPolicy` applies to Defender's gated deployment misconfiguration enforcement; it does not remove the Azure Policy/Gatekeeper dependency from every Defender for Cloud posture-management scenario.
{: .prompt-warning}

> **Audit mode does not change this boundary.** You can run Defender's gated-deployment misconfiguration feature in `Audit` mode without using Azure Policy for that admission-time evaluation, but this does not populate or change Defender for Cloud posture-management recommendations. To get recommendation visibility for workload-hardening issues such as privileged containers, continue to use the Azure Policy Kubernetes add-on and its Gatekeeper-based evaluation.
{: .prompt-warning}

This gives us two different control paths:

| Control path | Enforcement or assessment mechanism |
|---|---|
| Defender gated deployment misconfiguration rules | Kubernetes `ValidatingAdmissionPolicy` and bindings |
| Defender for Cloud posture-management recommendations | Azure Policy Kubernetes add-on and Gatekeeper-based policy evaluation where required |

Keeping these paths separate avoids a common troubleshooting mistake: seeing an Azure Policy or Gatekeeper object in the cluster and assuming it is responsible for the new Defender gated-deployment rule, or removing Azure Policy while still expecting its posture recommendations to work.

## ⚙️ The advantages of native `ValidatingAdmissionPolicy`

The advantages are practical. The API server remains the enforcement boundary, policy state is inspectable with `kubectl` and Kubernetes RBAC, and CEL expressions evaluate the resource arriving at the API server. A rule about `securityContext`, resource limits or service-account token mounting is therefore close to the object it protects.

The audit-to-block rollout also leaves useful evidence on the resource. In my test, annotations identified the policy owner, rule name, resource kind, action, namespace, resource name and policy name. That is much easier to investigate than a vague “policy denied” message.

Most importantly for multi-cloud teams, the policy is not dependent on an Azure Policy assignment or a Gatekeeper installation being projected into a non-Azure cluster. EKS and GKE still have their own identity, connectivity and onboarding requirements, but the enforcement construct is recognisable to Kubernetes operators.

> Native admission does not remove the need for version and feature checks. `ValidatingAdmissionPolicy` is enabled by default on Kubernetes `1.30` and later according to the Defender documentation, while gated image deployment is currently listed for Kubernetes `1.31` and later. Check the provider-supported version before enabling a production block.
{: .prompt-warning}

## 🔍 Seeing the result in the cluster

The first check I reach for is whether the Defender components are actually running. A quick cluster-wide filter gives a useful first signal:

```bash
kubectl get pods -A | grep defender
```

This should show admission controller used for gated deployment and the known Defender sensor components to collect and publish telemetry.

```text
mdc  defender-admission-controller-58c5646d48-dtbsx                    1/1  Running  0             34m
mdc  microsoft-defender-collectors-ds-cx65c                            3/3  Running  0             42m
mdc  microsoft-defender-pod-collector-misc-6f79d97b88-b4t5h            1/1  Running  0             50d
mdc  microsoft-defender-pod-collector-virtual-kubelet-f75fcb668sx6zj   1/1  Running  0             50d
mdc  microsoft-defender-publisher-ds-zzbmt                             1/1  Running  2 (10m ago)   42m
```

The admission controller is the obvious component for deployment-time decisions. The collectors and publisher matter as well: a healthy admission pod does not by itself prove that telemetry collection or vulnerability findings publication is working. The restart count is worth checking too - a pod can be `Running` while still showing recent instability.

The next checks are the CRDs, policy templates and admission objects:

```bash
kubectl get crds | grep defender

# get policy templates (rules)
kubectl get policytemplates.defender.microsoft.com

# the then translated VAP policies
kubectl get validatingadmissionpolicies
kubectl get validatingadmissionpolicybindings
```

The final policy binding may then look like the below:

```shell
NAME                                                                                    POLICYNAME                                                                          PARAMREF                                                                            AGE
aks-managed-deny-svc-binding-wireserver-ip-binding                                      aks-managed-deny-svc-binding-wireserver-ip                                          <unset>                                                                             3d
aks-managed-enforce-kubernetes-endpoints                                                aks-managed-protect-kubernetes-endpoints                                            <unset>                                                                             6d
aks-managed-enforce-kubernetes-endpointslice                                            aks-managed-protect-kubernetes-endpointslice                                        <unset>                                                                             6d
default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.binding   default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.vap   */default-k8s-misconfiguration-policy.22ea7d22-e63b-48e5-a268-7edbca4ea05d-params   3d
default-k8s-misconfiguration-policy-container-images-should-be-deployed-only.binding    default-k8s-misconfiguration-policy-container-images-should-be-deployed-only.vap    */default-k8s-misconfiguration-policy.a1b2c3d4-5678-90ab-cdef-111111111111-params   3d
default-k8s-misconfiguration-policy-container-with-privilege-escalation-shoul.binding   default-k8s-misconfiguration-policy-container-with-privilege-escalation-shoul.vap   */default-k8s-misconfiguration-policy.f5a6b7c8-9012-34de-f012-666666666666-params   3d
default-k8s-misconfiguration-policy-containers-sharing-sensitive-host-namespa.binding   default-k8s-misconfiguration-policy-containers-sharing-sensitive-host-namespa.vap   */default-k8s-misconfiguration-policy.e4f5a6b7-8901-23cd-ef01-555555555555-params   3d
default-k8s-misconfiguration-policy-immutable-read-only-root-filesystem-shoul.binding   default-k8s-misconfiguration-policy-immutable-read-only-root-filesystem-shoul.vap   */default-k8s-misconfiguration-policy.d3e4f5a6-7890-12bc-def0-444444444444-params   3d
default-k8s-misconfiguration-policy-kubernetes-clusters-should-be-accessible.binding    default-k8s-misconfiguration-policy-kubernetes-clusters-should-be-accessible.vap    */default-k8s-misconfiguration-policy.a7b8c9d0-1234-56ef-0123-777777777777-params   3d
default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.binding   default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.vap   */default-k8s-misconfiguration-policy.c3d4e5f6-7890-12ab-cdef-666666666666-params   3d
default-k8s-misconfiguration-policy-kubernetes-clusters-shouldn-t-use-the-def.binding   default-k8s-misconfiguration-policy-kubernetes-clusters-shouldn-t-use-the-def.vap   */default-k8s-misconfiguration-policy.b1c2d3e4-1111-2222-3333-888888888888-params   3d
default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.binding   default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap   */default-k8s-misconfiguration-policy.c2d3e4f5-6789-01ab-cdef-333333333333-params   3d
default-k8s-misconfiguration-policy-privileged-containers-should-be-avoided.binding     default-k8s-misconfiguration-policy-privileged-containers-should-be-avoided.vap     */default-k8s-misconfiguration-policy.7b4f3d2e-1c0a-4b7f-b31b-9c9f4c0bf8a2-params   3d
default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.binding   default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.vap   */default-k8s-misconfiguration-policy.a1b2c3d4-5555-6666-7777-888899990000-params   3d
ps-block-misconfig-container-images-should-be-deployed-only.binding                     ps-block-misconfig-container-images-should-be-deployed-only.vap                     */ps-block-misconfig.a1b2c3d4-5678-90ab-cdef-111111111111-params                    3d
ps-block-misconfig-container-with-privilege-escalation-shoul.binding                    ps-block-misconfig-container-with-privilege-escalation-shoul.vap                    */ps-block-misconfig.f5a6b7c8-9012-34de-f012-666666666666-params                    3d
ps-block-misconfig-containers-sharing-sensitive-host-namespa.binding                    ps-block-misconfig-containers-sharing-sensitive-host-namespa.vap                    */ps-block-misconfig.e4f5a6b7-8901-23cd-ef01-555555555555-params                    3d
ps-block-misconfig-immutable-read-only-root-filesystem-shoul.binding                    ps-block-misconfig-immutable-read-only-root-filesystem-shoul.vap                    */ps-block-misconfig.d3e4f5a6-7890-12bc-def0-444444444444-params                    3d
ps-block-misconfig-kubernetes-clusters-should-be-accessible.binding                     ps-block-misconfig-kubernetes-clusters-should-be-accessible.vap                     */ps-block-misconfig.a7b8c9d0-1234-56ef-0123-777777777777-params                    3d
ps-block-misconfig-kubernetes-clusters-should-disable-automo.binding                    ps-block-misconfig-kubernetes-clusters-should-disable-automo.vap                    */ps-block-misconfig.c3d4e5f6-7890-12ab-cdef-666666666666-params                    3d
ps-block-misconfig-privileged-containers-should-be-avoided.binding                      ps-block-misconfig-privileged-containers-should-be-avoided.vap                      */ps-block-misconfig.7b4f3d2e-1c0a-4b7f-b31b-9c9f4c0bf8a2-params 


The old-fashioned admission-controller checks are still valuable for the image path:

```bash
kubectl get validatingwebhookconfigurations
kubectl describe validatingwebhookconfigurations "defender-admission-controller.mdc.svc"

kubectl get clusterrole defender-admission-controller-cluster-role
kubectl get clusterrole defender-admission-controller-resource-cluster-role
kubectl get clusterrolebinding defender-admission-controller-cluster-role-binding
kubectl get clusterrolebinding defender-admission-controller-cluster-resource-role-binding
```

If the webhook name differs, list the configurations as JSON and filter the service names for `defender` rather than guessing generated names.

For image gating, also inspect the Defender admission webhook configuration:

```bash
kubectl get validatingwebhookconfigurations -o json \
  | jq '.items[].webhooks[]
      | {name: .name,
         serviceName: .clientConfig.service.name,
         path: .clientConfig.service.path,
         port: .clientConfig.service.port}' \
  | grep -i -C 2 defender
```

The above will show the Defender admission webhook and its service configuration. The output looks like this:

```json
{
  "name": "defender-admission-controller.mdc.svc",
  "serviceName": "defender-admission-controller",
  "path": "/validate",
  "port": 443
}
```

When a deliberately non-compliant test pod is submitted, Kubernetes can return multiple validation warnings. That is useful because the default audit policy and custom block policy may both evaluate the object. A test pod with an unapproved image, no resource limits, a writable root filesystem and a mounted service-account token is a good way to see the controls overlap.

In one test, the response contained messages for missing CPU and memory limits, a mounted service-account token, a writable root filesystem, running as root and missing capability drops. That single request demonstrated an important operational detail: several rules can evaluate the same object, and the output tells you which policy and binding produced each warning.

For the image-gating test, use an image from a supported registry. For instance:

```text
<private-registry>.azurecr.io/ps-http-echo:<tag>
```

That keeps the test aligned with the registry access and findings-artifact path. Replace the placeholder with the real private registry and image digest, then confirm that Defender has published the signed vulnerability artifact before expecting the image rule to evaluate it.

The same behaviour appears even when deploying a very basic pod without adding any security settings. For example, a plain `ps-http-echo` pod produced audit warnings from the default policy and was then rejected by the custom blocking policy:

```shell
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.vap' with binding 'default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.binding': Service account token mounted at default path in "ps-http-echo". Set spec.automountServiceAccountToken to false
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.vap' with binding 'default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.binding': Projected service account token volume is not allowed in "ps-http-echo". Remove serviceAccountToken from projected volume sources
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap' with binding 'default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.binding': Required capability drops missing in "ps-http-echo". Failing container(s): ps-http-echo. Must drop: ALL or ALL
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.vap' with binding 'default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.binding': Container must run as non-root in "ps-http-echo". Set runAsUser to non-zero or runAsNonRoot to true
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.vap' with binding 'default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.binding': Resource limits missing in "ps-http-echo". Set resources.limits.cpu and resources.limits.memory
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-immutable-read-only-root-filesystem-shoul.vap' with binding 'default-k8s-misconfiguration-policy-immutable-read-only-root-filesystem-shoul.binding': Read-only root filesystem required in "ps-http-echo". Set securityContext.readOnlyRootFilesystem to true
Error from server (Forbidden): pods "ps-http-echo" is forbidden: ValidatingAdmissionPolicy 'ps-block-misconfig-kubernetes-clusters-should-disable-automo.vap' with binding 'ps-block-misconfig-kubernetes-clusters-should-disable-automo.binding' denied request: Service account token mounted at default path in "ps-http-echo". Set spec.automountServiceAccountToken to false
```

This output is a nice demonstration of the two actions in one request. The `default-k8s-misconfiguration-policy-*` bindings are reporting violations in `Audit` mode, while the `ps-block-misconfig-*` binding changes the final result to `Forbidden`. The pod never becomes an admitted workload.

I corrected some of the manifest settings and tried again with an image from my private ACR. This time I disabled automatic service-account token mounting and enabled a read-only root filesystem.

```bash
kubectl run ps-http-echo \
  --image <private-registry>.azurecr.io/ps-http-echo-py:latest \
  -n 1other \
  --restart=Never \
  --override-type=strategic \
  --overrides='{
    "spec": {
      "automountServiceAccountToken": false,
      "containers": [{
        "name": "ps-http-echo",
        "securityContext": {"readOnlyRootFilesystem": true}
      }]
    }
  }'
```

This time the request got further, but the result was still blocked but this time by the Defender image gate. The audit warnings from the default policy still appeared, but the final result was a `Forbidden` response because the image contained a high-severity CVE:

```shell
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.vap' with binding 'default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.binding': Resource limits missing in "ps-http-echo". Failing container(s): ps-http-echo. Set resources.limits.cpu and resources.limits.memory
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap' with binding 'default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.binding': Required capability drops missing in "ps-http-echo". Failing container(s): ps-http-echo. Must drop: ALL or ALL
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.vap' with binding 'default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.binding': Container must run as non-root in "ps-http-echo". Set runAsUser to non-zero or runAsNonRoot to true
Error from server: admission webhook "defender-admission-controller.mdc.svc" denied the request: <private-registry>.azurecr.io/ps-http-echo-py:latest:Image contains 1 high or higher CVEs, which is more than the allowed count of: 0
Verifier rule name: ps-block-medium-to-critical-images-in-specific-ns
```

This is the two-gate story in one deployment. The manifest fixes addressed some of the workload-level requirements, but the default audit policy still reported missing resource limits, dropped capabilities and non-root execution. Then the separate Defender image gate evaluated the private ACR image and blocked it because the configured rule allowed zero high-or-higher CVEs. Passing one gate does not automatically pass the next one.

If the request was blocked, the pod is not created and the node never pulls the image. If the request was allowed, the pod is admitted and the node can pull the image layers and start the container. The audit warnings are still present, but they do not prevent the pod from being admitted.

> Label the evidence correctly: an audit warning shows evaluation, a rejected request demonstrates blocking, and the presence of a `ValidatingAdmissionPolicy` alone does not prove that its binding is active or that the request matched its scope.
{: .prompt-tip}

## 📊 Monitoring the gates

Defender exposes admission activity for review directly in the portal, and the cluster audit trail gives another useful perspective. You can also use `CloudPolicyEnforcementEvents` to check policy evaluation and enforcement. This is useful in playbooks for enrichment and investigation.

```shell
CloudPolicyEnforcementEvents
| summarize Events = count() by bin(Timestamp, 1h), ActionType, AzureResourceId, ResourceKind, KubernetesNamespace, Reason
| extend ActionType = case(
    ActionType == "Audit", "ℹ️ Audit",
    ActionType == "Deny", "⛔ Block",
    "✅ Allow"
)
```

For image admission failures, `CloudAuditEvents` can help connect the Kubernetes request to the response status and annotations. Filtering for HTTP `403`, admission validation annotations and excluding legacy Gatekeeper messages helps separate Defender's admission result from older Azure Policy or Gatekeeper enforcement that may still coexist in a cluster:

```shell
CloudAuditEvents
| where Timestamp > ago(2d)
| extend ResponseCode = toint(RawEventData.ResponseStatus.code),
    ResourceName = tostring(RawEventData.ObjectRef.name),
    Namespace = tostring(RawEventData.ObjectRef.namespace),
    Annotations = tostring(RawEventData.Annotations)
| where OperationName == "create"
| where ResponseCode == 403
| where Annotations has "validation.policy.admission.k8s.io/validation_failure"
| where tostring(RawEventData.ResponseStatus.message) !contains "validation.gatekeeper.sh"
| project Timestamp, AzureResourceId, ResourceName, Namespace,
    ResponseCode, RawEventData, Annotations
```

If you then check the `Annotations` field, you can see the Defender admission result and the rule that triggered it. The `RawEventData` contains the full request and response, which is useful for troubleshooting.

```shell
"default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/owner": "MDC",
"default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/ruleName": "Least privileged Linux capabilities should be enfo",
"default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/resourceKind": "Pod",
"default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/action": "Audit",
"default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/namespace": "1other",
"default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/resourceName": "alpine",
"default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/policyName": "Default K8s misconfiguration policy"
```

The portal's Admission Monitoring view is useful for image gating because it shows the digest, violations, triggered rule, criteria and exemptions. Kubernetes objects and audit logs are more useful for misconfiguration scope or VAP binding problems.

## 🚀 A sensible rollout sequence

I would roll this out in layers:

1. Confirm the Kubernetes version and supported cluster configuration.
2. Confirm Defender sensor, registry access and security findings are working.
3. Enable misconfiguration policies in `Audit` mode.
4. Test representative workloads from the real deployment pipelines.
5. Review scope, parameters and exemptions.
6. Block one or two high-confidence controls first.
7. Expand the block policy once the exceptions are understood.

For vulnerable images, wait until the findings artifact is present for the test image. For misconfigurations, use a test namespace and deliberately create a small workload that violates several rules. This separates “the rule did not match” from “the rule matched but audit mode allowed the request”. Usually the scan happens quickly after the image is pushed, but the admission evaluation can be delayed if the findings artifact is not yet available. Here you could configure "Default Block" if no artifact is present, or "Default Allow" if you want to avoid blocking until the scan completes.

## ⚠️ Limitations and open questions

There are a few boundaries worth keeping in mind:

- **It only evaluates new admission requests.** A workload that was admitted before a rule was enabled is not automatically re-evaluated just because the policy has changed.
- **Audit mode is not posture management.** Audit events show that an admission policy evaluated a request, but they do not replace Defender for Cloud recommendations or provide the same workload-hardening visibility. Azure Policy and its Kubernetes add-on are still required for those recommendations.
- **The gates depend on supporting data and access.** Image enforcement depends on supported registries, vulnerability findings, registry access and the relevant Defender components. A missing artifact or connectivity problem can change the result or make troubleshooting difficult.
- **Kubernetes support matters.** Native `ValidatingAdmissionPolicy` support, provider versions, cloud-specific onboarding and the selected Defender chart all need to line up.
- **Helm changes the operating model.** Manual installation provides control over versions and upgrades, but the platform team now owns upgrades, health checks, rollback planning and avoiding conflicts with automatic provisioning.

The next questions I would like to see answered are how audit results could feed posture recommendations, whether Defender could offer one policy definition for both admission and posture views, and how policy drift could be surfaced across clusters. A unified model would make it easier to see not only that a workload was blocked, but also which existing workloads would fail if they were redeployed today.

## 🧭 Conclusion

Defender for Cloud gated deployment now gives Kubernetes teams two useful admission-time controls: block images based on vulnerability findings, and audit or block workloads that violate Kubernetes security practices.

The larger change for multi-cloud platforms is the misconfiguration path. With native `ValidatingAdmissionPolicy` objects, the enforcement point is the Kubernetes API server and the policy state is visible through Kubernetes itself. Defender no longer needs Gatekeeper or Azure Policy for this admission-time control, which is a better fit for teams managing AKS, EKS, GKE and Arc-connected clusters. That is the exciting bit: the control is no longer trapped in a cloud-specific policy layer.

The remaining work is the usual security engineering work - start with audit, make the scope precise, understand the exceptions, and only then turn on the block action.

My personal view is that this is a meaningful improvement to the layered security approach: Defender now brings security gates to deployment time as well as the existing assessment and monitoring layers. I would still like to see the Azure Policy dependency removed altogether for container posture management, with Defender for Cloud posture recommendations based on this newer misconfiguration-enforcement capability. That would give teams one Kubernetes-native source for both admission-time enforcement and posture visibility, instead of splitting those responsibilities across two policy mechanisms.

### Further reading

- [Gated deployment for Kubernetes container images](https://learn.microsoft.com/en-us/azure/defender-for-cloud/runtime-gated-overview)
- [Kubernetes misconfiguration enforcement](https://learn.microsoft.com/en-us/azure/defender-for-cloud/kubernetes-misconfiguration-enforcement)
- [Containers support matrix](https://learn.microsoft.com/en-us/azure/defender-for-cloud/support-matrix-defender-for-containers)
