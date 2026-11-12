-- Collect Stormwind pack% → real% samples for refining the affine grid.
-- /ravcal          sample current target (must be NPC with 1519/5581 spawn in pack)
-- /ravcal list     show samples
-- /ravcal clear    wipe samples
-- /ravcal suggest  print mean Δ and remind affine is in RavenStormwindFixes
---@class RavenMapCalibrate
local M = QuestieLoader:CreateModule("RavenMapCalibrate")
---@type RavenPack
local RavenPack = QuestieLoader:ImportModule("RavenPack")
---@type RavenStormwindFixes
local RavenStormwindFixes = QuestieLoader:ImportModule("RavenStormwindFixes")
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

local SW, NW = 1519, 5581

local function db()
    if not (Questie and Questie.db and Questie.db.global) then return nil end
    Questie.db.global.ravenMapCal = Questie.db.global.ravenMapCal or { samples = {} }
    return Questie.db.global.ravenMapCal
end

local function packSpawn(id)
    if not (RavenPack and RavenPack.npcData) then return nil end
    local chunk = loadstring(RavenPack.npcData)
    local pack = chunk and chunk()
    local row = pack and pack[id]
    local spawns = row and row[7]
    if type(spawns) ~= "table" then return nil end
    local list = spawns[SW] or spawns[NW]
    return list and list[1] or nil, list
end

local function playerPct()
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return { x * 100, y * 100 }, mapID
end

local function sample()
    local guid = UnitGUID("target")
    if not guid then
        print("|cffE07A1FRavenCal|r target an NPC first")
        return
    end
    local id = tonumber(guid:match("Creature%-0%-%d+%-%d+%-%d+%-(%d+)"))
    if not id then
        print("|cffE07A1FRavenCal|r not a creature")
        return
    end
    local before = packSpawn(id)
    if not before then
        print("|cffE07A1FRavenCal|r npc " .. id .. " has no pack 1519/5581 spawn")
        return
    end
    local after, mapID = playerPct()
    if not after then
        print("|cffE07A1FRavenCal|r no player map position")
        return
    end
    local name = UnitName("target")
    local affX, affY = RavenStormwindFixes.Transform(before[1], before[2])
    local store = db()
    if not store then return end
    store.samples[id] = {
        name = name,
        before = { before[1], before[2] },
        after = { after[1], after[2] },
        affine = { affX, affY },
        mapID = mapID,
        dx = after[1] - before[1],
        dy = after[2] - before[2],
        affErr = math.sqrt((affX - after[1]) ^ 2 + (affY - after[2]) ^ 2),
    }
    print(string.format(
        "|cffE07A1FRavenCal|r %s (%d): pack (%.2f,%.2f) → you (%.2f,%.2f) | affine (%.2f,%.2f) err=%.2f",
        name or "?", id, before[1], before[2], after[1], after[2], affX, affY,
        store.samples[id].affErr
    ))
end

local function list()
    local store = db()
    if not store or not store.samples then
        print("|cffE07A1FRavenCal|r no samples")
        return
    end
    local n = 0
    for id, s in pairs(store.samples) do
        n = n + 1
        print(string.format(
            "  %d %s  before=%.2f,%.2f after=%.2f,%.2f affErr=%.2f",
            id, s.name or "?", s.before[1], s.before[2], s.after[1], s.after[2], s.affErr or -1
        ))
    end
    print("|cffE07A1FRavenCal|r samples: " .. n)
end

local function suggest()
    local store = db()
    if not store or not store.samples then return end
    local sx, sy, n = 0, 0, 0
    local maxErr = 0
    for _, s in pairs(store.samples) do
        sx = sx + (s.dx or 0)
        sy = sy + (s.dy or 0)
        n = n + 1
        if (s.affErr or 0) > maxErr then maxErr = s.affErr end
    end
    if n == 0 then
        print("|cffE07A1FRavenCal|r no samples")
        return
    end
    print(string.format(
        "|cffE07A1FRavenCal|r n=%d meanΔ=(%.2f,%.2f) maxAffineErr=%.2f — if maxErr>2, add points and refit Tools/sw_affine_fit.py",
        n, sx / n, sy / n, maxErr
    ))
end

SLASH_RAVENMAPCAL1 = "/ravcal"
SlashCmdList.RAVENMAPCAL = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "sample" then
        sample()
    elseif msg == "list" then
        list()
    elseif msg == "clear" then
        local store = db()
        if store then store.samples = {} end
        print("|cffE07A1FRavenCal|r cleared")
    elseif msg == "suggest" then
        suggest()
    else
        print("|cffE07A1FRavenCal|r /ravcal | list | clear | suggest")
    end
end

return M
