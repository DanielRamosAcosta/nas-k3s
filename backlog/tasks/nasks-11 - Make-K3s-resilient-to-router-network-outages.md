---
id: NASKS-11
title: Make K3s resilient to router/network outages
status: Done
assignee: []
created_date: '2026-03-09 17:02'
updated_date: '2026-04-12 02:15'
labels: []
dependencies: []
priority: high
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

When the network cable is disconnected or the router loses power, `enp4s0` loses carrier. dhcpcd reacts by removing the IP `192.168.1.200` from the interface and deleting all routes. This causes a cascade of failures:

1. Kubelet liveness/readiness probes to `192.168.1.200` fail with `network is unreachable`
2. Pods with `hostNetwork: true` (node-exporter, nut-exporter) get killed and restarted
3. CoreDNS loses its kubernetes watch and restarts, breaking cluster DNS
4. Services depending on DNS (ArgoCD, Authelia) restart in cascade
5. VictoriaMetrics loses scrape targets, creating gaps in metrics
6. CPU spikes to 100% during recovery as K3s reconciles all pods

Additionally, the `network-link-monitor` service was actively worsening the problem: it detected carrier loss and ran `ip link set enp4s0 down` + `dhcpcd -x enp4s0` to "recover", which destroyed the network config even faster, up to 3 times per outage.

Note: K3s does NOT have `node-ip` configured (contrary to what was originally assumed). It uses auto-detection. The root cause is dhcpcd removing the IP on carrier loss, not K3s configuration.

## Incident: 2026-03-09

- 09:43 - Power outage, UPS kicks in
- 10:51 - UPS battery depleted, NAS shuts down
- 11:16 - Power restored, NAS boots, K3s starts without network IP
- 11:29-11:34 - Continuous `nodeIP not found` errors every 10s
- ~11:34 - Router back, IP assigned, K3s recovers
- SFTPGo was in CrashLoopBackOff for ~15 minutes

## Investigation: 2026-04-12

Reproduced the issue by disconnecting the NAS ethernet cable for 2 minutes, 3 times:

**Test 1 (baseline):** Cable disconnected. dhcpcd removed IP on carrier loss, kubelet probes failed (`dial tcp 192.168.1.200:9100: network is unreachable`), node-exporter/nut-exporter killed, CoreDNS crashed, Authelia restarted, metrics gap of 2.5 min, CPU spike to 100% on recovery.

**Test 2 (dhcpcd `nocarrier`):** `nocarrier` is not a valid option in dhcpcd 10.2.4 — silently ignored. Same failure as test 1. Also confirmed `network-link-monitor` was making it worse by running `dhcpcd -x enp4s0` 3 times during the outage.

**Test 3 (dhcpcd `nolink` + removed monitor):** dhcpcd ignored carrier loss entirely. IP stayed on the interface. Zero pod restarts. Zero metric gaps. No CPU spike.

## Root cause

Two compounding issues:
1. **dhcpcd** removes the IP from `enp4s0` when carrier is lost, even though the DHCP lease is still valid
2. **network-link-monitor.service** aggressively tears down and rebuilds the network config on carrier loss, making recovery slower

## Fix applied

1. Added `nolink` to dhcpcd config — dhcpcd no longer reacts to carrier loss events
2. Removed `network-link-monitor` service and script — was counterproductive
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 K3s continues to function when the network cable is disconnected
- [x] #2 The IP 192.168.1.200 stays on enp4s0 during carrier loss
- [x] #3 NAS can reach the internet when the cable is reconnected
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Resolved 2026-04-12. Changes in `nas` repo: `hosts/nas/services/network-monitor.nix` (removed service, added `nolink` to dhcpcd), deleted `hosts/nas/services/scripts/network-link-monitor.sh`.
<!-- SECTION:NOTES:END -->
