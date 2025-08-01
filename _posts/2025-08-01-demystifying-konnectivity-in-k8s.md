---
title: Demystifying Konnectivity in k8s - Secure Control Plane to Node Communication"
author: pit
date: 2025-08-01
categories: [Blogging]
tags: [azure, aks, kubernetes, konnectivity, kubelet, networking, security, admission-webhooks]
render_with_liquid: false
---

Hey there 🖖 - Have you ever wondered how the Kubernetes `Control Plane` can reach into your cluster and execute commands, stream logs, or call webhooks without having direct network access to your nodes? This might seem tricky in cloud-managed Kubernetes platforms like GKE, EKS, or AKS where the worker nodes usually sit behind private IPs, NAT gateways, or firewalls in a customer-managed VNet, but in reality, it’s not 😅

> The key is a shift to a proxy-based architecture: Instead of the control plane reaching into the cluster, the cluster reaches out to the control plane — thanks to a component called **Konnectivity** service <https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/>.
{: .prompt-tip}

## 🧭 The origin problem: Secure Control Plane to Node Communication

In Kubernetes, the control plane needs to initiate connections to worker nodes for operations like:

- kubectl exec
- kubectl logs
- kubectl port-forward
- Metrics scraping

Traditionally, this was done using `SSH tunnels` or open inbound ports to the nodes on `tcp:10250`, which posed security and scalability challenges.

## 🚀 The Solution: Konnectivity

It became the default mechanism for control plane to node communication in Kubernetes 1.22, released in August 2021 by replacing the older direct kubelet API server proxy and SSH tunneling mechanisms.

On AKS we have it since October 2021 replacing the former `aks-link` and `tunnel-front` implementation: <https://github.com/Azure/AKS/blob/master/CHANGELOG.md#release-2021-10-28>

🔄 How It Works:

- A Konnectivity agent runs as a DaemonSet on each node or as a regular Pod, preferably on system nodes.
- The Agent is maintaining a persistent outbound connection to the Konnectivity Server in the control plane.
- This long-lived, multiplexed connection allows the API server to reach nodes (e.g., for exec, logs, or metrics) without inbound access.
- Requests are routed through the server to the agent, which then forwards them to the kubelet API (typically on tcp:10250).

![img-description](/assets/img/posts/demystifying-konnectivity-in-k8s/aks-konnectivity-architecture.jpg)

💡For more information, check out <https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/connectivity/tunnel-connectivity-issues>

On AKS you can check for the Konnectivity Agent pods by running:

```bash
kubectl get pods -n kube-system -l app=konnectivity-agent
konnectivity-agent-69bd86f5f7-82rc5   1/1     Running
konnectivity-agent-69bd86f5f7-l9gpz   1/1     Running
```

> This Konnectivity-based setup is super network and firewall friendly, built for the cloud, and way more secure. You don’t need to mess with exposing node ports, setting up SSH access, or tweaking custom network rules for your VNet or NSGs. It’s basically plug-and-play—it just works out of the box - no extra setup required 😊{: .prompt-info}

## 🧩 Admission Controller Webhooks: Konnectivity used as well?

Short answer: Yes, they do! 😊

When internal admission webhooks are deployed as services within the cluster, they are typically accessed via cluster DNS or service IPs. In managed k8s environments where the API server runs outside the cluster, the API server leverages `Konnectivity` to securely reach these internal services. This ensures seamless communication without requiring direct network access to the cluster.

> Note: You can use Inspektor Gadget to observe network traffic and verify that the API server communicates with internal admission webhooks via Konnectivity. While the requests to the Konnectivity Agent aren't directly visible due to already existing connection using this approach, you can inspect the outbound connections from the agent pod to the Admission Webhook service and its backing pods. <https://inspektor-gadget.io/docs/latest/gadgets/trace_tcp>
{: .prompt-tip}

```bash
kubectl gadget deploy
kubectl gadget version
kubectl gadget run trace_tcp:latest -n kube-system -p konnectivity-agent-xxxxxx --connect-only
```

> 💡Alternatively you could also `nsenter` into the Konnectivity Agent namespace and use `tcpdump` to capture traffic sent to the node, as well to the webhooks.
{: .prompt-info}

## 🛡️ Security Benefits

- No need to expose node ports or open SSH.
- All traffic is authenticated and encrypted.
- Easier to comply with zero-trust networking principles.
- No difference in using Public or Private clusters

## ☁️ Cloud Provider Implementations

While implementation details can vary between cloud providers, the core principles remain consistent. AKS closely follows the standard Konnectivity setup as outlined on <https://kubernetes.io>, and GKE appears to adopt a similar approach. EKS, however, uses a more customized model that relies on the EKS Connector and VPC CNI instead of the default Konnectivity agent.
