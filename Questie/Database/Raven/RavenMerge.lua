-- RavenMerge: embed RavenCraft pack into Questie at LoadBaseDB / PreCompile (was CinderQuestieData + !CinderCompat).
---@class RavenMerge
local RavenMerge = QuestieLoader:CreateModule("RavenMerge")

---@type RavenPack
local RavenPack = QuestieLoader:ImportModule("RavenPack")
---@type RavenObjectImport
local RavenObjectImport = QuestieLoader:ImportModule("RavenObjectImport")
---@type RavenExploreImport
local RavenExploreImport = QuestieLoader:ImportModule("RavenExploreImport")
---@type RavenStormwindFixes
local RavenStormwindFixes = QuestieLoader:ImportModule("RavenStormwindFixes")
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")
---@type QuestieProfessions
local QuestieProfessions = QuestieLoader:ImportModule("QuestieProfessions")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
---@type QuestieCorrections
local QuestieCorrections = QuestieLoader:ImportModule("QuestieCorrections")
---@type QuestieQuestFixes
local QuestieQuestFixes = QuestieLoader:ImportModule("QuestieQuestFixes")
---@type QuestieQuestBlacklist
local QuestieQuestBlacklist = QuestieLoader:ImportModule("QuestieQuestBlacklist")
---@type QuestieEvent
local QuestieEvent = QuestieLoader:ImportModule("QuestieEvent")

local ns = RavenPack
local band, bor = bit.band, bit.bor
local bootstrapped = false
local starters = {}
local serverMasks = {}

local function packStamp()
    local oi = RavenObjectImport and RavenObjectImport.build or "0"
    local ei = RavenExploreImport and RavenExploreImport.build or "0"
    return (ns.version or "?") .. "+" .. (ns.build or "?") .. "+oi" .. tostring(oi) .. "+ei" .. tostring(ei)
end

--- Apply pfQuest areatrigger/explore pins (triggerEnd + specialFlags=2).
--- Coords always from pfQuest; title keeps stock Questie text when import is "Explore <id>".
local function applyExploreImport()
    if not RavenExploreImport or not RavenExploreImport.explore or not QuestieDB or not QuestieDB.questKeys then
        return 0
    end
    local qk = QuestieDB.questKeys
    QuestieDB.questDataOverrides = QuestieDB.questDataOverrides or {}
    local n = 0
    for qid, row in pairs(RavenExploreImport.explore) do
        if type(row) == "table" and type(row[1]) == "string" and type(row[2]) == "table" then
            local title = row[1]
            local existing = QuestieDB.questData and QuestieDB.questData[qid]
                and QuestieDB.questData[qid][qk.triggerEnd]
            if title:match("^Explore %d+$") and type(existing) == "table" and type(existing[1]) == "string"
                and existing[1] ~= "" then
                title = existing[1]
            end
            local trigger = { title, row[2] }
            QuestieDB.questDataOverrides[qid] = QuestieDB.questDataOverrides[qid] or {}
            QuestieDB.questDataOverrides[qid][qk.triggerEnd] = trigger
            QuestieDB.questDataOverrides[qid][qk.specialFlags] = 2
            if QuestieDB.questCache then
                QuestieDB.questCache[qid] = nil
            end
            if QuestieDB.questData and type(QuestieDB.questData[qid]) == "table" then
                QuestieDB.questData[qid][qk.triggerEnd] = trigger
                QuestieDB.questData[qid][qk.specialFlags] = 2
            end
            n = n + 1
        end
    end
    return n
end

--- Apply pfQuest-Raven object coords + item.objectDrops overlays after base pack merge.
local function applyObjectImport()
    if not RavenObjectImport or not QuestieDB or not QuestieDB.objectData then
        return 0, 0
    end
    local OK = QuestieDB.objectKeys
    local IK = QuestieDB.itemKeys
    if not OK or not IK then return 0, 0 end

    local nObj, nItem = 0, 0
    local objects = RavenObjectImport.objects and loadstring(RavenObjectImport.objects)
    objects = objects and objects()
    if type(objects) == "table" then
        for id, patch in pairs(objects) do
            if type(patch) == "table" and type(patch.spawns) == "table" then
                local row = QuestieDB.objectData[id]
                if type(row) ~= "table" then
                    row = {
                        [OK.name] = patch.name or ("Object " .. tostring(id)),
                        [OK.questStarts] = nil,
                        [OK.questEnds] = nil,
                        [OK.spawns] = {},
                        [OK.zoneID] = patch.zone,
                    }
                    QuestieDB.objectData[id] = row
                end
                local spawns = row[OK.spawns]
                if type(spawns) ~= "table" then
                    spawns = {}
                    row[OK.spawns] = spawns
                end
                for zone, list in pairs(patch.spawns) do
                    if type(list) == "table" and #list > 0 then
                        -- Prefer imported coords for that zone (pfQuest is denser for Turtle/Raven).
                        spawns[zone] = list
                        nObj = nObj + 1
                    end
                end
                if row[OK.zoneID] == nil and patch.zone ~= nil then
                    row[OK.zoneID] = patch.zone
                end
                if (row[OK.name] == nil or row[OK.name] == "") and patch.name then
                    row[OK.name] = patch.name
                end
            end
        end
    end

    local drops = RavenObjectImport.itemObjectDrops and loadstring(RavenObjectImport.itemObjectDrops)
    drops = drops and drops()
    if type(drops) == "table" and QuestieDB.itemData then
        for itemId, objList in pairs(drops) do
            if type(objList) == "table" then
                local row = QuestieDB.itemData[itemId]
                if type(row) == "table" then
                    local cur = row[IK.objectDrops]
                    local have = {}
                    if type(cur) == "table" then
                        for _, oid in pairs(cur) do have[oid] = true end
                    else
                        cur = {}
                        row[IK.objectDrops] = cur
                    end
                    for _, oid in pairs(objList) do
                        if not have[oid] then
                            cur[#cur + 1] = oid
                            have[oid] = true
                            nItem = nItem + 1
                        end
                    end
                end
            end
        end
    end

    RavenObjectImport.objects = nil
    RavenObjectImport.itemObjectDrops = nil
    return nObj, nItem
end

--- Stormwind on Raven: classic pack % → Raven % via affine, then manual overrides.
--- Also drops bogus dual 5581 pins that spill onto the city map.
local function applyStormwindNpcFixes()
    if not (QuestieDB and RavenStormwindFixes) then
        return 0, 0
    end
    local SW, NW = 1519, 5581
    local stamp = RavenStormwindFixes.affine1519 and RavenStormwindFixes.affine1519.stamp
    local nAff, nMan = 0, 0

    local function patchEntity(kind, id, pts)
        local Keys = kind == "npc" and QuestieDB.npcKeys or QuestieDB.objectKeys
        local data = kind == "npc" and QuestieDB.npcData or QuestieDB.objectData
        local overs = kind == "npc" and "npcDataOverrides" or "objectDataOverrides"
        if not Keys or not Keys.spawns then return end
        local function patchSpawns(spawns, list)
            if type(spawns) ~= "table" then spawns = {} end
            spawns[SW] = list
            spawns[NW] = nil
            return spawns
        end
        local row = data and data[id]
        if type(row) == "table" then
            row[Keys.spawns] = patchSpawns(row[Keys.spawns], pts)
        end
        QuestieDB[overs] = QuestieDB[overs] or {}
        QuestieDB[overs][id] = QuestieDB[overs][id] or {}
        local ov = QuestieDB[overs][id]
        local base = ov[Keys.spawns]
        if type(base) ~= "table" and type(row) == "table" then base = row[Keys.spawns] end
        if type(base) ~= "table" and kind == "npc" and QuestieDB.QueryNPCSingle then
            base = QuestieDB.QueryNPCSingle(id, "spawns")
        end
        if type(base) ~= "table" and kind == "object" and QuestieDB.QueryObjectSingle then
            base = QuestieDB.QueryObjectSingle(id, "spawns")
        end
        local copy = {}
        if type(base) == "table" then
            for z, list in pairs(base) do copy[z] = list end
        end
        ov[Keys.spawns] = patchSpawns(copy, pts)
    end

    -- 1) Affine every pack NPC/object that has classic 1519 (or only 5581 dual).
    -- Always re-apply from PACK classic %: overrides live only in memory and die on /reload,
    -- while ravenSWAffine stamp in SavedVariables would otherwise skip and leave classic pins.
    if RavenStormwindFixes.TransformList and stamp and ns.npcData then
        local function runPack(chunkKey, kind, spawnIdx)
            local chunk = ns[chunkKey] and loadstring(ns[chunkKey])
            local pack = chunk and chunk()
            if type(pack) ~= "table" then return 0 end
            local n = 0
            for id, row in pairs(pack) do
                local spawns = type(row) == "table" and row[spawnIdx]
                if type(spawns) == "table" then
                    local src = spawns[SW] or spawns[NW]
                    if type(src) == "table" and #src > 0 then
                        local pts = RavenStormwindFixes.TransformList(src)
                        patchEntity(kind, id, pts)
                        n = n + 1
                    end
                end
            end
            return n
        end
        -- RavenPack npcKeys.spawns = 7, objectKeys.spawns = 4 (see ns.questieKeys)
        nAff = runPack("npcData", "npc", 7) + runPack("objectData", "object", 4)
        local g = Questie and Questie.db and Questie.db.global
        if g then g.ravenSWAffine = stamp end
    end

    -- 2) Manual measured overrides win (already Raven %).
    local fixes = RavenStormwindFixes.npcSpawns1519
    if type(fixes) == "table" and QuestieDB.npcKeys then
        for id, pts in pairs(fixes) do
            if type(pts) == "table" then
                patchEntity("npc", id, pts)
                nMan = nMan + 1
            end
        end
    end
    return nAff, nMan
end

function RavenMerge:ShouldRecompile()
    local g = Questie and Questie.db and Questie.db.global
    if not g then return false end
    return g.ravenPackBuild ~= packStamp()
end

function RavenMerge:MarkCompiled()
    local g = Questie and Questie.db and Questie.db.global
    if g then
        g.ravenPackBuild = packStamp()
    end
end

local function applyZonesAndCategories()
    local zoneTables = ZoneDB and ZoneDB.GetZoneTables and ZoneDB:GetZoneTables()
    local areaToUi = zoneTables and zoneTables[1]
    if type(areaToUi) == "table" and ns.uiMaps then
        for areaId, uiMapId in pairs(ns.uiMaps) do
            if areaToUi[areaId] == nil then
                areaToUi[areaId] = uiMapId
            end
        end
        local getAreaId = ZoneDB.GetAreaIdByUiMapId
        if getAreaId and ns.uiMapsReverse and not ZoneDB.RavenUiMaps then
            ZoneDB.GetAreaIdByUiMapId = function(self, uiMapId)
                local pinned = ns.uiMapsReverse[uiMapId]
                if pinned ~= nil then return pinned end
                return getAreaId(self, uiMapId)
            end
            ZoneDB.RavenUiMaps = true
        end
        -- dungeons[areaId] = {name, altId, parentAreaId}; GetParentZoneId иначе nil для 1337
        local dungeons = zoneTables[2]
        if type(dungeons) == "table" and not ZoneDB.RavenDungeonParent then
            local origParent = ZoneDB.GetParentZoneId
            ZoneDB.GetParentZoneId = function(self, areaId)
                local hit = origParent and origParent(self, areaId)
                if hit then return hit end
                local entry = dungeons[areaId]
                if type(entry) == "table" and entry[3] then return entry[3] end
                return nil
            end
            ZoneDB.RavenDungeonParent = true
        end
    end

    for id, name in pairs({ [-373] = "Jewelcrafting", [-669] = "Survival", [-670] = "Other professions" }) do
        if type(l10n.zoneCategoryLookup) == "table" and type(l10n.zoneCategoryLookup[6]) == "table"
            and l10n.zoneCategoryLookup[6][id] == nil then
            l10n.zoneCategoryLookup[6][id] = name
        end
        if type(l10n.questCategoryLookup) == "table" and l10n.questCategoryLookup[id] == nil then
            l10n.questCategoryLookup[id] = name
        end
    end

    local lookup = l10n.zoneLookup
    if type(lookup) == "table" and ns.zoneNames then
        local getAreaInfo = C_Map and C_Map.GetAreaInfo
        for areaId, entry in pairs(ns.zoneNames) do
            local named = false
            for _, zones in pairs(lookup) do
                if type(zones) == "table" and zones[areaId] ~= nil then
                    named = true
                    break
                end
            end
            if not named then
                if lookup[entry[1]] == nil then lookup[entry[1]] = {} end
                local name = getAreaInfo and getAreaInfo(areaId)
                name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
                if type(lookup[entry[1]]) == "table" then
                    lookup[entry[1]][areaId] = name ~= "" and name or entry[2]
                end
            end
        end
    end

    if type(l10n.questCategoryLookup) == "table" and ns.sortNames then
        for sort, name in pairs(ns.sortNames) do
            if l10n.questCategoryLookup[sort] == nil then
                l10n.questCategoryLookup[sort] = name
            end
        end
    end

    local categories = l10n.zoneCategoryLookup
    local continentOf = QuestiePlayer and QuestiePlayer.GetCurrentContinentId
    if type(continentOf) == "function" and type(categories) == "table" and not QuestiePlayer.RavenContinent then
        QuestiePlayer.GetCurrentContinentId = function(self, ...)
            local id = continentOf(self, ...)
            if categories[id] ~= nil then return id end
            local zone = type(self.GetCurrentZoneId) == "function" and self:GetCurrentZoneId() or nil
            for category, zones in pairs(categories) do
                if type(zones) == "table" and zone ~= nil and zones[zone] ~= nil then return category end
            end
            return 1
        end
        QuestiePlayer.RavenContinent = true
    end

    local zonesWith = ZoneDB and ZoneDB.GetZonesWithQuests
    if type(zonesWith) == "function" and ns.journeyZones and not ZoneDB.RavenJourney then
        ZoneDB.GetZonesWithQuests = function(self, ...)
            local map = zonesWith(self, ...)
            if type(map) ~= "table" or type(QuestieDB.QueryQuestSingle) ~= "function" then return map end
            local fixes = QuestieLoader:ImportModule("QuestieCorrections")
            local hidden = type(fixes.hiddenQuests) == "table" and fixes.hiddenQuests or {}
            for questId, zone in pairs(ns.journeyZones) do
                if not hidden[questId] and (QuestieDB.QuestPointers == nil or QuestieDB.QuestPointers[questId])
                    and QuestiePlayer:HasRequiredRace(QuestieDB.QueryQuestSingle(questId, "requiredRaces"))
                    and QuestiePlayer:HasRequiredClass(QuestieDB.QueryQuestSingle(questId, "requiredClasses")) then
                    local key = (type(self.GetParentZoneId) == "function" and self:GetParentZoneId(zone)) or zone
                    map[key] = map[key] or {}
                    map[key][questId] = true
                end
            end
            return map
        end
        ZoneDB.RavenJourney = true
    end
end

local function applyBlacklistsAndEvents()
    if QuestieEvent and type(QuestieEvent.eventQuests) == "table" and ns.seasonalQuests and not QuestieEvent.RavenSeasons then
        local brewfest = false
        for questId, festival in pairs(ns.seasonalQuests) do
            table.insert(QuestieEvent.eventQuests, { festival, questId })
            if festival == "Brewfest" then brewfest = true end
        end
        local fixes = QuestieEvent.eventDateCorrections
        if brewfest and type(fixes) == "table" and type(fixes.CLASSIC) == "table" and fixes.CLASSIC.Brewfest == false then
            fixes.CLASSIC.Brewfest = nil
        end
        QuestieEvent.RavenSeasons = true
    end

    if QuestieQuestBlacklist and type(QuestieQuestBlacklist.Load) == "function"
        and (ns.hiddenQuests or ns.unhideQuests or ns.seasonalQuests) and not QuestieQuestBlacklist.RavenHidden then
        local load = QuestieQuestBlacklist.Load
        QuestieQuestBlacklist.Load = function(self, ...)
            local list = load(self, ...)
            if type(list) == "table" then
                for questId in pairs(ns.hiddenQuests or {}) do list[questId] = true end
                for questId in pairs(ns.unhideQuests or {}) do list[questId] = nil end
                for questId in pairs(ns.seasonalQuests or {}) do list[questId] = true end
            end
            return list
        end
        QuestieQuestBlacklist.RavenHidden = true
    end
end

local function hookStarters()
    local chunk = ns.starters and loadstring(ns.starters)
    starters = chunk and chunk() or {}
    ns.starters = nil

    local function starterLine(tooltip)
        local _, link = tooltip:GetItem()
        local item = link and tonumber(link:match("item:(%d+)"))
        local entry = item and starters[item]
        if not entry then return end
        local questId = entry[1]
        local name = type(QuestieDB.QueryQuestSingle) == "function" and QuestieDB.QueryQuestSingle(questId, "name")
        if type(name) ~= "string" then return end
        local char = Questie and Questie.db and Questie.db.char
        if char and char.complete and char.complete[questId] then
            tooltip:AddLine("Begins a quest you have done: " .. name, 0.6, 0.6, 0.6)
        elseif QuestiePlayer and QuestiePlayer.currentQuestlog and QuestiePlayer.currentQuestlog[questId] then
            tooltip:AddLine("Begins a quest in your log: " .. name, 0.6, 0.6, 0.6)
        elseif type(QuestieDB.IsDoable) == "function" and not QuestieDB:IsDoable(questId) then
            tooltip:AddLine("Begins a quest you cannot take: " .. name, 0.6, 0.6, 0.6)
        else
            tooltip:AddLine("Begins a quest: " .. name, 0.878, 0.478, 0.122)
        end
        tooltip:Show()
    end
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript and not tip.RavenStarters then
            tip:HookScript("OnTooltipSetItem", function(self) pcall(starterLine, self) end)
            tip.RavenStarters = true
        end
    end

    local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest")
    local private = QuestieQuest and QuestieQuest.private
    if type(private) ~= "table" or type(private.DrawAvailableQuest) ~= "function" or private.RavenStarters then
        return
    end
    local drawAvailable = private.DrawAvailableQuest
    local STARTER_CLUSTER = 3
    local drawn = {}
    local function near(key, x, y)
        for _, p in ipairs(drawn[key] or {}) do
            if math.abs(p[1] - x) < STARTER_CLUSTER and math.abs(p[2] - y) < STARTER_CLUSTER then return true end
        end
        drawn[key] = drawn[key] or {}
        table.insert(drawn[key], { x, y })
        return false
    end
    local function drawAt(quest, itemName, kind, sourceId, record)
        if not (record and record.spawns) then return end
        local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
        local scale = (Questie.db.global and Questie.db.global.availableScale) or 1.3
        for zone, spawns in pairs(record.spawns) do
            for _, coords in ipairs(spawns) do
                local data = {
                    Id = quest.Id, Icon = private:GetQuestIcon(quest), IconScale = scale,
                    GetIconScale = function() return (Questie.db.global and Questie.db.global.availableScale) or 1.3 end,
                    Type = "available", QuestData = quest, IsObjectiveNote = false,
                    Name = itemName .. " (" .. tostring(record.name) .. ")"
                }
                if coords[1] == -1 or coords[2] == -1 then
                    for _, at in ipairs(ZoneDB:GetDungeonLocation(zone) or {}) do
                        if not near(quest.Id .. ":" .. at[1], at[2], at[3]) then
                            QuestieMap:DrawWorldIcon(data, at[1], at[2], at[3])
                        end
                    end
                elseif not near(quest.Id .. ":" .. zone, coords[1], coords[2]) then
                    QuestieMap:DrawWorldIcon(data, zone, coords[1], coords[2])
                end
            end
        end
    end
    local function drawItemStarts(quest)
        for key in pairs(drawn) do
            if key:find("^" .. quest.Id .. ":") then drawn[key] = nil end
        end
        for _, item in ipairs(quest.Starts.Item) do
            local entry = starters[item]
            if entry and entry[1] == quest.Id then
                local itemName = QuestieDB.QueryItemSingle and QuestieDB.QueryItemSingle(item, "name") or ("item " .. item)
                for _, npcId in ipairs(entry[2] or {}) do
                    drawAt(quest, itemName, "npc", npcId, QuestieDB:GetNPC(npcId))
                end
                for _, objId in ipairs(entry[3] or {}) do
                    drawAt(quest, itemName, "object", objId, QuestieDB:GetObject(objId))
                end
            end
        end
    end
    private.DrawAvailableQuest = function(self, quest, ...)
        local r = drawAvailable(self, quest, ...)
        if type(quest) == "table" and type(quest.Starts) == "table" and quest.Starts.Item
            and quest.Starts.NPC == nil and quest.Starts.GameObject == nil then
            pcall(drawItemStarts, quest)
        end
        return r
    end
    private.RavenStarters = true
end

local function hookPreCompile()
    local chunk = ns.serverMasks and loadstring(ns.serverMasks)
    serverMasks = chunk and chunk() or {}
    ns.serverMasks = nil

    if QuestieCorrections and type(QuestieCorrections.PreCompile) == "function" and not QuestieCorrections.RavenRaces then
        local preCompile = QuestieCorrections.PreCompile
        QuestieCorrections.PreCompile = function(self, ...)
            local races = QuestieDB.questKeys and QuestieDB.questKeys.requiredRaces or 6
            local classes = QuestieDB.questKeys and QuestieDB.questKeys.requiredClasses or 7
            for id, mine in pairs(ns.ourQuests or {}) do
                local row = QuestieDB.questData and QuestieDB.questData[id]
                if type(row) == "table" and row ~= mine then
                    for k, v in pairs(mine) do
                        if row[k] == nil then row[k] = v end
                    end
                end
            end
            local gk = QuestieDB.questKeys and QuestieDB.questKeys.preQuestGroup or 12
            local sk = QuestieDB.questKeys and QuestieDB.questKeys.preQuestSingle or 13
            local removed = ns.hiddenQuests or {}
            local function dead(list, all)
                if type(list) ~= "table" or #list == 0 then return false end
                local n = 0
                for _, p in ipairs(list) do
                    if removed[p] then
                        if all then return true end
                        n = n + 1
                    end
                end
                return not all and n == #list
            end
            local function without(list)
                local out = {}
                for _, p in ipairs(list) do
                    if not removed[p] then out[#out + 1] = p end
                end
                return #out > 0 and out or nil
            end
            for id, row in pairs(QuestieDB.questData or {}) do
                if type(row) == "table" and not removed[id] and (dead(row[gk], true) or dead(row[sk], false)) then
                    local mine = ns.ourQuests and ns.ourQuests[id]
                    if type(mine) == "table" and mine ~= row then
                        row[gk], row[sk] = mine[gk], mine[sk]
                    else
                        if type(row[gk]) == "table" then row[gk] = without(row[gk]) end
                        if type(row[sk]) == "table" then row[sk] = without(row[sk]) end
                    end
                end
            end
            ns.ourQuests = nil
            for id, m in pairs(serverMasks) do
                local row = QuestieDB.questData and QuestieDB.questData[id]
                if type(row) == "table" then
                    if m[1] >= 0 then row[races] = m[1] end
                    if m[2] >= 0 then row[classes] = m[2] end
                end
            end
            for _, row in pairs(QuestieDB.questData or {}) do
                local mask = type(row) == "table" and row[races]
                if type(mask) == "number" and mask > 0 then
                    local wide = mask
                    if band(wide, 77) == 77 then wide = bor(wide, 512) end
                    if band(wide, 178) == 178 then wide = bor(wide, 256) end
                    if wide ~= mask then row[races] = wide end
                end
            end
            local flags = QuestieDB.questKeys and QuestieDB.questKeys.specialFlags or 24
            for id, rep in pairs(ns.serverRepeat or {}) do
                local row = QuestieDB.questData and QuestieDB.questData[id]
                if type(row) == "table" then
                    local f = type(row[flags]) == "number" and row[flags] or 0
                    if (f % 2 == 1) ~= (rep == 1) then
                        row[flags] = rep == 1 and f + 1 or f - 1
                    end
                end
            end
            return preCompile(self, ...)
        end
        QuestieCorrections.RavenRaces = true
    end

    if QuestieQuestFixes and type(QuestieQuestFixes.LoadFactionFixes) == "function" and not QuestieQuestFixes.RavenRaces then
        local loadFaction = QuestieQuestFixes.LoadFactionFixes
        QuestieQuestFixes.LoadFactionFixes = function(self, ...)
            local fixes = loadFaction(self, ...)
            local races = QuestieDB.questKeys and QuestieDB.questKeys.requiredRaces or 6
            local classes = QuestieDB.questKeys and QuestieDB.questKeys.requiredClasses or 7
            if type(fixes) == "table" then
                for id, fields in pairs(fixes) do
                    local m = serverMasks[id]
                    if type(fields) == "table" then
                        if fields[races] ~= nil then
                            if m and m[1] >= 0 then
                                fields[races] = m[1]
                            elseif type(fields[races]) == "number" and fields[races] > 0 then
                                local wide = fields[races]
                                if band(wide, 77) == 77 then wide = bor(wide, 512) end
                                if band(wide, 178) == 178 then wide = bor(wide, 256) end
                                fields[races] = wide
                            end
                        end
                        if fields[classes] ~= nil and m and m[2] >= 0 then
                            fields[classes] = m[2]
                        end
                    end
                end
            end
            return fixes
        end
        QuestieQuestFixes.RavenRaces = true
    end
end

--- Merge Raven Lua pack tables into QuestieDB.* after stock LoadDatabase.
function RavenMerge:MergeBaseDB()
    local added = {}
    local tables = ZoneDB and ZoneDB.GetZoneTables and ZoneDB:GetZoneTables()
    local function placeable(z, list)
        if type(tables) ~= "table" then return true end
        local a2u, locations, dparents, subzones = tables[1] or {}, tables[3] or {}, tables[4] or {}, tables[5] or {}
        local real = false
        for _, c in ipairs(list or {}) do
            if type(c) == "table" and not (c[1] == -1 and c[2] == -1) then real = true end
        end
        if not real then return locations[z] ~= nil or a2u[z] ~= nil end
        if a2u[z] then return true end
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(z)
        local parent = (info and info.parentMapID) or (type(dparents[z]) == "number" and dparents[z]) or subzones[z]
        return parent ~= nil and a2u[parent] ~= nil
    end
    local function drawable(key, row)
        local K = key == "npcData" and QuestieDB.npcKeys or key == "objectData" and QuestieDB.objectKeys or nil
        local at = K and K.spawns
        local spawns = at and type(row) == "table" and row[at]
        if type(spawns) ~= "table" then return true end
        local had, kept = false, 0
        for z, list in pairs(spawns) do
            had = true
            if placeable(z, list) then kept = kept + 1 else spawns[z] = nil end
        end
        return not had or kept > 0
    end
    for _, key in ipairs({ "questData", "npcData", "objectData", "itemData" }) do
        local chunk = ns[key] and loadstring(ns[key])
        local ours = chunk and chunk()
        if ours and QuestieDB[key] then
            local n = 0
            for id, row in pairs(ours) do
                local okd, keep = pcall(drawable, key, row)
                if okd and not keep and QuestieDB[key][id] ~= nil then
                    -- keep stock row when every Raven spawn is unplaceable
                else
                    local theirs = key == "itemData" and QuestieDB[key][id]
                    if type(theirs) == "table" and type(row) == "table" and theirs[1] == row[1] then
                        for k, v in pairs(theirs) do
                            local mine = row[k]
                            if mine == nil or mine == 0 or (type(mine) == "table" and next(mine) == nil) then
                                row[k] = v
                            end
                        end
                    end
                    QuestieDB[key][id] = row
                    n = n + 1
                end
            end
            if key == "questData" then ns.ourQuests = ours end
            added[#added + 1] = key .. " " .. n
        end
        ns[key] = nil
    end
    local fixes = ns.questFixes and loadstring(ns.questFixes)
    fixes = fixes and fixes()
    if fixes and QuestieDB.questData then
        local n = 0
        for id, fields in pairs(fixes) do
            local row = QuestieDB.questData[id]
            if type(row) == "table" then
                for key, value in pairs(fields) do row[key] = value end
                n = n + 1
            end
        end
        added[#added + 1] = "questFixes " .. n
    end
    ns.questFixes = nil
    local oZones, oItems = applyObjectImport()
    if oZones > 0 or oItems > 0 then
        added[#added + 1] = "objImport zones=" .. oZones .. " itemO=" .. oItems
    end
    local swAff, swMan = applyStormwindNpcFixes()
    if (swAff or 0) > 0 or (swMan or 0) > 0 then
        added[#added + 1] = "swAffine " .. tostring(swAff or 0) .. "+man " .. tostring(swMan or 0)
    end
    local ei = applyExploreImport()
    if (ei or 0) > 0 then
        added[#added + 1] = "explore " .. tostring(ei)
    end
    RavenMerge:MarkCompiled()
    -- merge summary kept in `added` / packStamp for ShouldRecompile; no chat spam on login
end

function RavenMerge:Bootstrap()
    if bootstrapped then return end
    bootstrapped = true
    -- Skip shape check when packed into the same fork; still drop keys table to free memory.
    ns.questieKeys = nil
    applyZonesAndCategories()
    applyBlacklistsAndEvents()
    hookStarters()
    hookPreCompile()
    -- Explore/areatrigger pins from pfQuest 1.18 (RavenExploreImport).
    applyExploreImport()
    applyStormwindNpcFixes()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, applyExploreImport)
        C_Timer.After(5, applyExploreImport)
        C_Timer.After(1, applyStormwindNpcFixes)
        C_Timer.After(5, applyStormwindNpcFixes)
    end
end
