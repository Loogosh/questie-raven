---@class Migration
local Migration = QuestieLoader:CreateModule("Migration")

-- add functions to this table to migrate users who have not yet run said function.
-- make sure to always add to the end of the table as it runs first to last
local migrationFunctions = {
    [1] = function(hasRunAccountWide)
        Questie:Print("[Migration] Migrating Questie for v6.0.0")
    
        -- This is not needed anymore since we calculate the quests with zones at each login.
        -- If not we would have to store the zoneMap for each character because we only show
        -- quests in the Journey a character (race + class) can accept.
        if not hasRunAccountWide then
            Questie.db.global.zoneMapCache = nil
        end
    
        if Questie.db.char.manualMinLevelOffset and Questie.db.char.absoluteLevelOffset then
            Questie.db.char.manualMinLevelOffset = false
            Questie.db.char.absoluteLevelOffset = false
        end
    
        local removedPartyEntries = 0
    
        for _, entry in pairs(Questie.db.char.journey) do
            if entry.Party then
                entry.Party = nil
                removedPartyEntries = removedPartyEntries + 1
            end
        end
    
        Questie:Print("[Migration] Migrated Questie to v6.0.0 and removed", removedPartyEntries, "party entries from the Journey")
    end,
    [2] = function(hasRunAccountWide)
        if not hasRunAccountWide then
            Questie.db.global.stickyDurabilityFrame = false
        end
    end,
    [3] = function(hasRunAccountWide)
        local optionsDefaults = QuestieLoader:ImportModule("QuestieOptionsDefaults"):Load()

        local journey
        local migrationTable, globalMigrationTable

        if Questie.db.char then
            journey = Questie.db.char.journey
        end

        if not hasRunAccountWide then
            if Questie.db.global then
                migrationTable = Questie.db.global.migrationVersion
                globalMigrationTable = Questie.db.global.globalMigrationSteps
            end
            Questie.db.global = {}
        end

        Questie.db.char = {}

        if not hasRunAccountWide then
            for k,v in pairs(optionsDefaults.global) do
                Questie.db.global[k] = v
            end
        end

        -- only toggle questie if it's off (must be called before resetting the value)
        if (not Questie.db.char.enabled) then
            Questie.db.char.enabled = true
        end

        for k,v in pairs(optionsDefaults.char) do
            Questie.db.char[k] = v
        end

        Questie.db.profile.minimap.hide = optionsDefaults.profile.minimap.hide;

        if journey then
            Questie.db.char.journey = journey
        end

        if not hasRunAccountWide then 
            if migrationTable then
                Questie.db.global.migrationVersion = migrationTable
            end

            if globalMigrationTable then
                Questie.db.global.globalMigrationSteps = globalMigrationTable
            end

            Questie.db.global.dbIsCompiled = false
        end
    end,
    [4] = function()
        Questie.db.char.enableMinimalisticIcons = nil -- Remove unused remnants of minimalistic icons
    end,
    [5] = function()
        Questie.db.char.showEventQuests = true -- Enable event quests again since some might have disabled it to hide the delayed Midsummer quests
        if Questie.db.char.townsfolkConfig then
            Questie.db.char.townsfolkConfig["Meeting Stones"] = true
        end
    end,
    [6] = function()
        if (not Questie.db.char.questAnnounce) or Questie.db.char.questAnnounce == "disabled" then
            Questie.db.char.questAnnounce = false
        else
            Questie.db.char.questAnnounce = true
        end
    end,
    [7] =  function()
        Questie.db.global.hasSeenBetaMessage = nil
    end,
}

function Migration:Migrate()

    if not Questie.db.global.migrationVersion then
        Questie.db.global.migrationVersion = {}
    end

    if not Questie.db.global.globalMigrationSteps then
        Questie.db.global.globalMigrationSteps = {}
    end

    local player = UnitName("Player") .. GetRealmName()
    local currentVersion = Questie.db.global.migrationVersion[player] or 0
    local targetVersion = table.getn(migrationFunctions)

    Questie:Debug(Questie.DEBUG_DEVELOP, "[Migration] Starting Questie migration for targetVersion", targetVersion)

    while currentVersion < targetVersion do
        currentVersion = currentVersion + 1
        migrationFunctions[currentVersion](Questie.db.global.globalMigrationSteps[currentVersion])
        Questie.db.global.globalMigrationSteps[currentVersion] = true
    end

    Questie.db.global.migrationVersion[player] = currentVersion

    -- AceDB first-login relink: migration step 3 may assign new tables to Questie.db.global/char
    -- that AceDB never wrote back to SavedVariables (stock Questie recompiles every second login).
    local sv, keys = rawget(Questie.db, "sv"), rawget(Questie.db, "keys")
    if type(sv) == "table" and type(keys) == "table" then
        local g = rawget(Questie.db, "global")
        if type(g) == "table" and sv.global ~= g then
            sv.global = g
        end
        local c, key = rawget(Questie.db, "char"), keys.char
        if type(c) == "table" and key ~= nil then
            if type(sv.char) ~= "table" then sv.char = {} end
            if sv.char[key] ~= c then
                sv.char[key] = c
            end
        end
    end
end
