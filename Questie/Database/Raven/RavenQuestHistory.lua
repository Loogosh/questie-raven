-- RavenQuestHistory: restore completed-quest list the way ClassicAPI/pfQuest do on Turtle 1.18.
-- Client GetQuestsCompleted() / IsQuestFlaggedCompleted are empty stubs on Raven 1.14.2.
-- Turtle-lineage servers answer player command ".queststatuses" with CHAT_MSG_ADDON
-- prefix TWQUEST (see raven-era-mods/reference/ClassicAPI/src/quest/Completed.cpp).
---@class RavenQuestHistory
local RavenQuestHistory = QuestieLoader:CreateModule("RavenQuestHistory")

local MESSAGE_SPLIT = 2000 -- tortoise ChatHandler::HandleQuestStatusesCommand MaxMessageSize
local PREFIX = "TWQUEST"

local incoming = {}
local pending = false
local requested = false
local bootstrapped = false

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function applyCompleted(ids)
    if type(Questie.db) ~= "table" or type(Questie.db.char) ~= "table" then
        return
    end
    local complete = Questie.db.char.complete
    if type(complete) ~= "table" then
        complete = {}
        Questie.db.char.complete = complete
    end
    local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest")
    local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
    local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
    local added = 0
    for id in pairs(ids) do
        if not complete[id] then
            added = added + 1
        end
        complete[id] = true
        -- Pins may already be drawn before history arrives; available-quest
        -- redraw skips completed IDs and would leave stale "!" icons.
        if QuestieMap and QuestieMap.UnloadQuestFrames then
            QuestieMap:UnloadQuestFrames(id)
        end
        if QuestieTooltips and QuestieTooltips.RemoveQuest then
            QuestieTooltips:RemoveQuest(id)
        end
        if QuestieQuest and QuestieQuest.availableQuests then
            QuestieQuest.availableQuests[id] = nil
        end
    end
    Questie.db.char.ravenCompleteFromServer = true
    Questie.db.char.ravenCompleteCount = count(complete)
    Questie:Debug(Questie.DEBUG_INFO, "[RavenQuestHistory] server completed:", count(ids),
        "merged into", Questie.db.char.ravenCompleteCount, "(+" .. added .. ")")
end

local function parseChunk(msg)
    if type(msg) ~= "string" then return 0 end
    local n = 0
    for idStr in msg:gmatch("%d+") do
        local id = tonumber(idStr)
        if id and id > 0 then
            incoming[id] = true
            n = n + 1
        end
    end
    return n
end

local function onAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    if channel ~= "GUILD" then return end
    -- Server echoes as the player; ignore other guild members' forged TWQUEST.
    local me = UnitName("player")
    if sender and me and sender ~= me and not tostring(sender):find("^" .. me .. "%-") then
        return
    end
    parseChunk(message)
    -- Last fragment is shorter than MESSAGE_SPLIT (possibly empty).
    if type(message) == "string" and #message >= MESSAGE_SPLIT then
        return
    end
    local ids = incoming
    incoming = {}
    pending = false
    applyCompleted(ids)
end

function RavenQuestHistory:Request()
    if pending then return end
    incoming = {}
    pending = true
    requested = true
    -- ClassicAPI sends CMSG_MESSAGECHAT GUILD / LANG_UNIVERSAL / ".queststatuses".
    -- SendChatMessage does the same; server parses commands before guild lookup.
    local ok, err = pcall(SendChatMessage, ".queststatuses", "GUILD")
    if not ok then
        pending = false
        Questie:Debug(Questie.DEBUG_CRITICAL, "[RavenQuestHistory] SendChatMessage failed:", err)
    else
        Questie:Debug(Questie.DEBUG_INFO, "[RavenQuestHistory] queried .queststatuses")
    end
end

function RavenQuestHistory:Bootstrap()
    if bootstrapped then return end
    bootstrapped = true

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end

    local frame = CreateFrame("Frame", "QuestieRavenQuestHistoryFrame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            onAddonMessage(...)
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Delay: server answers only while STATUS_LOGGEDIN.
            if C_Timer and C_Timer.After then
                C_Timer.After(1.5, function()
                    RavenQuestHistory:Request()
                end)
            else
                RavenQuestHistory:Request()
            end
        end
    end)

    -- QuestieInit runs after PLAYER_ENTERING_WORLD on /reload, so the event
    -- above is often missed — always schedule a query from Bootstrap too.
    if C_Timer and C_Timer.After then
        C_Timer.After(2.0, function()
            RavenQuestHistory:Request()
        end)
    else
        RavenQuestHistory:Request()
    end

    -- pfQuest-compatible shim when ClassicAPI is absent
    if type(QueryQuestsCompleted) ~= "function" then
        _G.QueryQuestsCompleted = function()
            RavenQuestHistory:Request()
        end
    end
end
