# Questie Raven 7.0

Fork of Questie **6.9.0** (TOC `11402`) for RavenCraft 1.14.2. Stock Questie + what used to be `!CinderCompat` and `CinderQuestieData`, in one addon.

## What is baked in

| Source | In 7.0 |
|---|---|
| ID width (sourceItemId / requiredSourceItems / npcDrops / itemDrops / vendors → 24-bit + `u16u24array`) | `questDB.lua`, `itemDB.lua`, `compiler.lua` |
| High Elf / Goblin race masks (589 / 434 / 1023) | `QuestieDB.raceKeys`, `QuestieLib:GetRaceString`, PreCompile widen in `RavenMerge` |
| Jewelcrafting / Survival / unknown profession sorts | `QuestieProfessions` |
| Raven zones, uiMaps, blacklist, seasons, item-starters | `Database/Raven/RavenMerge.lua` |
| Raven quest/npc/object/item pack | `Database/Raven/RavenPack.lua` (Lua string tables, same shape as Questie base DB) |
| AceDB first-login relink | `Migration:Migrate` |

## Lua, not HDB

Pack stays **Lua** (`loadstring` → merge in `QuestieInit:LoadBaseDB`). That is Questie’s native compile path. HearthDB is optional for *building* the pack offline, not for runtime.

## Do not install beside

Disable / remove: stock Questie, `!CinderCompat`, `CinderQuestieData`, `CinderQuest` (if you use this fork as the quest helper).

Folder name must remain **`Questie`** (VersionCheck enforces the addon name; SavedVariables are `QuestieConfig`).

## Deploy

Copy `F:\wow ai\1.14\Questie` → client `Interface\AddOns\Questie`, then `/reload` (1.14.2).

First login after install recompiles the DB once (lag). Pack stamp is `Questie.db.global.ravenPackBuild`.

## Upstream

Based on Questie v6.9.0. Raven pack currently from CinderQuestieData build `4f37fd79a59a`.
