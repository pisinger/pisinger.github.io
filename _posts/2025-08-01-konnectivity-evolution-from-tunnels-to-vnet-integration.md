---
title: Konnectivity Evolution - From Tunnels to VNet Integration
author: pit
date: 2025-08-01
categories: [Blogging]
tags: [azure, aks, kubernetes, konnectivity, kubelet, networking, security, admission-webhooks, control plane]
render_with_liquid: false
---

Hey there 🖖 - Have you ever wondered how a managed kubernetes `Control Plane` can reach into your cluster and execute commands, stream logs, or call webhooks without having direct network access to your nodes? 

This might seem tricky in cloud-managed Kubernetes platforms like GKE, EKS, or AKS where the worker nodes usually sit behind private IPs, NAT gateways, or firewalls in a customer-managed VNet, but in reality, it’s not 😅

> The key is a shift to a proxy-based architecture: Instead of the control plane reaching into the cluster, the cluster reaches out to the control plane - thanks to a component called **Konnectivity** service <https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/>.
{: .prompt-tip}

When managing your own Kubernetes clusters, it's possible to expose the kubelet API via `tcp:10250`, allowing direct communication between the control plane and the nodes. However, in provider-managed environments, this approach isn’t feasible due to strict security policies, network limitations, and because the control plane operating entirely within the provider's managed virtual network.

> Spoiler alert: The ability for the managed control plane to directly connect to cluster nodes is making a comeback with AKS's new API Server VNet Integration feature. But we’ll unpack that in more detail later in this blog 😊
{: .prompt-info}

## 🧭 The origin problem: Secure Control Plane to Node Communication

In Kubernetes, the control plane needs to initiate connections to worker nodes for operations like:

- kubectl exec
- kubectl logs
- kubectl port-forward
- Metrics and status scraping

Historically, direct connectivity to nodes was achieved through `SSH tunnels` or by exposing inbound ports on `tcp:10250`. While this method was acceptable for on-premises clusters, it introduced significant security and scalability concerns. In managed Kubernetes services such as AKS, GKE, or EKS, this strategy is generally impractical due to strict access controls and network isolation as mentioned above.

## 🚀 The Solution: Konnectivity

Konnectivity became the default method for control plane to node communication in Kubernetes 1.22, released in August 2021, replacing the older mechanisms such as direct kubelet API server proxying and SSH tunneling: <https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/>

> On AKS this has been available since October 2021, replacing the former `aks-link` and `tunnel-front` implementation: <https://github.com/Azure/AKS/blob/master/CHANGELOG.md#release-2021-10-28>
{: .prompt-info}

🔄 How It Works:

- A Konnectivity agent runs as a DaemonSet on each node or as a regular Pod, preferably on system nodes.
- The Agent is maintaining a persistent outbound connection to the Konnectivity Server in the control plane.
- This long-lived, multiplexed connection allows the API server to reach nodes (exec, logs, metrics, etc.) without inbound access.
- Requests are routed through the server to the agent, which then forwards them to the kubelet API (typically on tcp:10250).

![img-description](/assets/img/posts/konnectivity-evolution-from-tunnels-to-vnet-integration/aks-konnectivity-architecture.jpg)

💡For more information, check out <https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/connectivity/tunnel-connectivity-issues>

On AKS you can check for the Konnectivity Agent pods by running:

```bash
kubectl get pods -n kube-system -l app=konnectivity-agent
konnectivity-agent-69bd86f5f7-82rc5   1/1     Running
konnectivity-agent-69bd86f5f7-l9gpz   1/1     Running
```

The agent also comes with a default outbound allow `networkPolicy`, which allows it to communicate with the Konnectivity server in the control plane. This is crucial for maintaining the secure connection and ensuring that the API server can reach the nodes without needing direct inbound access. If you remove this policy, you can no longer run commands like `kubectl exec` or `kubectl logs` against your nodes, as the API server won't be able to reach the Konnectivity agent.

```bash
kubectl get networkpolicy konnectivity-agent -n kube-system 
```

> This Konnectivity-based setup is super network and firewall friendly, built for the cloud, and way more secure. You don’t need to mess with exposing node ports, setting up SSH access, or tweaking custom network rules for your VNet or NSGs. It’s basically plug-and-play and just works out of the box - no extra setup required 😊
{: .prompt-info}

## 🧩 Admission Controller Webhooks: Konnectivity used as well?

>Short answer: Yes, they do! 😊
{: .prompt-info}

When internal admission webhooks are deployed as services within the cluster, they are typically accessed via cluster DNS or service IPs. In managed k8s environments where the API server runs outside the cluster, the API server also leverages `Konnectivity` to securely reach these internal services. This ensures seamless communication without requiring direct network access to the cluster.

> With that in mind, deleting the above mentioned `networkPolicy` will also break Admission Controller Webhooks, which are essential for validating and mutating requests before they reach the API server. Without proper connection we then relying on the defined `failurePolicy` within the webhook configuration. For instance, having it defined as `ignore` would simply result in bypassing the webhook, while `fail` would cause the API server to reject requests that require webhook validation or mutation even while dealing with proper yaml configuration.
{: .prompt-warning}

```bash
kubectl get validatingwebhookconfigurations -o yaml
kubectl get mutatingwebhookconfigurations -o yaml
```

> Note: You can use Inspektor Gadget to monitor network traffic and confirm that the API server interacts with internal admission webhooks through Konnectivity. This should reveal outbound connections originating from the Konnectivity agent to the Admission Webhook service and its associated pods. <https://inspektor-gadget.io/docs/latest/gadgets/trace_tcp>
{: .prompt-tip}

```bash
kubectl gadget deploy
kubectl gadget version
kubectl gadget run trace_tcp:latest -n kube-system -p konnectivity-agent-xxxxxx --connect-only
```

> 💡Alternatively you could also `nsenter` into the Konnectivity Agent namespace and use `tcpdump` to capture traffic sent to the node, and to the webhooks.
{: .prompt-info}

## 🛡️ Security Benefits

- No need to expose node ports or open SSH.
- All traffic is authenticated and encrypted.
- Easier to comply with zero-trust networking principles.
- No difference in using Public or Private clusters

## ☁️ Cloud Provider Implementations

While implementation details can vary between cloud providers, the core principles remain consistent. AKS closely follows the standard Konnectivity setup as outlined on <https://kubernetes.io>, and GKE appears to adopt a similar approach. EKS, however, uses a more customized model that relies on the EKS Connector and VPC CNI instead of the default Konnectivity agent.

## 🔗 VNet Integration: The Comeback of Direct Control Plane to Node Communication

The introduction of `API Server VNet Integration` <https://learn.microsoft.com/en-us/azure/aks/api-server-vnet-integration> marks a major milestone in optimizing secure communication between the control plane and  kubelet API of the nodes.

By allowing selected operations to bypass the Konnectivity server, this feature reduces latency and streamlines the network architecture, especially for high-frequency tasks like exec and logs. With this enhancement, the managed control plane can now connect directly to the kubelet API on nodes using private IPs, eliminating the need for Konnectivity as an intermediary in these scenarios.

See below for how to enable this feature on an existing AKS cluster:

> Important: Once API Server VNet Integration is enabled, it becomes a permanent part of the cluster configuration. The feature cannot be disabled or rolled back.
{: .prompt-warning}

```powershell
az aks update --name "clusterName" --resource-group "resourceGroup" --enable-apiserver-vnet-integration --apiserver-subnet-id "apiserver-subnet-resource-id"
```

> While the API server can now directly access the kubelet API on nodes using private IPs and an internal load balancer, it's important to note that Admission Controller Webhook traffic still relies on Konnectivity. These webhooks require reverse connections from the control plane to the nodes, and Konnectivity continues to play a crucial role in securely enabling that communication path. Based on my own observations, this part of the setup appears to remain unchanged
{: .prompt-warning}

In practice, combining both technologies offers the best of both worlds:

- Control plane → Nodes (kubelet API): Direct access via private IPs and internal load balancer.
- Nodes → Control plane: Direct access to the API server using private IPs through the load balancer.
- Control plane → Admission Controller Webhooks: Still routed securely via the Konnectivity agent.

## Conclusion

By enabling direct access from the managed control plane to the kubelet API over private IPs, it brings AKS closer to the operational flexibility of self-managed clusters where exposing the kubelet API on tcp:10250 is straightforward. In the past, such direct communication wasn’t possible in cloud-managed environments due to network isolation which is one of the key reasons Konnectivity was introduced in order to securely bridge that gap. 😊
