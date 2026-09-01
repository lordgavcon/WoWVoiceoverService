# Bandits & Survivors (Project Zomboid, Build 42)

Adds persistent, world-navigating human NPCs to Build 42.20+:

- **Bandits** in three tiers:
  - **Civilians** — desperate people with planks, kitchen knives and rolling pins. They prefer robbing you (hand over some items and they leave) to fighting, and they break and run when hurt.
  - **Thugs** — organised muggers with real melee weapons and the occasional pistol; sometimes travel in pairs.
  - **Rogue militia** — squads of 2–5 with firearms. They attack on sight, launch raids on player bases, and garrison fortified strongholds.
- **Base raids & sabotage** — bandit squads periodically march on player bases (MP safehouses are detected directly; elsewhere the mod learns where you spend your time). Raiders smash barricades and player-built walls, shut down and damage generators, and steal from your containers before withdrawing.
- **Fortified points of interest** — the militia claims a configurable number of known locations (fire stations, gas stations, warehouses, gun stores across Rosewood, Muldraugh, West Point, Riverside, March Ridge…). Claimed POIs get barricaded windows/doors, supply-stocked containers (food, ammo, meds, fuel, building materials) and a standing garrison. Clear the garrison and the supplies are yours.
- **Survivors & traders** — neutral NPCs wander the world. Right-click a survivor to talk (they drop rumours, including militia base warnings); right-click a trader to open a barter window and trade your goods against their stock, valued item-for-item.
- **Persistence** — every NPC is a record in global mod data. NPCs near players are fully simulated ("live"); distant ones are *virtualised* — despawned but still travelling the map abstractly — and rematerialise when you come near their current position. State survives save/load and server restarts.
- **Multiplayer compatible** — all AI, combat, robbery, raid and trade logic runs on the server; clients only render speech/UI and send trade proposals, which the server validates (no client-side item forging). The same server code runs in-process in single player, so SP and MP share one code path.

## How it works (the honest version)

Build 42 still has no official NPC API. Like the well-known Bandits and
Superb Survivors mods, this mod implements NPCs as **server-controlled
zombie shells**: each NPC is an `IsoZombie` spawned in a human outfit whose
zombie instincts are suppressed every tick, driven instead by a Lua brain
stored in its mod data. That buys us the engine's real pathfinding
(`pathToLocationF`) for natural navigation, and free multiplayer position
sync (zombies already sync). Consequences you should know about:

- NPC locomotion/animations are zombie animation sets — they walk and run
  believably but won't visibly swing weapons or aim. Attacks are simulated
  server-side (hit rolls, gunshot sounds and noise that attracts zombies,
  body-part damage through `BodyDamage`).
- NPCs read as zombies to some vanilla systems (e.g. kill counts).

## Installation

Copy `PZBanditsSurvivors/` into your mods folder
(`Zomboid/Workshop/` or `Zomboid/mods/`), enable **Bandits & Survivors
(B42)** in the mod list. For dedicated servers add `PZBanditsSurvivors` to
the server's `Mods=` line; the mod must be installed on server **and**
clients.

## Sandbox options (page: "Bandits & Survivors")

| Option | Default | Meaning |
|---|---|---|
| Bandit spawn rate | 3 | 0 disables bandits |
| Survivor spawn rate | 2 | 0 disables survivors/traders |
| Max live NPCs | 20 | Simulation cap; the rest are virtualised |
| Rogue militia groups | on | Top bandit tier |
| Militia firearm chance | 60% | Per squad member |
| Base raids & sabotage | on | |
| Raid cooldown | 24h | Per base, in-game hours |
| Fortified POIs | on / max 4 | Militia strongholds |
| Traders | on | |
| Robberies | on | Low-tier bandits mug instead of attack |
| NPC damage multiplier | 1.0 | Scales NPC → player damage |

## Code layout

```
42/media/lua/
  shared/BNS/   BNS_Core (namespace/helpers) · BNS_Loadouts (tiers, weapons,
                loot, trader stock, barter values) · BNS_POIs (stronghold list)
  server/BNS/   BNS_Persistence (records, virtualisation) · BNS_Spawner
                (shell (de)materialisation, squads, loot drops) · BNS_Combat
                (simulated melee/gunfire) · BNS_Programs (wander/approach/rob/
                attack/flee/defend/trade) · BNS_Brain (per-tick dispatcher,
                damage & death hooks) · BNS_Bases (POI claiming, lazy
                barricading & stocking) · BNS_Raids (base detection, raid
                squads, sabotage) · BNS_Commands (validated trade/talk) ·
                BNS_Main (director: population, live/virtual boundary)
  client/BNS/   BNS_Client (server commands, floating speech) ·
                BNS_ContextMenu (Talk/Trade) · BNS_TradeWindow (barter UI)
```

## Known limitations / TODO

- Not yet play-tested against 42.20 — B42's Lua API is still moving, and a
  few calls (e.g. `setUseless`, `IsoBarricade.AddBarricadeToObject`,
  outfit names) may need renaming against the current javadocs. Everything
  is guarded where practical; check `console.txt` for `[BNS]` lines.
- NPCs don't loot buildings for themselves, use vehicles, or fight zombies
  intelligently (they rely on toughness).
- Trader stock doesn't restock over time yet.
- Raids target the learned base centre; sprawling multi-building bases are
  only partially swept.
