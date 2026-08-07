---
title: Defender for Containers - Blocking Kubernetes Misconfigurations with VAP
author: pit
date: 2026-08-05
categories: [blogging, tutorial]
tags: [defender-containers, kubernetes, misconfiguration, validatingadmissionpolicy, gated-deployment, aks, eks, gke, azure-policy, container-security]
render_with_liquid: false
---

A clean image does not make a safe deployment. The workload can still run as root, request a privileged container, share a host namespace, mount the service-account token it never needs, or ship without resource limits.

Defender for Containers now evaluates those misconfigurations at deployment time and can audit or block the object before the API server admits it. The implementation is Kubernetes-native: Defender translates its policy into `ValidatingAdmissionPolicy` objects and matching bindings. Each rule is a CEL expression evaluated in-process by the API server during the admission request; the binding decides whether a violation is audited or denied. No webhook, no policy controller in the request path.

> The obvious question is why this matters when the Azure Policy add-on and Gatekeeper already do admission control.
{: .prompt-warning}

The difference is where the decision is made. Gatekeeper is an external policy controller: the API server calls out over the network, waits for a verdict, and depends on that pod, its certificates and its network path staying healthy. When the webhook is unreachable, `failurePolicy` decides which way you fail — `Fail` blocks writes cluster-wide, `Ignore` admits everything silently. Neither is a good day.

VAP removes the choice. The evaluation runs inside the API server, so there is no hop, no certificate rotation, and no availability domain to lose. If the Defender component that manages the policies goes down, the policies already in the cluster keep enforcing.

> The trade-off is scope. Azure Policy also feeds compliance and posture assessment, so it reports on workloads that are already running. The VAP-based gate only decides on objects at admission time — it tells you nothing about what is already deployed in the cluster (yet). Deployment-time enforcement and retrospective posture visibility remain two separate mechanisms even while the Azure Policy Addon can also be used to block.
{: .prompt-info}

> FYI - The image gate is another mechanism, part of the gated deployment feature in Defender for Containers. It evaluates vulnerability findings associated with a container image, which requires a lookup against Defender's scan results — external state that CEL cannot reach from inside the API server. That gate therefore still runs as a validating admission webhook. I cover it in more detail in [Defender Containers - Gated Deployment - Blocking Vulnerable Container Images](https://pisinger.github.io/posts/defender-for-containers-gated-deployment-blocking-vulnerable-images).
{: .prompt-tip}

## 🧭 What the feature evaluates

The misconfiguration gate asks:

> Does this Kubernetes object violate one of the enabled security rules?
{: .prompt-info}

The built-in rule set covers familiar controls you may know already from the Azure Policy Addon such as:

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

Defender creates `Default K8s misconfiguration rule` in `Audit` mode. Custom policies can select rules, configure supported parameters and narrow scope to subscriptions, clusters, namespaces or labels. Changing the action to `Deny` rejects a non-compliant object before it becomes an admitted Kubernetes resource.

## ✅ Enable the Defender Plan and configure the misconfiguration policy

The following permissions are required to manage and view the misconfiguration policies:

- Enable and manage deployment-time enforcement policies: Subscription `Owner` or `Security Admin`.
- View policies and monitoring data: `Security Reader` or equivalent.

Before enabling the feature, confirm the following:

- ValidatingAdmissionPolicy is available on the cluster. The API is GA and enabled by default from Kubernetes 1.30 onward.
- Kubernetes API access is enabled for Defender for Containers. Without it, Defender cannot reconcile the misconfiguration policies into native `ValidatingAdmissionPolicy` and binding objects.

> Microsoft documents the plan settings below in the context of Gated Deployment. I enabled them here as well, on the assumption that both features run through the same admission path.
{: .prompt-info}

![img-description](/assets/img/posts/defender-containers-blocking-kubernetes-misconfigurations-vap/mdc-gated-deployment-plan-enablement.png)

Next go for Security Policy blade and create a new misconfiguration policy. The default policy is already in `Audit` mode, so you can start with that and then create a custom policy for blocking.

![img-description](/assets/img/posts/defender-containers-blocking-kubernetes-misconfigurations-vap/mdc-security-policies.png)

For my custom policy, I selected a few rules to block and for the rest I kept the default audit misconfiguration policy to handle the rest.

![img-description](/assets/img/posts/defender-containers-blocking-kubernetes-misconfigurations-vap/policy-misconfig-2.png)

## 🛠️ Manual Helm installation

Microsoft supports automatic provisioning as well as a public Helm-based installation. The Helm documentation covers AKS, EKS and GKE and states the trade-off directly: Helm gives you control over the sensor version and upgrade timing, automatic provisioning follows Microsoft's rollout schedule.

I usually prefer Helm even for standard, non-AKS-Automatic clusters. It makes the deployment method explicit, keeps the chart values next to the rest of the platform configuration, and gives me a deliberate upgrade point. The price is that sensor upgrades become my responsibility — including the ones I would rather Microsoft had shipped for me.

> For standard AKS, EKS and GKE clusters the public instructions use the `mdc` namespace. AKS Automatic is the exception: gated deployment requires the sensor to be installed with Helm in `kube-system`, and neither the add-on nor an `mdc` installation is supported there.
{: .prompt-info}

The two paths must not overlap. Before starting the Helm installation, exclude the cluster from automatic sensor provisioning, and do not remediate the automatic-installation recommendations afterwards. Without that exclusion, Defender can deploy its own sensor while you are managing a second one with Helm — two sensor deployments, conflicting resources, and no clear owner of the lifecycle. Pick Helm and make it the single source of truth for that cluster.

```bash
# Exclude a cluster from automatic sensor deployment
az tag update \
  --resource-id "$AZURE_RESOURCE_ID" \
  --operation merge \
  --tags "ms_defender_container_exclude_sensors=true"
```

> Apply the tag before automatic provisioning deploys the sensor. It prevents future automatic deployment; it does not remove a sensor that is already installed. See the [Microsoft Learn exclusion guidance](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-exclude-cluster?tabs=aks) for supported cluster types and limitations.
{: .prompt-warning}

Before running Helm, confirm that Helm is installed, the cluster version and cloud-provider combination are supported, and the Defender components have the required permissions and outbound connectivity. The exact values below are environment-specific (AKS, EKS, GKE, Arc) and should be adapted to the current installation documentation:

> --set defender-admission-controller.enableMisconfigurationPolicies=true
{: .prompt-info}

```bash
helm install defender-k8s \
  oci://mcr.microsoft.com/azuredefender/microsoft-defender-for-containers \
  --create-namespace \
  --namespace mdc \
  --set defender-admission-controller.enableMisconfigurationPolicies=true \
  --set global.cloudIdentifiers.Azure.subscriptionId="<subscription-id>" \
  --set global.cloudIdentifiers.Azure.resourceGroupName="<resource-group>" \
  --set global.cloudIdentifiers.Azure.clusterName="<cluster-name>" \
  --set global.cloudIdentifiers.Azure.region="<region>"
```

Keep the admission-policy switch explicit. The current public documentation still instructs you to set this value, even if a particular chart version enables it by default. Use `mdc` for standard AKS, EKS and GKE clusters, and `kube-system` for AKS Automatic. The auto provisioning sensor deployment has this enabled by default anyway, so the Helm switch is only relevant for manual installations.

## 🔍 Inspecting the generated policy state

Once the feature is enabled, the portal policy is translated into Defender policy templates, parameter resources and native `ValidatingAdmissionPolicy` (VAP) objects with their bindings. All of it lands in the cluster as ordinary Kubernetes objects, so the normal toolchain is enough to inspect the result.

Start cluster-wide and confirm the Defender pods are running. The admission controller publishes policy updates and runs the image gate (see [Defender for Containers Gated Deployment - Blocking Vulnerable Container Images](2026-08-04-defender-for-containers-gated-deployment-blocking-vulnerable-images.md)); the collectors and publisher handle the common defender telemetry collection and publishing:

```bash
kubectl get pods -A | grep defender
```

An example from my test cluster:

```shell
mdc  defender-admission-controller-58c5646d48-dtbsx                    1/1  Running  0             34m
mdc  microsoft-defender-collectors-ds-cx65c                            3/3  Running  0             42m
mdc  microsoft-defender-pod-collector-misc-6f79d97b88-b4t5h            1/1  Running  0             50d
mdc  microsoft-defender-pod-collector-virtual-kubelet-f75fcb668sx6zj   1/1  Running  0             50d
mdc  microsoft-defender-publisher-ds-zzbmt                             1/1  Running  2 (10m ago)   42m
```

> Note: The admission controller is not in the request path for the `misconfiguration` gate. That gate runs on `ValidatingAdmissionPolicy` objects and their bindings, evaluated by the API server itself — the pod can be unavailable and the policies still enforce. What it does affect is the image gate, which is webhook-based, and policy reconciliation: if it is down, existing policies keep applying but stop being updated. Worth internalising, because it inverts the intuition from Gatekeeper.
{: .prompt-tip}

To check the generated policy state, list the Defender CRDs, the policy templates, and the translated VAP objects and their bindings run the below commands:

```bash
kubectl get crds | grep defender

# get policy templates (rules)
kubectl get policytemplates.defender.microsoft.com

# the translated VAP policies
kubectl get validatingadmissionpolicies
kubectl get validatingadmissionpolicybindings

kubectl describe validatingadmissionpolicy <policy-name>
```

When I inspected my cluster, the Defender CRDs made this relationship visible. The parameter CRDs had names such as `containercpuandmemorylimitsshouldbeparams`, `privilegedcontainersshouldbeavoidedparams` and `runningcontainersasrootusershouldbeparams`. The policy templates then showed both the built-in default rules and the custom `ps-block-misconfig` rules.

The policy-template list was especially useful because it showed the split between the default audit policy and the custom policies I had enabled for blocking. The generated names are not pretty, but they are useful evidence of what this cluster was actually running. Treat them as inspection output rather than stable names to build automation around.

The generated names can be long and can change, but their relationship is useful. You may see something like below:


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
```

> Optional: For the image gate, inspect the admission `webhook` and its RBAC objects too, but as stated before, this is not in the path for misconfiguration evaluation where evaluation is done by the API server itself. The webhook is only used for image evaluation, which requires a lookup against Defender's scan results.
{: .prompt-info}

```bash
kubectl get validatingwebhookconfigurations
kubectl describe validatingwebhookconfigurations "defender-admission-controller.mdc.svc"

kubectl get clusterrole defender-admission-controller-cluster-role
kubectl get clusterrole defender-admission-controller-resource-cluster-role
kubectl get clusterrolebinding defender-admission-controller-cluster-role-binding
kubectl get clusterrolebinding defender-admission-controller-cluster-resource-role-binding

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

## 🧪 Testing audit and block behaviour

When a deliberately non-compliant pod is submitted, Kubernetes can return several validation warnings. In my test, the default audit policy reported missing CPU and memory limits, a mounted service-account token, a writable root filesystem, running as root and missing capability drops. A custom policy then rejected the request:

```shell
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.vap' with binding 'default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.binding': Service account token mounted at default path in "ps-http-echo". Set spec.automountServiceAccountToken to false
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.vap' with binding 'default-k8s-misconfiguration-policy-kubernetes-clusters-should-disable-automo.binding': Projected service account token volume is not allowed in "ps-http-echo". Remove serviceAccountToken from projected volume sources
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap' with binding 'default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.binding': Required capability drops missing in "ps-http-echo". Failing container(s): ps-http-echo. Must drop: ALL or ALL
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.vap' with binding 'default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.binding': Container must run as non-root in "ps-http-echo". Set runAsUser to non-zero or runAsNonRoot to true
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.vap' with binding 'default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.binding': Resource limits missing in "ps-http-echo". Set resources.limits.cpu and resources.limits.memory
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-immutable-read-only-root-filesystem-shoul.vap' with binding 'default-k8s-misconfiguration-policy-immutable-read-only-root-filesystem-shoul.binding': Read-only root filesystem required in "ps-http-echo". Set securityContext.readOnlyRootFilesystem to true
Error from server (Forbidden): pods "ps-http-echo" is forbidden: ValidatingAdmissionPolicy 'ps-block-misconfig-kubernetes-clusters-should-disable-automo.vap' with binding 'ps-block-misconfig-kubernetes-clusters-should-disable-automo.binding' denied request: Service account token mounted at default path in "ps-http-echo". Set spec.automountServiceAccountToken to false
```

The default bindings reported violations in `Audit` mode, while the custom binding changed the final result to `Forbidden`. The pod never became an admitted workload. You can check the violations also in the Defender portal under `Environment → Security Rules → Admission Monitoring` as shown in the screenshot below:

![img-description](/assets/img/posts/defender-containers-blocking-kubernetes-misconfigurations-vap/policy-misconfig-in-action.png)

After correcting some workload settings, the request got further and finally deployed the pod. For this, I did run the below by setting `automountServiceAccountToken` to `false` and `readOnlyRootFilesystem` to `true` to satisfy the misconfiguration gate:

```bash
kubectl run ps-http-echo \
  --image <myregistry>.azurecr.io/ps-http-echo-py:latest \
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

The full response still showed audit warnings - if we would have an image gate as well, then the pod deployment would have been blocked if the image was vulnerable. The audit warnings are useful for troubleshooting and for understanding what the policy is checking, but they do not prevent the pod from being admitted.

```shell
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.vap' with binding 'default-k8s-misconfiguration-policy-container-cpu-and-memory-limits-should-be.binding': Resource limits missing in "ps-http-echo". Failing container(s): ps-http-echo. Set resources.limits.cpu and resources.limits.memory
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.vap' with binding 'default-k8s-misconfiguration-policy-running-containers-as-root-user-should-be.binding': Container must run as non-root in "ps-http-echo". Failing container(s): ps-http-echo. Set runAsUser to non-zero or runAsNonRoot to true
Warning: Validation failed for ValidatingAdmissionPolicy 'default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap' with binding 'default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.binding': Required capability drops missing in "ps-http-echo". Failing container(s): ps-http-echo. Must drop: ALL or ALL
pod/ps-http-echo created
```

> An audit warning shows evaluation, a rejected request demonstrates blocking, and the presence of a `ValidatingAdmissionPolicy` alone does not prove that its binding is active or that the request matched its scope.
{: .prompt-tip}

Also keep in mind how admission policies and webhooks are processed in Kubernetes. See below for a simplified order of evaluation. The image gate is a validating webhook, which is called after the in-process mutating and validating admission policies. If a mutating policy changes the image reference, the webhook will see the updated value.

1. MutatingAdmissionPolicy (CEL) — in-process, beta 1.34, gate off by default, v1 in 1.36
2. MutatingAdmissionWebhook — callout, serial, last mutator
3. Validating admission plugins (PodSecurity, NodeRestriction) — in-process, before VAP
4. ValidatingAdmissionPolicy (CEL) — in-process, GA 1.30
5. ValidatingAdmissionWebhook — callout, parallel
6. Persist — etcd

> This also means if there are any misconfigurations that prevent the pod from being admitted, the image gate will not be called at all as the request will be rejected before it reaches the webhook. The image gate is not a replacement for misconfiguration policies, it is an additional control point.
{: .prompt-warning}

## 📝 Summary of the admission control flow

### Policy distribution (once, at onboarding / policy change)

  - Defender for Containers holds the security misconfiguration policies in the backend and writes them to the cluster via the Kubernetes API.
  - The in-cluster Defender sensor component reconciles those policies into native `ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding` objects.
  - From that point the kube-apiserver enforces them natively. No in-cluster component sits in the admission request path.

```text
  ┌──────────────────────────────┐
  │  Defender for Containers     │   security misconfiguration policies
  │  (Defender backend)          │
  └──────────────┬───────────────┘
                 │ writes via kube-apiserver (needs Kubernetes API access)
                 ▼
  ┌──────────────────────────────┐
  │  PolicyTemplate CR           │   policytemplates.defender.microsoft.com
  │  (Defender-owned CRD)        │   the intent, in Defender's own schema
  └──────────────┬───────────────┘
                 │ watched and translated
                 ▼
  ┌───────────────────────────────┐
  │ Defender admission controller │   in-cluster, reconcile loop only
  │  (in-cluster pod)             │   NOT in the admission request path
  └──────────────┬────────────────┘
                 │ creates
                 ▼
  ┌──────────────────────────────┐
  │  ValidatingAdmissionPolicy   │   the CEL rule (what is checked)
  │  + Binding                   │   scope + action (Deny / Audit)
  └──────────────┬───────────────┘
                 │
                 └──► resident in the cluster, evaluated by kube-apiserver
```

### Deploy-time enforcement (every request)

  - A Kubernetes object is submitted to the API server.
  - The API server evaluates the `ValidatingAdmissionPolicy` objects and their bindings.
  - No webhook in the request path, no network hop, no external controller pod.
  - If a violation is found, the request is either audited or denied based on the binding's action.

```text
  ┌──────────────┐
  │ kubectl apply│  Pod: privileged: true
  └──────┬───────┘
         │
         ▼
╔══════ kube-apiserver ════════════════════════╗
║                                              ║
║   VAP evaluated in-process (CEL)             ║
║   no webhook, no network hop                 ║
║                                              ║
║        violates?                             ║
║        │                                     ║
║        ├── yes ──► BLOCKED (403 Forbidden)   ║
║        │                                     ║
║        └── no  ──► persisted to etcd         ║
║                                              ║
╚══════════════════════════════════════════════╝
                        │
                        ▼
                  scheduled & running
```

## ☁️ The Azure Policy and Gatekeeper boundary

This feature and Defender for Cloud posture management are separate capabilities. The gated-deployment misconfiguration feature can evaluate requests in `Audit` mode without Azure Policy for that admission-time evaluation.

That does **not** replace Azure Policy-based Defender for Cloud recommendations. If you want workload-hardening visibility and recommendations such as identifying privileged containers, you still need the Azure Policy Kubernetes add-on and its Gatekeeper-based evaluation.

This distinction matters because a cluster can show audit events from Defender's native admission policies while Defender for Cloud recommendations still depend on the Azure Policy path.

> My personal view: this is a meaningful addition to layered security. Defender now enforces more easily at deployment time, and it does so without an Azure Policy dependency in the admission path. What I would still like to see is the same shift applied to container posture management — Defender for Cloud recommendations built on this Kubernetes-native mechanism rather than on Azure Policy definitions. That would remove the last piece of friction.
{: .prompt-info}

## 📊 Monitoring the result

Defender surfaces admission activity in the portal under `Environment → Security Rules → Admission Monitoring`, while cluster audit data offers a second troubleshooting angle. That data lives in the `CloudAuditEvents` table in Defender Advanced Hunting, where you can correlate the Kubernetes request with its response and annotations:

```shell
CloudAuditEvents
| where Timestamp > ago(2d)
| extend ResponseStatus = (RawEventData.ResponseStatus)
| extend 
    ResponseMessage = tostring(ResponseStatus.message),
    ResponseCode = toint(RawEventData.ResponseStatus.code),
    ResourceName = tostring(RawEventData.ObjectRef.name),
    Namespace = tostring(RawEventData.ObjectRef.namespace),
    Annotations = tostring(RawEventData.Annotations)
| where OperationName == "create"
| where ResponseCode == 403
| where Annotations has "validation.policy.admission.k8s.io/validation_failure"
| where tostring(RawEventData.ResponseStatus.message) !contains "validation.gatekeeper.sh"
| project Timestamp, AzureResourceId, ResourceName, Namespace, UserAgent, ResponseCode, ResponseMessage, Annotations
```

The `ResponseMessage` field contains the admission controller's explanation of the violation:

> pods "ps-http-echo" is forbidden: ValidatingAdmissionPolicy 'ps-block-misconfig-kubernetes-clusters-should-disable-automo.vap' with binding 'ps-block-misconfig-kubernetes-clusters-should-disable-automo.binding' denied request: Service account token mounted at default path in "ps-http-echo". Set spec.automountServiceAccountToken to false
{: .prompt-warning}

The `Annotations` field can identify the policy owner, rule, resource and action. An observed event looked like this:

```json
{
  "default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/owner": "MDC",
  "default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/ruleName": "Least privileged Linux capabilities should be enforced",
  "default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/resourceKind": "Pod",
  "default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/action": "Audit",
  "default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/namespace": "1other",
  "default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/resourceName": "alpine",
  "default-k8s-misconfiguration-policy-least-privileged-linux-capabilities-shoul.vap/policyName": "Default K8s misconfiguration policy"
}
```

## ⚠️ Limitations and open questions

- The feature evaluates admission requests. Existing workloads are not automatically re-evaluated when a policy changes.
- `Audit` mode is NOT posture management and does not populate Defender for Cloud recommendations. This is still based on azure policy as of writing this post.
- Native `ValidatingAdmissionPolicy` support, provider versions, cloud onboarding and the selected Defender chart must line up.

The questions I would like to see answered are how audit results could feed posture recommendations, whether one policy definition could serve both admission and posture views, and how policy drift could be surfaced across clusters. A unified model would show not only that a workload was blocked, but also which existing workloads would fail if redeployed today.

## 🚀 A sensible rollout sequence

I would roll this out in layers:

1. Confirm the Kubernetes version and supported cluster configuration.
2. Confirm Defender sensor and admission controller health.
3. Enable misconfiguration policies in `Audit` mode or leverage those in `Deny` mode for the ones you had already covered via Azure Policy
4. Test representative workloads from the real deployment pipelines.
5. Review scope and policies.
6. Block one or two high-confidence controls first.
7. Expand the block policy once the exceptions are understood.

## 🧭 Conclusion

Defender for Containers misconfiguration enforcement adds a Kubernetes-native admission control for workload security settings. `ValidatingAdmissionPolicy` makes the policy state visible in the cluster and gives teams an audit-to-block path for controls that were previously easy to discover only after deployment.

The important operational boundary is that this does not (yet 🤔) remove Azure Policy from Defender for Cloud posture management. Today, the admission gate and the recommendation system remain separate control paths where the admission gate is directly shipped with the Defender sensor.

### Further reading

- [Kubernetes misconfiguration enforcement](https://learn.microsoft.com/en-us/azure/defender-for-cloud/kubernetes-misconfiguration-enforcement)
- [Gated deployment for Kubernetes container images](https://learn.microsoft.com/en-us/azure/defender-for-cloud/runtime-gated-overview)
- [Containers support matrix](https://learn.microsoft.com/en-us/azure/defender-for-cloud/support-matrix-defender-for-containers)
