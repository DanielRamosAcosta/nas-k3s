---
id: NASKS-10
title: Fix Invidious Companion PO token validation failure
status: Done
assignee: []
created_date: '2026-03-09 16:57'
updated_date: '2026-03-15 16:52'
labels:
  - media
  - bugfix
  - blocked
dependencies: []
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Invidious Companion cannot generate valid PO tokens due to YouTube.js v16.0.0 failing to parse YouTube's current player. The signature decipher and n decipher functions fail with `exportedVars.nFunction is not a function`.

This affects all Invidious instances globally. Upstream issue: https://github.com/iv-org/invidious-companion/issues/274

Root cause: YouTube changed their player (player ID `140dafda`) and YouTube.js hasn't been updated to handle the new format.

Workaround mentioned in issue: manually changing the player ID constant in companion source, using IDs from https://youtube-player-ids.nadeko.net/ — but no official fix yet.

Action: Monitor the upstream issue and update companion when a fix is released.
<!-- SECTION:DESCRIPTION:END -->
