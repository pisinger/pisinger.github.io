---
title: Sizing Event Hubs for the Defender Streaming API - TUs, Partitions and Tier Selection
author: pit
date: 2026-08-19
categories: [blogging]
tags: [event-hubs, defender-xdr, streaming-api, siem, azure, sizing, throughput-units, partitions]
render_with_liquid: false
---

Turning on the Defender XDR Streaming API is a five minute job. Pick a namespace, pick your tables, hit save, and Advanced Hunting events start landing in Event Hubs on their way to whatever reads them. The sizing decision you made in that same five minutes - `Standard`, one throughput unit, whatever partition count the portal defaulted to - is the one that bites on the first busy day.

What sits on the far side barely matters for this post. A SIEM, a data lake, a stream processor, a function app, your own consumer - they all pull through the same quotas, and the sizing model below is about the hub, not the receiver. Where consumer behaviour does change the answer I say so explicitly.

Event Hubs doesn't fail loudly. Ingress gets throttled with `ServerBusy`, egress quietly gets slower with no error at all, and the first symptom your SOC sees is the downstream running behind reality in exactly the window where that matters.

> Official sizing starting point, including the estimation query I pick apart below: <https://learn.microsoft.com/defender-xdr/streaming-api-event-hub>
{: .prompt-info}

```text
┌──────────────────────┐
│  Defender XDR        │  Streaming API / Raw Data Export
│  Advanced Hunting    │  batched JSON: { "records": [ ... ] }
└──────────┬───────────┘
           │  ingress ── bound by TU / PU / CU ──┐
           ▼                                     │
┌──────────────────────────────────────────┐     │ budget is
│ Event Hubs namespace                     │     │ namespace-level,
│  ┌────────────┐  ┌────────────┐          │◄────┘ NOT per hub
│  │ hub: Device│  │ hub: Email │   ...    │
│  │ p0 p1 … p31│  │ p0 … p7    │          │
│  └─────┬──────┘  └─────┬──────┘          │
└────────┼───────────────┼─────────────────┘
         │  egress = separate quota (2x ingress), shared by ALL consumers
         ▼               ▼
   ┌───────────┐   ┌───────────┐
   │ consumer  │   │ consumer  │  readers ≤ partitions
   │     A     │   │     B     │  own consumer group each
   └───────────┘   └───────────┘
   (SIEM, lake, stream processor, function app, ...)
```

## The decision in one page

Start with measured **peak bytes per second**, then check whether the tier can supply enough namespace throughput, partitions and observability. The rough decision path is:

| Situation | Starting point |
|---|---|
| Under 20-30 MB/s peak, no more than 10 hubs, consumer lag visible elsewhere | Standard |
| Approaching 40 MB/s, needing more than 10 hubs, or needing native consumer-lag telemetry | Compare Premium and Dedicated |
| Around 4-6 PUs without a zone-redundancy requirement | Price one Dedicated CU before adding another PU |
| Roughly 120-140 MB/s or more | Dedicated; Premium is near its practical edge |
| Zone redundancy is mandatory | Recalculate with Dedicated's three-CU floor rather than comparing one CU with Premium |

Those are routing thresholds, not purchase recommendations. Standard has enforced TU quotas; Premium and Dedicated publish approximate capacity ranges and need a representative load test.

I use four evidence labels throughout the post:

- **Documented limit** - an enforced quota such as 40 TUs or 32 partitions on a Standard hub.
- **Microsoft approximation** - expected throughput that varies with the workload, such as MB/s per PU, CU or partition.
- **Planning assumption** - the conservative value used in the worked examples.
- **Field observation** - something measured in my environment but not promised by Microsoft, such as ~128 KB batches or ten partitions on an auto-created hub.

## 📡 What actually lands in the hub

Be precise about the payload first, because it changes the answer. An Event Hubs message from the Streaming API carries a *list* of Advanced Hunting records, not a single row:

```shell
{
   "records": [
      {
         "time": "<time Defender XDR received the event>",
         "tenantId": "<tenant id>",
         "category": "<AH table name with 'AdvancedHunting-' prefix>",
         "properties": { <actual data - multi defender events as json> }
      }
   ]
}
```

The `category` field tells your consumer which table a record came from - which matters later for the one-hub-or-many question.

The consequence for sizing: the "events per second" number from Advanced Hunting counts **records**, while what the Event Hubs docs call an *ingress event* is one **message** - the whole batch, chunked into 64 KB units. Treating them as the same unit is the fastest way to buy four times the capacity you need, or a quarter of it. How much batching you get is a thing to measure, not assume.

Note that the batching is Defender's, not Event Hubs'. An event hub is an append log - it stores publications verbatim and serves them back unchanged, never parsing that `records` array. So the batch size is decided by a producer you don't configure and Microsoft doesn't document.

## 🧮 The official sizing query, and where it under-reports

Microsoft ships a query for this, under [Estimating initial Event Hub capacity](https://learn.microsoft.com/defender-xdr/streaming-api-event-hub#estimating-initial-event-hub-capacity) on the streaming setup page, and it's a reasonable starting point:

```shell
let bytes_ = 1000;
union withsource=MDTables Device* // e.g. Device*, EmailEvents, ...
| where Timestamp > startofday(ago(7d))
| summarize count() by bin(Timestamp, 1m), MDTables
| extend EPS = count_ /60 
| summarize avg(EPS), estimatedMBPerSec = avg(EPS) * bytes_ / (1024*1024) by MDTables, bin(Timestamp, 3h)
| summarize avg_EPS=max(avg_EPS), estimatedMBPerSec = max(estimatedMBPerSec) by MDTables
| sort by toint(estimatedMBPerSec) desc
| project MDTables, avg_EPS, estimatedMBPerSec
//| render columnchart
```

Read the first line again: `bytes_ = 1000`. Every table is assumed to average 1 KB per record - roughly right for `DeviceLogonEvents`, quite wrong for `DeviceProcessEvents` with long command lines. Measure it instead:

```shell
DeviceProcessEvents
| where Timestamp > ago(14d)
| summarize avgBytes = avg(estimate_data_size(*)), p95Bytes = percentile(estimate_data_size(*), 95)
```

Then re-run the sizing query per table with that value. Microsoft's own caveat on the [MDE streaming page](https://learn.microsoft.com/defender-endpoint/api/raw-data-export-event-hub#the-schema-of-the-events-in-azure-event-hubs): data transferred to Event Hubs **can exceed** what `estimate_data_size()` reports, because the JSON envelope, the prefixed category and the added `MachineGroup` decoration are overhead the Kusto function never sees.

> The query also averages EPS per 3-hour bin before taking the max, which smooths away exactly the peaks you need to see. Size on that number and you have sized for the calm hours. More on that in the next section.
{: .prompt-info}

### Why bytes per message decides which limit bites first

One throughput unit entitles the whole namespace to the following, per the [scalability guide](https://learn.microsoft.com/azure/event-hubs/event-hubs-scalability#throughput-units):

| Direction | Rate limit | Per minute | Event limit | Whichever comes first |
|---|---|---|---|---|
| Ingress | 1 MB/s | 60 MB/min | 1,000 events/s | Yes |
| Egress | 2 MB/s | 120 MB/min | 4,096 events/s | Yes |
| Storage | 84 GB | - | - | - |

Both directions carry that *or* clause, and it's where sizing goes wrong in both directions:

| Avg bytes per message | Binding limit at 1 TU | Effective ceiling |
|---|---|---|
| 200 bytes | events/sec | 1,000 msg/s = ~0.2 MB/s (80% of the MB budget wasted) |
| 1 KB | balanced | 1,000 msg/s = ~1 MB/s |
| 64 KB | MB/sec | ~16 msg/s |
| ~128 KB (measured in my lab) | MB/sec | ~8 msg/s |
| ~1 MB batch | MB/sec | ~1 msg/s |

Because the Streaming API batches, real Defender traffic sits far down that table - MB-bound, not message-bound. So "40,000 records/sec, therefore 40 TUs" is the wrong calculation. Size on megabytes, then verify with one division in Azure Monitor: `IncomingBytes` over `IncomingMessages` gives your actual average message size, and both carry an `EntityName` dimension so you can split it per hub.

### Reading the ceiling off a metrics chart

The per-minute column above is not decoration. Select `IncomingBytes`, set the time grain to **one minute**, and use **Sum**: each point is then bytes per minute. Hold the ceiling in the same unit and utilisation reads straight off the graph. At 4 TUs the ingress ceiling is 240 MB/min, so a point at 210 MB is at 87% of budget.

That unit choice pays off when you widen the date range. Preserve the one-minute time grain where the portal allows it. If Azure Monitor rolls the chart into wider buckets, use **Max** rather than **Average** to expose the busiest underlying interval. Check the displayed time grain before comparing a point with the `60 MB/min × TU` ceiling: a Max across rolled-up buckets and a one-minute Sum answer related but not interchangeable questions.

> Microsoft says the quiet part out loud in [Azure Monitor Metrics aggregation and display explained](https://learn.microsoft.com/azure/azure-monitor/metrics/metrics-aggregation-explained): "Min and Max indicate there are underlying anomalies while the Average and Sums lose that information as your time granularity goes up." Precisely the failure mode of the official sizing query binning EPS into three-hour averages. A one-minute `Sum` is the direct comparison with the TU ceiling; `Max` helps preserve the busiest underlying sample when the chart is rolled into wider intervals.
{: .prompt-info}

Make that a standing check rather than a diagnostic. `ThrottledRequests` and `QuotaExceededErrors` only tell you the wall has already been hit, an hour after the SOC started looking at stale data. Peak-minute `IncomingBytes` against `60 MB/min × TU` tells you how much room is left before it is.

> Don't reach for `ServerErrors` when you go looking for throttling. That metric counts requests the Event Hubs service itself failed to process - a fault, not a refusal - and throttling is very much a deliberate refusal. Throttling lands in `ThrottledRequests` and `QuotaExceededErrors`, both dimensioned by `OperationResult`. The `ServerBusy` string surfaces in the diagnostic error logs, where `OperationResult` is `ServerBusy` and the error code is `50013`. There used to be a dedicated **Server Busy Errors** (`SVRBSY`) metric carrying exactly this, but it's deprecated - so if you inherited a dashboard or alert rule built on it, that tile is quietly telling you nothing. All of it is in the [Event Hubs monitoring data reference](https://learn.microsoft.com/azure/event-hubs/monitor-event-hubs-reference).
{: .prompt-warning}

### How big is the batch, then?

No Microsoft page answers this. The streaming pages say only that each message contains a list of records; they document neither the batch size nor the record count. **Field observation:** in my lab, messages topped out around **128 KB** (`131,072` bytes) on a Basic namespace.

Treat it as a field observation rather than a contract, and note that it's a ceiling rather than a constant. Batching flushes on whichever trips first, the size cap or a maximum wait, so a storm produces full messages and a quiet Sunday produces 20 KB ones.

**None of which destabilises the sizing**, because bytes don't care how they're packaged. 20 MB/s is 20 MB/s whether it arrives as 160 full messages or 1,000 half-empty ones, and every number that decides the design - TUs, PUs, partition floors, retention - comes off the byte rate. The events-per-second quota would need messages below `1 MB/s ÷ 1,000 msg/s` = **1 KB** before it could bind, and even a thin 20 KB batch is twenty times past that. Measure the batch size to confirm you sit comfortably north of 1 KB per message, then stop thinking about it.

> For billing, an ingress event is a unit of data of 64 KB or less, so a 1 MB batch is billed as 16 events, and a 128 KB message is exactly two. The docs are explicit about pricing and silent on whether the 1,000 events/sec throttle counts the same way. Watch `ThrottledRequests` against your traffic rather than deriving throttling from the pricing definition.
{: .prompt-info}

## ⚡ Sizing for the spike, not the average

Defender telemetry isn't a flat stream. It tracks what people do, so it inherits the shape of the working day.

The obvious one is the morning login storm. A whole fleet powers on inside a 60-90 minute window and every device does the same expensive thing at once: `DeviceLogonEvents` on sign-in, a burst of `DeviceProcessEvents` as logon scripts, agents and browsers start, `DeviceImageLoadEvents` behind them, `DeviceNetworkEvents` as everything reconnects. Four of your highest-volume tables peak simultaneously, not in sequence.

A single-country tenant gets one brutal peak; a tenant spread across timezones gets a flatter curve because the storms stagger. That alone can change which tier you need, which is why a generic "MB/s per thousand devices" rule isn't worth much - distribution matters more than total. Add patch Tuesday, scheduled full AV scans, onboarding waves, and live IR work that piles on exactly when you least want the pipeline degraded.

Measure the ratio rather than guessing it:

```shell
let bytes_ = 2000;   // blended average record size across the tables you union
union Device*, Email*, Identity*, AlertInfo, AlertEvidence, CloudAppEvents, UrlClickEvents
| where Timestamp > ago(14d)
| summarize records = count() by bin(Timestamp, 1m)
| summarize
    median_MBps = percentile(records, 50) * bytes_ / (60 * 1024 * 1024),
    p99_MBps    = percentile(records, 99) * bytes_ / (60 * 1024 * 1024),
    peak_MBps   = max(records) * bytes_ / (60 * 1024 * 1024)
| extend peakToMedian = peak_MBps / median_MBps
```

### The reusable sizing model

For an initial estimate, keep the inputs and limits in the same units:

```text
peak ingress MB/s = peak records/min × measured bytes/record ÷ 60,000,000

Standard TUs = ceil(max(
  peak ingress MB/s,
  total peak egress MB/s ÷ 2
))

Standard partitions = ceil(max(
  peak ingress MB/s ÷ 1,
  peak egress MB/s ÷ 2,
  peak egress MB/s ÷ measured per-reader MB/s
))
```

The TU rates are **documented enforced limits**. The per-partition rates are **Microsoft approximations**, so the partition result is a conservative starting point rather than a guaranteed ceiling. Premium and Dedicated do not have an enforced throughput quota per PU or CU; start from Microsoft's ranges, then load-test representative payloads and consumers.

`peakToMedian` is the multiplier on everything the previous section told you - the factor between "sized for the average" and "sized to never throttle."

### Ingress spikes and egress spikes are different problems

This is the part that changed how I size these pipelines, and why that multiplier doesn't simply multiply your bill.

**Ingress throttling cannot be assumed to be recoverable.** When the namespace runs out of budget, Event Hubs returns `ServerBusy`, but Microsoft does not document whether the Defender Streaming API retries, buffers or drops the affected publication. I therefore treat throttling as potential data loss and size ingress for the measured peak.

**Egress lag is recoverable**, because an event hub is a buffer, not a pipe. A consumer falling behind during the login storm is fine as long as it burns the backlog down before the next one, so consumers can be sized between average and peak with retention absorbing the difference.

That makes retention a sizing parameter rather than only a compliance one: can the consumer drain a peak backlog before retention drops the oldest events? If not, diagnose the binding constraint. Add TUs when the namespace egress quota is pinned; add partitions and readers when parallelism is exhausted; fix the consumer or sink when neither Event Hubs limit is binding.

> [**Auto-inflate**](https://learn.microsoft.com/azure/event-hubs/event-hubs-auto-inflate) **is a scale-up-only feature** - It raises TUs when load crosses the threshold and leaves them there; scaling back down is a manual edit you have to remember. Billing takes the *maximum* TU count selected during each hour, so one 45-minute login storm can inflate the namespace and quietly bill at the new ceiling until somebody notices. It also reacts only *after* the threshold is crossed, which for a spike that short means the extra units arrive late and earn little. Set the upper limit as a cost stop, not a sizing strategy.
{: .prompt-warning}

## 📊 The limits that actually differ per SKU

The quotas that change the design, trimmed to the ones a Defender export pipeline actually runs into.

| Limit | Basic | Standard | Premium | Dedicated |
|---|---|---|---|---|
| Scaling unit | TU (max 40) | TU (max 40) | PU (1,2,4,6,8,10,12,16) | CU (1-10 self-service; larger through support) |
| Throughput per unit, enforced | 1 MB/s or 1,000 ev/s in; 2 MB/s or 4,096 ev/s out | same as Basic | No per-PU limit | No per-CU limit |
| Throughput per unit, approximate capacity | same as enforced | same as enforced | ~5-10 MB/s in, 10-20 MB/s out | ~100-200 MB/s ingress per CU* |
| Event hubs per namespace | 10 | 10 | 100 per PU | 1,000 |
| Partitions per hub | 32, immutable | 32, immutable | 100 (200 per PU namespace-wide) | 1,024 (2,000 per CU) |
| Dynamic partition scale-out | No | No | Yes | Yes |
| Consumer groups per hub | 1 (`$Default`) | 20 | 100 | 1,000 |
| Max retention | 1 day | 7 days | 90 days | 90 days |
| Retention storage included | 84 GB per TU | 84 GB per TU | 1 TB per PU | 10 TB per CU |
| Max message size | 256 KB | 1 MB | 1 MB | 20 MB |
| Capture | No | Priced separately | Included | Included |
| Availability zones | Yes | Yes, automatic | Yes, from 1 PU | 3+ CUs required |
| Runtime audit logs | No | No | Yes | Yes |
| Ingress events | `$0.028` per million 64-KB units* | `$0.028` per million 64-KB units* | Included | Included |
| Auto-inflate | No | Yes - scales up only, manual scale-down | No | No |

**Basic is out**, and not on throughput. One consumer group means a second reader needs a second namespace; 24-hour retention gives you nothing to absorb consumer lag with. Either is disqualifying on its own.

The [256 KB publication cap](https://learn.microsoft.com/azure/event-hubs/event-hubs-quotas#basic-vs-standard-vs-premium-vs-dedicated-tiers) is the softer objection now that I've measured the batches - ~128 KB clears it by exactly half - but that margin is an undocumented producer behaviour, not a guarantee. And the failure mode is hard: the quotas page states that the publication limit "applies regardless of whether it's a single event or a batch" and that oversized publications "are rejected", with Event Hubs raising [`MessageSizeExceededException`](https://learn.microsoft.com/azure/event-hubs/event-hubs-messaging-exceptions#exception-types) - against which Microsoft's own note is that retrying won't help. Nothing throttles, nothing queues, the publication is simply gone. Staking a telemetry pipeline on that to save half a throughput unit's price isn't a trade I'd take. Everything below assumes Standard or above.

Two more rows decide most architectures before cost enters the conversation: **10 event hubs per namespace** on Standard, and **runtime audit logs are Premium and above**.

The two throughput rows are the distinction worth holding onto. On Standard the quota is a **throttle** the service enforces, and you get `ServerBusy` when you cross it. On Premium and Dedicated there is no enforced per-unit rate at all - you're buying CPU and memory, and the capacity figures are Microsoft's approximations of what that yields, which is why they come with standing advice to load test rather than calculate.

Read the fine print on the Premium one. The ~5-10 MB/s is quoted for *one PU with a single event hub at 100 partitions* - the per-hub maximum. Run that same PU against a hub with eight partitions and you don't automatically lose an order of magnitude, but partition parallelism becomes a candidate for the binding constraint, especially once you add PUs without adding partitions. Microsoft's headline number already assumes you got the next section right, which is the point: on Premium and Dedicated, **partition count is one of the things that determines your throughput**, not a separate dial beside it.

> Canonical tier comparison - these numbers do move, so check it rather than this post: <https://learn.microsoft.com/azure/event-hubs/compare-tiers>
{: .prompt-info}

\* Basic and Standard ingress is billed per 64-KB unit: an event of 64 KB or less counts as one billable ingress event, while a 96-KB event counts as two. The `$0.028` figure is a reference price and varies by region, currency and agreement. Microsoft currently describes Dedicated capacity as approximately 100-200 MB/s ingress per CU and stresses workload dependence. For the calculations in this post, I use the more conservative planning benchmark of 100 MB/s inbound and 200 MB/s outbound per CU; validate it with a representative load test. The Event Hubs pricing page is the source of truth for a purchase estimate.

### The practical Premium boundary

Premium has a theoretical planning range of roughly `80-160 MB/s` when using the approximate `5-10 MB/s` ingress capacity per PU across the maximum 16 PUs. That is not an enforced per-PU quota, and actual throughput depends on producers, consumers, partitions, payload shape and resource allocation.

Microsoft positions Premium as often more cost-effective than Dedicated for event-streaming workloads up to **160 MB/s per namespace**. Read that as a broad workload guideline rather than a universal price crossover: the comparison changes with the PU count actually required, regional pricing, availability-zone requirements, partition layout and the throughput your workload achieves per PU.

For a production decision, I would keep the practical Premium ceiling around `120-140 MB/s` and load-test the real Defender Streaming API payloads before committing to the upper end. Above that range, I would move to a Dedicated cluster instead of designing Premium at its theoretical edge.

## 🧮 Worked throughput, partition and bill examples

The following calculations use decimal units: `1 MB = 1,000,000 bytes` and `1 GB = 1,000 MB`. Where EPS is shown, it assumes the stated size is the average logical event size. Defender Streaming API records arrive inside Event Hubs messages, so use measured batch size for the actual Event Hubs ingress-billing calculation.

| Scenario | Calculation | Ingress rate | Per minute | Approx. 12 hours |
|---|---|---:|---:|---:|
| 80,000 EPS at 1 KB | `80,000 × 1 KB` | 80 MB/s (640 Mbps) | 4,800 MB (4.8 GB) | 3.46 TB |
| 80,000 EPS at 10 KB | `80,000 × 10 KB` | 800 MB/s (6.4 Gbps) | 48,000 MB (48 GB) | 34.56 TB |
| 90,000 EPS at 2 KB | `90,000 × 2 KB` | 180 MB/s (1.44 Gbps) | 10,800 MB (10.8 GB) | 7.78 TB |
| 20 MB/s at 1 KB | `20 MB/s ÷ 1 KB` = 20,000 EPS | 20 MB/s (160 Mbps) | 1,200 MB (1.2 GB) | 0.86 TB |
| 20 MB/s with 40 MB/s peaks | `20-40 MB/s ÷ 1 KB` = 20-40k EPS | 20-40 MB/s (160-320 Mbps) | 1,200-2,400 MB | 0.86-1.73 TB |
| 70-90 MB/s at 1 KB | `70-90 MB/s ÷ 1 KB` = 70-90k EPS | 70-90 MB/s (560-720 Mbps) | 4,200-5,400 MB | 3.02-3.89 TB |

The first three rows start from a records-per-second figure and derive the byte rate; the last three start from a byte rate and derive the implied records per second. As a quick conversion, `100 MB/s = 800 Mbps`, and `1 MB/s = 60 MB/min`. The per-minute column is the one to compare against a metrics chart; the MB/s column is the one to compare against a TU count. These numbers describe the incoming stream; Sentinel/Log Analytics ingestion, DCR throughput, retention, Event Hubs egress and downstream processing are additional calculations.

### Standard's 40 MB/s boundary

Standard provides up to `1 MB/s` ingress per TU and the namespace can be configured with up to 40 TUs. That gives a theoretical namespace ceiling of:

```text
40 TUs × 1 MB/s = 40 MB/s ingress = 2,400 MB/min
```

This is an aggregate namespace limit, not a per-partition limit. Partitions still need to be sized for parallelism and distribution. Using Microsoft's approximate `1 MB/s` per-partition planning rate, 20 MB/s starts at 20 partitions and 40 MB/s at 40. A Standard Event Hub is limited to 32 partitions, so a single Standard hub is not a comfortable design for the 40-TU ceiling under that planning model. The rate is a load-testing starting point, not an enforced per-partition quota; the namespace can also spread the workload across multiple hubs, but that is an architectural split rather than extra namespace capacity.

| Scenario | Per minute | Partitions at peak* | Standard assessment |
|---|---:|---:|---|
| 20 MB/s sustained | 1,200 MB/min | 20 | Fits one Standard hub and 20 TUs |
| 20 MB/s, 40 MB/s peak | 1,200-2,400 MB/min | 40 | The planning model exceeds one hub's 32 partitions; 40 TUs required at peak |
| 40 MB/s sustained | 2,400 MB/min | 40 | At the theoretical Standard namespace ceiling; validate any single-hub design with a load test |
| 70 MB/s sustained | 4,200 MB/min | 70 | Exceeds the 40-TU Standard limit |
| 90 MB/s sustained | 5,400 MB/min | 90 | Exceeds the 40-TU Standard limit |
| 80-160 MB/s Premium planning range | 4,800-9,600 MB/min | 80-160 | Using the conservative 1 MB/s/partition model, Premium needs sharding above 100 partitions per hub; Dedicated is the cleaner option at the upper end |

\* These are the per-partition floors at peak, which is where Microsoft's guidance stops - choose at least as many partitions as peak load requires. They assume events spread evenly across partitions. The Premium/Dedicated row uses the conservative 1 MB/s per-partition planning rate; Microsoft documents approximately 1-2 MB/s ingress per partition for those tiers, so load-test before reducing the count. Partitions do not add TU/PU/CU allocation or incur a separate partition charge.

### Monthly Standard examples

These examples use the **field observation** of 128 KB per Defender message, 730 hours per month, `$0.028` per million 64-KB billing units, and an illustrative `$0.03` per TU-hour. The spike scenario assumes 40 TUs remain provisioned for the entire month; hourly scaling would produce a lower TU charge. These are Event Hubs-only examples: Sentinel/Log Analytics ingestion, retention, DCR processing, Capture, networking and downstream services are separate costs.

| Scenario | Monthly data | Messages at 128 KB | 64-KB billing units | Ingress charge | Plus TU charge |
|---|---:|---:|---:|---:|---:|
| 20 MB/s sustained | 52.56 TB | 410.6 M | 821.3 M | `$23.00` | `$461.00` |
| 20 MB/s sustained, 40 MB/s peak for 1 hour/day; 40 TUs provisioned all month | 54.72 TB | 427.5 M | 855.0 M | `$23.94` | `$899.94` |
| 40 MB/s sustained | 105.12 TB | 821.3 M | 1,642.5 M | `$45.99` | `$921.99` |
| 70 MB/s sustained | 183.96 TB | 1,437.2 M | 2,874.4 M | `$80.48` | Not feasible on Standard |
| 90 MB/s sustained | 236.52 TB | 1,847.8 M | 3,695.6 M | `$103.48` | Not feasible on Standard |

The actual batch size moves, so bound the result rather than defending one measurement. Ingress cost per terabyte across the modeled range is:

| Avg batch | 64-KB billing units per message | Ingress cost per TB |
|---|---:|---:|
| 1 KB - no batching at all | 1 | `$28.00` |
| 20 KB - modeled small batch | 1 | `$1.40` |
| 60 KB | 1 | `$0.47` |
| 65 KB | 2 | `$0.86` |
| 128 KB - what I measured | 2 | `$0.44` |
| 1 MB | 16 | `$0.45` |

Across the modeled 20-KB to 1-MB range, the span is `$0.44` to `$1.40` per TB. At 20 MB/s that is roughly `$23` to `$74` per month against `$438` of throughput units. Smaller messages can cost more, up to the `$28/TB` unbatched example in the first row. Batch size materially affects billing arithmetic, but not the capacity decision; the 64-KB boundaries merely make the cost curve a sawtooth.

These use the decimal convention stated at the top of this section. Reading both the batch and the billing unit as binary - `131,072` and `65,536` bytes - moves the totals by about 2% and changes none of the conclusions.

## 💰 Where the price curves cross

List prices, West Europe, USD, from an Azure retail price API snapshot at a 730-hour month. Treat these as a dated planning snapshot, not a universal quote; region, currency, offer and agreement can change the values. Verify them on the [Event Hubs pricing page](https://azure.microsoft.com/en-us/pricing/details/event-hubs/) before procurement.

| Unit | Per hour | Per month | Rough ingress | Cost per MB/s ingress |
|---|---|---|---|---|
| Standard TU | $0.030 | $21.90 | 1 MB/s | ~$22 |
| Premium PU | $1.336 | $975 | 5-10 MB/s | ~$98-195 |
| Dedicated CU | $6.849 | $5,000 | ~100-200 MB/s ingress per CU | ~$25-50 |

Standard looks unbeatable per megabyte - and it is, right up until you hit the 40 TU wall at 40 MB/s or one of the structural limits below.

**Premium versus Dedicated.** Six PUs cost $5,852/month for roughly 30-60 MB/s. One capacity unit costs $5,000/month for roughly 100 MB/s inbound under the planning assumption. The crossover sits around **4 to 6 PUs** - past that, a single-CU dedicated cluster is both cheaper and larger. "Dedicated" sounds like the expensive enterprise tier; above a fairly modest scale it's the *cheap* one.

**Except when you need zone redundancy.** Event Hubs Standard, Premium and Dedicated support availability zones with no additional charge for the feature itself. In a supported region, Standard and Premium namespaces are zone-redundant automatically, spreading the service across physically separate datacenters so it can tolerate a local zone failure. Dedicated requires a zone-redundant cluster to be provisioned separately.

The deployment floors differ by tier:

| Tier | Minimum for zone redundancy |
|---|---|
| Standard | No additional TUs |
| Premium | 1 PU |
| Dedicated, self-service scalable cluster | 3 CUs |

The current [reliability guide](https://learn.microsoft.com/azure/reliability/reliability-event-hubs) and [Dedicated overview](https://learn.microsoft.com/azure/event-hubs/event-hubs-dedicated-overview) set the three-CU minimum for a self-service scalable Dedicated cluster. At the prices used here, a zone-redundant Dedicated deployment therefore starts at $15,000/month. The extra cost comes from its required capacity footprint, not an availability-zone surcharge.

So with AZ as a hard requirement the curve inverts. Premium is zone-redundant from its first PU and stays competitive to about 12 PUs ($11,703) before a new Dedicated cluster's three-CU floor is worth paying. That changed my default from "Premium, obviously" to "Premium, unless you're past ~4 PUs and can live without zone redundancy." What it does *not* do is push you off Standard - zone redundancy is not one of the reasons to leave.

**What about ingress event charges?** I expected these to be the hidden cost that pushes Defender workloads off Standard. The arithmetic says otherwise. At the `$0.028` reference price per million 64-KB billing units, the cost per decimal terabyte is:

```text
messages per TB × billing units per message × $0.028 / 1,000,000
= (1,000,000,000,000 ÷ average message bytes)
  × ceil(average message bytes ÷ 64,000)
  × $0.028 ÷ 1,000,000
```

That is `$0.44/TB` at a 128-KB average message, `$1.40/TB` at 20 KB, and `$28/TB` in the pathological case where every 1-KB record is published separately. So the earlier `$0.44-$1.40/TB` range is valid for the **modeled 20-KB to 1-MB batch sizes**, not for every possible Defender batch: the producer's batching behavior is undocumented, and smaller average messages move the cost toward the `$28/TB` unbatched bound. Premium and Dedicated include ingress events, but at measured Defender batch sizes that saving is unlikely to drive the tier decision.

**The case for leaving Standard is structural, not financial.** A fine place to *start* a Defender pipeline. A bad place to be surprised.

### The large end: 100 MB/s sustained, 180 MB/s peak

Very large tenant, or a consolidated MSSP pipeline. Four independent limits push this to Dedicated, and only one of them is throughput. Head to head:

| | 16 PU Premium (the maximum) | 2 CU Dedicated |
|---|---|---|
| Ingress capacity | 80-160 MB/s | ~200 MB/s under the 100 MB/s per-CU planning benchmark; official range can be ~200-400 MB/s |
| Peak fits? | No - 180 MB/s is past the top of the range | Yes under the planning benchmark, with limited headroom |
| Partitions per hub | 100 | 1,024 |
| Partitions the peak needs | ~90-180 under the conservative 1 MB/s/partition model - must shard across hubs | Fits in one |
| Included retention at 8.6 TB/day | 16 TB ≈ 1.9 days | 20 TB ≈ 2.3 days |
| Monthly list | $15,600 | $10,000 |

Premium runs out of room on three rows at once, and 16 PUs is the end of the road - there's no larger namespace to buy. Two CUs cost $5,600/month less and win everywhere except one place worth dwelling on.

**Retention isn't a differentiator here.** At 8.6 TB/day neither tier gives you two full days, so the extra 0.4 days Dedicated buys is noise. That's not an argument for either tier - it's the point where you stop treating the hub as storage and put Capture or an archival consumer behind it.

> With zone redundancy required, this gets closer. 2 CUs cannot be zone-redundant - that needs three or more, so $15,000 against maxed Premium's $15,600. Dedicated still wins, but the margin is gone, and zone-redundant clusters can't be created through the portal or ARM at all. Support request only.
{: .prompt-warning}

## 🧩 Partition behaviour and consumer parallelism

The earlier formula gives the initial partition count; this section explains why each floor exists and how consumers change it. Start from what partitions are not: they do not add namespace capacity. A Standard hub with 32 partitions on a 1 TU namespace has the same enforced 1 MB/s namespace quota as a hub with one partition, at the same price. What partitions give you is **parallelism**.

That's exactly true on Standard, where the TU quota is an enforced throttle - and a useful simplification rather than a rule on Premium and Dedicated, where nothing caps you per unit and partition count becomes one of the inputs to what the namespace delivers.

On ingress, partitions give you multiple parallel logs instead of one storage-bound append log - uneven distribution across them is a documented cause of `ServerBusy` even when the namespace has budget left. On egress, Microsoft states the ceiling flatly: the number of partitions equals the maximum number of parallel consumers per consumer group.

That holds regardless of how the receiver connects:

| Consumer type | Ownership model | More instances than partitions? |
|---|---|---|
| Epoch (`EventProcessorClient`, the recommended pattern) | Exclusive ownership of a partition | Surplus instances get no assignment, sit idle |
| Kafka client | Group coordination, one member per partition | Surplus members wait for a rebalance |
| Non-epoch | Up to 5 receivers share a partition | All see the same events - fan-out, not throughput |

### How many partitions, then

Microsoft does document a method, and it's a good starting point - it just sits on the scalability page rather than anywhere near the Defender streaming docs. The [scalability guide](https://learn.microsoft.com/azure/event-hubs/event-hubs-scalability) gives these approximate per-partition planning rates and tells you to validate them with load tests:

| Tier | Per-partition ingress | Per-partition egress |
|---|---|---|
| Standard | ~1 MB/s | ~2 MB/s |
| Premium / Dedicated | ~1-2 MB/s | ~2-5 MB/s |

> Estimate partitions by dividing your expected ingress and egress by the applicable per-partition rates and taking the larger result.
{: .prompt-info}

So on Standard:

```text
partitions ≥ max( peak ingress MB/s ÷ 1 , peak egress MB/s ÷ 2 )
```

This planning floor is independent of your TU count, which is what makes it easy to miss: eight TUs feeding a four-partition hub can become partition-bound around 4 MB/s with namespace budget still available. That is a load-test hypothesis, not an enforced four-partition quota. Microsoft's other line says it from the front: choose at least as many partitions as you expect at **peak** load, the same peak the spike section told you to measure rather than average away.

Two floors of my own on top, both about the consumer rather than the hub:

**Consumer parallelism.** `partitions ≥ peak egress MB/s ÷ per-reader MB/s`. Per-reader throughput is a measurement, not a constant - it swings with parsing cost, sink latency and batching. When a single reader is slow, this floor overtakes Microsoft's.

**Drain rate.** If a 45-minute login storm leaves a few GB queued, you need enough partitions to drain that *on top of* live traffic before retention drops it.

**The small end** - mid-size tenant, consolidated Defender hub on Standard, one consumer group:

| Input | Value |
|---|---|
| Peak ingress, measured with `peakToMedian` applied | 6 MB/s |
| Consumer groups | 1 |
| Peak egress - one full read of the stream | 6 MB/s |
| Per-reader sustained | ~1.5 MB/s |
| TUs: `max(6, 6÷2)` | 6 |
| Per-partition ingress floor: 6 ÷ 1 | 6 |
| Per-partition egress floor: 6 ÷ 2 | 3 |
| Consumer parallelism floor: 6 ÷ 1.5 | 4 |
| Partitions: highest floor, rounded up | 6 → 8 |

Note which floor won: with one consumer group, per-partition **ingress** sets the number - not the consumer, not egress. That's the normal case here, because egress gets 2 MB/s per partition against 1 MB/s in, so it has twice the headroom before binding.

> Microsoft warns against simply maxing the count out, on two grounds: more partitions complicate the consumer side, and heavy partitioning defeats ordering. Only the first applies here - the Streaming API doesn't let you set a partition key, so you get round-robin distribution and no cross-partition ordering to lose.
{: .prompt-info}

### Consumer groups, and the egress half of the calculation

Egress is a separate quota, not a competing one - a TU gives 1 MB/s in *and* 2 MB/s out. But every consumer group reading the full stream pulls its own copy over the wire, so the unit count you need is `max(peak ingress MB/s, peak egress MB/s ÷ 2)`. Work that through on the same 6 MB/s ingest and the curve isn't linear:

| Consumer groups | Egress | ÷ 2 | TU floor | Extra TUs |
|---|---|---|---|---|
| 1 | 6 MB/s | 3 | 6 - ingress-bound | - |
| 2 | 12 MB/s | 6 | 6 - exactly tied | 0 |
| 3 | 18 MB/s | 9 | 9 - egress-bound | +3 |
| 4 | 24 MB/s | 12 | 12 | +6 |

**The second consumer group is free**, because the egress budget is 2x ingress by construction. So an archival copy beside your primary receiver, or a parallel run while migrating between them, costs nothing. The third group is where you start paying, and a fan-out to four or five is a bad deal in a specific way: you buy ingress capacity you will never use, purely to fund reads. That's where splitting per table - each consumer reading only the tables it needs - beats buying throughput units.

> One thing consumer groups are *not*: a scaling mechanism. Parallelism comes from partitions within a single group. Spinning up a second group to "read faster" doubles your egress for the same data and gains nothing.
{: .prompt-info}

### Get it wrong on Standard and you get a new hub

How reversible that number is depends entirely on the tier:

| Tier | Change partition count later? | What it costs you |
|---|---|---|
| Standard | No, immutable | A new hub plus a re-pointed export setting |
| Premium / Dedicated | [Increase only, never decrease](https://learn.microsoft.com/azure/event-hubs/dynamically-add-partitions) | Hash mapping shifts; event processor consumers need a restart to see new partitions |

That asymmetry is worth reading as design rather than inconvenience. **Standard has to be calculated because it can't be tuned; Premium and Dedicated are meant to be tuned because they can't be calculated.** There's no enforced per-unit rate on those tiers to divide by, which is why Microsoft's own instruction is a loop rather than a formula: *"If observed throughput or latency doesn't meet expectations, increase partitions (Premium and Dedicated tiers only) and retest."* Raising the count there isn't recovering from a bad guess, it's the documented method of arriving at the number.

Note that **latency** carries equal weight with throughput in that sentence. A namespace can be inside its byte budget and still be the wrong shape - too few partitions means too few parallel logs on the write side and too few possible readers on the read side, and the symptom is delay rather than an error. Microsoft says as much when it tells you to start from a workload profile that includes "sensitivity to throughput drops or latency spikes". Nothing in the metrics table further down will page you about that; you have to be looking for it.

> Because Standard gives you exactly one attempt, I'd start at 8-16 for a consolidated Defender hub rather than the portal default - above the floors for a mid-size tenant, cheap to over-provision, and it buys room to grow into. On Premium and Dedicated I'd deliberately start lower and walk it up, since the loop above is available and over-provisioning partitions carries its own cost on the consumer side. The one thing that doesn't work on any tier is guessing once and never re-testing.
{: .prompt-warning}

## 🔗 One hub, or one hub per table?

Name a hub and everything lands in it, or leave the name blank and Defender creates one hub per event type. Mostly decided by your SKU, not your preference - and the count that drives it is the **32 selectable event types** on the [supported event types](https://learn.microsoft.com/defender-xdr/supported-event-types) page:

| Group | Count | Tables |
|---|---|---|
| Alerts & behaviors | 4 | `AlertInfo`, `AlertEvidence`, `BehaviorInfo`, `BehaviorEntities` |
| Devices | 10 | `DeviceInfo`, `DeviceNetworkInfo`, `DeviceProcessEvents`, `DeviceNetworkEvents`, `DeviceFileEvents`, `DeviceRegistryEvents`, `DeviceLogonEvents`, `DeviceImageLoadEvents`, `DeviceEvents`, `DeviceFileCertificateInfo` |
| Email & collaboration | 8 | `EmailAttachmentInfo`, `EmailEvents`, `EmailPostDeliveryEvents`, `EmailUrlInfo`, `UrlClickEvents`, `MessageEvents`, `MessageUrlInfo`, `MessagePostDeliveryEvents` |
| Apps & identities | 7 | `IdentityEvents`, `IdentityInfo`, `IdentityLogonEvents`, `IdentityQueryEvents`, `IdentityDirectoryEvents`, `CloudAppEvents`, `OAuthAppInfo` |
| Cloud infrastructure | 3 | `CloudAuditEvents`, `CloudProcessEvents`, `CloudStorageAggregatedEvents` |

The Devices group is where nearly all your volume lives, and it's also the group whose tables all peak together during the morning storm. Note that not everything here is a high-rate stream: `DeviceInfo`, `IdentityInfo` and `OAuthAppInfo` are inventory-shaped, low and flat. Sizing a per-table hub the same way for both is how you end up with idle readers on one hub and throttling on another.

That count runs straight into the tier limits:

| Tier | Binding limit | Cost of splitting all 32 tables | Verdict |
|---|---|---|---|
| Standard | 10 hubs per namespace | Four namespaces, each with its own TU budget to size and monitor | Consolidate. You barely have a choice |
| Premium | 200 partitions per PU, namespace-wide | 32 tables x 32 partitions = 1,024, so 6 PUs (~$5,850/month) for the partition budget alone | A cost decision, not a free one |
| Dedicated | None that bites | 1,000 hubs, 2,000 partitions per CU, 50 namespaces per CU | Split freely |

Both numbers moved the wrong way as coverage grew. Standard's export setting carries ten tables, so full-fidelity streaming now needs four namespaces rather than three - and on Premium the partition budget for a full per-table split has gone from four PUs to six. Broader table coverage is good; it just isn't free.

Consolidating means the consumer routes on `category`, which is what that field is there for. Where splitting earns its cost anyway:

| Reason | What consolidation costs you |
|---|---|
| Noisy-neighbour isolation | `DeviceNetworkEvents` and `DeviceEvents` dominate volume; the morning spike competes for the same partitions as `AlertInfo` - the records you least want delayed |
| Per-table consumer scaling | A high-volume table wants many partitions and many readers, `DeviceInfo` does not. One hub forces one partition count on everything |
| Per-table observability | `IncomingBytes` and `ThrottledRequests` split by `EntityName`. Dimensions aren't exported to Log Analytics, so this works in Metrics, not KQL |

Against that: one hub is less to operate. Microsoft leans further the other way still - one event hub per namespace, since throughput applies at namespace level. Defensible for isolation, but it multiplies the TU budgets you have to right-size, which for a single-tenant SOC pipeline I find harder to run, not easier.

**If you let Defender auto-create the hubs, check what it chose.** Leave the **Event-Hub name** field empty and Defender creates one hub per table for you - but the docs never say what partition count it picks, and on Standard that value is permanent. The ones I've looked at came out at **10 partitions**, a number that appears nowhere in the documentation, so treat it as a field observation rather than a contract. It's a middling default: fine for a mid-size consolidated hub, and wrong at both ends. Go and look:

```bash
az eventhubs eventhub list \
  --resource-group <rg> --namespace-name <namespace> \
  --query "[].{hub:name, partitions:partitionCount}" -o table
```

Run that before the first busy day, not after. If the count sits below the floors above, the fix on Standard is a new hub and a re-pointed export setting - which is to say: name the hub yourself and create it with the partition count you want, rather than letting the export setting decide for you.

## 🔍 The observability gap in the tier comparison

This is the argument for Premium I'd put ahead of throughput. Everything telling you the *producer* side is healthy exists on every tier. Everything telling you the *consumer* side is healthy does not - and that same split is how you work out which limit is binding. Stop at the first row that matches:

| Signal | Tiers | Reading | Diagnosis and fix |
|---|---|---|---|
| `ThrottledRequests`, `QuotaExceededErrors` | All | Above zero | A request or quota was throttled. Inspect `OperationResult`, `EntityName` and diagnostic error logs to identify ingress, egress or another quota before scaling |
| `OutgoingBytes` at peak | Basic / Standard | Pinned at `120 MB/min × TU` | Egress quota-bound. Add TUs; partitions won't move the namespace quota |
| `OutgoingBytes` vs `IncomingBytes` | All | Below, backlog growing | Consumer-bound - continue down the table |
| Reader instances vs partitions | - | Instances fewer than partitions | Not a partition problem yet. Scale reader instances, which costs nothing |
| `ApplicationMetricsLogs` consumer lag | Premium, Dedicated | Even across partitions, instances = partitions | Genuinely partition-bound. More partitions plus more readers |
| `ApplicationMetricsLogs` consumer lag | Premium, Dedicated | A few partitions lag, rest current | Rebalance issue or a poison message. Adding partitions makes it worse |
| Reader CPU/memory | - | Pinned | Reader-bound per instance. Parsing rules, batch size, enrichment - before touching the hub |
| Reader CPU/memory | - | Idle, lag still growing | The sink behind the reader. Nothing in Event Hubs fixes this |
| `IncomingBytes` / `IncomingMessages` | All | Any time | Average message size - the division the whole sizing model starts from |
| One-minute `IncomingBytes`, `Sum`, over 7+ days | Basic / Standard | Peak minute approaching `60 MB/min × TU` | Sized for the average, not the storm. Add TUs before the next one rather than after it |
| `NamespaceCpuUsage`, cluster `CPU` (`Role` Max) | Premium / Dedicated | Sustained ~70% | Approaching the ceiling. Plan the next PU or CU |

```shell
AZMSApplicationMetricLogs
| where TimeGenerated > ago(1h)
| where Provider == "EVENTHUB"
```

Note where the tier column bites: the four rows that diagnose the *consumer* side need [`ApplicationMetricsLogs`](https://learn.microsoft.com/azure/event-hubs/monitor-event-hubs-reference#resource-logs), and that's Premium and above. On Standard you can tell that something is behind, but not which of the three consumer causes it is - so the first hard signal is somebody noticing a stale dashboard. Some receivers expose their own lag metric, which helps for the ones that do and tells you nothing about a hub read by several consumers.

Watch all of this across a login storm and the recovery after it, not a flat hour. Egress below ingress *during* the spike is normal; egress that never overshoots afterwards to burn the backlog down is the failure. And the decisive test costs nothing: if instances are below partition count, add one. Throughput rises, you were consumer-bound.

## ⚠️ Limitations and open questions

- **What happens when ingress is throttled?** Event Hubs returns `ServerBusy` to the producer. I found no documentation on how the Streaming API handles that - retry, buffer, or drop. The most important unknown here, and I'd want it answered before running a Standard namespace near its ceiling.
- **No migration path between tiers.** Standard to Premium isn't supported, nor automated migration into a Dedicated cluster. Changing tier means a new namespace, a new export setting, and a cutover. Factor that into "we'll start small and grow."
- **Dedicated has a four hour minimum**, billed and undeletable, making "let's just try it" a $27 experiment.
- **Retention storage overage.** At 10 MB/s over seven days you store ~6 TB against a 10 TU allowance of 840 GB, excess billed at blob rates - the [Event Hubs FAQ](https://learn.microsoft.com/azure/event-hubs/event-hubs-faq#is-there-a-charge-for-retaining-event-hubs-events-for-more-than-24-hours) spells out how the daily peak is measured and charged. Long retention on Standard is not as cheap as it looks.
- **Per-PU and per-CU throughput figures are approximations** in Microsoft's own docs, dependent on producers, consumers, payload size and partition count. No number here substitutes for a load test.
- **The batch size is undocumented.** I measured ~128 KB on Basic, but whether it changes with the tier is unknown. Nothing structural rests on it; measure yours with `IncomingBytes` over `IncomingMessages` for the billing calculation.
- **Table coverage moves, and it only moves up.** 32 event types are selectable today, including `BehaviorInfo` and `BehaviorEntities`, which were unavailable not long ago. Every addition raises the hub count and partition budget a full per-table split needs, so re-check the count before sizing rather than trusting a number from an older post - including this one.

## 📝 Conclusion

The working rule, in order:

| Step | Do this | Not this |
|---|---|---|
| 1 | Size from bytes per second, never from records per second | Multiply an Advanced Hunting EPS figure by an assumed 1 KB |
| 2 | Take the peak minute - one-minute `IncomingBytes` with `Sum`; use `Max` only when inspecting wider rollups | Size for an average that smooths the login storm away |
| 3 | Divide `IncomingBytes` by `IncomingMessages` to confirm you sit well above 1 KB per message | Treat that ratio as a sizing input - it's a sanity check |
| 4 | Set partitions from the per-partition floors - `max(ingress ÷ 1, egress ÷ 2)` on Standard | Derive partitions from TU count, or copy a connector's "32 partitions" prerequisite |
| 5 | Diagnose egress lag: add TUs only when the egress quota binds; otherwise scale or fix consumers | Assume all consumer lag is an Event Hubs capacity problem |
| 6 | Treat Standard as a start with a known expiry date | Treat it as a destination |

Three findings run against intuition:

- **Ingress event charges are a rounding error** at Defender volumes. They aren't the reason to leave Standard - the 10-hub cap, immutable partitions and missing consumer-lag telemetry are.
- **Partitions impose their own practical throughput constraint.** Microsoft's Standard planning rates are roughly 1 MB/s in and 2 MB/s out per partition. You can starve a well-funded namespace by under-partitioning it, and no amount of TUs will create parallelism.
- **Dedicated stops being the expensive option around four to six processing units** - a much lower bar than the name suggests, and it only moves up when zone redundancy is mandatory.

This is a first pass at the model rather than a validated benchmark. The throughput-per-unit figures are Microsoft's own approximations and won't survive contact with your traffic unchanged.

## 📚 References

Every figure in this post that isn't my own measurement traces to one of these. They move, so check them rather than this post.

Streaming setup, event schema, the EPS estimation query: [Configure Microsoft Defender XDR to stream Advanced Hunting events to your Azure event hub](https://learn.microsoft.com/defender-xdr/streaming-api-event-hub) |
The `estimate_data_size()` caveat, `MachineGroup` decoration: [Configure Microsoft Defender for Endpoint to stream Advanced Hunting events](https://learn.microsoft.com/defender-endpoint/api/raw-data-export-event-hub) |
The 32 selectable tables: [Supported Microsoft Defender XDR event types in event streaming API](https://learn.microsoft.com/defender-xdr/supported-event-types) |
TU/PU definitions, per-partition rates, consumer parallelism, increase-and-retest: [Scaling with Event Hubs](https://learn.microsoft.com/azure/event-hubs/event-hubs-scalability) |
Per-tier limits - publication size, consumer groups, retention, partitions: [Event Hubs quotas and limits](https://learn.microsoft.com/azure/event-hubs/event-hubs-quotas) |
Tier feature comparison: [Compare Azure Event Hubs tiers](https://learn.microsoft.com/azure/event-hubs/compare-tiers) |
`ThrottledRequests`, `QuotaExceededErrors`, `ServerErrors`, deprecated `SVRBSY`, resource logs: [Event Hubs monitoring data reference](https://learn.microsoft.com/azure/event-hubs/monitor-event-hubs-reference) |
Sum vs Max, one-minute granularity, why averages hide spikes: [Azure Monitor Metrics aggregation and display explained](https://learn.microsoft.com/azure/azure-monitor/metrics/metrics-aggregation-explained) |
`MessageSizeExceededException` and why retrying won't help: [Event Hubs messaging exceptions](https://learn.microsoft.com/azure/event-hubs/event-hubs-messaging-exceptions) |
Scale-up-only behaviour and hourly maximum billing: [Automatically scale up throughput units](https://learn.microsoft.com/azure/event-hubs/event-hubs-auto-inflate) |
Adding partitions on Premium and Dedicated: [Dynamically add partitions to an event hub](https://learn.microsoft.com/azure/event-hubs/dynamically-add-partitions) |
Availability-zone support and tier minimums: [Premium overview](https://learn.microsoft.com/azure/event-hubs/event-hubs-premium-overview) / [Dedicated overview](https://learn.microsoft.com/azure/event-hubs/event-hubs-dedicated-overview) / [Reliability guide](https://learn.microsoft.com/azure/reliability/reliability-event-hubs) |
Retention storage allowance and blob-rate overage: [Event Hubs FAQ](https://learn.microsoft.com/azure/event-hubs/event-hubs-faq) |
List prices: [Event Hubs pricing](https://azure.microsoft.com/en-us/pricing/details/event-hubs/) |
