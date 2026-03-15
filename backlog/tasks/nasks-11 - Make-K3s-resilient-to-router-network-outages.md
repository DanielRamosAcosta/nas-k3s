---
id: nasks-11
title: Make K3s resilient to router/network outages
status: To Do
assignee: []
created_date: '2026-03-09 17:02'
updated_date: '2026-03-09 17:12'
labels:
  - infra
  - bugfix
  - nixos
dependencies: []
priority: high
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

When the power goes out, the router loses power and the NAS (connected to a UPS) either stays running or reboots before the router is back. In both cases, the DHCP-assigned IP `192.168.1.200` on `enp4s0` disappears from the interface.

K3s is configured with `node-ip: 192.168.1.200`. When that IP is missing, K3s enters a failure loop:

```
Failed to set some node status fields: failed to validate nodeIP: node IP: "192.168.1.200" not found in the host's network interfaces
```

This causes pods to enter CrashLoopBackOff (e.g., SFTPGo was down ~15 min on 2026-03-09) and internal cluster networking breaks until the router comes back and DHCP reassigns the IP.

## Incident: 2026-03-09

- 09:43 - Power outage, UPS kicks in
- 10:51 - UPS battery depleted, NAS shuts down
- 11:16 - Power restored, NAS boots, K3s starts without network IP
- 11:29-11:34 - Continuous `nodeIP not found` errors every 10s
- ~11:34 - Router back, IP assigned, K3s recovers
- SFTPGo was in CrashLoopBackOff for ~15 minutes

## Options

### Option 1: Static IP (simple)
Configure `enp4s0` with a static IP in NixOS instead of DHCP. The IP is always present on the interface regardless of router state.

**Pros:** Simple, reliable, no moving parts
**Cons:** Must manually update config if network topology changes; need to hardcode DNS servers and gateway

### Option 2: DHCP with static fallback (flexible)
Use DHCP normally but configure a fallback static IP via `systemd-networkd`. If DHCP fails (router down), the static IP is assigned automatically.

**Pros:** Best of both worlds - automatic config from DHCP when available, static fallback when not
**Cons:** Slightly more complex config

### Option 3: K3s dependency on network-online.target (weak)
Add `After=network-online.target` + `Requires=network-online.target` to the K3s service.

**Pros:** Simple systemd change
**Cons:** Only fixes boot timing; does NOT fix the case where the IP disappears while K3s is already running

## Recommendation

Option 1 or 2. Both solve the root cause (IP always present on the interface). Option 3 is insufficient on its own.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 K3s continues to function when the router is powered off
- [ ] #2 The IP 192.168.1.200 is always present on enp4s0 regardless of DHCP availability
- [ ] #3 NAS can still reach the internet when the router is available
<!-- AC:END -->
