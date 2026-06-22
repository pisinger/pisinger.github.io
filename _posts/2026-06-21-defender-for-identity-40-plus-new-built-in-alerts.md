---
title: "Defender for Identity - 40+ New or Expanded Built-In Alerts You Might Have Missed"
author: pit
date: 2026-06-21
categories: [blogging]
tags: [defender, defender-identity, sentinel, detection, alerts, entra-id, active-directory, security, identity, soc]
render_with_liquid: false
---

Was catching up on the Defender for Identity what's-new page the other day and kept scrolling. And scrolling. New alert after new alert, month after month.

> What's-new changelog: <https://learn.microsoft.com/en-us/defender-for-identity/whats-new>
{: .prompt-info}

Microsoft lists 46 Defender for Identity alert entries between January and June 2026. I wouldn't call all 46 "net-new" detections. Some Active Directory items such as Pass-the-Ticket, DCSync, and Golden Ticket style detections map to familiar MDI detection families that were further improved rather than introduced. But even with that conservative filter, we're still looking at a large number of new or materially expanded built-in detections across Entra ID, hybrid identity, and third-party identity providers.

> That's not just a minor update cycle; it's a product transformation that is easy to miss when most of the detection engineering conversation is about which Analytic Rules are available in Content Hub, or whether to build custom detections at all. 
{: .prompt-tip}

The important part is the direction of travel: Entra ID sync application abuse, OAuth and AiTM patterns, session cookie replay, Conditional Access bypass indicators, Intune registration activity, and third-party identity provider signals are becoming first-party identity detection coverage.

## The 2026 Alert Wave

Here is the breakdown of alert entries Microsoft added to the Defender for Identity alert catalog since January. I would still review each candidate before retiring local content, because "newly listed" does not automatically mean "fully equivalent to your custom rule."

> Defender Identity Alert Reference: <https://learn.microsoft.com/en-us/defender-for-identity/alerts-xdr>
{: .prompt-info}

| Month | Category | Alert |
|---|---|---|
| **Jan 2026** | Entra ID | Suspicious sign-in observed from Entra ID sync application to an uncommon resource app |
| **Jan 2026** | Entra ID | Suspicious sign-in observed to Entra ID sync application using an uncommon user agent |
| **Jan 2026** | Entra ID | Possible OAuth code theft detected through consent abuse |
| **Jan 2026** | Entra ID | Possible adversary-in-the-middle (AiTM) attack detected (ConsentFix) |
| **Jan 2026** | Entra ID | Skipped MFA on remembered device from uncommon ISP sign-in |
| **Jan 2026** | AD | Pass-the-Ticket (PtT) attack |
| **Jan 2026** | AD | Possible Active Directory Certificate Services enumeration |
| **Jan 2026** | AD | Possible Active Directory enumeration via ADWS |
| **Jan 2026** | AD | Suspicious NTLM authentication |
| **Jan 2026** | AD | Possible Kerberoasting attack using a stealthy LDAP search |
| **Jan 2026** | AD | Suspicious Kerberos authentication (TGT request using TGS-REQ) |
| **Feb 2026** | Entra ID | Suspicious user configuration change activity from Entra ID sync application |
| **Feb 2026** | Entra ID | Anomalous OAuth device code authentication activity |
| **Feb 2026** | Entra ID | Suspicious Graph API request made from Entra ID sync application |
| **Feb 2026** | Entra ID | Suspicious sign-in observed from Entra ID sync application |
| **Feb 2026** | Entra ID | Suspicious sign in with CSRF speedbump trigger |
| **Feb 2026** | AD | Possible golden ticket attack (suspicious ticket) |
| **Feb 2026** | AD | Possible Kerberos key list attack |
| **Mar 2026** | Entra ID | Attempt to disable Defender for Identity service principal observed |
| **Mar 2026** | Entra ID | Suspicious Entra account enablement after disruption |
| **Mar 2026** | Entra ID | Suspicious Intune device registration activity |
| **Mar 2026** | Entra ID | Suspicious OS switch sign-in |
| **Mar 2026** | Entra ID | User sign-in from shared client infrastructure exhibiting anomalous activity |
| **Mar 2026** | Entra ID | Suspicious sign-in from an unusual user agent and IP address using PowerShell |
| **Mar 2026** | Entra ID | Suspicious sign-in from an unusual user agent and IP address using device code flow |
| **Mar 2026** | AD | Suspicious on-premises account enablement after disruption |
| **Mar 2026** | AD | Suspicious resource-based constrained delegation (RBCD) attribute change |
| **Mar 2026** | AD | Suspicious resource-based constrained delegation (RBCD) authentication |
| **May 2026** | Entra ID | Guest user account promoted to member |
| **May 2026** | Entra ID | User was created and assigned to Global Administrator role |
| **May 2026** | Entra ID | Failed credential abuse attempt in Entra ID authentication |
| **May 2026** | Entra ID | Malicious sign in from a randomized user agent |
| **May 2026** | Entra ID | Possible use of a stolen session cookie |
| **May 2026** | Entra ID | Stolen session cookie replay detected |
| **May 2026** | Entra ID | Suspected Conditional Access bypass via non-compliant device |
| **May 2026** | Entra ID | Suspicious addition of default third-party MFA method to user account |
| **Jun 2026** | Entra ID | Anomalous activity following Global Administrator elevation |
| **Jun 2026** | Entra ID | Reciprocal Temporary Access Pass creation between users |
| **Jun 2026** | Entra ID | Suspicious service principal sign-in following credential addition |
| **Jun 2026** | Entra ID | Suspicious bulk user deletion via scripted activity |
| **Jun 2026** | Entra ID | Suspicious removal of privileged app role assignment through Graph API |
| **Jun 2026** | Entra ID | Suspicious sign-in by a user exhibiting a spike in account update activity |
| **Jun 2026** | Entra ID | User exhibiting spike in distinct application-resource access combinations |
| **Jun 2026** | AD | DCSync attack (replication of directory services) |
| **Jun 2026** | AD | Suspicious Entra Connect account authentication |
| **Jun 2026** | Other | SailPoint ISC suspected brute-force attack |

## What this means for Sentinel customers

If you're running Sentinel with custom KQL detections (Analytics Rules) for identity threats, this list should prompt a review. Many of these alerts cover modern scenarios that SOC teams have historically had to build themselves, such as OAuth abuse, session cookie theft, AiTM patterns, and Entra ID sync application anomalies.

The time-to-value shift is significant. A custom KQL detection for a `suspicious resource-based constrained delegation attribute change` takes design, build, testing, tuning, and ongoing maintenance. A built-in alert removes most of that burden. It also helps answer a question I often hear from customers: what additional native detection value do we get beyond the risk detections and controls Entra ID Protection already provides? This wave of alerts makes that answer far more concrete — without the requirement of deploying extra content hub solutions or building the logic yourself.

## SOC Optimization — The Technique-led Gap Analysis

Rather than a line-by-line audit of every custom rule, take a technique-led approach. Start by exporting your custom identity rules with their MITRE Technique (e.g. `T1558.003` for Kerberoasting) and mapping them against the MITRE column in the MDI alert table. 

> Where MDI now ships a high-fidelity alert for the same technique, that custom rule becomes your first potential candidate for retirement.
{: .prompt-tip}

## Depth vs. Breadth: Do I only need one rule per Technique?

A common trap is thinking that once you have a detection for a MITRE Technique ID, you're "done" with that technique. The reality is that Techniques are broad, but **Procedures** are specific. One Technique can be executed in dozens of different ways. 

> - **Built-in alerts** are strongest where Microsoft has broad telemetry, product context, and enough volume to tune behavior-based detections.
> - **Custom detections** should focus on procedures that are unique to your environment, your specific high-value assets, your control-plane design, or your response-routing requirements.
{: .prompt-info}

The goal isn't just to have a single "Kerberoasting" rule. The goal is to let the **built-in** logic cover the common, well-understood cases so your **custom** logic can focus on the edge cases. If your custom rule and the new MDI alert are watching for the exact same event, pick the built-in one. If they're watching for different markers of the same attack, keep both.

## Conclusion

46 newly listed alert entries in six months is a pace that's easy to miss if you're heads-down on daily operations. They are not all net-new detections, but the cumulative effect is still real: Defender for Identity has quietly become a much more complete detection surface for identity threats across Entra ID, on-prem AD, and increasingly third-party IdPs like SailPoint. This is a huge step forward and a significant opportunity for SOC teams to optimize their detection catalog and focus on the truly unique scenarios in their environment.

> It’s less about "deleting everything" and more about retiring the technical debt of maintaining rules for problems that Microsoft has finally solved natively. It frees you up to focus on the stuff that is *truly* unique to your environment. If you haven't looked at the alert catalog since last year, it's worth an afternoon with the what's-new page and a review of your current Sentinel detection inventory. You might find more overlap than you expect.
{: .prompt-tip}
