---
title: How kubelet really knows what to do - The Tale of HTTP Watch
author: pit
date: 2025-07-03
categories: [Blogging]
tags: [kubernetes, k8s, container, basics, kubelet, kube-api]
render_with_liquid: false
---

Hey there 🖖 - Ever wondered how the **kubelet** - the well known small node agent in Kubernetes - keeps tabs on what pods to deploy? I did too, and thus decided to have a deeper look on it. Initially, I assumed it might use good old `HTTP long polling`, maybe even something fancier like `WebSockets` but the reality is as often different 😅

Instead, kubelet retrieves pod specs from the Kubernetes API server through a mechanism called **HTTP watch** (<https://kubernetes.io/docs/reference/using-api/api-concepts/#efficient-detection-of-changes>). Unlike long polling, which re-requests the resource every time and keeps the connection open until an update arrives (then repeats), HTTP watch is more efficient even while they share similarities. It uses the `watch` parameter in the API call, which streams resource updates as they happen that allows clients (kubectl or controllers) to subscribe to changes on resources.

> "In the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes." <https://kubernetes.io/docs/reference/using-api/api-concepts>.
{: .prompt-info}
> Also worth noting that HTTP watch is heavily used by the different k8s compents such as kube-scheduler or kube-controller-manager to efficiently monitor changes in the cluster to then react accordingly. WebSockets are also used in Kubernetes, but not for this purpose. They are primarily used for interactive sessions like `kubectl exec` or `port-forward`, where low-latency, bidirectional communication is essential. <https://kubernetes.io/blog/2024/08/20/websockets-transition/>
{: .prompt-tip}

## 👀How kubelet makes use of HTTP watch

Before we dive into how kubelet uses HTTP watch, let's clarify what kubelet is:

> On every node in a Kubernetes cluster runs the kubelet, a small but critical agent. Its job? To ensure the containers scheduled to a node are actually running and behaving as expected. This agent constantly checks the pod specs assigned to its node and talks to the container runtime to start or stop containers as needed. It also tracks pod health and reports back to the control plane. Without kubelet doing its rounds, your nodes would be blind to the orchestration above.
{: .prompt-info}

When kubelet starts, it needs to know which pods are assigned to its node. It does this by making an HTTP GET request to the Kubernetes API server with the `watch=true` query parameter. This tells the API server that kubelet wants to receive updates about changes to pods assigned to its node.

See the below example of how kubelet uses `HTTP watch` to keep track of pods assigned to its node. The important part is the `watch=true` query parameter, which essentially saying: "Hey, don’t just tell me what’s happening now, keep me posted."

```text
GET /api/v1/pods?fieldSelector=spec.nodeName%3D_name_&resourceVersion=5054847&timeoutSeconds=509&watch=true
```

When the watch request is made, the API server keeps the connection open and sends a stream of events. Each event includes the type of change (ADDED, MODIFIED, DELETED) and the resource object that was changed. This allows kubelet to react to changes in real-time. For example, if a new pod is scheduled to the node, kubelet will receive an ADDED event with the details of the new pod to then spin it up.

>💡To get a even clearer picture, let's give it a try with `kubectl` as you as a user can do the same by using `watch` to subscribe to changes like kubelet does 😊.
{: .prompt-tip}

For example, if you want to watch all pods in specific namespace, you can run the below - this will also show you the events such as ADDED, MODIFIED, and DELETED in real-time. To feel more like kubelet, go for the second command:

```shell
kubectl get pods -n test --watch --output-watch-events
kubectl get pods -A --field-selector spec.nodeName=<nodeName> --watch --output-watch-events
```

> So far so good, but how is a node assigned to a pod? For this we need to look at the role of the `kube-scheduler` and how it interacts with the API server and etcd.
{: .prompt-info}

When a new Pod is created, the process of deploying it involves several steps, and `HTTP watch` plays a crucial role in this workflow as we learned above. However, before the pod can be deployed, it must be assigned to a node. This is the role of the scheduler.

In fact, the **kube-scheduler** continuously watches for new pods that don't have an assigned node. When it detects a new pod, it evaluates the available nodes in the cluster based on resource availability, constraints like nodeSelector, and other scheduling policies. Once it finds a suitable node, it updates the Pod's specifications in etcd. When the Pod specs are updated, any active HTTP watches on the Pod resource are triggered. This notifies kubelet on the assigned node, to deploy the Pod.

> As you may have observed, the scheduler also uses an HTTP watch to monitor for any unassigned pods. It then updates the pod's specifications in etcd. This process is a crucial part of the Kubernetes control plane, ensuring that pods are efficiently scheduled and deployed throughout the cluster.
{: .prompt-info}

In essence, the scheduler ensures the Pod is assigned to the right node, updates etcd, and the HTTP watch mechanism ensures that the node is promptly informed to deploy the Pod.

## 🧠 Watch is a Verb

In Kubernetes, watch is a first class API verb - not just a query parameter. When you send a GET request with `?watch=true`, you are not just asking for data, you are subscribing to a live stream of events such as:

- ADDED: A new object was created
- MODIFIED: An existing object changed
- DELETED: An object was removed
- BOOKMARK: A lightweight event to mark progress

This stream is chunked and persistent, but not inifinite. It can expire, disconnect, or return a 410 Gone status if your resourceVersion is outdated.

For more information on verbs see <https://kubernetes.io/docs/reference/using-api/api-concepts/#api-verbs>.

Standard HTTP Verbs:

- GET: Retrieves data from a specified resource.
- HEAD: Similar to GET, but only retrieves the headers, not the body.
- POST: Submits data to be processed to a specified resource.
- PUT: Updates or creates a resource at a specified URI.
- DELETE: Deletes the specified resource.
- CONNECT: Establishes a tunnel to the server identified by the target resource.
- OPTIONS: Describes the communication options for the target resource.
- TRACE: Performs a message loop-back test along the path to the target resource.
- PATCH: Applies partial modifications to a resource.

Kubernetes Verbs:

- list: Retrieves a collection of resources.
- watch: Monitors changes to a resource and streams updates.
- create: Adds a new resource.
- update: Modifies an existing resource.
- patch: Applies partial updates to a resource.
- deletecollection: Deletes a collection of resources

## 👀Which resources are watched by kubelet?

The Kubelet watches several key resources to ensure it can manage the state of the node and the workloads running on it such as:

- Pods: Kubelet watches for changes to Pods assigned to its node. This includes creating, updating, and deleting Pods.
- ConfigMaps: These are used to manage configuration data for applications. The Kubelet watches for changes to ConfigMaps that are mounted as volumes in Pods.
- Secrets: Similar to ConfigMaps, Secrets store sensitive data such as passwords and tokens. The Kubelet watches for changes to Secrets that are used by Pods on its node.
- Nodes: Kubelet watches for changes to its own Node object to stay updated on its status and conditions.
- PersistentVolumeClaims: Kubelet watches for changes to PVCs that are used by Pods on its node to manage storage.

## 🔄 Resource Versions and Consistency

Every Kubernetes object has a `metadata.resourceVersion`. This is not a timestamp - it is an opaque string used to track changes. When you start a watch, you can specify a resourceVersion to resume from a known point. But if that version is too stale, the API server will say "nope" and force you to re-list.

To handle this, Kubernetes clients often:

- Start with a list to get current state
- Use the resourceVersion from that list to begin a watch
- Handle 410 Gone by repeating the process

This ensures strong consistency between client and server.

## 🧰Watch Cache: The API Server’s Memory Bank

Behind the scenes, the API server maintains a watch cache - an in-memory mirror of etcd. This cache serves most reads and watches, making them fast and efficient. It also helps with:

- Reducing etcd load
- Serving consistent snapshots
- Supporting progress notifications

## ⏳Does HTTP Watch Expire?

Short answer: Yes, HTTP watch connections can expire or be interrupted.

- Time limits: Most clusters impose a maximum duration for a watch - often around 5 minutes to prevent stale connections.
- Resource version too old: If you try to resume a watch using a resourceVersion that is no longer valid, the API server returns a 410 Gone error.
- Idle timeout or network hiccups: Connections can drop due to inactivity or transient network issues.

When a watch expires, the client must re-establish it by first listing the current state and then starting a new watch from the latest resourceVersion.

## 🧪Where Kubernetes actually utilizes WebSockets

Kubernetes does also make use of `WebSockets` but more selectively (<https://kubernetes.io/blog/2024/08/20/websockets-transition/>). The below scenarios now use WebSockets instead of the deprecated `SPDY` protocol for streaming:

- kubectl exec
- kubectl attach
- kubectl cp
- kubectl port-forward

These endpoints need low-latency, bidirectional streaming, which WebSockets handle perfectly.

> For most resource updates (like pod specs), Kubernetes still uses HTTP watch because it is simpler, more efficient for its purpose, and fits the declarative model of Kubernetes. WebSockets require a persistent, bidirectional connection. It is great for interactive sessions (like kubectl exec), but overkill for most control plane interactions.
{: .prompt-info}

See the below example of the upgrade request of a `kubectl exec` command that wants to use WebSocket:

```shell
kubectl exec -v=8 nginx -- date
GET https://127.0.0.1:43251/api/v1/namespaces/default/pods/nginx/exec?command=date…
Request Headers:
    Connection: Upgrade
    Upgrade: websocket
    Sec-Websocket-Protocol: v5.channel.k8s.io
    User-Agent: kubectl/v1.31.0 (linux/amd64) kubernetes/6911225
```

## Conclusion

I hope this dive into how kubelet uses HTTP watch to keep track of pods was insightful. Kubernetes is a complex system, but understanding the basics of how components like kubelet communicate can help demystify its inner workings 😊.
