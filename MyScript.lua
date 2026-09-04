-- ============================================================
--  Anime Card Farm  –  Rayfield Edition
--  JonYueroHub  ·  Config managed via custom Settings tab.
--
--  SECURITY NOTE
--  This direct-execution check prevents simple bypasses such as
--  running this file directly without first running Loader.lua.
--  It is NOT unbreakable: a determined user can fabricate
--  getgenv().JYH_SESSION because all client-side state can be
--  modified.  For stronger protection consider a server-issued
--  short-lived launch token, backend verification from this
--  script, authenticated script delivery, or obfuscation as an
--  additional deterrent.  Do not add fake cryptography or
--  hardcoded secrets here.
-- ============================================================

-- ── URL constants (single source of truth) ───────────────────
local LOADER_URL    = "https://raw.githubusercontent.com/JonYuero/JYH-Test/refs/heads/main/Loader.lua"
local ANIME_CARD_FARM_URL = "https://raw.githubusercontent.com/JonYuero/JYH-Test/refs/heads/main/MyScript.lua"

local VALID_LICENSE_TYPES = { FREE = true, ["30D"] = true, LIFETIME = true }

-- ── Environment ───────────────────────────────────────────────
local ENV = getgenv()
local HttpService = game:GetService("HttpService")

-- The device ID must use the same global path and validation rules as the
-- Loader. This is a persistent device-installation ID, not an unbreakable
-- hardware fingerprint. Executor file resets or copying this file can
-- change or imitate the installation identity.
local DEVICE_ROOT = "Jon Yuero Hub"
local DEVICE_FILE = DEVICE_ROOT .. "/DeviceId.txt"

local function getPersistentDeviceId()
    local localPlayer = game:GetService("Players").LocalPlayer
    -- Compatibility fallback for executors without file APIs. This keeps
    -- ACF from crashing, but remains account-based on that executor.
    local fallback = "ROBLOX-USER-" .. tostring(localPlayer.UserId)
    local fileApisSupported = (
        type(makefolder) == "function" and type(isfolder) == "function"
        and type(writefile) == "function" and type(readfile) == "function"
        and type(isfile) == "function"
    )
    if not fileApisSupported then
        return fallback
    end

    local folderOk = pcall(function()
        if not isfolder(DEVICE_ROOT) then
            makefolder(DEVICE_ROOT)
        end
    end)
    if not folderOk then
        return fallback
    end

    local folderExistsOk, folderExists = pcall(isfolder, DEVICE_ROOT)
    if not folderExistsOk or not folderExists then
        return fallback
    end

    local fileExistsOk, fileExists = pcall(isfile, DEVICE_FILE)
    if fileExistsOk and fileExists then
        local readOk, raw = pcall(readfile, DEVICE_FILE)
        if readOk and type(raw) == "string" then
            local savedId = raw:match("^%s*(.-)%s*$")
            if #savedId >= 16 and #savedId <= 128 then
                return savedId
            end
        end
    end

    local guidOk, guid = pcall(HttpService.GenerateGUID, HttpService, false)
    if not guidOk or type(guid) ~= "string" or guid == "" then
        return fallback
    end

    local deviceId = "JYH-DEVICE-" .. guid
    pcall(writefile, DEVICE_FILE, deviceId)
    return deviceId
end

-- ── Lightweight notification (available before Rayfield) ──────
local function coreNotify(title, text)
    pcall(
        game:GetService("StarterGui").SetCore,
        game:GetService("StarterGui"),
        "SendNotification",
        { Title = title, Text = text, Duration = 5 }
    )
end

-- ── Safe Lua source fetcher ───────────────────────────────────
-- Returns a compiled function on success, or nil + reason on failure.
local function fetchLua(url)
    local ok, raw = pcall(game.HttpGet, game, url, true)
    if not ok or type(raw) ~= "string" or raw == "" then
        return nil, "HttpGet failed: " .. tostring(raw)
    end
    local head = raw:sub(1, 300):lower()
    if head:find("<!doctype", 1, true)
    or head:find("<html",     1, true)
    or head:find("404: not found", 1, true)
    or head:find("rate limit",     1, true)
    or head:find("access denied",  1, true) then
        return nil, "Server returned HTML or error page instead of Lua source"
    end
    local fn, err = loadstring(raw)
    if not fn then
        return nil, "Compile error: " .. tostring(err)
    end
    return fn
end

-- ── Return to the official loader ────────────────────────────
-- Shows the reason, clears session state, and re-executes Loader.lua.
-- A duplicate guard prevents the Loader ↔ MyScript redirect loop.
local function returnToLoader(reason)
    -- Prevent multiple concurrent redirect attempts.
    if ENV.JYH_RETURNING_TO_LOADER == true then
        return
    end
    ENV.JYH_RETURNING_TO_LOADER = true
    ENV.JYH_SESSION             = nil
    ENV.JYH_ACTIVE_SESSION      = nil

    local msg = tostring(reason or "Session validation failed")
    warn("[MyScript] Returning to Loader. Reason: " .. msg)
    coreNotify("JonYueroHub", msg .. "\nGet key first...")

    local fn, fetchErr = fetchLua(LOADER_URL)
    if not fn then
        warn("[MyScript] Could not fetch Loader: " .. tostring(fetchErr))
        coreNotify("JonYueroHub",
            "Could not load Loader automatically.\n"
            .. "Please run Loader.lua manually.")
        -- Clear the redirect guard so the user can try again.
        ENV.JYH_RETURNING_TO_LOADER = nil
        return
    end

    local execOk, execErr = pcall(fn)
    if not execOk then
        warn("[MyScript] Loader execution failed: " .. tostring(execErr))
        ENV.JYH_RETURNING_TO_LOADER = nil
    end
    -- If execOk == true, the Loader is now running; leave
    -- JYH_RETURNING_TO_LOADER = true so a stale MyScript coroutine
    -- cannot kick off another redirect.
end

-- ── Session validator ─────────────────────────────────────────
-- Validates every required field of the short-lived launch session.
-- Returns true on success; false + reason string on any failure.
-- Uses os.time() throughout — never tick() — for Unix comparisons.
local function validateSession(session)
    -- 1. Must be a table
    if type(session) ~= "table" then
        return false, "No valid key"
    end

    -- 2. authenticated must be exactly true
    if session.authenticated ~= true then
        return false, "Session is not authenticated"
    end

    -- 3. issuedAt must be numeric
    local issuedAt = tonumber(session.issuedAt)
    if not issuedAt then
        return false, "Session issuedAt is missing or non-numeric"
    end

    -- 4. Session must not be older than 120 seconds
    if math.abs(os.time() - issuedAt) > 120 then
        return false, "The loader session has expired (> 120 s old)"
    end

    -- 5. PlaceId must match
    if session.placeId ~= game.PlaceId then
        return false, "Session PlaceId does not match current game"
    end

    -- 6. The persistent device ID must match. userId remains diagnostic
    -- metadata only and must not block another Roblox account on this device.
    local currentDeviceId = getPersistentDeviceId()
    if type(session.deviceId) ~= "string" or session.deviceId == "" then
        return false, "Session device ID is missing"
    end
    if session.deviceId ~= currentDeviceId then
        return false, "Session device ID does not match this device"
    end

    -- 7. currentGame must be "Anime Card Farm"
    if session.currentGame ~= "Anime Card Farm" then
        return false, "Session currentGame mismatch"
    end

    -- 8. licenseType must be FREE, 30D, or LIFETIME
    local lt = tostring(session.licenseType or "")
    if not VALID_LICENSE_TYPES[lt] then
        return false, "Unknown license type: '" .. lt .. "'"
    end

    -- 9. loaderUrl must match the official URL when present
    if session.loaderUrl ~= nil and session.loaderUrl ~= LOADER_URL then
        return false, "Session loaderUrl does not match the official Loader"
    end

    -- 10. scriptUrl must match the official MyScript URL when present
    if session.scriptUrl ~= nil and session.scriptUrl ~= ANIME_CARD_FARM_URL then
        return false, "Session scriptUrl does not match the official game script"
    end

    return true
end

-- ════════════════════════════════════════════════════════════════
--  SESSION VALIDATION  ← must be the first executable gate
--  Nothing below this point runs if the session is invalid.
-- ════════════════════════════════════════════════════════════════
local valid, reason = validateSession(ENV.JYH_SESSION)
if not valid then
    returnToLoader(reason)
    return   -- stop all further initialization
end

-- ── Duplicate game-script guard ───────────────────────────────
-- Validation passed.  Check for an already-running instance before
-- consuming the session token so a double-run is caught cleanly.
if ENV.JYH_GAME_SCRIPT_RUNNING == true then
    coreNotify("JonYueroHub", "Anime Card Farm is already running.")
    return
end

-- From this point the script is the single authoritative instance.
ENV.JYH_GAME_SCRIPT_RUNNING = true

-- ── Consume the one-time launch session ──────────────────────
-- Copy necessary values to the long-lived active session, then nil
-- the short-lived token.  Running MyScript again directly will fail
-- validation because JYH_SESSION is now nil.
ENV.JYH_ACTIVE_SESSION = {
    authenticated = true,
    licenseType   = ENV.JYH_SESSION.licenseType,
    expiresAt     = ENV.JYH_SESSION.expiresAt,
    issuedAt      = ENV.JYH_SESSION.issuedAt,
    userId        = ENV.JYH_SESSION.userId,
    clientId      = ENV.JYH_SESSION.clientId,
    deviceId      = ENV.JYH_SESSION.deviceId,
    placeId       = ENV.JYH_SESSION.placeId,
    currentGame   = ENV.JYH_SESSION.currentGame,
}

ENV.JYH_SESSION             = nil
ENV.JYH_RETURNING_TO_LOADER = nil

-- ── Derive membership from validated license type ─────────────
-- Do NOT trust a client-supplied role string; derive it here.
local licenseType = ENV.JYH_ACTIVE_SESSION.licenseType
local isPremium   = (licenseType == "30D" or licenseType == "LIFETIME")
local userRole    = isPremium and "Premium User" or "Freemium User"

local licenseLabel = licenseType == "LIFETIME" and "Lifetime"
                  or licenseType == "30D"       and "30 Days"
                  or "FREE"

-- ── Expiry check for FREE and 30D keys ───────────────────────
-- For LIFETIME allow nil / "Never" / any non-numeric sentinel.
-- Use os.time() — never tick() — for Unix timestamp comparisons.
if licenseType ~= "LIFETIME" then
    local expiry = tonumber(ENV.JYH_ACTIVE_SESSION.expiresAt)
    if expiry and expiry <= os.time() then
        returnToLoader("The license has expired")
        return
    end
end

-- ════════════════════════════════════════════════════════════════
--  Everything below this line is the original Anime Card Farm
--  game script, unchanged except for:
--    • Rayfield now loads here (after validation) instead of at line 1.
--    • The Rayfield window name includes the membership role.
--    • The `notify` helper is defined early (before setPlotNumber).
--    • Rayfield built-in saving is disabled; the Settings tab handles it.
-- ════════════════════════════════════════════════════════════════

-- ── Load Rayfield ─────────────────────────────────────────────
local Rayfield
local rayfieldUrls = {
    "https://sirius.menu/rayfield",
    "https://raw.githubusercontent.com/UI-Hub/Rayfield/main/source",
    "https://raw.githubusercontent.com/shlexware/Rayfield/main/source",
}
for _, url in ipairs(rayfieldUrls) do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(url, true))()
    end)
    if ok and result then
        Rayfield = result
        break
    end
end
if not Rayfield then
    error("[ACF] Failed to load Rayfield from all sources. Check executor HTTP settings.")
end

-- ── Services ─────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")
local StarterGui        = game:GetService("StarterGui")

local player = Players.LocalPlayer
if not player.Character then player.CharacterAdded:Wait() end
local playerGui = player:WaitForChild("PlayerGui")

-- ── In-game notification (uses StarterGui, defined early so
--    setPlotNumber and other helpers can call it safely) ───────
local function notify(title, text)
    pcall(StarterGui.SetCore, StarterGui, "SendNotification", {
        Title = title, Text = text, Duration = 3,
    })
end

-- ── Remotes ──────────────────────────────────────────────────
local Remotes    = ReplicatedStorage:WaitForChild("Remotes")
local ConveyorRE = Remotes:WaitForChild("ConveyorRE")
local ItemsREForAutomation = Remotes:WaitForChild("ItemsRE", 15)
local PlayTimeRewardRE = Remotes:FindFirstChild("PlayTimeRewardRE")
local DailyRewardRE    = Remotes:FindFirstChild("DailyRewardRE")
local UpgradesRE       = Remotes:FindFirstChild("UpgradesRE")
-- BossRaidClient waits for this remote before it can receive the authoritative
-- open/closed state.  Do the same here instead of taking a one-time snapshot:
-- FindFirstChild can run before the remote has replicated and leave the
-- automation permanently disabled for the rest of the session.
local BossRaidRE = Remotes:WaitForChild("BossRaidRE", 15)
local GradeRollRE      = Remotes:FindFirstChild("GradeRollRE")
local TraitRollRE      = Remotes:FindFirstChild("TraitRollRE")
local Modules    = ReplicatedStorage:WaitForChild("Modules", 15)
local BossRaidConfig
if Modules and Modules:FindFirstChild("BossRaidConfig") then
    pcall(function()
        BossRaidConfig = require(Modules.BossRaidConfig)
    end)
end
local RankGradeRollConfig
if Modules and Modules:FindFirstChild("GradeRollConfig") then
    pcall(function()
        RankGradeRollConfig = require(Modules.GradeRollConfig)
    end)
end
local TraitRollConfig
if Modules and Modules:FindFirstChild("TraitRollConfig") then
    pcall(function()
        TraitRollConfig = require(Modules.TraitRollConfig)
    end)
end
local GuiManager
if Modules and Modules:FindFirstChild("GuiManager") then
    pcall(function()
        GuiManager = require(Modules.GuiManager)
    end)
end
local ConveyorPacks
if Modules then
    local conveyorPacksModule = Modules:WaitForChild("ConveyorPacks", 15)
    if conveyorPacksModule then
        pcall(function()
            ConveyorPacks = require(conveyorPacksModule)
        end)
    end
end
-- Keep raid state in one local table.  This script is close to Luau's
-- top-level local-register limit, so separate locals here can prevent the
-- entire script from compiling.
local raidState = {
    BossId = "",
    Received = false,
    Open = false,
    AlreadyUsed = false,
    RetryAt = 0,
    DifficultyOptions = {},
    CompletedDifficulties = {},
    AttemptConsumed = false,
    ClosedSince = nil,
    InfoParagraph = nil,
    TimerText = "Searching for Boss Raid timer...",
    DifficultyInfo = {},
}

-- Card Craft is driven by the same CardCraftRE used by the game's own
-- CardCraftClient. Keep all live values in one table so the automation does
-- not add a large number of top-level locals to this already-large script.
local cardCraftState = {
    Remote = Remotes:WaitForChild("CardCraftRE", 15),
    Module = nil,
    Received = false,
    Active = false,
    Job = nil,
    ServerNow = os.time(),
    LocalClock = os.clock(),
    Requesting = false,
    Claiming = false,
    NextAttemptAt = 0,
    StatusParagraph = nil,
    RecipeMap = {},
    RecipeOptions = { "No recipes found" },
    MutationOptions = { "All" },
    SelectedRecipeId = nil,
    LastMessage = nil,
    CachedInventory = {},
    InventoryCacheAt = 0,
    LastStatusTitle = nil,
    LastStatusContent = nil,
}
if Modules and Modules:WaitForChild("CardCraftConfig", 15) then
    pcall(function()
        cardCraftState.Module = require(Modules.CardCraftConfig)
    end)
end
if Modules then
    local cardsConfigModule = Modules:WaitForChild("CardsConfig", 15)
    if cardsConfigModule then
        pcall(function()
            cardCraftState.IndexConfig = require(cardsConfigModule)
        end)
    end
end

-- ── Data lists ───────────────────────────────────────────────
local RARITIES = {
    "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Secret", "Divine",
    "Transcendent", "Shadow", "Emperor", "Demon",
    "Manga", "Celestial", "Heavenly", "Corrupted",
    "Striker", "Sacred", "Paradox", "Founder",
    "Evolved", "Magic", "Oni", "Chaos",
    "Ruin", "Reborn", "Beast", "Nordic",
    "Hunter", "Soul", "Swordsman", "Gamer",
    "Revenge", "Chainsaw", "Grail", "Conquest",
    "Blaze", "Devour", "Raven", "Arcane", "Nightfall",
}

local MUTATIONS = {
    "Normal", "Golden", "Venomous", "Diamond",
    "Rainbow", "Sakura", "Candy", "Blessed",
    "Radioactive", "Glitch", "Starfallen", "Admin", "Unknow",
}

-- The IndexClient builds its cards and mutation buttons from CardsConfig.
-- Use that same module here so new cards/mutations appear automatically
-- instead of requiring another hard-coded list update.
cardCraftState.IndexCards = {}
if type(cardCraftState.IndexConfig) == "table" then
    if type(cardCraftState.IndexConfig.GetAllCardsSorted) == "function" then
        local ok, cards = pcall(cardCraftState.IndexConfig.GetAllCardsSorted)
        if ok and type(cards) == "table" then
            local seen = {}
            for _, entry in ipairs(cards) do
                if type(entry) == "table" then
                    local cardName = entry.Name or entry.CardName
                    if cardName ~= nil then
                        cardName = tostring(cardName)
                        local key = string.lower(cardName)
                        if cardName ~= "" and not seen[key] then
                            seen[key] = true
                            table.insert(cardCraftState.IndexCards, cardName)
                        end
                    end
                end
            end
        end
    end

    if type(cardCraftState.IndexConfig.MutationOrder) == "table"
        and #cardCraftState.IndexConfig.MutationOrder > 0 then
        local indexMutations = {}
        local seen = {}
        for _, mutation in ipairs(cardCraftState.IndexConfig.MutationOrder) do
            mutation = tostring(mutation)
            local key = string.lower(mutation)
            if mutation ~= "" and not seen[key] then
                seen[key] = true
                table.insert(indexMutations, mutation)
            end
        end
        if #indexMutations > 0 then
            MUTATIONS = indexMutations
        end
    end
end

local PACKS = {
    "Ice Pack", "Sand Pack", "Inferno Pack", "Lightning Pack",
    "Hightech Pack", "Dark Pack", "Eclipse Pack", "Isekai Pack",
    "Slayer Pack", "Monarch Pack", "Pirate King Pack", "Demon Pack",
    "Manga Pack", "Galaxy Pack", "Heaven Pack", "Void Pack",
    "Soccer Pack", "Empyrean Pack", "Bizarre Pack", "Titan Pack",
    "Evolved Pack", "Grimoire Pack", "Oni Pack", "Chaos Pack",
    "Ruin Pack", "Royal Pack", "Mage Pack", "Beast Pack", "Viking Pack",
    "Hunter Pack", "Soul Pack", "Swordsman Pack", "Gamer Pack",
    "Revenge Pack", "Chainsaw Pack", "Eternity Pack", "Academy Pack",
    "Dynasty Pack", "Grail Pack", "Conquest Pack", "Blaze Pack",
    "Devour Pack", "Raven Pack", "Arcane Pack", "Nightfall Pack",
}

-- ConveyorSettingsClient uses ReplicatedStorage.Modules.ConveyorPacks as the
-- authoritative catalog. Build the same non-Robux pack list and rarity order
-- here so every filter, fallback name matcher, auto-buy path, and sell filter
-- automatically includes content added by the game.
if type(ConveyorPacks) == "table" then
    local dynamicPackEntries = {}
    local dynamicPackSeen = {}
    local dynamicRaritySeen = {}

    if type(ConveyorPacks.List) == "table" then
        for _, entry in ipairs(ConveyorPacks.List) do
            if type(entry) == "table" then
                local packName = entry.Id
                    or entry.PackId
                    or entry.PackName
                    or entry.Name
                if packName ~= nil and entry.RobuxOnly ~= true then
                    packName = tostring(packName)
                    if packName ~= "" and not dynamicPackSeen[packName] then
                        dynamicPackSeen[packName] = true
                        table.insert(dynamicPackEntries, {
                            Name = packName,
                            Rarity = tostring(entry.Rarity or ""),
                            Price = tonumber(entry.Price) or 0,
                        })
                    end
                end

                local rarity = entry.Rarity
                if rarity ~= nil and tostring(rarity) ~= "" then
                    dynamicRaritySeen[tostring(rarity)] = true
                end
            end
        end
    end

    local dynamicRarityEntries = {}
    local dynamicRarityEntryByName = {}
    if type(ConveyorPacks.RarityRank) == "table" then
        for rarity, rank in pairs(ConveyorPacks.RarityRank) do
            local entry = {
                Name = tostring(rarity),
                Rank = tonumber(rank) or 0,
            }
            table.insert(dynamicRarityEntries, entry)
            dynamicRarityEntryByName[string.lower(entry.Name)] = true
        end
    end
    for rarity in pairs(dynamicRaritySeen) do
        if not dynamicRarityEntryByName[string.lower(rarity)] then
            table.insert(dynamicRarityEntries, {
                Name = rarity,
                Rank = 0,
            })
            dynamicRarityEntryByName[string.lower(rarity)] = true
        end
    end

    if #dynamicPackEntries > 0 then
        local rarityRanks = type(ConveyorPacks.RarityRank) == "table"
            and ConveyorPacks.RarityRank
            or {}
        table.sort(dynamicPackEntries, function(a, b)
            local aRank = tonumber(rarityRanks[a.Rarity]) or 0
            local bRank = tonumber(rarityRanks[b.Rarity]) or 0
            if aRank ~= bRank then return aRank < bRank end
            if a.Price ~= b.Price then return a.Price < b.Price end
            return a.Name < b.Name
        end)

        PACKS = {}
        for _, entry in ipairs(dynamicPackEntries) do
            table.insert(PACKS, entry.Name)
        end
    end

    if #dynamicRarityEntries > 0 then
        table.sort(dynamicRarityEntries, function(a, b)
            if a.Rank ~= b.Rank then return a.Rank < b.Rank end
            return a.Name < b.Name
        end)

        RARITIES = {}
        for _, entry in ipairs(dynamicRarityEntries) do
            table.insert(RARITIES, entry.Name)
        end
    end
end

local POTIONS = {
    "LuckPotion1", "LuckPotion2", "LuckPotion3",
    "CashPotion1", "CashPotion2", "CashPotion3",
    "MutationPotion1", "MutationPotion2", "MutationPotion3",
    "ProductionPotion1", "ProductionPotion2",
}

-- Keep the strongest time potion first so pack automation always spends the
-- best available skip potion before falling back to a weaker one.
local TIME_POTIONS = { "TimePotion3", "TimePotion2", "TimePotion1" }

local function normalizeGeneralPotionSelection(selection)
    local valid = {}
    local validSet = {}
    for _, potion in ipairs(POTIONS) do
        validSet[potion] = true
    end

    local values = type(selection) == "table" and selection or { selection }
    for _, value in ipairs(values) do
        value = tostring(value or "")
        if value == "All" then
            return { "All" }
        end
        if validSet[value] then
            table.insert(valid, value)
        end
    end
    return valid
end

local BOOSTS = {
    { label = "Base Expansion", id = "base" },
    { label = "Luck Boost",     id = "luck" },
    { label = "Cash Boost",     id = "cash" },
    { label = "Time Boost",     id = "time" },
    { label = "Speed Boost",    id = "speed" },
}

local function selectionIncludes(selection, wanted)
    if type(selection) ~= "table" then
        return selection == nil or tostring(selection) == "All"
            or tostring(selection) == wanted
    end
    if #selection == 0 then
        return true
    end
    for _, value in ipairs(selection) do
        if tostring(value) == "All" or tostring(value) == wanted then
            return true
        end
    end
    return false
end

local function collapseFullSelection(selection, options)
    if type(selection) ~= "table" or #selection == 0 then
        return { "All" }
    end
    for _, value in ipairs(selection) do
        if tostring(value) == "All" then return { "All" } end
    end
    local selected = {}
    for _, value in ipairs(selection) do selected[tostring(value)] = true end
    local allSelected = true
    for _, option in ipairs(options) do
        if not selected[option] then
            allSelected = false
            break
        end
    end
    if allSelected then return { "All" } end
    return selection
end

local MAX_CARD_LEVEL = 50
local CARD_REMOVAL_DELAY = 0.5

local RARITY_RANK = {}
for index, rarity in ipairs(RARITIES) do
    RARITY_RANK[string.lower(rarity)] = index
end

local MUTATION_RANK = {}
for index, mutation in ipairs(MUTATIONS) do
    MUTATION_RANK[string.lower(mutation)] = index
end

-- ── Config ───────────────────────────────────────────────────
local Config = {
    -- Spawn
    AutoSpawnPack   = false,
    SpawnDelay      = 0.5,
    AutoStopSpawn   = false,
    AutoBuyMatching   = false,
    AutoContinueSpawn = false,
    AutoCarryBox    = false,
    AutoSellBox     = false,
    AutoSellDelay   = 30,
    CardCraftRecipeId = nil,
    CardCraftCard   = "",
    CardCraftMutations = { "All" },
    AutoCardCraft    = false,
    AutoClaimCardCraft = false,
    PlotNumber      = 1,    -- will be overwritten by auto-detect at startup

    -- Filter
    SelectedRarities  = {},
    SelectedMutations = {},
    SelectedPacks     = {},

    -- Cards
    AutoUpgrade       = false,
    UpgradeDelay      = 0.15,
    CardActionDelay   = 0.6,
    AutoTraitRoll     = false,
    SelectedRankCards = { "All" },
    TargetRank        = {},
    SelectedTraitCards = { "All" },
    TargetTraits      = {},
    RankUseGems       = true,
    RankUseCash       = false,
    AutoRankRoll      = false,
    AutoClaimPlaytime = false,
    AutoClaimDaily    = false,
    AutoPlacePack     = false,
    AutoOpenPack      = false,
    AutoTimePotion    = false,
    AutoBuyBoost      = false,
    AutoUpgradeArtifact = false,
    AutoEquipArtifact = false,
    SelectedArtifactSlots = {},
    SelectedArtifacts = { "All" },
    SelectedArtifactLevels = { "All" },
    AutoSellArtifacts = false,
    SelectedBossCard  = "WhiteTitan",
    AutoEquipBossCard = false,
    AutoUpgradeBossCard = false,
    AutoRemoveCard    = false,
    AutoRemoveCardSlot = "Slot 1-5",

    -- Auto Sell Cards
    FilteredSellMode  = "Whitelist",
    FilteredSellCard  = { "All" },
    FilteredSellMutation = { "All" },
    FilteredSellRanking = { "All" },
    FilteredSellTrait = { "All" },
    AutoFilteredSell  = false,

    -- Combat
    AutoInfinityEquip = false,
    AutoInfinityTower = false,
    AutoInfinityHide  = false,
    RaidDifficulties  = { "Easy" },
    AutoRaidEquip     = false,
    AutoRaid          = false,
    AutoRaidHide      = false,
    AutoTeamCardCycle = false,

    -- Misc
    AutoPotion = false,
    SelectedPotions = {},
    SelectedBoosts = {},
    AntiAfk    = true,

    -- Cash safety (Auto Buy Pack)
    UseCashReserve = false,
    CashReserve    = 0,
}

-- ── Controls table (Rayfield control references for config loading) ──
local Controls = {}

-- Artifact and boss-card automation state. Keep this in one table because
-- this script is already close to Luau's top-level local-register limit.
local artifactState = {
    ArtifactRE = Remotes:WaitForChild("ArtifactRE", 15),
    BossCardRE = Remotes:WaitForChild("BossCardRE", 15),
    ArtifactDropdown = nil,
    ArtifactSellDropdown = nil,
    ArtifactLevelDropdown = nil,
    ArtifactSelectParagraph = nil,
    BossCardDropdown = nil,
    ArtifactCatalog = {},
    CatalogScanned = false,
    ArtifactOptions = { "All" },
    ArtifactSelectionOptions = {},
    ArtifactSelectionOptionMap = {},
    BossCardOptions = { "White Titan", "Moon Demon", "Chimera King" },
    LastSoldAt = {},
    LastArtifactEquipAt = {},
    LastBossEquipAt = 0,
    LastArtifactRefreshAt = 0,
    InventoryCounts = {},
}

-- Playtime state is pushed by the game's client remote.
local playtimeReadyRewards = {}
local playtimeStateReceived = false
local potionInventoryCounts = {}

-- Forward declarations
local clickGuiButton
local startCombatBattle
local removeAllCards
local removeFirstFourCardSlots
local doEquipBestCards
local closeBossRaidReward
local exitInfinityTowerBattle

-- ── Remote helpers ───────────────────────────────────────────
local function findRemote(name)
    local directRemote = Remotes and Remotes:FindFirstChild(name)
    if directRemote then return directRemote end
    return ReplicatedStorage:FindFirstChild(name, true)
end

local function fireRemote(name, ...)
    local remote = findRemote(name)
    if not remote then
        warn("[ACF] Remote not found: " .. name)
        return false
    end

    local ok, err
    if remote:IsA("RemoteEvent") then
        ok, err = pcall(remote.FireServer, remote, ...)
    elseif remote:IsA("RemoteFunction") then
        ok, err = pcall(remote.InvokeServer, remote, ...)
    else
        warn("[ACF] " .. name .. " is not a RemoteEvent or RemoteFunction")
        return false
    end

    if not ok then
        warn("[ACF] " .. name .. " failed: " .. tostring(err))
    end
    return ok
end

-- ── Button firing ────────────────────────────────────────────
local function fireButton(part)
    if not part then return false end

    local click = part:IsA("ClickDetector") and part
        or part:FindFirstChildOfClass("ClickDetector")
        or part:FindFirstChild("ClickDetector", true)
    if click then
        if fireclickdetector then
            local ok = pcall(fireclickdetector, click)
            if ok then return true end
        end
        local ok = pcall(function()
            click.MouseClick:Fire(player.Character)
        end)
        if ok then return true end
    end

    local prompt = part:IsA("ProximityPrompt") and part
        or part:FindFirstChildOfClass("ProximityPrompt")
        or part:FindFirstChild("ProximityPrompt", true)
    if prompt then
        if fireproximityprompt then
            local ok = pcall(fireproximityprompt, prompt)
            if ok then return true end
        end
        if firetouchinterest then
            local targetPart = part:IsA("BasePart") and part
                or prompt.Parent and prompt.Parent:IsA("BasePart")
                    and prompt.Parent
            if targetPart then
                local ok = pcall(
                    firetouchinterest,
                    targetPart,
                    player.Character,
                    0
                )
                if ok then return true end
            end
        end
    end

    return false
end

local function firePrompt(prompt)
    if not prompt then return false end
    if fireproximityprompt then
        local ok, err = pcall(fireproximityprompt, prompt)
        if ok then return true end
        return false, err
    end
    local remote = prompt:FindFirstChild("Remote")
        or prompt:FindFirstChild("RemoteEvent")
        or prompt:FindFirstChild("RemoteFunction")
    if remote and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
        if remote:IsA("RemoteEvent") then
            return pcall(remote.FireServer, remote)
        end
        return pcall(remote.InvokeServer, remote)
    end
    return false, "No prompt firing primitive or prompt remote available"
end

local function fireClickDetector(detector)
    if not detector then return false end
    if fireclickdetector then
        local ok = pcall(fireclickdetector, detector)
        if ok then return true end
    end
    return pcall(function() detector.MouseClick:Fire(player) end)
end

local function refreshPlaytimeReadyRewards(state)
    if type(state) ~= "table" then return end
    playtimeStateReceived = true
    table.clear(playtimeReadyRewards)
    local rewards = state.Rewards or state
    if type(rewards) ~= "table" then return end
    for index = 1, 12 do
        local reward = rewards[index] or rewards[tostring(index)]
        if type(reward) == "table"
            and reward.Claimed ~= true
            and reward.Ready == true then
            playtimeReadyRewards[index] = true
        end
    end
end

if PlayTimeRewardRE and PlayTimeRewardRE:IsA("RemoteEvent") then
    PlayTimeRewardRE.OnClientEvent:Connect(function(eventName, payload)
        if eventName == "State" then
            refreshPlaytimeReadyRewards(payload)
        elseif eventName == "ClaimSuccess" and type(payload) == "table" then
            local index = tonumber(payload.RewardIndex)
            if index then playtimeReadyRewards[index] = nil end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════
--  PLOT AUTO-DETECTION
-- ══════════════════════════════════════════════════════════════

local function setPlotNumber(n)
    if type(n) ~= "number" or n == Config.PlotNumber then return end
    Config.PlotNumber = n
    warn("[ACF] Plot auto-detected: #" .. tostring(n))
    notify("Plot Detected", "Your plot is slot #" .. tostring(n))
end

local function readPlayerPlotNumber()
    local iv = player:FindFirstChild("PlotNumber")
    if iv and iv:IsA("IntValue") then return tonumber(iv.Value) end
    local attr = player:GetAttribute("PlotNumber")
    if attr ~= nil then return tonumber(attr) end
    return nil
end

local function autoDetectMyPlotNumber()
    return readPlayerPlotNumber()
end

task.spawn(function()
    local map = workspace:FindFirstChild("MAP")
    if not map then
        map = workspace:WaitForChild("MAP", 30)
    end
    if not map then
        warn("[ACF] workspace.MAP not found after 30 s — game may use a different structure.")
    end

    local iv = player:FindFirstChild("PlotNumber")
    if not iv then
        iv = player:WaitForChild("PlotNumber", 15)
    end

    if iv and iv:IsA("IntValue") then
        local n = tonumber(iv.Value)
        if n and n > 0 then
            setPlotNumber(n)
        end

        iv.Changed:Connect(function(newVal)
            local num = tonumber(newVal)
            if num and num > 0 then
                Config.PlotNumber = num
                warn("[ACF] Plot reassigned by server: #" .. tostring(num))
                notify("Plot Updated", "Moved to slot #" .. tostring(num))
                sellBoxPartCache = nil
            end
        end)
    else
        local attr = player:GetAttribute("PlotNumber")
        if attr ~= nil then
            local n = tonumber(attr)
            if n and n > 0 then setPlotNumber(n) end
        else
            warn("[ACF] PlotNumber not found on player after 15 s. "
                .. "Carry/Sell will not work correctly until the plot is assigned.")
        end
        player:GetAttributeChangedSignal("PlotNumber"):Connect(function()
            local num = tonumber(player:GetAttribute("PlotNumber"))
            if num and num > 0 then
                Config.PlotNumber = num
                sellBoxPartCache  = nil
                warn("[ACF] Plot (attr) assigned: #" .. tostring(num))
            end
        end)
    end
end)

local function findPlot(plotNumber)
    local map   = workspace:FindFirstChild("MAP")
    local plots = map and map:FindFirstChild("Plots")
    if plots then
        local slot = plots:FindFirstChild(tostring(plotNumber))
        if slot then
            local plotN0 = slot:FindFirstChild("Plot_N0")
            if plotN0 then return plotN0 end
            return slot
        end
    end

    local fallbackPlots = workspace:FindFirstChild("Plots")
    if fallbackPlots then
        local slot = fallbackPlots:FindFirstChild(tostring(plotNumber))
                  or fallbackPlots:FindFirstChild("Plot" .. tostring(plotNumber))
        if slot then
            return slot:FindFirstChild("Plot_N0") or slot
        end
    end

    return nil
end

local function getPlotButtons(plotNumber)
    local plot = findPlot(plotNumber)
    if not plot then return nil, nil end

    local spawnBtn = plot:FindFirstChild("ButtonPart", true)
               or plot:FindFirstChild("ButtonSelect", true)

    local placeBtn = plot:FindFirstChild("PlaceButton",    true)
               or plot:FindFirstChild("ConveyorButton", true)
               or plot:FindFirstChild("ButtonPlace",    true)

    return spawnBtn, placeBtn
end

-- ── Filter logic ─────────────────────────────────────────────
local function normalizeFilterValue(value)
    if value == nil then return nil end
    local normalized = string.lower(string.gsub(tostring(value), "^%s*(.-)%s*$", "%1"))
    -- The game calls this mutation "Unknow" (without the final n).
    -- Canonicalize both the UI value and any older/live "Unknown" value.
    if normalized == "unknown" then
        return "unknow"
    end
    return normalized
end

local function normalizeFilterSelection(value)
    local selected = {}

    if type(value) ~= "table" then
        value = value == nil and {} or { value }
    end

    local function add(option)
        local normalized = normalizeFilterValue(option)
        if normalized == "any" or normalized == "all" then
            -- "Any" is an explicit wildcard.  Rayfield can return the
            -- previous selections together with the newly selected wildcard,
            -- so it must win over those stale values.
            return true
        end
        if normalized then
            selected[normalized] = true
        end
        return false
    end

    local hadArrayValues = false
    for _, option in ipairs(value) do
        hadArrayValues = true
        if add(option) then return {} end
    end
    if not hadArrayValues then
        for option, enabled in pairs(value) do
            if enabled and add(option) then return {} end
        end
    end

    return selected
end

local function filterCompareKey(value)
    local normalized = normalizeFilterValue(value)
    if not normalized then return nil end
    return string.gsub(normalized, "[^%w]", "")
end

local function filterValueMatches(value, selected)
    if next(selected) == nil then return true end
    local valueKey = filterCompareKey(value)
    if not valueKey then return false end

    for wanted in pairs(selected) do
        local wantedKey = filterCompareKey(wanted)
        if wantedKey == valueKey
            or (wantedKey and string.find(valueKey, wantedKey, 1, true))
            or (wantedKey and string.find(wantedKey, valueKey, 1, true)) then
            return true
        end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════
--  AUTO BUY UTILITY FUNCTIONS
--  These replace all old ItemId-based and workspace-scan-based
--  approaches with the confirmed game structure from screenshots.
-- ════════════════════════════════════════════════════════════════

-- Normalize a pack name for comparison (strips spaces, lowercases).
local function normalizePackName(value)
    if value == nil then return nil end
    local s = tostring(value)
    s = s:gsub("^%s*(.-)%s*$", "%1")  -- trim
    s = s:lower()
    s = s:gsub("%s+", "")              -- remove internal spaces for comparison
    return s
end

-- Decode Anime Card Farm compact cash strings:
-- K, M, B, T, Qd, Qn, Sx, Sp, O, N, Dc, Ud, Dd, Td.
-- Returns a number on success, nil on failure.
local function parseCompactCash(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub(",", ""):gsub("%s+", "")  -- strip commas and spaces
    text = text:gsub("^%$", "")                -- strip leading $
    if text == "" then return nil end

    local suffixMap = {
        k = 1e3,
        m = 1e6,
        b = 1e9,
        t = 1e12,
        qd = 1e15,
        qn = 1e18,
        sx = 1e21,
        sp = 1e24,
        o = 1e27,
        n = 1e30,
        dc = 1e33,
        ud = 1e36,
        dd = 1e39,
        td = 1e42,
    }

    -- Try two-letter suffix first, then one-letter suffix, then plain number.
    local num, suffix2 = text:match("^([%d%.]+)([A-Za-z][A-Za-z])$")
    if num and suffix2 then
        local mult = suffixMap[suffix2:lower()]
        if mult then return (tonumber(num) or 0) * mult end
    end

    local num1, suffix1 = text:match("^([%d%.]+)([A-Za-z])$")
    if num1 and suffix1 then
        local mult = suffixMap[suffix1:lower()]
        if mult then return (tonumber(num1) or 0) * mult end
    end

    -- Plain number with no suffix.
    local plain = text:match("^([%d%.]+)$")
    if plain then return tonumber(plain) end

    -- Also tolerate labels such as "Cash: $4.15N".
    local embeddedNum, embeddedSuffix =
        text:match("([%d%.]+)([A-Za-z][A-Za-z]?)")
    if embeddedNum then
        local mult = suffixMap[(embeddedSuffix or ""):lower()]
        if mult then return (tonumber(embeddedNum) or 0) * mult end
        if not embeddedSuffix or embeddedSuffix == "" then
            return tonumber(embeddedNum)
        end
    end

    return nil
end

-- Get the player's current exact cash as a number.
-- Primary source: Players.LocalPlayer.CashValue (NumberValue or IntValue).
-- Fallback: leaderstats.Cash text parsed through parseCompactCash.
local function getPlayerCash()
    local function readCashValue(valueObject)
        if not valueObject or not valueObject:IsA("ValueBase") then
            return nil
        end
        local value = valueObject.Value
        if type(value) == "number" then
            return value
        end
        return parseCompactCash(tostring(value or ""))
    end

    local function readCashAttribute(instance, attributeName)
        local value = instance:GetAttribute(attributeName)
        if type(value) == "number" then
            return value
        end
        if value ~= nil then
            return parseCompactCash(tostring(value))
        end
        return nil
    end

    for _, name in ipairs({
        "CashValue", "Cash", "Money", "Currency", "CashAmount", "MoneyValue",
    }) do
        local value = readCashValue(player:FindFirstChild(name))
        if value ~= nil then return value end
        value = readCashAttribute(player, name)
        if value ~= nil then return value end
    end

    -- Fallback: leaderstats may expose cash as a number or compact string.
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        for _, name in ipairs({
            "Cash", "Money", "Currency", "CashValue", "CashAmount",
        }) do
            local cashObj = ls:FindFirstChild(name)
            local value = readCashValue(cashObj)
            if value ~= nil then return value end
            value = readCashAttribute(ls, name)
            if value ~= nil then return value end
        end
    end

    -- Last fallback for versions that place the balance directly on the
    -- player's attributes.
    for _, name in ipairs({ "Cash", "Money", "Currency", "CashAmount" }) do
        local value = readCashAttribute(player, name)
        if value ~= nil then return value end
    end

    -- HUD fallback: some game versions expose the balance only as a
    -- TextLabel. Prefer labels whose instance names identify them as cash,
    -- money, currency, or balance so pack prices are not mistaken for cash.
    for _, descendant in ipairs(playerGui:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
            local name = string.lower(descendant.Name)
            if string.find(name, "cash", 1, true)
                or string.find(name, "money", 1, true)
                or string.find(name, "currency", 1, true)
                or string.find(name, "balance", 1, true) then
                local value = parseCompactCash(tostring(descendant.Text or ""))
                if value ~= nil then return value end
            end
        end
    end

    return nil
end

local function getPlayerGems()
    local gv = player:FindFirstChild("GemsValue")
    if gv and (gv:IsA("NumberValue") or gv:IsA("IntValue")) then
        return tonumber(gv.Value) or 0
    end
    return 0
end

local function getPlayerTraitGems()
    for _, name in ipairs({
        "TraitGemsValue", "TraitGems", "TraitGemValue", "TraitGem",
    }) do
        local value = player:FindFirstChild(name)
        if value and value:IsA("ValueBase") then
            return tonumber(value.Value) or 0
        end

        local attribute = player:GetAttribute(name)
        if attribute ~= nil then
            local number = tonumber(attribute)
            if number ~= nil then return number end
        end
    end

    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then
        for _, name in ipairs({
            "TraitGemsValue", "TraitGems", "TraitGemValue", "TraitGem",
        }) do
            local value = leaderstats:FindFirstChild(name)
            if value and value:IsA("ValueBase") then
                return tonumber(value.Value) or 0
            end
        end
    end

    return 0
end

-- CONFIRMED GAME STRUCTURE (from screenshots):
--   packModel.GuiHolder.BillboardGuiInfo.Price   → TextLabel with Text "$500.0K"
--   packModel.GuiHolder.BillboardGuiInfo.Rarity  → child named after rarity (e.g. "Epic")
--   packModel.GuiHolder.BillboardGuiInfo.Mutation → child named after mutation (e.g. "Normal")

-- Get the raw price text from the pack's billboard GUI (used only as last resort).
local function getPackPriceText(packModel)
    if not packModel then return nil end
    local gui = packModel:FindFirstChild("GuiHolder", true)
    local info = gui and gui:FindFirstChild("BillboardGuiInfo", true)
    local priceContainer = info and info:FindFirstChild("Price", true)
    if priceContainer then
        -- Try TextLabel/TextButton text first (confirmed in screenshots).
        for _, child in ipairs(priceContainer:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                local t = tostring(child.Text or ""):gsub("^%s*(.-)%s*$", "%1")
                if t ~= "" and parseCompactCash(t) ~= nil then return t end
            end
        end
        -- The price container itself might be a TextLabel.
        if priceContainer:IsA("TextLabel") or priceContainer:IsA("TextButton") then
            local t = tostring(priceContainer.Text or ""):gsub("^%s*(.-)%s*$", "%1")
            if t ~= "" and parseCompactCash(t) ~= nil then return t end
        end
    end
    return nil
end

-- Get the pack price as an exact number.
-- Tries three sources in order so suffix parsing is only a last resort:
--   1. Model attributes  (Price, Cost, CashCost, CashPrice, cash, price)
--   2. NumberValue / IntValue children anywhere in the model tree
--      named Price, Cost, CashCost, CashPrice, cash, or price
--   3. GUI text label parsed through parseCompactCash (suffix-based, may fail)
-- Returns: number or nil.
-- Writes a warnOnce if every source fails so the failure is visible in console.
local PRICE_ATTR_NAMES = { "Price", "Cost", "CashCost", "CashPrice", "cash", "price" }

local function getPackPrice(packModel)
    if not packModel then return nil end

    -- 1. Model attributes — exact number, no parsing needed.
    for _, attrName in ipairs(PRICE_ATTR_NAMES) do
        local v = packModel:GetAttribute(attrName)
        if type(v) == "number" and v > 0 then
            return v
        end
        if type(v) == "string" then
            local parsed = parseCompactCash(v)
            if parsed and parsed > 0 then return parsed end
        end
    end

    -- 2. Numeric or formatted ValueBase children anywhere in the model.
    local function searchValueObjects(parent)
        for _, child in ipairs(parent:GetDescendants()) do
            if child:IsA("ValueBase") then
                local n = child.Name:lower()
                for _, attrName in ipairs(PRICE_ATTR_NAMES) do
                    if n == attrName:lower() then
                        local v = type(child.Value) == "number"
                            and child.Value
                            or parseCompactCash(tostring(child.Value or ""))
                        if v and v > 0 then return v end
                    end
                end
            end
        end
        return nil
    end

    local fromValue = searchValueObjects(packModel)
    if fromValue then return fromValue end

    -- 3. GUI text label — last resort, suffix parsing.
    local priceText = getPackPriceText(packModel)
    if priceText then
        local parsed = parseCompactCash(priceText)
        if parsed and parsed > 0 then
            return parsed
        end
        -- Text was found but couldn't be parsed — warn so it shows in console.
        warnOnce("price-parse:" .. tostring(packModel),
            "[AutoBuy] Pack price text could not be parsed: '"
                .. tostring(priceText)
                .. "' — add the suffix to parseCompactCash if this suffix is used in-game.")
        return nil
    end

    -- No source found at all (GUI not yet replicated is normal on first tick).
    return nil
end

-- Decorative UI children to ignore when extracting rarity/mutation names.
local IGNORE_UI_CLASSES = {
    UIStroke = true, UIGradient = true, UICorner = true,
    UIListLayout = true, UIAspectRatioConstraint = true,
    UIPadding = true, UIScale = true, UITableLayout = true,
    UIGridLayout = true, UIFlexItem = true,
}

local function firstMeaningfulChildName(container)
    if not container then return nil end
    for _, child in ipairs(container:GetChildren()) do
        if not IGNORE_UI_CLASSES[child.ClassName] then
            local n = tostring(child.Name):gsub("^%s*(.-)%s*$", "%1")
            if n ~= "" then return n end
        end
    end
    return nil
end

local function firstMeaningfulTextLabel(container)
    if not container then return nil end
    for _, child in ipairs(container:GetChildren()) do
        if not IGNORE_UI_CLASSES[child.ClassName] then
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                local t = tostring(child.Text or ""):gsub("^%s*(.-)%s*$", "%1")
                if t ~= "" then return t end
            end
        end
    end
    return nil
end

-- Get the rarity string from the pack's billboard GUI.
-- Path: packModel.GuiHolder.BillboardGuiInfo.Rarity.<child name> (e.g. "Epic")
local function getPackRarity(packModel)
    if not packModel then return nil end
    local gui = packModel:FindFirstChild("GuiHolder")
    local info = gui and gui:FindFirstChild("BillboardGuiInfo")
    local rarityContainer = info and info:FindFirstChild("Rarity")
    if rarityContainer then
        -- 1. Check text labels inside (most reliable for display value).
        local t = firstMeaningfulTextLabel(rarityContainer)
        if t then return t end
        -- 2. Check meaningful child name (e.g. a Frame named "Epic").
        local n = firstMeaningfulChildName(rarityContainer)
        if n then return n end
        -- 3. Container itself is a TextLabel.
        if rarityContainer:IsA("TextLabel") or rarityContainer:IsA("TextButton") then
            local t2 = tostring(rarityContainer.Text or ""):gsub("^%s*(.-)%s*$", "%1")
            if t2 ~= "" then return t2 end
        end
        -- 4. Attribute fallback.
        local attr = rarityContainer:GetAttribute("Rarity")
            or rarityContainer:GetAttribute("Value")
        if attr then return tostring(attr) end
    end
    return nil
end

-- Get the mutation string from the pack's billboard GUI.
-- Path: packModel.GuiHolder.BillboardGuiInfo.Mutation.<child name> (e.g. "Normal")
local function getPackMutation(packModel)
    if not packModel then return nil end
    local gui = packModel:FindFirstChild("GuiHolder")
    local info = gui and gui:FindFirstChild("BillboardGuiInfo")
    local mutationContainer = info and info:FindFirstChild("Mutation")
    if mutationContainer then
        -- 1. Check text labels inside.
        local t = firstMeaningfulTextLabel(mutationContainer)
        if t then return t end
        -- 2. Check meaningful child name (e.g. a Frame named "Normal").
        local n = firstMeaningfulChildName(mutationContainer)
        if n then return n end
        -- 3. Container itself is a TextLabel.
        if mutationContainer:IsA("TextLabel") or mutationContainer:IsA("TextButton") then
            local t2 = tostring(mutationContainer.Text or ""):gsub("^%s*(.-)%s*$", "%1")
            if t2 ~= "" then return t2 end
        end
        -- 4. Attribute fallback.
        local attr = mutationContainer:GetAttribute("Mutation")
            or mutationContainer:GetAttribute("Value")
        if attr then return tostring(attr) end
    end
    return nil
end

-- ────────────────────────────────────────────────────────────────────────────

local metadataCache = setmetatable({}, { __mode = "k" })

local function readBoxValue(box, names)
    for _, name in ipairs(names) do
        local attribute = box:GetAttribute(name)
        if attribute ~= nil then
            return attribute
        end
    end

    local metadata = metadataCache[box]
    if not metadata then
        metadata = {
            attributes = {},
            values = {},
        }
        for _, descendant in ipairs(box:GetDescendants()) do
            for key, value in pairs(descendant:GetAttributes()) do
                key = string.lower(key)
                if metadata.attributes[key] == nil then
                    metadata.attributes[key] = value
                end
            end

            local key = string.lower(descendant.Name)
            if metadata.values[key] == nil then
                if descendant:IsA("ValueBase") then
                    metadata.values[key] = descendant.Value
                elseif descendant:IsA("TextLabel")
                    or descendant:IsA("TextButton") then
                    metadata.values[key] = descendant.Text
                end
            end
        end
        metadataCache[box] = metadata
    end

    for _, name in ipairs(names) do
        local key = string.lower(name)
        if metadata.attributes[key] ~= nil then
            return metadata.attributes[key]
        end
        if metadata.values[key] ~= nil then
            return metadata.values[key]
        end
    end

    return nil
end

local function getBoxInfo(box)
    if not box then return nil end

    local packValue = readBoxValue(box, { "Pack", "PackName", "pack" })

    if packValue == nil and box:IsA("Model") then
        local name = box.Name
        if string.find(string.lower(name), "pack", 1, true) then
            packValue = name
        end
    end

    if packValue == nil then
        local function findKnownPackName(value)
            local key = filterCompareKey(value)
            if not key then return nil end
            for _, packName in ipairs(PACKS) do
                local packKey = filterCompareKey(packName)
                if packKey and (key == packKey
                    or string.find(key, packKey, 1, true)
                    or string.find(packKey, key, 1, true)) then
                    return packName
                end
            end
            return nil
        end

        local current = box
        for _ = 1, 6 do
            if not current then break end
            packValue = findKnownPackName(current.Name)
            if packValue then break end
            current = current.Parent
        end

        if not packValue then
            for _, descendant in ipairs(box:GetDescendants()) do
                packValue = findKnownPackName(descendant.Name)
                if packValue then break end
            end
        end
    end

    return {
        rarity   = readBoxValue(box, { "Rarity",   "rarit",        "rarity"   }),
        mutation = readBoxValue(box, { "Mutation",  "MutationName", "mutation" }),
        pack     = packValue,
    }
end

-- ════════════════════════════════════════════════════════════════════════
--  ARTIFACTS & BOSS CARDS
--  Artifact inventory entries are rendered by ArtifactClient as
--  ArtifactSelectFrame_<uid>. Placed artifacts and the boss card live on the
--  player's plot and expose their upgrade data as attributes.
-- ════════════════════════════════════════════════════════════════════════
do
    local ARTIFACT_LEVEL_OPTIONS = {
        "1", "2", "3", "4", "5",
        "6", "7", "8", "9", "10",
    }

    local BOSS_CARDS = {
        {
            Id = "WhiteTitan",
            Label = "White Titan",
            Shards = { "WhiteTitanShards", "WhiteTitanShard" },
        },
        {
            Id = "MoonDemon",
            Label = "Moon Demon",
            Shards = { "MoonDemonShards", "MoonDemonShard" },
        },
        {
            Id = "ChimeraKing",
            Label = "Chimera King",
            Shards = { "ChimeraKingShards", "ChimeraKingShard" },
        },
    }

    local function lowerSet(names)
        local result = {}
        for _, name in ipairs(names) do
            result[string.lower(tostring(name))] = true
        end
        return result
    end

    local function readFreshValue(root, names)
        if not root then return nil end
        local wanted = lowerSet(names)

        for _, name in ipairs(names) do
            local value = root:GetAttribute(name)
            if value ~= nil then return value end
        end

        local function valueFrom(instance)
            if instance:IsA("ValueBase") then
                return instance.Value
            end
            if instance:IsA("TextLabel") or instance:IsA("TextButton") then
                return instance.Text
            end
            return nil
        end

        if wanted[string.lower(root.Name)] then
            local value = valueFrom(root)
            if value ~= nil then return value end
        end

        for _, child in ipairs(root:GetDescendants()) do
            if wanted[string.lower(child.Name)] then
                local value = valueFrom(child)
                if value ~= nil then return value end
            end
        end
        return nil
    end

    local function readNumber(root, names)
        local value = readFreshValue(root, names)
        if type(value) == "number" then return value end
        if value ~= nil then
            return tonumber(value) or parseCompactCash(tostring(value))
        end
        return nil
    end

    local function readBool(root, names)
        local value = readFreshValue(root, names)
        if type(value) == "boolean" then return value end
        if value ~= nil then
            return string.lower(tostring(value)) == "true"
        end
        return false
    end

    local function artifactUidFromFrame(frame)
        local uid = readFreshValue(frame, {
            "ArtifactUid", "ArtifactUID", "Uid", "UID",
        })
        if uid ~= nil and tostring(uid) ~= "" then
            return tostring(uid)
        end

        local suffix = tostring(frame.Name):match(
            "^[Aa]rtifact[Ss]elect[Ff]rame[_%-](.+)$"
        )
        if suffix and suffix ~= "" then return suffix end
        return nil
    end

    local function getArtifactLevel(entry)
        local value = readNumber(entry, {
            "ArtifactLevel", "Level", "Lvl",
        })
        if value then return math.floor(value) end

        for _, child in ipairs(entry:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                local text = tostring(child.Text or "")
                local level = text:match("[Ll][Ee][Vv][Ee][Ll]%s*[.:%-]?%s*(%d+)")
                    or text:match("[Ll][Vv]%s*[.:%-]?%s*(%d+)")
                if level then
                    return tonumber(level)
                end

                local childName = string.lower(tostring(child.Name))
                level = text:match("(%d+)")
                if level and (
                    string.find(childName, "lvl", 1, true)
                    or string.find(childName, "level", 1, true)
                ) then
                    return tonumber(level)
                end
            end
        end
        return 0
    end

    local function getArtifactName(entry)
        local value = readFreshValue(entry, {
            "ArtifactId", "ArtifactID", "ArtifactName", "Name",
        })
        if value ~= nil and tostring(value) ~= "" then
            return tostring(value)
        end
        return tostring(entry.Name)
    end

    local artifactGenericNames = {
        artifact = true,
        artifacts = true,
        artifactconfig = true,
        artifactdata = true,
        artifactlist = true,
        artifactselectframe = true,
        config = true,
        data = true,
        id = true,
        name = true,
        level = true,
        rarity = true,
        cost = true,
        icon = true,
        description = true,
        uid = true,
        quantity = true,
    }

    local function prettyArtifactName(value)
        value = tostring(value or "")
        value = value:gsub("_", " "):gsub("-", " ")
        value = value:gsub("([a-z])([A-Z])", "%1 %2")
        return value:gsub("^%s*(.-)%s*$", "%1")
    end

    local function addArtifactCatalogName(result, seen, value)
        if type(value) ~= "string" then return end
        local label = prettyArtifactName(value)
        local key = string.lower(label)
        if label == "" or artifactGenericNames[key] then return end
        if string.find(key, "artifactselectframe", 1, true)
            or string.find(key, "rbxasset", 1, true)
            or string.find(key, "http", 1, true) then
            return
        end
        if tonumber(label) ~= nil or #label > 80 then return end
        if not seen[key] then
            seen[key] = true
            table.insert(result, label)
        end
    end

    local function collectArtifactConfig(value, result, seen, depth)
        if depth > 3 or type(value) ~= "table" then return end
        for key, entry in pairs(value) do
            if type(entry) == "table" then
                local label = entry.DisplayName
                    or entry.ArtifactName
                    or entry.Name
                    or entry.Id
                    or entry.ArtifactId
                if type(label) == "string" then
                    addArtifactCatalogName(result, seen, label)
                elseif type(key) == "string" then
                    addArtifactCatalogName(result, seen, key)
                end
                collectArtifactConfig(entry, result, seen, depth + 1)
            elseif type(entry) == "string" then
                local keyName = string.lower(tostring(key))
                if type(key) == "number"
                    or string.find(keyName, "name", 1, true)
                    or string.find(keyName, "id", 1, true) then
                    addArtifactCatalogName(result, seen, entry)
                end
            end
        end
    end

    local getArtifactEntries

    local function discoverArtifactCatalog()
        local result = {}
        local seen = {}

        for _, entry in ipairs(getArtifactEntries()) do
            addArtifactCatalogName(result, seen, entry.Name)
        end

        local plot = findPlot(Config.PlotNumber)
        if plot then
            for slotIndex = 1, 3 do
                local slot = plot:FindFirstChild(
                    "ArtifactSlot" .. tostring(slotIndex),
                    true
                )
                if slot then
                    addArtifactCatalogName(result, seen, tostring(
                        readFreshValue(slot, {
                            "ArtifactId", "ArtifactID", "ArtifactName", "Name",
                        }) or ""
                    ))
                end
            end
        end

        -- ArtifactSelectFrame entries only exist for owned items in some
        -- versions of the game. Also read the replicated artifact config so
        -- zero-quantity artifacts still appear in the dropdown.
        if not artifactState.CatalogScanned then
            for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
                local name = string.lower(tostring(descendant.Name))
                if descendant:IsA("ModuleScript")
                    and string.find(name, "artifact", 1, true) then
                    local ok, data = pcall(require, descendant)
                    if ok then
                        collectArtifactConfig(data, result, seen, 0)
                    end
                end
            end

            for _, folderName in ipairs({
                "Artifacts", "Artifact", "ArtifactConfig", "ArtifactsConfig",
            }) do
                local folder = ReplicatedStorage:FindFirstChild(folderName)
                if folder then
                    for _, descendant in ipairs(folder:GetDescendants()) do
                        if descendant:IsA("StringValue")
                            or descendant:IsA("ObjectValue") then
                            addArtifactCatalogName(
                                result,
                                seen,
                                tostring(descendant.Value or "")
                            )
                        elseif descendant.Parent == folder then
                            addArtifactCatalogName(result, seen, descendant.Name)
                        end
                    end
                end
            end
            artifactState.CatalogScanned = true
        end

        table.sort(result, function(a, b)
            return string.lower(a) < string.lower(b)
        end)
        artifactState.ArtifactCatalog = result
        return result
    end

    getArtifactEntries = function()
        local result = {}
        local seen = {}

        for _, descendant in ipairs(playerGui:GetDescendants()) do
            local name = string.lower(tostring(descendant.Name))
            if string.find(name, "artifactselectframe", 1, true) then
                local uid = artifactUidFromFrame(descendant)
                if uid and not seen[uid] then
                    seen[uid] = true
                    table.insert(result, {
                        Uid = uid,
                        Name = getArtifactName(descendant),
                        Level = getArtifactLevel(descendant),
                        Frame = descendant,
                    })
                end
            end
        end

        table.sort(result, function(a, b)
            local an = string.lower(tostring(a.Name))
            local bn = string.lower(tostring(b.Name))
            if an ~= bn then return an < bn end
            if a.Level ~= b.Level then return a.Level < b.Level end
            return a.Uid < b.Uid
        end)
        return result
    end

    -- Match the rank/trait card selectors: every owned copy gets its own
    -- option, while the first copy keeps the base name and later copies get
    -- a numbered suffix. The map is important because two artifacts with
    -- the same name can have different Uids.
    local function buildArtifactSelectionOptions()
        local options = {}
        local optionMap = {}
        local counts = {}
        local baseSeen = {}

        for _, entry in ipairs(getArtifactEntries()) do
            local baseName = tostring(entry.Name or "")
            if baseName ~= "" then
                counts[baseName] = (counts[baseName] or 0) + 1
                local label = baseName
                if counts[baseName] > 1 then
                    label = baseName .. " #" .. tostring(counts[baseName])
                end
                table.insert(options, label)
                optionMap[label] = entry
                baseSeen[string.lower(baseName)] = true
            end
        end

        -- Keep catalog entries selectable even when the inventory UI has not
        -- replicated an owned copy yet. These entries have no Uid and use
        -- the normal name-based fallback when they become available.
        for _, label in ipairs(discoverArtifactCatalog()) do
            local key = string.lower(tostring(label))
            if not baseSeen[key] then
                table.insert(options, label)
                optionMap[label] = nil
                baseSeen[key] = true
            end
        end

        table.sort(options, function(a, b)
            return string.lower(tostring(a)) < string.lower(tostring(b))
        end)
        return options, optionMap
    end

    local function getPlacedArtifactUids()
        local result = {}
        local plot = findPlot(Config.PlotNumber)
        if not plot then return result end

        for slotIndex = 1, 3 do
            local slot = plot:FindFirstChild("ArtifactSlot" .. tostring(slotIndex), true)
            local uid = slot and readFreshValue(slot, {
                "ArtifactUid", "ArtifactUID", "Uid", "UID",
            })
            if uid ~= nil and tostring(uid) ~= "" then
                result[tostring(uid)] = true
            end
        end
        return result
    end

    local function getResourceCount(names)
        local function readFromContainer(container)
            if not container then return nil end
            local value = readNumber(container, names)
            if value ~= nil then return value end
            return nil
        end

        for _, name in ipairs(names) do
            local value = readFromContainer(player:FindFirstChild(name))
            if value ~= nil then return value end
            local attribute = player:GetAttribute(name)
            value = tonumber(attribute)
                or (attribute ~= nil
                    and parseCompactCash(tostring(attribute)))
            if value ~= nil then return value end
        end

        for _, descendant in ipairs(player:GetDescendants()) do
            local descendantName = string.lower(tostring(descendant.Name))
            for _, name in ipairs(names) do
                if descendantName == string.lower(tostring(name)) then
                    local value = readFromContainer(descendant)
                    if value ~= nil then return value end
                end
            end
        end

        local leaderstats = player:FindFirstChild("leaderstats")
        for _, name in ipairs(names) do
            local value = readFromContainer(
                leaderstats and leaderstats:FindFirstChild(name)
            )
            if value ~= nil then return value end
        end

        -- The Items UI uses ObjectFrame_<resource> with a nested Quantity
        -- label. This is the fallback used when the balance is not replicated
        -- as a ValueBase or player attribute.
        local wanted = {}
        for _, name in ipairs(names) do
            local key = string.lower(tostring(name))
            wanted[key] = true
            wanted["objectframe_" .. key] = true
        end
        for _, descendant in ipairs(playerGui:GetDescendants()) do
            if wanted[string.lower(tostring(descendant.Name))] then
                for _, child in ipairs(descendant:GetDescendants()) do
                    if child:IsA("TextLabel") or child:IsA("TextButton") then
                        local value = parseCompactCash(tostring(child.Text or ""))
                        if value ~= nil then return value end
                    end
                end
            end
        end

        -- Use the ItemsRE mirror only after live values/UI have been checked.
        -- The mirror can briefly contain an old zero during replication and
        -- must not hide a newer player attribute or value.
        for _, name in ipairs(names) do
            local cached = artifactState.InventoryCounts[name]
            if cached ~= nil then
                return tonumber(cached)
                    or parseCompactCash(tostring(cached))
                    or 0
            end
        end
        return 0
    end

    local function selectedMatches(value, selection)
        return filterValueMatches(value, normalizeFilterSelection(selection))
    end

    local function selectedLevelMatches(level, selection)
        local selected = normalizeFilterSelection(selection)
        if next(selected) == nil then return true end
        local key = normalizeFilterValue(tostring(level))
        return key ~= nil and selected[key] == true
    end

    local function selectedBossId(value)
        if type(value) == "table" then value = value[1] end
        value = tostring(value or "")
        for _, card in ipairs(BOSS_CARDS) do
            if value == card.Id or value == card.Label then
                return card.Id
            end
        end
        return BOSS_CARDS[1].Id
    end

    local function bossCardById(id)
        for _, card in ipairs(BOSS_CARDS) do
            if card.Id == id then return card end
        end
        return BOSS_CARDS[1]
    end

    local function getBossSlot()
        local plot = findPlot(Config.PlotNumber)
        return plot and (
            plot:FindFirstChild("BossSlot", true)
            or plot:FindFirstChild("BossSlot1", true)
        )
    end

    local function fireArtifact(action, data)
        if not artifactState.ArtifactRE then return false end
        local ok = pcall(function()
            if data == nil then
                artifactState.ArtifactRE:FireServer(action)
            else
                artifactState.ArtifactRE:FireServer(action, data)
            end
        end)
        return ok
    end

    local function fireBossCard(action, data)
        if not artifactState.BossCardRE then return false end
        local ok = pcall(function()
            if data == nil then
                artifactState.BossCardRE:FireServer(action)
            else
                artifactState.BossCardRE:FireServer(action, data)
            end
        end)
        return ok
    end

    artifactState.getArtifactEntries = getArtifactEntries
    artifactState.getArtifactLevelOptions = function()
        return ARTIFACT_LEVEL_OPTIONS
    end
    artifactState.getBossCards = function()
        return BOSS_CARDS
    end
    artifactState.getBossCardId = selectedBossId

    local function normalizeArtifactSlotSelection(value)
        local values = type(value) == "table" and value or { value }
        local result = {}
        local seen = {}
        for _, option in ipairs(values) do
            option = tostring(option or "")
            local key = string.lower(option)
            if option ~= "" and key ~= "all"
                and key ~= "no artifacts found"
                and not seen[key] then
                table.insert(result, option)
                seen[key] = true
                if #result >= 3 then break end
            end
        end
        return result
    end

    artifactState.normalizeArtifactSlotSelection =
        normalizeArtifactSlotSelection

    artifactState.refreshArtifactOptions = function()
        local options = { "All" }
        local seen = { all = true }

        for _, label in ipairs(discoverArtifactCatalog()) do
            local key = string.lower(tostring(label))
            if not seen[key] then
                seen[key] = true
                table.insert(options, label)
            end
        end

        for _, entry in ipairs(getArtifactEntries()) do
            local label = tostring(entry.Name)
            local key = string.lower(label)
            if label ~= "" and not seen[key] then
                seen[key] = true
                table.insert(options, label)
            end
        end

        -- Keep loaded selections visible until the inventory UI/config modules
        -- replicate, even when the player currently owns zero copies.
        local selections = {
            type(Config.SelectedArtifactSlots) == "table"
                and Config.SelectedArtifactSlots or {},
            type(Config.SelectedArtifacts) == "table"
                and Config.SelectedArtifacts or {},
        }
        for _, selection in ipairs(selections) do
            for _, selected in ipairs(type(selection) == "table"
                and selection or {}) do
            local label = tostring(selected)
            local key = string.lower(label)
            if label ~= "" and label ~= "All" and not seen[key] then
                seen[key] = true
                table.insert(options, label)
            end
        end
        end

        table.sort(options, function(a, b)
            if a == b then return false end
            if a == "All" then return true end
            if b == "All" then return false end
            return string.lower(a) < string.lower(b)
        end)
        artifactState.ArtifactOptions = options
        local selectionOptions, selectionMap =
            buildArtifactSelectionOptions()
        artifactState.ArtifactSelectionOptions = selectionOptions
        artifactState.ArtifactSelectionOptionMap = selectionMap
        if #artifactState.ArtifactSelectionOptions == 0 then
            artifactState.ArtifactSelectionOptions = { "No artifacts found" }
            artifactState.ArtifactSelectionOptionMap = {}
        end

        local selectDropdown = artifactState.ArtifactDropdown
        if selectDropdown and selectDropdown.Refresh then
            pcall(function()
                selectDropdown:Refresh(
                    artifactState.ArtifactSelectionOptions,
                    Config.SelectedArtifactSlots
                )
            end)
        end

        local sellDropdown = artifactState.ArtifactSellDropdown
        if sellDropdown and sellDropdown.Refresh then
            pcall(function()
                sellDropdown:Refresh(options, Config.SelectedArtifacts)
            end)
        end
        if artifactState.updateArtifactSelectionInfo then
            artifactState.updateArtifactSelectionInfo()
        end
    end

    local function findSelectedArtifactEntry(wanted, entries, used)
        local label = tostring(wanted or "")
        local mapped = artifactState.ArtifactSelectionOptionMap[label]
        if mapped then
            for _, entry in ipairs(entries) do
                if tostring(entry.Uid) == tostring(mapped.Uid)
                    and (not used or not used[tostring(entry.Uid)]) then
                    return entry
                end
            end
        end

        -- A saved selection may outlive the inventory frame that created it.
        -- Fall back to the base name after removing our duplicate suffix.
        local baseName = label:gsub("%s+#%d+$", "")
        for _, entry in ipairs(entries) do
            local uid = tostring(entry.Uid)
            if (not used or not used[uid])
                and selectedMatches(entry.Name, { baseName }) then
                return entry
            end
        end
        return nil
    end

    artifactState.updateArtifactSelectionInfo = function()
        local paragraph = artifactState.ArtifactSelectParagraph
        if not paragraph or not paragraph.Set then return end

        local selected = normalizeArtifactSlotSelection(
            Config.SelectedArtifactSlots
        )
        local entries = getArtifactEntries()
        local used = {}
        local lines = {}

        if #selected == 0 then
            table.insert(lines, "No artifacts selected.")
        else
            for slotIndex, wanted in ipairs(selected) do
                local match = findSelectedArtifactEntry(wanted, entries, used)
                if match then used[tostring(match.Uid)] = true end
                if match then
                    table.insert(
                        lines,
                        "Slot " .. tostring(slotIndex) .. ": "
                            .. tostring(wanted)
                            .. " (Level " .. tostring(match.Level) .. ")"
                    )
                else
                    table.insert(
                        lines,
                        "Slot " .. tostring(slotIndex) .. ": "
                            .. tostring(wanted)
                            .. " (not currently owned)"
                    )
                end
            end
        end

        pcall(function()
            paragraph:Set({
                Title = "Selected Artifacts",
                Content = table.concat(lines, "\n"),
            })
        end)
    end

    artifactState.sellMatchingArtifacts = function()
        local placed = getPlacedArtifactUids()
        local sold = 0
        local now = os.clock()
        for _, entry in ipairs(getArtifactEntries()) do
            local matchesName = selectedMatches(
                entry.Name,
                Config.SelectedArtifacts
            )
            local matchesLevel = selectedLevelMatches(
                tostring(entry.Level),
                Config.SelectedArtifactLevels
            )
            local recentlySold = (now - (artifactState.LastSoldAt[entry.Uid] or 0)) < 2
            if matchesName and matchesLevel
                and not placed[entry.Uid] and not recentlySold then
                if fireArtifact("Sell", { Uid = entry.Uid }) then
                    artifactState.LastSoldAt[entry.Uid] = now
                    sold = sold + 1
                    task.wait(0.25)
                end
            end
        end
        return sold
    end

    artifactState.equipArtifacts = function()
        local selected = normalizeArtifactSlotSelection(
            Config.SelectedArtifactSlots
        )
        if #selected == 0 then return 0 end

        local entries = getArtifactEntries()
        local placed = getPlacedArtifactUids()
        local plot = findPlot(Config.PlotNumber)
        if not plot then return 0 end
        local equipped = 0

        for slotIndex, wanted in ipairs(selected) do
            local slot = plot:FindFirstChild(
                    "ArtifactSlot" .. tostring(slotIndex),
                    true
                )
            local currentUid = slot and readFreshValue(slot, {
                "ArtifactUid", "ArtifactUID", "Uid", "UID",
            })
            local match = findSelectedArtifactEntry(wanted, entries)

            if match
                and (
                    tostring(match.Uid) == tostring(currentUid or "")
                    or not placed[match.Uid]
                )
                and tostring(match.Uid) ~= tostring(currentUid or "") then
                local last = artifactState.LastArtifactEquipAt[slotIndex] or 0
                if os.clock() - last >= 2
                    and fireArtifact("Place", {
                        SlotIndex = slotIndex,
                        Uid = match.Uid,
                    }) then
                    artifactState.LastArtifactEquipAt[slotIndex] = os.clock()
                    placed[match.Uid] = true
                    equipped = equipped + 1
                    task.wait(0.25)
                end
            end
        end
        return equipped
    end

    artifactState.upgradeArtifacts = function()
        local upgraded = 0

        -- ArtifactRE performs the live ownership, level, and shard checks on
        -- the server. Do not gate this request on slot attributes: those
        -- values are not replicated consistently and were preventing the
        -- remote from being called at all.
        for slotIndex = 1, 3 do
            if fireArtifact("Upgrade", { SlotIndex = slotIndex }) then
                upgraded = upgraded + 1
                task.wait(0.2)
            end
        end
        return upgraded
    end

    artifactState.equipBossCard = function()
        local id = selectedBossId(Config.SelectedBossCard)
        local slot = getBossSlot()
        local current = slot and readFreshValue(slot, {
            "BossCardId", "BossCardID", "CardId",
        })
        if tostring(current or "") == id then return false end

        local now = os.clock()
        if now - artifactState.LastBossEquipAt < 2 then return false end
        artifactState.LastBossEquipAt = now
        return fireBossCard("Place", {
            SlotIndex = 1,
            BossCardId = id,
        })
    end

    artifactState.upgradeBossCard = function()
        -- BossCardRE upgrades the equipped boss card in slot 1. The request
        -- intentionally has no payload, matching the game's own call.
        return fireBossCard("Upgrade")
    end
end

local function getItemId(container)
    local value = readBoxValue(container, {
        "ItemId", "ItemID", "itemId",
    })
    if value ~= nil then return tonumber(value) or value end

    local current = container.Parent
    for _ = 1, 6 do
        if not current or current == workspace then break end
        -- The reference pack objects can expose ItemId on a holder above
        -- the visible model. Only inspect that holder itself here: scanning
        -- all descendants of an ancestor could borrow a sibling pack's ID.
        local parentValue = nil
        for _, name in ipairs({
            "ItemId", "ItemID", "itemId",
        }) do
            parentValue = current:GetAttribute(name)
            if parentValue ~= nil then break end
        end
        if parentValue == nil then
            for _, name in ipairs({
                "ItemId", "ItemID", "itemId",
            }) do
                local child = current:FindFirstChild(name)
                if child and child:IsA("ValueBase") then
                    parentValue = child.Value
                    break
                end
            end
        end
        if parentValue ~= nil then return tonumber(parentValue) or parentValue end
        current = current.Parent
    end

    return nil
end

local function getPackId(container)
    if not container then return nil end
    local value = readBoxValue(container, {
        "PackId", "PackID", "packId",
    })
    if value ~= nil then return tonumber(value) or value end
    return nil
end

-- PackId is useful for recognizing a conveyor object, but the purchase
-- endpoint uses ItemId. Keep it separate so PackId can never be sent as
-- ItemId by mistake.
local function hasPackId(container)
    return getPackId(container) ~= nil
end

local function isPackContainer(container, info)
    if not container then return false end

    local name = string.lower(container.Name)
    if name == "boxbasemodel"
        or string.find(name, "pack", 1, true)
        or string.find(name, "box", 1, true) then
        return true
    end

    local hasConveyorName = string.find(name, "conveyor", 1, true) ~= nil
    return hasConveyorName
        or getItemId(container) ~= nil
        or hasPackId(container)
        or info and info.pack ~= nil
end

-- ════════════════════════════════════════════════════════════════════════
-- ════════════════════════════════════════════════════════════════════════
--  OPTIMIZED CONVEYOR & AUTO-BUY SYSTEM
--  State machine per pack:
--    New → WaitingForMetadata → WaitingForItemId
--       → WaitingForPurchaseWindow → Queued → Buying
--       → BoughtAndRemove → Removed
--
--  REGISTER BUDGET NOTE
--  Lua enforces a limit of 200 local registers per function (chunk).
--  All conveyor internals are wrapped in a do...end block so their ~38
--  registers are freed when the block ends, keeping the outer chunk well
--  under the limit. Only the 10 values that other loops need are exposed
--  as outer upvalues declared before the block.
-- ════════════════════════════════════════════════════════════════════════

-- ── Shared gate used by box handling and combat loops ─────────────────
local boxHandlingActive = false
-- Auto Stop uses this only while newly spawned records are being checked.
-- Auto Buy waits during that window so it cannot remove the desired pack
-- before the watcher sees the replicated metadata.
local autoStopSearchActive = false

-- ── Diagnostic helpers (used throughout the entire script) ───────────
local diagnosticState = {}

-- These upvalues are assigned inside the do block below.
local warnOnce, passesFilter, debugAutoBuy, markFilterCacheDirty
local getConveyorPacks, getPackKey, indexPackIds
local reevaluateAutoBuy, autoBuyHasPending

do -- ════ CONVEYOR INTERNALS (isolated scope — frees ~38 registers on exit) ════

-- ── Registry and queue tables ─────────────────────────────────────────
local ConveyorRecords = {}                     -- [packModel] = record
local ItemIdIndex     = {}                     -- [itemId]    = packModel
local PurchaseQueue   = {}                     -- ordered list of records
local PurchaseQueued  = {}                     -- [record]    = true (dedup)
local WatchedPrompts  = setmetatable({}, { __mode = "k" })
-- Keep attempts serialized per record through the state machine. Do not use a
-- global purchase lock here: packs arrive independently and waiting for one
-- removal confirmation stalls Auto Buy for every other matching pack.

-- ── Timing constants ──────────────────────────────────────────────────
local BUY_RETRY_DELAY  = 0.75   -- min seconds between buy attempts per record
local BUY_CONFIRM_TIMEOUT = 2.0 -- wait for removal/disable confirmation
local MAX_BUY_ATTEMPTS = 4

local METADATA_TTL     = 1.5    -- seconds between metadata refreshes per record
local ITEMID_FALLBACK_INTERVAL = 2.0
local RETRY_BACKOFF    = 3.0
local DEBUG_COOLDOWN   = 3.0    -- seconds between identical debug lines

-- ── Debug rate-limiting table ─────────────────────────────────────────
local DebugCooldowns = {}

-- ── Filter cache (rebuilt only when a filter dropdown changes) ────────
local FilterCache = { Rarities = {}, Mutations = {}, Packs = {}, dirty = true }

-- ── Forward declarations for mutually recursive functions ─────────────
local cleanupRecord, refreshRecordMetadata, evaluateRecordReadiness
local queuePurchase, tryBuyRecord
local confirmBought

-- ── Outer-upvalue assignments (begin) ────────────────────────────────

warnOnce = function(key, message)
    if diagnosticState[key] then return end
    diagnosticState[key] = true
    warn("[ACF] " .. message)
end

-- Debug logging removed; keep no-op stubs so call sites compile cleanly.
local function autoBuyDebugInner() end
debugAutoBuy = autoBuyDebugInner
local function debugOnce() end

local function rebuildFilterCache()
    FilterCache.Rarities  = normalizeFilterSelection(Config.SelectedRarities)
    FilterCache.Mutations = normalizeFilterSelection(Config.SelectedMutations)
    FilterCache.Packs     = normalizeFilterSelection(Config.SelectedPacks)
    FilterCache.dirty     = false
end

markFilterCacheDirty = function()
    FilterCache.dirty = true
end

passesFilter = function(info)
    if FilterCache.dirty then rebuildFilterCache() end
    info = info or {}
    return filterValueMatches(info.rarity,   FilterCache.Rarities)
       and filterValueMatches(info.mutation, FilterCache.Mutations)
       and filterValueMatches(info.pack,     FilterCache.Packs)
end

-- ── Connection tracker ────────────────────────────────────────────────
local function trackConnection(record, conn)
    if conn then table.insert(record.connections, conn) end
end

-- ── State-machine transition ──────────────────────────────────────────
local function transitionState(record, newState, reason)
    if record.state == newState then return end
    record.state = newState
end

-- ── Conveyor topology checks ──────────────────────────────────────────
local function hasConveyorAncestor(instance)
    local cur = instance
    for _ = 1, 10 do
        if not cur then break end
        local lname = string.lower(cur.Name)
        if lname == "conveyor"
            or string.find(lname, "conveyor", 1, true)
            or lname == "conveyorpacks"
            or string.find(lname, "conveyorpacks", 1, true) then
            return true
        end
        -- Some versions keep the live objects below LocalConveyorModels
        -- or PackAtB without naming the intermediate model "Conveyor".
        if lname == "localconveyormodels"
            or string.find(lname, "localconveyor", 1, true)
            or lname == "packatb" then
            return true
        end
        cur = cur.Parent
    end
    return false
end

local function isConveyorModel(model)
    return model and model:IsA("Model") and hasConveyorAncestor(model)
end

local function isLikelyPackModel(model)
    if not model or not model:IsA("Model") then return false end
    local modelName = string.lower(model.Name)
    local inConveyor = isConveyorModel(model)
    local knownPackName = string.find(modelName, "pack", 1, true) ~= nil
        or string.find(modelName, "box", 1, true) ~= nil
    if not inConveyor and not knownPackName then return false end

    for _, n in ipairs({
        "ItemId", "ItemID", "itemId",
    }) do
        if model:GetAttribute(n) ~= nil then return true end
    end
    if hasPackId(model) then return true end
    if model:FindFirstChildWhichIsA("ProximityPrompt", true) then return true end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("ValueBase") then
            local childName = string.lower(child.Name)
            if childName == "itemid" or childName == "packid" then
                return true
            end
        end
    end

    -- A workspace fallback must have an identifier, PackId, or prompt.
    -- Inside the live conveyor hierarchy, a pack-like model may be observed
    -- before its ItemId holder is created, so retain it for the watcher.
    if not inConveyor then return false end
    return knownPackName
end

-- ── Buy prompt helpers ────────────────────────────────────────────────
local function normalizePromptText(value)
    if value == nil then return "" end
    return string.lower(string.gsub(tostring(value), "^%s*(.-)%s*$", "%1"))
end

local function isBuyPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    local n = normalizePromptText(prompt.Name)
    local a = normalizePromptText(prompt.ActionText)
    local o = normalizePromptText(prompt.ObjectText)
    return string.find(n, "buy", 1, true) ~= nil
        or string.find(a, "buy", 1, true) ~= nil
        or string.find(o, "buy", 1, true) ~= nil
        or string.find(n, "purchase", 1, true) ~= nil
        or string.find(a, "purchase", 1, true) ~= nil
        or string.find(o, "purchase", 1, true) ~= nil
end

-- Primary: confirmed path  packModel.Main.ProximityPrompt
-- Fallback: scan descendants for any enabled buy prompt.
local function getBuyPrompt(packModel)
    if not packModel then return nil end
    -- Confirmed exact path from screenshots. Prefer it when it is explicitly
    -- a buy prompt, but do not let a generic/disabled prompt hide a better
    -- matching prompt elsewhere in the same pack.
    local exactPrompt = nil
    local main = packModel:FindFirstChild("Main")
    if main then
        local prompt = main:FindFirstChild("ProximityPrompt")
        if prompt and prompt:IsA("ProximityPrompt") then
            exactPrompt = prompt
            if isBuyPrompt(prompt) and prompt.Enabled ~= false then
                return prompt
            end
        end
    end

    -- Recursive fallback: prefer an enabled prompt whose text identifies the
    -- purchase action. If the confirmed Main prompt exists, keep using it
    -- before falling back to unrelated enabled prompts.
    local firstBuyPrompt = nil
    local firstEnabled = nil
    for _, desc in ipairs(packModel:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            if isBuyPrompt(desc) then
                if desc.Enabled ~= false then return desc end
                if not firstBuyPrompt then firstBuyPrompt = desc end
            end
            if desc.Enabled ~= false and not firstEnabled then
                firstEnabled = desc
            end
        end
    end
    return exactPrompt or firstBuyPrompt or firstEnabled
end

-- Legacy alias used by prompt-watcher helpers below.
local findBestBuyPrompt = getBuyPrompt

-- ── Cash safety check ─────────────────────────────────────────────────
-- Returns true when the player has enough known cash (and enough reserve) to
-- buy. Unknown client-side cash/price is allowed through to the server, which
-- remains authoritative.
local function canBuyWithCash(record)
    local cash = getPlayerCash()
    if cash == nil then
        -- Cash can be exposed only through a late-replicating HUD or can be
        -- represented by a server-side value that the client cannot read.
        -- The purchase prompt/remote still performs the authoritative check.
        return true, "CashValueUnavailable"
    end
    local price = record.price
    if price == nil then
        -- Do not discard a matching pack while its BillboardGui/Cost value is
        -- still replicating.  The server knows the actual price.
        return true, "PriceUnavailable"
    end
    if cash < price then
        return false, "NotEnoughCash"
    end
    if Config.UseCashReserve then
        local reserve = tonumber(Config.CashReserve) or 0
        if reserve > 0 and (cash - price) < reserve then
            return false, "BelowCashReserve"
        end
    end
    return true
end

-- ── Record cleanup ────────────────────────────────────────────────────
cleanupRecord = function(record)
    if not record or record.state == "Removed" then return end
    transitionState(record, "Removed", "cleanup")
    PurchaseQueued[record] = nil
    record.queued = false
    for _, conn in ipairs(record.connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(record.connections)
    if record.model then
        ConveyorRecords[record.model] = nil
        metadataCache[record.model]   = nil
    end
    if record.itemId ~= nil and ItemIdIndex[record.itemId] == record.model then
        ItemIdIndex[record.itemId] = nil
    end
end

confirmBought = function(record, reason)
    if not record or record.state == "Removed" then return end
    transitionState(record, "BoughtAndRemove", reason)
    debugOnce(
        "confirmed:" .. tostring(record.model),
        "Purchase confirmed (" .. tostring(reason) .. ")",
        0
    )
    cleanupRecord(record)
end

-- ── Metadata refresh (lazy, TTL-gated) ───────────────────────────────
refreshRecordMetadata = function(record, force)
    if not record or not record.model then return end
    local now = os.clock()
    if not force
        and record.lastMetadataRefresh
        and now - record.lastMetadataRefresh < METADATA_TTL then
        return
    end
    record.lastMetadataRefresh = now

    -- ── NEW: read from confirmed BillboardGuiInfo structure ──────────
    -- Prefer a canonical pack name or the name recovered by getBoxInfo.
    -- Some live conveyor models are generic names such as BoxBaseModel;
    -- replacing a resolved pack with that generic name breaks specific pack
    -- filters while "Any" appears to work.
    local liveInfo = getBoxInfo(record.model)
    local modelNameKey = filterCompareKey(record.model.Name)
    local canonicalPackName = nil
    for _, packName in ipairs(PACKS) do
        if filterCompareKey(packName) == modelNameKey then
            canonicalPackName = packName
            break
        end
    end
    record.packName = canonicalPackName
        or (liveInfo and liveInfo.pack)
        or record.packName
        or record.model.Name

    -- Rarity, mutation from BillboardGuiInfo children.
    local freshRarity   = getPackRarity(record.model)
    local freshMutation = getPackMutation(record.model)
    record.rarity   = freshRarity
    record.mutation = freshMutation

    -- Price: try exact numeric sources first, GUI text only as last resort.
    -- getPackPrice searches attributes → NumberValue children → suffix text.
    local freshPrice = getPackPrice(record.model)
    if freshPrice and freshPrice > 0 then
        record.price      = freshPrice
        -- Keep priceText for the debug log line; re-read the raw label if possible.
        record.priceText  = getPackPriceText(record.model) or tostring(freshPrice)
        record.priceState = "Valid"
    else
        -- Could not resolve a price yet.
        if record.price == nil then
            -- Only overwrite if we never had a valid price (don't erase a
            -- previously-cached good value just because the GUI is mid-update).
            record.priceState = "Missing"
        end
    end

    -- Prompt: use confirmed path first.
    local freshPrompt = getBuyPrompt(record.model)
    if freshPrompt then record.prompt = freshPrompt end

    -- ── Legacy compatibility: keep record.info populated for passesFilter ─
    -- passesFilter reads record.info.{pack,rarity,mutation}.
    record.info = {
        pack     = record.packName,
        rarity   = record.rarity,
        mutation = record.mutation,
    }

    -- ── Keep ItemId index updated (kept as optional fallback only) ─────
    local freshId = getItemId(record.model)
    if freshId ~= record.itemId then
        local oldId = record.itemId
        if oldId ~= nil and ItemIdIndex[oldId] == record.model then
            ItemIdIndex[oldId] = nil
        end
        record.itemId = freshId
        if freshId ~= nil then
            ItemIdIndex[freshId] = record.model
        end
    end
end

-- ── Readiness evaluation ──────────────────────────────────────────────
evaluateRecordReadiness = function(record)
    if not record then return end
    local st = record.state
    if st == "BoughtAndRemove" or st == "Removed" or st == "Buying" then
        return
    end

    -- Resolve buy prompt using the confirmed path.
    if not record.prompt then
        record.prompt = getBuyPrompt(record.model)
        record.buyPrompt = record.prompt   -- keep legacy alias in sync
    end
    if not record.buyPrompt then
        record.buyPrompt = record.prompt
    end

    if not passesFilter(record.info) then
        record.filterPassed = false
        if st ~= "FilterRejected" then
            transitionState(record, "FilterRejected", "filter")
            debugOnce(
                "filter-miss:" .. tostring(record.model),
                "Filter rejected pack=" .. tostring(record.info and record.info.pack)
                    .. " rarity=" .. tostring(record.info and record.info.rarity)
                    .. " mutation=" .. tostring(record.info and record.info.mutation),
                0
            )
        end
        return
    end

    record.filterPassed = true

    -- With the prompt-first approach the purchase window opens as soon as
    -- the confirmed prompt is present, regardless of whether ItemId has
    -- replicated yet. The cash/price check is enforced inside tryBuyRecord.
    local hasPrompt = record.prompt ~= nil
    local hasId     = record.itemId ~= nil

    if not hasPrompt and not hasId then
        -- Neither prompt nor ItemId yet; wait for one to appear.
        if st ~= "WaitingForItemId" then
            transitionState(record, "WaitingForItemId", "no prompt or ItemId yet")
        end
        return
    end

    if st ~= "WaitingForPurchaseWindow" then
        local reason = hasPrompt and "prompt present" or "ItemId present"
        transitionState(record, "WaitingForPurchaseWindow", reason)
    end

    local purchaseWindowOpen =
        record.state == "WaitingForPurchaseWindow"
        and os.clock() >= (record.retryNotBefore or 0)
        and (hasPrompt or hasId)

    if Config.AutoBuyMatching and purchaseWindowOpen
        and not autoStopSearchActive then
        queuePurchase(record)
    end
end

-- ── Purchase queue ────────────────────────────────────────────────────
queuePurchase = function(record)
    if not record or record.state ~= "WaitingForPurchaseWindow"
        or record.filterPassed ~= true or PurchaseQueued[record]
        or autoStopSearchActive
        or os.clock() < (record.retryNotBefore or 0) then
        return
    end
    PurchaseQueued[record] = true
    record.queued = true
    transitionState(record, "Queued", "purchase queue")
    table.insert(PurchaseQueue, record)
    debugOnce(
        "queued:" .. tostring(record.model),
        "Queued matching pack=" .. tostring(record.info and record.info.pack)
            .. " rarity=" .. tostring(record.info and record.info.rarity)
            .. " mutation=" .. tostring(record.info and record.info.mutation)
            .. " ItemId=" .. tostring(record.itemId),
        0
    )
end

-- ── Buy attempt ───────────────────────────────────────────────────────
-- PRIMARY PATH: fireproximityprompt(packModel.Main.ProximityPrompt)
-- FALLBACK:     ConveyorRE:FireServer("TryBuy", { ItemId = itemId })
--               only when the prompt path is unavailable.
-- SAFETY RULE: never fire when known cash < known price. Unknown values are
-- allowed through because the server validates the actual transaction.
tryBuyRecord = function(record)
    if not record or not record.model or record.state ~= "Queued" then
        return false
    end
    if autoStopSearchActive then
        -- Auto Stop is still validating newly spawned records. Put this
        -- record back into the waiting state instead of buying it before the
        -- watcher can inspect its final rarity/mutation.
        PurchaseQueued[record] = nil
        record.queued = false
        transitionState(record, "WaitingForPurchaseWindow",
            "Auto Stop metadata check")
        return true
    end
    if not record.model:IsDescendantOf(workspace) then
        cleanupRecord(record)
        return false
    end

    -- Refresh ALL metadata (price, rarity, mutation, prompt) immediately
    -- before execution so we act on the latest server state.
    refreshRecordMetadata(record, true)

    -- Re-check filters after refresh.
    if not record.filterPassed or not passesFilter(record.info) then
        transitionState(record, "FilterRejected", "filter changed before buy")
        return true
    end

    -- ── MANDATORY CASH SAFETY CHECK ──────────────────────────────────
    -- Never fire the prompt when cash is insufficient — that would trigger
    -- the Robux purchase popup.
    local cashOk, cashReason = canBuyWithCash(record)
    if not cashOk then
        debugOnce(
            "cash-fail:" .. tostring(record.model),
            "Cash check failed: " .. tostring(cashReason)
                .. "  price=" .. tostring(record.priceText)
                .. "  cash=" .. tostring(getPlayerCash()),
            DEBUG_COOLDOWN
        )
        -- Keep record alive for re-evaluation when cash changes.
        transitionState(record, "WaitingForPurchaseWindow", cashReason)
        record.queued = false
        PurchaseQueued[record] = nil
        return true
    end

    -- ── Throttle: respect minimum retry delay ─────────────────────────
    local now = os.clock()
    if now - record.lastBuyAttempt < BUY_RETRY_DELAY then return false end
    record.lastBuyAttempt = now
    record.buyAttempts    = record.buyAttempts + 1

    -- ── Resolve the confirmed buy prompt ─────────────────────────────
    -- record.prompt is set by refreshRecordMetadata via getBuyPrompt().
    local prompt = record.prompt
    if not prompt then
        prompt = getBuyPrompt(record.model)
        record.prompt = prompt
    end
    -- Keep buyPrompt in sync for the existing prompt-watcher code.
    if prompt then record.buyPrompt = prompt end

    transitionState(record, "Buying", "prompt-based attempt #" .. tostring(record.buyAttempts))

    -- ── PRIMARY: fire the ProximityPrompt ────────────────────────────
    if prompt then
        -- Final check: prompt must be enabled (not just present).
        if not prompt.Enabled then
            debugOnce("prompt-disabled:" .. tostring(record.model),
                "Prompt not enabled at fire time — waiting", DEBUG_COOLDOWN)
            transitionState(record, "WaitingForPurchaseWindow", "prompt disabled")
            record.retryNotBefore = os.clock() + BUY_RETRY_DELAY
            return true
        end

        local promptOk, _ = pcall(fireproximityprompt, prompt)
        if promptOk then
            record.promptSent = true
            -- Confirmation comes from model removal or prompt becoming disabled.
            return true
        end
    end

    -- ── FALLBACK: ConveyorRE:FireServer("TryBuy", ...) ───────────────
    -- Only used when fireproximityprompt is unavailable or threw.
    local itemId = record.itemId
    if itemId ~= nil then
        local ok, _ = pcall(function()
            ConveyorRE:FireServer("TryBuy", { ItemId = itemId })
        end)
        if ok then
            record.remoteSent = true
            return true
        else
            record.remoteFailed = true
        end
    end

    -- All purchase paths failed; back off and retry later.
    transitionState(record, "WaitingForPurchaseWindow", "all buy paths failed")
    record.retryNotBefore = os.clock() + RETRY_BACKOFF
    return true
end

-- ── Prompt event watcher ──────────────────────────────────────────────
local function watchPromptEnabled(prompt, record)
    if not prompt or WatchedPrompts[prompt] then return end
    WatchedPrompts[prompt] = true
    trackConnection(record,
        prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
            if record.state == "Removed" then return end
            if not prompt.Enabled then
                if record.state == "Buying" then
                    confirmBought(record, "buy prompt disabled")
                end
                return
            end
            -- Sync both prompt aliases.
            if isBuyPrompt(prompt) or record.prompt == nil then
                record.prompt    = prompt
                record.buyPrompt = prompt
            end
            refreshRecordMetadata(record, false)
            evaluateRecordReadiness(record)
        end)
    )
end

local function attachPromptsOnPack(record)
    -- Attach to any already-present ProximityPrompts.
    for _, desc in ipairs(record.model:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            watchPromptEnabled(desc, record)
        end
    end

    trackConnection(record,
        record.model.DescendantAdded:Connect(function(desc)
            if desc:IsA("ProximityPrompt") then
                watchPromptEnabled(desc, record)
                -- Prefer the confirmed exact path when it arrives.
                local main = record.model:FindFirstChild("Main")
                if main and desc.Parent == main and desc.Name == "ProximityPrompt" then
                    record.prompt    = desc
                    record.buyPrompt = desc
                end
                if isBuyPrompt(desc) and desc.Enabled then
                    record.buyPrompt = desc
                    if record.prompt == nil then record.prompt = desc end
                    evaluateRecordReadiness(record)
                end
            end
            -- Any new descendant may bring the Price or rarity/mutation labels.
            metadataCache[record.model] = nil
            -- Trigger a price/metadata refresh if the Price label arrives.
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                local parent = desc.Parent
                local grandparent = parent and parent.Parent
                local ggparent    = grandparent and grandparent.Parent
                -- Check if we are inside GuiHolder.BillboardGuiInfo.Price
                if parent and parent.Name == "Price"
                    and grandparent and grandparent.Name == "BillboardGuiInfo"
                    and ggparent and ggparent.Name == "GuiHolder" then
                    -- Watch for text changes on this price label.
                    trackConnection(record,
                        desc:GetPropertyChangedSignal("Text"):Connect(function()
                            if record.state == "Removed" then return end
                            refreshRecordMetadata(record, true)
                            evaluateRecordReadiness(record)
                        end)
                    )
                    -- Refresh immediately so the new price is captured.
                    refreshRecordMetadata(record, true)
                    evaluateRecordReadiness(record)
                end
            end
        end)
    )

    trackConnection(record,
        record.model.DescendantRemoving:Connect(function()
            metadataCache[record.model] = nil
        end)
    )
end

-- ── ItemId event watcher ──────────────────────────────────────────────
local function attachItemIdWatcher(record)
    local model = record.model
    local itemIdNames = { "ItemId", "ItemID", "itemId" }
    local watchedSources = setmetatable({}, { __mode = "k" })

    local function refreshItemId()
        if record.state == "BoughtAndRemove" or record.state == "Removed" then return end

        -- readBoxValue caches ValueBase lookups; a conveyor can add or
        -- replace its holder after registration, so invalidate that cache
        -- before resolving the current identifier.
        metadataCache[model] = nil
        local freshId = getItemId(model)
        if freshId == record.itemId then
            evaluateRecordReadiness(record)
            return
        end

        local oldId = record.itemId
        if oldId ~= nil and ItemIdIndex[oldId] == model then
            ItemIdIndex[oldId] = nil
        end
        record.itemId = freshId

        if freshId ~= nil then
            ItemIdIndex[freshId] = model
        end
        evaluateRecordReadiness(record)
    end

    local function watchSource(source)
        if not source or watchedSources[source] then return end
        watchedSources[source] = true

        for _, attrName in ipairs(itemIdNames) do
            trackConnection(record,
                source:GetAttributeChangedSignal(attrName):Connect(refreshItemId)
            )
        end

        if source:IsA("ValueBase") then
            trackConnection(record, source.Changed:Connect(refreshItemId))
        end
    end

    -- The reference uses live conveyor objects, where the ID may be placed
    -- on a holder/child after the pack model is first observed.
    watchSource(model)
    for _, desc in ipairs(model:GetDescendants()) do
        watchSource(desc)
    end
    trackConnection(record,
        model.DescendantAdded:Connect(function(desc)
            watchSource(desc)
            refreshItemId()
        end)
    )
    refreshItemId()
end

-- ── Pack registration (idempotent) ────────────────────────────────────
local function registerPack(packModel)
    if not packModel then return nil end
    if ConveyorRecords[packModel] then return ConveyorRecords[packModel] end

    local info   = getBoxInfo(packModel)
    local itemId = getItemId(packModel)

    local record = {
        model               = packModel,
        container           = packModel.Parent,
        state               = "New",
        itemId              = itemId,
        info                = info,

        -- NEW: confirmed structure fields (populated by refreshRecordMetadata)
        packName            = (info and info.pack) or packModel.Name,
        rarity              = nil,
        mutation            = nil,
        price               = nil,
        priceText           = nil,
        priceState          = "Missing",
        prompt              = nil,   -- packModel.Main.ProximityPrompt

        buyPrompt           = nil,   -- legacy alias; kept for prompt-watcher code
        filterPassed        = nil,
        queued              = false,
        createdAt           = os.clock(),
        lastMetadataRefresh = 0,     -- force immediate refresh on registration
        lastFallbackCheck   = 0,
        lastBuyAttempt      = 0,
        buyAttempts         = 0,
        retryNotBefore      = 0,
        remoteSent          = false,
        remoteFailed        = false,
        fallbackUsed        = false,
        promptSent          = false,
        connections         = {},
    }
    ConveyorRecords[packModel] = record
    transitionState(record, "WaitingForMetadata", "registered")
    if itemId ~= nil then ItemIdIndex[itemId] = packModel end

    attachItemIdWatcher(record)
    attachPromptsOnPack(record)

    -- Populate price, rarity, mutation, and confirmed prompt immediately.
    -- lastMetadataRefresh is 0 so this always runs on first registration.
    refreshRecordMetadata(record, true)

    -- Sync legacy buyPrompt alias.
    if not record.buyPrompt then
        record.buyPrompt = record.prompt or getBuyPrompt(packModel)
        record.prompt    = record.buyPrompt
    end

    trackConnection(record,
        packModel.AncestryChanged:Connect(function()
            if not packModel:IsDescendantOf(workspace) then
                if record.state == "Buying" or record.remoteSent or record.promptSent then
                    confirmBought(record, "model removed")
                else
                    cleanupRecord(record)
                end
            end
        end)
    )

    evaluateRecordReadiness(record)
    return record
end

-- ── Plot-scoped conveyor container ────────────────────────────────────
-- Uses the same multi-path fallback logic as findPlot/getPlotButtons so
-- that the container is found even when MAP is absent or Plot_N0 is missing.
local function getLocalConveyorContainer()
    local plot = findPlot(Config.PlotNumber)
    if not plot then return nil end
    -- Direct child first, then recursive (handles Plot_N0 vs slot root).
    return plot:FindFirstChild("LocalConveyorModels")
        or plot:FindFirstChild("LocalConveyorModels", true)
end

-- ── Initial local-conveyor scan (direct children only) ────────────────
local function doInitialConveyorScan()
    local container = getLocalConveyorContainer()
    if not container then return end
    local children = container:GetChildren()
    for index, desc in ipairs(children) do
        if index % 200 == 0 then task.wait() end
        if desc:IsA("Model") then
            registerPack(desc, container)
        end
    end
end

-- ── Plot-change rebind ────────────────────────────────────────────────
local conveyorContainerConnections = {}
local boundConveyorContainer = nil

local function rebindConveyorContainerInner()
    local container = getLocalConveyorContainer()
    if container == boundConveyorContainer then return end

    for _, connection in ipairs(conveyorContainerConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(conveyorContainerConnections)

    for _, record in pairs(ConveyorRecords) do cleanupRecord(record) end
    table.clear(ConveyorRecords)
    table.clear(ItemIdIndex)
    table.clear(PurchaseQueue)
    table.clear(PurchaseQueued)

    boundConveyorContainer = container
    if not container then
        warnOnce("local-conveyor-missing",
            "LocalConveyorModels not found for plot "
                .. tostring(Config.PlotNumber)
                .. " — auto buy cannot register packs. Check plot number or game structure.")
        return
    end

    conveyorContainerConnections[1] =
        container.ChildAdded:Connect(function(child)
            if child:IsA("Model") then
                registerPack(child, container)
            end
        end)
    conveyorContainerConnections[2] =
        container.ChildRemoved:Connect(function(child)
            local record = ConveyorRecords[child]
            if not record then return end
            if record.state == "Buying" or record.remoteSent or record.promptSent then
                confirmBought(record, "removed from local conveyor")
            else
                cleanupRecord(record)
            end
        end)

    doInitialConveyorScan()
end

-- ── Conveyor scheduler (0.15 s) ───────────────────────────────────────
local lastConveyorDiscoveryScan = 0
task.spawn(function()
    while true do
        task.wait(0.2)
        rebindConveyorContainerInner()

        -- ChildAdded is not reliable during plot rebinding/rapid spawns.
        -- Periodically scan the live container as a discovery fallback so
        -- Auto Buy works even when Auto Stop is disabled.
        if os.clock() - lastConveyorDiscoveryScan >= 0.5 then
            lastConveyorDiscoveryScan = os.clock()
            doInitialConveyorScan()
        end

        -- Auto Buy must remain independent from Auto Stop / Auto Continue.
        -- Re-check live records here because a pack can receive its prompt,
        -- ItemId, price, or mutation after the ChildAdded callback fires.
        -- This is intentionally a cheap TTL-gated refresh, not a blocking
        -- wait for the spawn manager.
        if not boxHandlingActive and Config.AutoBuyMatching then
            for _, record in pairs(ConveyorRecords) do
                if record.model
                    and record.model:IsDescendantOf(workspace)
                    and record.state ~= "Buying"
                    and record.state ~= "Queued"
                    and record.state ~= "Removed" then
                    refreshRecordMetadata(record, false)
                    evaluateRecordReadiness(record)
                end
            end
        end

        -- Process purchase queue
        if not boxHandlingActive and Config.AutoBuyMatching then
            local record = table.remove(PurchaseQueue, 1)
            if record then
                PurchaseQueued[record] = nil
                record.queued = false
                local attempted = tryBuyRecord(record)
                if not attempted and record.state == "Queued" and record.model:IsDescendantOf(workspace) then
                    PurchaseQueued[record] = true
                    record.queued = true
                    table.insert(PurchaseQueue, record)
                end
            end
        end

        -- Slow fallback for waiting/stuck records
        for _, record in pairs(ConveyorRecords) do
            local st = record.state
            if st == "Detected" or st == "WaitingForMetadata"
                or st == "WaitingForItemId"
                or st == "WaitingForPurchaseWindow"
                or st == "FilterRejected" then
                if st == "WaitingForItemId"
                    and os.clock() - record.lastFallbackCheck
                        >= ITEMID_FALLBACK_INTERVAL then
                    record.lastFallbackCheck = os.clock()
                    record.lastMetadataRefresh = 0
                end
                refreshRecordMetadata(record, false)
                evaluateRecordReadiness(record)
            elseif st == "Buying" then
                if os.clock() - record.lastBuyAttempt > BUY_CONFIRM_TIMEOUT then
                    if record.model:IsDescendantOf(workspace) then
                        if record.buyAttempts >= MAX_BUY_ATTEMPTS then
                            transitionState(record, "WaitingForPurchaseWindow",
                                "maximum attempts reached")
                            record.retryNotBefore = os.clock() + RETRY_BACKOFF
                            record.buyAttempts = 0
                            record.remoteSent = false
                            record.remoteFailed = false
                            record.fallbackUsed = false
                        else
                            transitionState(record, "WaitingForPurchaseWindow",
                                "buy confirmation timeout")
                            record.retryNotBefore = os.clock() + BUY_RETRY_DELAY
                        end
                        if Config.AutoBuyMatching and not boxHandlingActive and record.filterPassed then
                            queuePurchase(record)
                        end
                    else
                        cleanupRecord(record)
                    end
                end
            end
        end
    end
end)

-- Re-arm the purchase path when the user enables the toggle after startup.
-- Packs may already exist by the time the UI is switched on, so refresh the
-- currently bound local container rather than relying only on ChildAdded.
reevaluateAutoBuy = function(enabled)
    if not enabled then return end
    task.spawn(function()
        rebindConveyorContainerInner()
        for _, record in pairs(ConveyorRecords) do
            if record.model:IsDescendantOf(workspace)
                and record.state ~= "Removed" then
                refreshRecordMetadata(record, true)
                evaluateRecordReadiness(record)
            end
        end
    end)
end

-- Auto Stop uses this as a coordination gate. A matching pack only pauses
-- spawning once the buyer has actually queued it or fired an attempt.
-- Merely waiting for metadata, price, or a purchase prompt must not stall
-- the fast spawn loop.
autoBuyHasPending = function()
    if not Config.AutoBuyMatching then return false end
    for _, record in pairs(ConveyorRecords) do
        if record.state == "Queued" or record.state == "Buying" then
            -- Only block if the pack is still physically on the conveyor.
            -- If ChildRemoved somehow missed it the scheduler will clean it up;
            -- don't let a ghost record freeze spawning forever.
            if record.model and record.model:IsDescendantOf(workspace) then
                return true
            end
        end
    end
    return false
end

-- ── Compatibility shims assigned to outer upvalues ────────────────────

getConveyorPacks = function()
    local packs = {}
    for model, record in pairs(ConveyorRecords) do
        if model:IsDescendantOf(workspace) then
            table.insert(packs, record)
        else
            cleanupRecord(record)
        end
    end
    return packs
end

getPackKey = function(record)
    -- ItemId can be reused for multiple packs of the same item. The live
    -- Instance is the reliable identity for detecting a newly spawned model.
    return record.model
end

indexPackIds = function(packs)
    local ids = {}
    for _, record in ipairs(packs) do
        ids[getPackKey(record)] = true
    end
    return ids
end

-- ── Deferred startup ──────────────────────────────────────────────────
task.spawn(rebindConveyorContainerInner)

end -- ════ END CONVEYOR INTERNALS ════

-- ── Loops ─────────────────────────────────────────────────────────────

-- Anti-AFK
task.spawn(function()
    while true do
        task.wait(55)
        if Config.AntiAfk then
            VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(0.1)
            VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        end
    end
end)

-- Guard preventing multiple concurrent coroutines from firing stop/resume
local autoStopHandled = false
local autoStopWatcherActive = false

-- Auto Spawn Pack
task.spawn(function()
    while true do
        task.wait(math.max(0.05, Config.SpawnDelay))
        if not Config.AutoSpawnPack then continue end
        if boxHandlingActive then continue end
        if not Config.AutoStopSpawn then
            -- Auto Stop may have been disabled after a previous match.
            -- Never let its old latch block normal spawning.
            autoStopHandled = false
        end
        if autoStopHandled then continue end
        -- Prefer the server-assigned plot before touching any ButtonPart.
        -- This prevents the default plot #1 from being clicked during the
        -- short window before PlotNumber finishes replicating.
        local detected = autoDetectMyPlotNumber()
        if detected and detected ~= Config.PlotNumber then
            setPlotNumber(detected)
        end

        local previousIds
        if Config.AutoStopSpawn and not autoStopWatcherActive then
            previousIds = indexPackIds(getConveyorPacks())
        end

        local spawnBtn, _ = getPlotButtons(Config.PlotNumber)
        if not spawnBtn then
            local detected = autoDetectMyPlotNumber()
            if detected and detected ~= Config.PlotNumber then
                warn("[ACF] Spawn: plot " .. Config.PlotNumber
                    .. " has no spawn button; auto-detected plot " .. detected)
                setPlotNumber(detected)
                spawnBtn, _ = getPlotButtons(Config.PlotNumber)
            end
            if not spawnBtn then
                warnOnce("Spawn:no-button",
                    "Spawn button was not found for plot " ..
                    tostring(Config.PlotNumber) ..
                    ". Use 'Detect My Plot' or set the plot number manually.")
                continue
            end
        end
        if not fireButton(spawnBtn) then
            warnOnce("Spawn:no-interaction",
                "Spawn button was found, but no working ClickDetector or "
                    .. "ProximityPrompt interaction was available.")
            continue
        end

        -- Start one rolling watcher instead of pausing the spawn loop or
        -- starting a separate 5-second coroutine for every spawned pack.
        -- The watcher keeps a small pending set and checks all new records
        -- while Auto Spawn continues at the configured rate.
        if Config.AutoStopSpawn then
            autoStopSearchActive = true
            if not autoStopWatcherActive then
                autoStopWatcherActive = true
                task.spawn(function()
                    local seenIds = previousIds or indexPackIds(getConveyorPacks())
                    local pendingRecords = {}
                    local pendingLifetime = 1.5

                    local function checkRecord(record)
                        if not record or not record.model
                            or not record.model:IsDescendantOf(workspace) then
                            return nil
                        end

                        local recordInfo = record.info or {}
                        local liveInfo = nil
                        local packName = recordInfo.pack or record.packName
                        local rarity = recordInfo.rarity or record.rarity
                        local mutation = recordInfo.mutation or record.mutation

                        -- The scheduler normally supplies these values. Only
                        -- scan the live hierarchy when one is still missing,
                        -- which keeps this watcher cheap with rapid spawning.
                        if not packName or not rarity or not mutation then
                            liveInfo = getBoxInfo(record.model)
                            packName = packName or (liveInfo and liveInfo.pack)
                            rarity = rarity or getPackRarity(record.model)
                            mutation = mutation or getPackMutation(record.model)
                        end

                        local packCandidates = {
                            packName,
                            liveInfo and liveInfo.pack,
                            record.packName,
                            record.model.Name,
                        }
                        for _, candidatePack in ipairs(packCandidates) do
                            if candidatePack and passesFilter({
                                pack = candidatePack,
                                rarity = rarity,
                                mutation = mutation,
                            }) then
                                return {
                                    pack = candidatePack,
                                    rarity = rarity,
                                    mutation = mutation,
                                }
                            end
                        end
                        return nil
                    end

                    while Config.AutoStopSpawn and Config.AutoSpawnPack
                        and not autoStopHandled do
                        local now = os.clock()
                        for _, record in ipairs(getConveyorPacks()) do
                            local key = getPackKey(record)
                            if not seenIds[key] then
                                seenIds[key] = true
                                pendingRecords[record] = now
                            end
                        end

                        local matchedRecord, matchedInfo
                        for record, firstSeen in pairs(pendingRecords) do
                            if not record.model:IsDescendantOf(workspace) then
                                pendingRecords[record] = nil
                            else
                                local info = checkRecord(record)
                                if info then
                                    matchedRecord = record
                                    matchedInfo = info
                                    break
                                elseif now - firstSeen >= pendingLifetime then
                                    -- It had enough time for the scheduler and
                                    -- replication to populate its metadata.
                                    pendingRecords[record] = nil
                                end
                            end
                        end

                        if matchedRecord then
                            if autoStopHandled then break end
                            autoStopHandled = true
                            autoStopSearchActive = false

                            -- Preserve the confirmed match for Auto Buy and
                            -- Auto Continue even if the scheduler had briefly
                            -- marked it FilterRejected during replication.
                            matchedRecord.info = matchedInfo
                            matchedRecord.packName = matchedInfo.pack
                            matchedRecord.rarity = matchedInfo.rarity
                            matchedRecord.mutation = matchedInfo.mutation
                            matchedRecord.filterPassed = true

                            Config.AutoSpawnPack = false
                            if Controls.AutoSpawnPack and Controls.AutoSpawnPack.Set then
                                pcall(function() Controls.AutoSpawnPack:Set(false) end)
                            end
                            notify("Auto Spawn Pack", "Stopped — filter match found!")

                            -- Always watch a match when Auto Continue is on.
                            -- It may be bought, removed, or expire independently
                            -- of whether Auto Buy is enabled.
                            if Config.AutoContinueSpawn then
                                local watchedRecord = matchedRecord
                                task.spawn(function()
                                    local deadline = os.clock() + 30
                                    while os.clock() < deadline do
                                        task.wait(0.2)
                                        local st = watchedRecord.state
                                        if st == "BoughtAndRemove" or st == "Removed"
                                            or not watchedRecord.model:IsDescendantOf(workspace) then
                                            if Config.AutoContinueSpawn then
                                                Config.AutoSpawnPack = true
                                                if Controls.AutoSpawnPack and Controls.AutoSpawnPack.Set then
                                                    pcall(function() Controls.AutoSpawnPack:Set(true) end)
                                                end
                                                notify("Spawn Manager", "Resumed — pack purchased or removed!")
                                            end
                                            autoStopHandled = false
                                            autoStopWatcherActive = false
                                            return
                                        elseif st == "FilterRejected"
                                            and watchedRecord.filterPassed ~= true then
                                            autoStopHandled = false
                                            autoStopWatcherActive = false
                                            return
                                        end
                                    end
                                    warn("[ACF] Auto Continue: 30 s timeout waiting for pack outcome — resuming spawn.")
                                    if Config.AutoContinueSpawn then
                                        Config.AutoSpawnPack = true
                                        if Controls.AutoSpawnPack and Controls.AutoSpawnPack.Set then
                                            pcall(function() Controls.AutoSpawnPack:Set(true) end)
                                        end
                                        notify("Spawn Manager", "Resumed — timeout waiting for pack.")
                                    end
                                    autoStopHandled = false
                                    autoStopWatcherActive = false
                                end)
                            else
                                autoStopWatcherActive = false
                            end
                            break
                        end
                        task.wait(0.15)
                    end

                    if not autoStopHandled then
                        autoStopSearchActive = false
                        autoStopWatcherActive = false
                    end
                end)
            end
        elseif not autoStopWatcherActive then
            autoStopSearchActive = false
        end
    end
end)

-- Auto Buy Matching is handled entirely by the conveyor scheduler above.
-- queuePurchase is called from evaluateRecordReadiness when:
--   • a record transitions to WaitingForPurchaseWindow
--   • Config.AutoBuyMatching is enabled
--   • passesFilter returns true
-- The scheduler drains one queue entry at 0.2 s intervals and pauses only
-- execution while box handling is active.

-- ── Auto Carry Box helpers ───────────────────────────────────
local function findOneCarryInteractionOnPlot()
    local plot = findPlot(Config.PlotNumber)
    if not plot then
        warnOnce("CarryBox:no-plot",
            "Auto Carry Box: could not find plot " .. tostring(Config.PlotNumber))
        return nil
    end
    for _, desc in ipairs(plot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled ~= false then
            local name   = string.lower(desc.Name)
            local action = string.lower(desc.ActionText or "")
            local obj    = string.lower(desc.ObjectText or "")
            if name == "carry"
                or action == "carry"
                or obj    == "carry"
                or string.find(name,   "carry", 1, true)
                or (string.find(name, "box", 1, true)
                    and (string.find(action, "pick", 1, true)
                        or string.find(action, "take", 1, true)
                        or string.find(action, "carry", 1, true)))
                or string.find(action, "carry", 1, true) then
                return desc
            end
        end
        if desc:IsA("ClickDetector") then
            local parentName = string.lower(desc.Parent and desc.Parent.Name or "")
            if string.find(parentName, "carry", 1, true)
                or string.find(parentName, "box", 1, true) then
                return desc
            end
        end
    end
    return nil
end

local findOneCarryPromptOnPlot = findOneCarryInteractionOnPlot

local function findOneBoxToolInCharacter()
    local char = player.Character
    if not char then return nil end
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            local handle = item:FindFirstChild("Handle")
            if handle and handle:FindFirstChild("Box") then
                return item
            end
        end
    end
    return nil
end

local function isBoxTool(item)
    if not item or not item:IsA("Tool") then return false end
    local handle = item:FindFirstChild("Handle")
    if handle and handle:FindFirstChild("Box") then return true end
    local name = string.lower(item.Name)
    return string.find(name, "box", 1, true) ~= nil
        and not string.find(name, "pack", 1, true)
end

local sellBoxPartCache = nil
local function findSellBoxPart()
    if sellBoxPartCache and sellBoxPartCache:IsDescendantOf(workspace) then
        return sellBoxPartCache
    end
    sellBoxPartCache = nil

    local function searchIn(descendants)
        for _, descendant in ipairs(descendants) do
            if descendant:IsA("ProximityPrompt") then
                local action = string.lower(descendant.ActionText or "")
                local obj    = string.lower(descendant.ObjectText or "")
                local name   = string.lower(descendant.Name)
                if string.find(action, "sell", 1, true)
                    or string.find(obj,    "sell", 1, true)
                    or string.find(name,   "sell", 1, true) then
                    return descendant
                end
            end
            if descendant:IsA("BasePart") or descendant:IsA("Model") then
                local name = string.lower(descendant.Name)
                if string.find(name, "sell", 1, true)
                    and string.find(name, "box", 1, true) then
                    return descendant
                end
            end
        end
        return nil
    end

    local plot = findPlot(Config.PlotNumber)
    if plot then
        local found = searchIn(plot:GetDescendants())
        if found then
            sellBoxPartCache = found
            return found
        end
    end

    local found = searchIn(workspace:GetDescendants())
    if found then
        sellBoxPartCache = found
    end
    return sellBoxPartCache
end

-- ── Teleport helpers ─────────────────────────────────────────
local function getCFrameOf(object)
    if not object then return nil end
    if object:IsA("BasePart") then return object.CFrame end
    if object:IsA("Model") then
        local primary = object.PrimaryPart
        if primary then return primary.CFrame end
        for _, child in ipairs(object:GetChildren()) do
            if child:IsA("BasePart") then return child.CFrame end
        end
    end
    return nil
end

local function teleportNear(cframe)
    if not cframe then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local offset = Vector3.new(0, 0, 3)
    pcall(function()
        root.CFrame = cframe * CFrame.new(offset)
    end)
end

local function doSellAtStation()
    local station = findSellBoxPart()
    if not station then
        warnOnce("SellBox:no-station", "Sell station not found on your plot.")
        return false
    end

    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    teleportNear(getCFrameOf(station))
    task.wait(0.35)  -- increased from 0.2 so the server registers the position

    if station:IsA("ProximityPrompt") or station:IsA("ClickDetector") then
        local target = station.Parent
        if not target then return false end
        teleportNear(getCFrameOf(target))
        task.wait(0.2)  -- increased from 0.1
        if station:IsA("ProximityPrompt") then
            return firePrompt(station)
        elseif station:IsA("ClickDetector") then
            return fireClickDetector(station)
        end
    end
    local prompt = station:FindFirstChildOfClass("ProximityPrompt")
                or station:FindFirstChild("ProximityPrompt", true)
    if prompt then return firePrompt(prompt) end
    local click = station:FindFirstChildOfClass("ClickDetector")
               or station:FindFirstChild("ClickDetector", true)
    if click then return fireClickDetector(click) end
    return fireButton(station)
end

-- Auto Carry + Auto Sell loop.
task.spawn(function()
    while true do
        task.wait(math.max(1, Config.AutoSellDelay))
        if not Config.AutoCarryBox and not Config.AutoSellBox then continue end
        if boxHandlingActive then continue end

        boxHandlingActive = true
        local savedCFrame
        local passOk, passError = xpcall(function()
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not root then return end

            savedCFrame = root.CFrame

            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if not humanoid then return end

            local function getBackpackBoxes()
                local boxes = {}
                local backpack = player:FindFirstChild("Backpack")
                if backpack then
                    for _, item in ipairs(backpack:GetChildren()) do
                        if isBoxTool(item) then table.insert(boxes, item) end
                    end
                end
                return boxes
            end

            local function getCharacterBox()
                return isBoxTool(char:FindFirstChildOfClass("Tool"))
                    and char:FindFirstChildOfClass("Tool") or nil
            end

            local function equipAndSell(boxTool)
                pcall(function() humanoid:EquipTool(boxTool) end)
                task.wait(0.3)
                if Config.AutoSellBox then
                    doSellAtStation()
                    task.wait(0.3)
                end
                pcall(function() humanoid:UnequipTools() end)
                task.wait(0.1)
            end

            local charBox = getCharacterBox()
            if charBox then
                if Config.AutoSellBox then
                    doSellAtStation()
                    task.wait(0.3)
                end
                pcall(function() humanoid:UnequipTools() end)
                task.wait(0.1)
            end

            local existingBoxes = getBackpackBoxes()
            if #existingBoxes > 0 then
                local boxTool = existingBoxes[1]
                if boxTool and boxTool.Parent then
                    equipAndSell(boxTool)
                end
            elseif Config.AutoCarryBox then
                local carryInteraction = findOneCarryInteractionOnPlot()
                if carryInteraction then
                    local interactParent = carryInteraction.Parent
                    if interactParent then
                        teleportNear(getCFrameOf(interactParent))
                    end
                    task.wait(0.35)  -- let the server register the new position before interacting

                    if carryInteraction:IsA("ProximityPrompt") then
                        firePrompt(carryInteraction)
                    elseif carryInteraction:IsA("ClickDetector") then
                        fireClickDetector(carryInteraction)
                    end
                    task.wait(0.5)  -- increased from 0.4 to give the server time to give us the box

                    local acquired = getCharacterBox()
                    if acquired then
                        if Config.AutoSellBox then
                            doSellAtStation()
                            task.wait(0.3)
                        end
                        pcall(function() humanoid:UnequipTools() end)
                        task.wait(0.1)
                    else
                        local newBoxes = getBackpackBoxes()
                        if #newBoxes > 0 then
                            local b = newBoxes[1]
                            if b and b.Parent then equipAndSell(b) end
                        end
                    end
                end
            end

        end, function(errorValue)
            return tostring(errorValue)
        end)

        local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if r and savedCFrame then
            pcall(function() r.CFrame = savedCFrame end)
        end
        if not passOk then
            warn("[ACF] Auto Carry/Sell pass failed: " .. tostring(passError))
        end
        boxHandlingActive = false
    end
end)

-- ── Card Slot helpers ────────────────────────────────────────
local findSlotButton
local slotIsOccupied
local findCardSlot
local getCardSlotIndex

-- Auto Upgrade
task.spawn(function()
    while true do
        local delay = math.max(0.05, Config.UpgradeDelay)
        task.wait(delay)
        if not Config.AutoUpgrade then continue end

        local plot = findPlot(Config.PlotNumber)
        if not plot then continue end

        for slotIndex = 1, 30 do
            local slot = findCardSlot(plot, slotIndex)
            if not slot then continue end
            if not slotIsOccupied(slot) then continue end

            local level = slot:FindFirstChild("CardLevel", true)
            if level and level:IsA("ValueBase")
                and tonumber(level.Value) >= MAX_CARD_LEVEL then
                continue
            end

            fireRemote("CardSlotRE", "UpgradeCard", {
                SlotIndex = slotIndex,
            })
            task.wait(delay)
        end
    end
end)

-- Auto Potions
-- Uses ItemsRE.OnClientEvent (same events the game's ItemsClient listens to)
-- for reliable inventory counts and active boost tracking. The replacement
-- confirmation is handled through the live Items UI when a higher tier is used.
do
    local ItemsRE = Remotes:WaitForChild("ItemsRE", 15)
    if ItemsRE then
        -- potionCounts[itemId] = number owned
        -- activeBoosts[family] = tier/expiry while that boost is running
        -- Keep this inventory mirror available to the pack automation below.
        local potionCounts = potionInventoryCounts
        local itemCounts = artifactState.InventoryCounts
        -- activeBoosts is indexed by potion family (luck/cash/etc.), not by
        -- the raw stat key.  That lets CashPotion I/II/III share one timer.
        local activeBoosts = {}
        local confirmationBusy = false
        local pendingPotion = nil
        local nextInventorySync = 0

        -- When a stronger potion replaces a weaker active potion, the game
        -- opens Items.Confirmation instead of completing UseItem immediately.
        -- Only accept the specific replacement warning; do not touch unrelated
        -- confirmation dialogs elsewhere in the game.
        local function guiObjectIsVisible(object)
            if not object then return false end
            local current = object
            while current do
                if current:IsA("GuiObject") and not current.Visible then
                    return false
                end
                if current:IsA("ScreenGui") and not current.Enabled then
                    return false
                end
                current = current.Parent
            end
            return true
        end

        local function findPotionConfirmation()
            local confirmation = playerGui:FindFirstChild("Confirmation", true)
            if not confirmation or not guiObjectIsVisible(confirmation) then
                return nil
            end

            local message = confirmation:FindFirstChild("FrameMessage", true)
            local messageText = ""
            if message then
                if message:IsA("TextLabel") or message:IsA("TextButton") then
                    messageText = tostring(message.Text or "")
                else
                    for _, descendant in ipairs(message:GetDescendants()) do
                        if descendant:IsA("TextLabel")
                            or descendant:IsA("TextButton") then
                            messageText = tostring(descendant.Text or "")
                            if messageText ~= "" then break end
                        end
                    end
                end
            end

            local normalized = string.lower(messageText)
            local isReplacementWarning =
                string.find(normalized, "already have", 1, true) ~= nil
                and string.find(normalized, "active", 1, true) ~= nil
                and (
                    string.find(normalized, "remove", 1, true) ~= nil
                    or string.find(normalized, "remaining time", 1, true) ~= nil
                )
            if not isReplacementWarning then return nil end

            local yes = confirmation:FindFirstChild("YES", true)
            if not yes or not yes:IsA("GuiButton")
                or not guiObjectIsVisible(yes) then
                return nil
            end
            return yes
        end

        local function acceptPotionReplacementConfirmation()
            if confirmationBusy then return false end
            local yes = findPotionConfirmation()
            if not yes then return false end

            confirmationBusy = true
            local clicked = false
            if firesignal then
                clicked = pcall(firesignal, yes.MouseButton1Click)
            end
            if not clicked then
                clicked = pcall(function() yes:Activate() end)
            end
            if clicked then
                task.wait(0.2)
            end
            confirmationBusy = false
            return clicked
        end

        -- ItemsClient only creates the replacement warning from the live
        -- inventory popup's USE button.  Calling ItemsRE directly can use an
        -- expired potion, but it cannot create that local confirmation.
        local function findItemsFrame()
            local direct = playerGui:FindFirstChild("ItemsFrame", true)
            if direct then return direct end
            for _, descendant in ipairs(playerGui:GetDescendants()) do
                if descendant.Name == "ItemsFrame" then
                    return descendant
                end
            end
            return nil
        end

        local function usePotionThroughItemsUi(itemId)
            local itemsFrame = findItemsFrame()
            if not itemsFrame then return false end

            local objectFrame = itemsFrame:FindFirstChild(
                "ObjectFrame_" .. tostring(itemId),
                true
            )
            if not objectFrame then
                return false
            end

            local objectButton = objectFrame:FindFirstChild("ObjectButton", true)
            if not objectButton or not clickGuiButton(objectButton) then
                return false
            end

            local popup
            for _ = 1, 10 do
                task.wait(0.05)
                popup = itemsFrame:FindFirstChild(
                    "Info_" .. tostring(itemId),
                    true
                )
                if popup then break end
            end
            if not popup then return false end

            local useButton = popup:FindFirstChild("USE", true)
            if not useButton or not clickGuiButton(useButton) then
                return false
            end
            return true
        end

        local function potionDetails(itemId)
            local name = string.lower(tostring(itemId or ""))
            local family
            if string.find(name, "luckpotion", 1, true)
                or string.find(name, "luck potion", 1, true) then
                family = "luck"
            elseif string.find(name, "cashpotion", 1, true)
                or string.find(name, "cash potion", 1, true) then
                family = "cash"
            elseif string.find(name, "timepotion", 1, true)
                or string.find(name, "time potion", 1, true) then
                family = "time"
            elseif string.find(name, "mutationpotion", 1, true)
                or string.find(name, "mutation potion", 1, true) then
                family = "mutation"
            elseif string.find(name, "productionpotion", 1, true)
                or string.find(name, "production potion", 1, true) then
                family = "production"
            end
            if not family then return nil, nil end

            local tier = tonumber(string.match(name, "(%d+)$"))
            if not tier then
                local roman = string.match(name, "(iii)$")
                if roman then
                    tier = 3
                else
                    roman = string.match(name, "(ii)$")
                    if roman then
                        tier = 2
                    elseif string.match(name, "([^iv]|^)i$") then
                        tier = 1
                    end
                end
            end
            return family, tier
        end

        local function tierFromValue(value)
            if type(value) == "number" then
                return value >= 1 and math.floor(value) or nil
            end
            if type(value) ~= "string" then return nil end
            local text = string.lower(value)
            local numeric = tonumber(string.match(text, "potion%s*(%d+)$"))
                or tonumber(string.match(text, "[^%d](%d+)$"))
            if numeric then return numeric end
            local roman = string.match(text, "(iii)$")
            if roman then return 3 end
            roman = string.match(text, "(ii)$")
            if roman then return 2 end
            if string.match(text, "([^iv]|^)i$") then return 1 end
            return nil
        end

        local function boostDetails(stat, info)
            local statText = string.lower(tostring(stat or ""))
            local family
            if string.find(statText, "luck", 1, true) then
                family = "luck"
            elseif string.find(statText, "cash", 1, true) then
                family = "cash"
            elseif string.find(statText, "time", 1, true) then
                family = "time"
            elseif string.find(statText, "mutation", 1, true) then
                family = "mutation"
            elseif string.find(statText, "production", 1, true) then
                family = "production"
            end

            local tier
            if type(info) == "table" then
                for _, key in ipairs({
                    "Tier", "Level", "PotionTier", "PotionLevel",
                    "ItemId", "PotionId", "Name", "Id",
                }) do
                    tier = tierFromValue(info[key])
                    if tier then break end
                end
            end
            tier = tier or tierFromValue(stat)
            return family, tier
        end

        local function applyBoosts(boostTable)
            activeBoosts = {}
            if type(boostTable) ~= "table" then return end
            for stat, info in pairs(boostTable) do
                local remaining = type(info) == "table"
                    and (tonumber(info.Remaining) or 0)
                    or 0
                if remaining > 0 then
                    local family, tier = boostDetails(stat, info)
                    if family then
                        activeBoosts[family] = {
                            tier = tier,
                            expiresAt = os.clock() + remaining,
                        }
                    end
                end
            end
        end

        local function canUsePotion(itemId)
            local family, tier = potionDetails(itemId)
            if not family then return false end

            local active = activeBoosts[family]
            if not active then
                return true
            end

            local remaining = (active.expiresAt or 0) - os.clock()
            if remaining <= 0 then
                activeBoosts[family] = nil
                return true
            end

            -- A running potion in the same category blocks an equal or
            -- weaker potion.  A higher tier is allowed through so the live
            -- game's confirmation dialog can ask whether to replace it.
            if not tier or not active.tier then
                return false
            end
            return tier > active.tier
        end

        -- Mirror the same events the ItemsClient script handles. The game
        -- has used both FullInventory and InventoryUpdate for this snapshot,
        -- so Auto Use Time Potion must understand both versions.
        ItemsRE.OnClientEvent:Connect(function(action, data)
            if (action == "FullInventory" or action == "InventoryUpdate")
                and type(data) == "table" then
                if data.ItemId ~= nil then
                    potionCounts[data.ItemId] = data.Quantity
                        or data.QuantityValue or data.Amount
                        or data.Count or 0
                    itemCounts[data.ItemId] = potionCounts[data.ItemId]
                else
                    local items = data.Items or data.Inventory or data.ItemsData
                    if type(items) ~= "table" then
                        -- Some game versions send the item map directly.
                        items = data
                    end
                    if action == "FullInventory" then
                        table.clear(potionCounts)
                        table.clear(itemCounts)
                    end
                    for itemId, quantity in pairs(items) do
                        if itemId ~= "Items" and itemId ~= "Inventory"
                            and itemId ~= "ItemsData" then
                            potionCounts[itemId] = quantity
                            itemCounts[itemId] = quantity
                        end
                    end
                end
                applyBoosts(data.Boosts)
                pendingPotion = nil

            elseif action == "ItemUpdate" and type(data) == "table" then
                potionCounts[data.ItemId] = data.Quantity or data.QuantityValue
                or data.Amount or data.Count or 0
                itemCounts[data.ItemId] = potionCounts[data.ItemId]

            elseif action == "BoostUpdate" then
                applyBoosts(data)
                pendingPotion = nil
            elseif action == "UseOk" or action == "UseFailed" then
                pendingPotion = nil
            end
        end)

        -- The normal Items window sends this request when it opens.  Auto
        -- Potion must request the same snapshot even when the user never
        -- opens the inventory UI.
        pcall(function() ItemsRE:FireServer("Init") end)

        task.spawn(function()
            while true do
                task.wait(0.15)
                if Config.AutoPotion then
                    acceptPotionReplacementConfirmation()
                end
            end
        end)

        task.spawn(function()
            while true do
                task.wait(1)
                if not Config.AutoPotion then
                    pendingPotion = nil
                    continue
                end

                local now = os.clock()
                if now >= nextInventorySync then
                    pcall(function() ItemsRE:FireServer("Init") end)
                    nextInventorySync = now + 5
                end

                if pendingPotion then
                    if now - pendingPotion.startedAt < 5 then
                        continue
                    end
                    pendingPotion = nil
                end

                local selected = Config.SelectedPotions
                local candidates = {}
                for _, potion in ipairs(POTIONS) do
                    if selectionIncludes(selected, potion)
                        and (potionCounts[potion] or 0) > 0 then
                        table.insert(candidates, potion)
                    end
                end
                table.sort(candidates, function(left, right)
                    local _, leftTier = potionDetails(left)
                    local _, rightTier = potionDetails(right)
                    return (leftTier or 0) > (rightTier or 0)
                end)

                for _, potion in ipairs(candidates) do
                    if not canUsePotion(potion) then continue end
                    local family, tier = potionDetails(potion)
                    local active = family and activeBoosts[family]
                    local isTierReplacement = active
                        and tier
                        and active.tier
                        and tier > active.tier
                    pendingPotion = {
                        itemId = potion,
                        startedAt = os.clock(),
                    }
                    local submitted = false
                    if isTierReplacement then
                        submitted = usePotionThroughItemsUi(potion)
                    end
                    if not submitted then
                        submitted = pcall(function()
                            ItemsRE:FireServer(
                                "UseItem",
                                { ItemId = potion, Amount = 1 }
                            )
                        end)
                    end
                    -- Give the game's ItemsClient time to create the warning,
                    -- then accept it if this was a tier replacement.
                    if submitted then
                        for _ = 1, 12 do
                            task.wait(0.1)
                            if acceptPotionReplacementConfirmation() then
                                break
                            end
                        end
                    end
                    break
                end
            end
        end)
    else
        warn("[ACF] ItemsRE not found – Auto Potion disabled")
    end
end

-- Auto Claim Playtime
task.spawn(function()
    local nextStateRequest = 0
    while true do
        task.wait(0.5)
        if not Config.AutoClaimPlaytime or not PlayTimeRewardRE then continue end
        local now = os.clock()
        if not playtimeStateReceived or now >= nextStateRequest then
            pcall(function() PlayTimeRewardRE:FireServer("RequestState") end)
            nextStateRequest = now + 10
        end
        for rewardIndex = 1, 12 do
            if playtimeReadyRewards[rewardIndex] then
                playtimeReadyRewards[rewardIndex] = nil
                pcall(function()
                    PlayTimeRewardRE:FireServer("ClaimReward", {
                        RewardIndex = rewardIndex,
                    })
                end)
                break
            end
        end
    end
end)

-- Daily rewards
task.spawn(function()
    if DailyRewardRE then
        pcall(function() DailyRewardRE:FireServer("RequestState") end)
    end
    while true do
        task.wait(5)
        if Config.AutoClaimDaily and DailyRewardRE then
            pcall(function() DailyRewardRE:FireServer("Claim") end)
        end
    end
end)

-- Auto Buy Boost
task.spawn(function()
    while true do
        task.wait(3)
        if UpgradesRE and Config.AutoBuyBoost then
            for _, boost in ipairs(BOOSTS) do
                local chosen = false
                chosen = selectionIncludes(Config.SelectedBoosts, boost.label)
                if chosen then
                    pcall(function()
                        UpgradesRE:FireServer("BuyCash", { Id = boost.id })
                    end)
                    task.wait(0.2)
                end
            end
        end
    end
end)

-- ── Artifact and Boss Card automation ─────────────────────────
-- Each action is gated by the live upgrade cost and the matching shard
-- balance. The loops intentionally stop quietly when the relevant UI/data has
-- not replicated yet; the next pass will try again.
task.spawn(function()
    while true do
        task.wait(1)

        if os.clock() - artifactState.LastArtifactRefreshAt >= 2 then
            artifactState.LastArtifactRefreshAt = os.clock()
            pcall(artifactState.refreshArtifactOptions)
        end

        if Config.AutoUpgradeArtifact then
            pcall(artifactState.upgradeArtifacts)
        end

        if Config.AutoEquipArtifact then
            pcall(artifactState.equipArtifacts)
        end

        if Config.AutoSellArtifacts then
            pcall(artifactState.sellMatchingArtifacts)
        end

        if Config.AutoEquipBossCard then
            pcall(artifactState.equipBossCard)
        end

        if Config.AutoUpgradeBossCard then
            pcall(artifactState.upgradeBossCard)
        end
    end
end)

-- ── Card Slot helper implementations ────────────────────────
findCardSlot = function(plot, slotIndex)
    if not plot or not slotIndex then return nil end
    local name = "CardSlot" .. tostring(slotIndex)
    local container = plot
    if slotIndex >= 11 and slotIndex <= 20 then
        container = plot:FindFirstChild("TOP")
    elseif slotIndex >= 21 and slotIndex <= 30 then
        container = plot:FindFirstChild("TOP2")
    end
    local slot = container and container:FindFirstChild(name)
    if slot then return slot end
    return plot:FindFirstChild(name, true)
end

getCardSlotIndex = function(slot)
    if not slot then return nil end
    local upgradePart = slot:FindFirstChild("UpgradePart")
    local attributeIndex = upgradePart and tonumber(
        upgradePart:GetAttribute("SlotIndex")
    )
    if attributeIndex then return attributeIndex end
    return tonumber(string.match(slot.Name, "CardSlot(%d+)"))
end

local function getAllCardSlots()
    local plot = findPlot(Config.PlotNumber)
    if not plot then return {} end
    local slots = {}
    for i = 1, 30 do
        local slot = findCardSlot(plot, i)
        if slot then table.insert(slots, slot) end
    end
    return slots
end

local function getAvailableCardSlots()
    local available = {}
    for _, slot in ipairs(getAllCardSlots()) do
        if not slotIsOccupied(slot) then
            table.insert(available, slot)
        end
    end
    return available
end

local function areAllCardSlotsOccupied()
    -- Auto Use Time Potion must work by itself, so do not rely on Auto Spawn
    -- having performed plot detection first.
    local detectedPlot = autoDetectMyPlotNumber()
    if detectedPlot and detectedPlot ~= Config.PlotNumber then
        setPlotNumber(detectedPlot)
    end

    local slots = getAllCardSlots()
    -- The feature is specifically for a full 30-slot plot. If a slot model
    -- has not replicated yet, do not treat the plot as full.
    if #slots < 30 then return false end

    -- Keep this check local to Auto Use Time Potion. Auto Place may be
    -- disabled, and the shared slotIsOccupied assignment can still be
    -- pending while the script is finishing initialization.
    local function timePotionSlotIsOccupied(slot)
        if not slot then return false, false end
        local occupied = false
        local packOnCooldown = false

        local function timerTextIsActive(text)
            local normalized = string.lower(tostring(text or ""))
            normalized = string.gsub(normalized, "%s+", "")
            if normalized == "" or normalized == "ready" then
                return false
            end
            return string.match(normalized, "^%d+:%d+:%d+$") ~= nil
                or string.match(normalized, "^%d+:%d+$") ~= nil
        end

        local function packModelHasActiveTimer(packModel)
            local timerGui = packModel:FindFirstChild(
                "BillboardGuiTimer",
                true
            )
            local timer = timerGui
                and timerGui:FindFirstChild("Timer", true)
            if not timer then return false end
            if timer:IsA("TextLabel") or timer:IsA("TextButton") then
                return timerTextIsActive(timer.Text)
            end
            if timer:IsA("StringValue") then
                return timerTextIsActive(timer.Value)
            end
            return false
        end

        -- Some game versions put the occupied state on the slot itself.
        for _, attributeName in ipairs({
            "Occupied", "IsOccupied", "HasCard", "HasPack",
            "CardName", "PackName", "ItemId",
        }) do
            local value = slot:GetAttribute(attributeName)
            if value ~= nil and value ~= false and value ~= "" then
                occupied = true
            end
        end

        -- Empty slots still contain a CardHolder with the static UI surface
        -- objects. An occupied card adds dynamic content below CardHolder
        -- (the current game commonly names the card child "1").
        local cardHolder = slot:FindFirstChild("CardHolder", true)
        if cardHolder then
            for _, child in ipairs(cardHolder:GetChildren()) do
                local childName = string.lower(child.Name)
                if childName ~= "surfaceguiback"
                    and childName ~= "surfaceguifront"
                    and (tonumber(child.Name) ~= nil
                        or child:IsA("Model")
                        or child:IsA("Tool")) then
                    occupied = true
                end
            end
        end

        for _, desc in ipairs(slot:GetDescendants()) do
            local name = string.lower(desc.Name)
            if name == "placedcard" or name == "cardname"
                or name == "cardlevel" or name == "packname" then
                occupied = true
            end

            -- Placed packs are live child Models under the slot, for example
            -- CardSlot9 > Void Pack or CardSlotN > Brown Crate. They do not
            -- necessarily expose a PackName value or attribute.
            if desc:IsA("Model") then
                local compactName = string.gsub(name, "[^%w]", "")
                local isPackModel = false
                if string.find(compactName, "pack", 1, true)
                    or string.find(compactName, "crate", 1, true) then
                    isPackModel = true
                end
                for _, knownPack in ipairs(PACKS) do
                    local compactPack = string.gsub(
                        string.lower(tostring(knownPack)),
                        "[^%w]",
                        ""
                    )
                    if compactPack ~= ""
                        and (compactName == compactPack
                            or string.find(compactName, compactPack, 1, true)
                            or string.find(compactPack, compactName, 1, true)) then
                        isPackModel = true
                    end
                end
                if isPackModel then
                    occupied = true
                    if packModelHasActiveTimer(desc) then
                        packOnCooldown = true
                    end
                end
            end

            if desc:GetAttribute("CardName") ~= nil
                or desc:GetAttribute("PackName") ~= nil
                or desc:GetAttribute("ItemId") ~= nil then
                occupied = true
            end

            -- Remove is only present for an occupied slot. Do not use
            -- UpgradePart or Open as generic occupancy signals: empty slots
            -- can contain those UI/state objects too.
            if string.find(name, "remove", 1, true) then
                occupied = true
            end

            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                local text = string.lower(tostring(desc.Text or ""))
                if string.find(text, "remove", 1, true) then
                    occupied = true
                end

            end

            if string.find(name, "remove", 1, true) ~= nil
                and (desc:IsA("ClickDetector")
                    or desc:IsA("ProximityPrompt")
                    or desc:IsA("GuiObject")) then
                occupied = true
            end
        end
        return occupied, packOnCooldown
    end

    local hasPackOnCooldown = false
    for _, slot in ipairs(slots) do
        local occupied, slotHasPackOnCooldown =
            timePotionSlotIsOccupied(slot)
        if not occupied then
            return false
        end
        hasPackOnCooldown = hasPackOnCooldown or slotHasPackOnCooldown
    end

    -- A full plot or a ready-to-open pack is not enough. At least one
    -- occupied slot must still contain a pack with an active timer.
    return hasPackOnCooldown
end

findSlotButton = function(slotModel, buttonName)
    if not slotModel then return nil end
    local lname = string.lower(buttonName)
    for _, desc in ipairs(slotModel:GetDescendants()) do
        if string.find(string.lower(desc.Name), lname, 1, true) then
            local cd = desc:FindFirstChildOfClass("ClickDetector")
                    or desc:FindFirstChildOfClass("ProximityPrompt")
            if cd then return cd end
            if desc:IsA("ClickDetector") or desc:IsA("ProximityPrompt") then
                return desc
            end
        end
        if desc:IsA("ProximityPrompt") then
            local action = string.lower(desc.ActionText or "")
            local obj    = string.lower(desc.ObjectText or "")
            if string.find(action, lname, 1, true)
                or string.find(obj, lname, 1, true) then
                return desc
            end
        end
    end
    return nil
end

local function fireSlotButton(btn)
    if not btn then return false end
    if btn:IsA("ClickDetector") then
        return fireClickDetector(btn)
    elseif btn:IsA("ProximityPrompt") then
        return firePrompt(btn)
    end
    return false
end

local function findSlotInteraction(slotModel, names)
    for _, name in ipairs(names) do
        local interaction = findSlotButton(slotModel, name)
        if interaction then return interaction end
    end
    return nil
end

-- Auto Place Pack must never use a card tool. Some card names can contain
-- words that also occur in pack names, so a loose substring check is unsafe.
-- Prefer the game's pack metadata and only fall back to an exact normalized
-- name match.
local function isKnownPackValue(value)
    local key = normalizePackName(value)
    if not key or key == "" then return false end
    for _, packName in ipairs(PACKS) do
        if key == normalizePackName(packName) then
            return true
        end
    end
    return false
end

local function isPackTool(item)
    if not item or not item:IsA("Tool") then return false end

    -- Card tools expose CardLevel/CardName in the backpack. Reject these
    -- before checking the display name so they can never be placed as packs.
    if item:FindFirstChild("CardLevel") ~= nil
        or item:GetAttribute("CardLevel") ~= nil
        or item:FindFirstChild("CardName") ~= nil
        or item:GetAttribute("CardName") ~= nil then
        return false
    end

    local packValue = readBoxValue(item, {
        "PackName", "Pack", "PackId",
    })
    if isKnownPackValue(packValue) then return true end

    return isKnownPackValue(item.Name)
end

local function slotIsOnCooldown(slotModel)
    if not slotModel then return false end
    for _, desc in ipairs(slotModel:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            if string.find(string.lower(desc.Text or ""), "skip", 1, true) then
                return true
            end
        end
    end
    return false
end

slotIsOccupied = function(slotModel)
    if findSlotButton(slotModel, "Remove") ~= nil then return true end
    for _, desc in ipairs(slotModel:GetDescendants()) do
        local name = string.lower(desc.Name)
        if name == "placedcard" or name == "cardname"
            or name == "cardlevel" or name == "packname" then
            return true
        end
        if desc:GetAttribute("CardName") ~= nil
            or desc:GetAttribute("PackName") ~= nil
            or desc:GetAttribute("ItemId") ~= nil then
            return true
        end
    end
    return false
end

local function getFilteredPacksInBackpack()
    local result = {}
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return result end
    for _, item in ipairs(backpack:GetChildren()) do
        if not isPackTool(item) then continue end
        local info = {
            pack     = item.Name,
            rarity   = readBoxValue(item, { "Rarity", "rarity" }),
            mutation = readBoxValue(item, {
                "Mutation", "MutationName", "mutation",
            }),
        }
        if passesFilter(info) then table.insert(result, item) end
    end
    return result
end

local function getAllPacksInBackpack()
    local result = {}
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return result end

    for _, item in ipairs(backpack:GetChildren()) do
        if isPackTool(item) then table.insert(result, item) end
    end
    return result
end

local function getCardCurrencyValue(item)
    local attributeNames = {
        "CurrencyValue", "Currency", "Income", "CashPerSecond",
        "Cash", "Value", "Coins", "Money",
    }
    for _, name in ipairs(attributeNames) do
        local value = tonumber(item:GetAttribute(name))
        if value then return value end
    end

    for _, descendant in ipairs(item:GetDescendants()) do
        local name = string.lower(descendant.Name)
        if descendant:IsA("ValueBase")
            and (name == "currencyvalue" or name == "currency"
                or name == "income" or name == "cashpersecond"
                or name == "cash" or name == "value" or name == "coins"
                or name == "money") then
            local value = tonumber(descendant.Value)
            if value then return value end
        end
    end

    return 0
end

local function restoreCharacterPosition(savedCFrame)
    if not savedCFrame then return end
    local root = player.Character
        and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    pcall(function()
        root.CFrame = savedCFrame
    end)
    task.wait(0.1)
    root = player.Character
        and player.Character:FindFirstChild("HumanoidRootPart")
    if root then
        pcall(function() root.CFrame = savedCFrame end)
    end
end

local function getCardInfo(item)
    local rarity = readBoxValue(item, { "Rarity", "CardRarity", "rarity" })
    local mutation = readBoxValue(item, {
        "Mutation", "MutationName", "CardMutation", "mutation",
    })

    return {
        rarity = rarity,
        mutation = mutation,
    }
end

local getSortedCardsInBackpack

local filteredSellState = {}

filteredSellState.getIndexCardName = function(value)
    if value == nil then return nil end

    local key = filterCompareKey(value)
    if not key then return nil end

    local partialMatch
    local partialLength = 0
    for _, cardName in ipairs(cardCraftState.IndexCards) do
        local cardKey = filterCompareKey(cardName)
        if cardKey then
            if cardKey == key then
                return cardName
            end
            -- Prefer the longest match so a short card name cannot win
            -- before a more specific card name in the Index.
            if #cardKey > partialLength
                and (string.find(key, cardKey, 1, true)
                    or string.find(cardKey, key, 1, true)) then
                partialMatch = cardName
                partialLength = #cardKey
            end
        end
    end
    return partialMatch
end

filteredSellState.getCardName = function(item)
    local cardValue = readBoxValue(item, {
        "CardName", "Card", "CardId", "Name",
        "cardname", "card", "cardid",
    })
    local cardName = filteredSellState.getIndexCardName(cardValue)
        or filteredSellState.getIndexCardName(item and item.Name)

    -- Keep a raw fallback for game versions that expose a card tool before
    -- the matching entry is replicated in CardsConfig.
    return cardName or (item and item.Name)
end

filteredSellState.getCardRanking = function(item)
    return readBoxValue(item, {
        "CardGrade", "Ranking", "Rank", "Grade",
    }) or (item and item:GetAttribute("CardGrade"))
end

filteredSellState.getCardTrait = function(item)
    return readBoxValue(item, {
        "CardTrait", "Trait", "TraitName", "trait",
    }) or (item and item:GetAttribute("CardTrait"))
end

filteredSellState.fieldMatches = function(value, selected)
    return filterValueMatches(value, normalizeFilterSelection(selected))
end

filteredSellState.cardMatches = function(item)
    local cardInfo = getCardInfo(item)
    local matches = (
        filteredSellState.fieldMatches(
            filteredSellState.getCardName(item),
            Config.FilteredSellCard
        )
        and filteredSellState.fieldMatches(
            cardInfo.mutation,
            Config.FilteredSellMutation
        )
        and filteredSellState.fieldMatches(
            filteredSellState.getCardRanking(item),
            Config.FilteredSellRanking
        )
        and filteredSellState.fieldMatches(
            filteredSellState.getCardTrait(item),
            Config.FilteredSellTrait
        )
    )

    if tostring(Config.FilteredSellMode) == "Blacklist" then
        return not matches
    end
    return matches
end

filteredSellState.getFilteredCards = function()
    local result = {}
    for _, entry in ipairs(getSortedCardsInBackpack()) do
        if filteredSellState.cardMatches(entry.tool) then
            table.insert(result, entry.tool)
        end
    end
    return result
end

-- The filtered action scans the backpack itself, then follows the same
-- equipped-tool path as the working "SellHand" action. The broad SellCards
-- remote is intentionally not used because it ignores these filters.
filteredSellState.sellCard = function(card)
    local backpack = player:FindFirstChild("Backpack")
    local character = player.Character
    local humanoid = character
        and character:FindFirstChildOfClass("Humanoid")
    if not card or not backpack or card.Parent ~= backpack
        or not character or not humanoid then
        return false
    end

    -- Make sure the card being processed is the active held tool.
    pcall(function() humanoid:UnequipTools() end)
    task.wait(0.1)
    pcall(function() humanoid:EquipTool(card) end)

    -- EquipTool is asynchronous in Roblox; do not fire SellHand until the
    -- server-visible parent has changed from Backpack to Character.
    for _ = 1, 15 do
        if card.Parent == character then break end
        task.wait(0.1)
    end
    if card.Parent ~= character then
        return false
    end

    -- Give the game's server a moment to register the newly held card before
    -- using the same SellHand request as the manual button.
    task.wait(0.15)
    local sold = fireRemote("SellRE", "SellHand")
    task.wait(0.15)
    pcall(function() humanoid:UnequipTools() end)
    return sold
end

getSortedCardsInBackpack = function()
    local result = {}
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return result end
    for _, item in ipairs(backpack:GetChildren()) do
        if not item:IsA("Tool") then continue end
        local handle = item:FindFirstChild("Handle")
        if handle and handle:FindFirstChild("Box") then continue end
        local lname = string.lower(item.Name)
        local isPack = false
        for _, packName in ipairs(PACKS) do
            if string.find(lname, string.lower(packName), 1, true) then
                isPack = true ; break
            end
        end
        if isPack then continue end
        if not item:FindFirstChild("CardLevel")
            and item:GetAttribute("CardLevel") == nil then
            continue
        end
        local info = getCardInfo(item)
        table.insert(result, {
            tool = item,
            rarityRank = RARITY_RANK[normalizeFilterValue(info.rarity)] or 0,
            mutationRank = MUTATION_RANK[normalizeFilterValue(info.mutation)] or 0,
            currencyValue = getCardCurrencyValue(item),
            level = tonumber(item:GetAttribute("CardLevel"))
                or tonumber(item:FindFirstChild("CardLevel")
                    and item.CardLevel.Value) or 0,
        })
    end
    table.sort(result, function(a, b)
        if a.mutationRank ~= b.mutationRank then
            return a.mutationRank > b.mutationRank
        end
        if a.rarityRank ~= b.rarityRank then
            return a.rarityRank > b.rarityRank
        end
        if a.level ~= b.level then
            return a.level > b.level
        end
        return a.currencyValue > b.currencyValue
    end)
    return result
end

-- ── Card Ranking reroll ──────────────────────────────────────
-- GradeRollClient uses card Tools directly and sends:
-- GradeRollRE:FireServer("RollGrade", { Tool = tool, Currency = "gems"|"cash" })
local rankCardDropdown
local rankCardOptionMap = {}
local rankCardOptionsSignature = ""
local rankCardOptions = { "All" }
local rankCardRefreshQueued = false
local rankRollPending = false
local rankRollPendingTool
local rankRollResponse

local function getRankCardsInBackpack()
    local result = {}
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return result end

    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") and item:GetAttribute("CardName") ~= nil then
            table.insert(result, item)
        end
    end

    table.sort(result, function(a, b)
        local aName = tostring(a:GetAttribute("CardName") or a.Name)
        local bName = tostring(b:GetAttribute("CardName") or b.Name)
        if aName ~= bName then return aName < bName end
        return a.Name < b.Name
    end)
    return result
end

local function buildRankCardOptions()
    local options = { "All" }
    local map = {}
    local seen = {}

    for _, tool in ipairs(getRankCardsInBackpack()) do
        local baseName = tostring(tool:GetAttribute("CardName") or tool.Name)
        seen[baseName] = (seen[baseName] or 0) + 1
        local label = baseName
        if seen[baseName] > 1 then
            label = baseName .. " #" .. tostring(seen[baseName])
        end
        table.insert(options, label)
        map[label] = tool
    end

    return options, map
end

local function selectedRankCardTools()
    local cards = getRankCardsInBackpack()
    local selected = Config.SelectedRankCards
    if type(selected) ~= "table" or #selected == 0 then
        return cards
    end

    for _, value in ipairs(selected) do
        if tostring(value) == "All" then return cards end
    end

    local byTool = {}
    for _, value in ipairs(selected) do
        local tool = rankCardOptionMap[tostring(value)]
        if tool and tool.Parent == player:FindFirstChild("Backpack") then
            byTool[tool] = true
        end
    end

    local result = {}
    for _, tool in ipairs(cards) do
        if byTool[tool] then table.insert(result, tool) end
    end
    return result
end

local function refreshRankCardDropdown()
    if not rankCardDropdown then return end
    local options, map = buildRankCardOptions()
    rankCardOptionMap = map
    rankCardOptions = options
    local signature = table.concat(options, "\0")
    if signature == rankCardOptionsSignature then return end
    rankCardOptionsSignature = signature

    local selected = Config.SelectedRankCards or { "All" }
    local refreshed = pcall(function()
        rankCardDropdown:Refresh(options, selected)
    end)
    if not refreshed then
        pcall(function() rankCardDropdown:Set(options) end)
    end
end

local function queueRankCardDropdownRefresh()
    if rankCardRefreshQueued then return end
    rankCardRefreshQueued = true
    task.delay(0.2, function()
        rankCardRefreshQueued = false
        refreshRankCardDropdown()
    end)
end

local function getRankTargetOptions()
    local result = {}
    if RankGradeRollConfig
        and type(RankGradeRollConfig.GetGrades) == "function" then
        local ok, grades = pcall(RankGradeRollConfig.GetGrades)
        if ok and type(grades) == "table" then
            for _, entry in ipairs(grades) do
                local grade = type(entry) == "table" and entry.Grade or entry
                if grade ~= nil and tostring(grade) ~= "" then
                    table.insert(result, tostring(grade))
                end
            end
        end
    end

    if #result == 0 then
        result = { "C", "B", "A", "S", "SS", "SR", "UR", "LR" }
    end
    return result
end

local function getRankTarget()
    local targets = Config.TargetRank
    -- Migrate legacy string value to table on the fly.
    if type(targets) == "string" then
        targets = targets ~= "" and { targets } or {}
    end
    if type(targets) ~= "table" or #targets == 0 then return nil end
    return targets
end

local function getRankCashCost(tool)
    if not tool then return 0 end
    local cardName = tool:GetAttribute("CardName")
    local level = tonumber(tool:GetAttribute("CardLevel"))
        or tonumber(tool:FindFirstChild("CardLevel")
            and tool.CardLevel.Value) or 1
    local mutation = tostring(tool:GetAttribute("CardMutation") or "Normal")

    if RankGradeRollConfig
        and type(RankGradeRollConfig.GetRollCost) == "function" then
        local ok, cost = pcall(
            RankGradeRollConfig.GetRollCost,
            cardName,
            level,
            mutation
        )
        if ok and tonumber(cost) then return tonumber(cost) end
    end
    return 0
end

local function getRankGemsCost()
    return GradeRollRE and tonumber(GradeRollRE:GetAttribute("CostGemsPerRoll"))
        or 1
end

local function chooseRankCurrency(tool)
    local gemsEnabled = Config.RankUseGems == true
    local cashEnabled = Config.RankUseCash == true
    local gemCost = getRankGemsCost()
    local gems = getPlayerGems()

    -- When both are enabled, gems are always preferred. Cash becomes
    -- eligible only after the gem balance reaches zero, as requested.
    if gemsEnabled and gems >= gemCost then
        return "gems"
    end

    if cashEnabled and (not gemsEnabled or gems <= 0) then
        local cash = getPlayerCash() or 0
        local cashCost = getRankCashCost(tool)
        if cashCost <= 0 or cash >= cashCost then
            return "cash"
        end
    end
    return nil
end

local function rankCardHasTarget(tool)
    if not tool then return false end
    local targets = getRankTarget()
    if not targets then return false end
    local grade = tostring(tool:GetAttribute("CardGrade") or "")
    for _, t in ipairs(targets) do
        if grade == tostring(t) then return true end
    end
    return false
end

local function stopRankReroll(message)
    Config.AutoRankRoll = false
    if Controls.AutoRankRoll and Controls.AutoRankRoll.Set then
        pcall(function() Controls.AutoRankRoll:Set(false) end)
    end
    if message then notify("Card Ranking", message) end
end

if GradeRollRE then
    GradeRollRE.OnClientEvent:Connect(function(action, data)
        if not rankRollPending or type(data) ~= "table" then return end
        if data.Tool and data.Tool ~= rankRollPendingTool then return end
        if action == "RollResult" or action == "RollFailed" then
            rankRollResponse = {
                action = action,
                data = data,
            }
        end
    end)
end

-- ── Trait reroll ──────────────────────────────────────────────
-- TraitRollClient uses the selected card Tool directly and sends:
-- TraitRollRE:FireServer("RollTrait", { Tool = tool })
local traitCardDropdown
local traitCardOptionMap = {}
local traitCardOptionsSignature = ""
local traitCardOptions = { "All" }
local traitRefreshQueued = false
local traitRollPending = false
local traitRollPendingTool
local traitRollResponse

local function getTraitOptions()
    local result = {}
    if TraitRollConfig and type(TraitRollConfig.GetTraits) == "function" then
        local ok, traits = pcall(TraitRollConfig.GetTraits)
        if ok and type(traits) == "table" then
            for _, entry in ipairs(traits) do
                local name = type(entry) == "table" and entry.Trait or entry
                if name ~= nil and tostring(name) ~= "" then
                    table.insert(result, tostring(name))
                end
            end
        end
    end

    -- The live game module is preferred. These are only a compatibility
    -- fallback for older game revisions that do not expose the config module.
    if #result == 0 then
        table.insert(result, "Almighty")
        table.insert(result, "Sovereign")
    end
    return result
end

local function getTraitGems()
    return getPlayerTraitGems()
end

local function getTraitGemsCost()
    if TraitRollRE then
        local cost = tonumber(TraitRollRE:GetAttribute("CostGemsPerRoll"))
        if cost then return cost end
    end
    if TraitRollConfig and type(TraitRollConfig.GetCostGems) == "function" then
        local ok, cost = pcall(TraitRollConfig.GetCostGems)
        if ok and tonumber(cost) then return tonumber(cost) end
    end
    return 1
end

local function buildTraitCardOptions()
    local options = { "All" }
    local map = {}
    local seen = {}

    for _, tool in ipairs(getRankCardsInBackpack()) do
        local baseName = tostring(tool:GetAttribute("CardName") or tool.Name)
        seen[baseName] = (seen[baseName] or 0) + 1
        local label = baseName
        if seen[baseName] > 1 then
            label = baseName .. " #" .. tostring(seen[baseName])
        end
        table.insert(options, label)
        map[label] = tool
    end
    return options, map
end

local function selectedTraitCardTools()
    local cards = getRankCardsInBackpack()
    local selected = Config.SelectedTraitCards
    if type(selected) ~= "table" or #selected == 0 then return cards end

    for _, value in ipairs(selected) do
        if tostring(value) == "All" then return cards end
    end

    local byTool = {}
    for _, value in ipairs(selected) do
        local tool = traitCardOptionMap[tostring(value)]
        if tool and tool.Parent == player:FindFirstChild("Backpack") then
            byTool[tool] = true
        end
    end

    local result = {}
    for _, tool in ipairs(cards) do
        if byTool[tool] then table.insert(result, tool) end
    end
    return result
end

local function refreshTraitCardDropdown()
    if not traitCardDropdown then return end
    local options, map = buildTraitCardOptions()
    traitCardOptionMap = map
    traitCardOptions = options
    local signature = table.concat(options, "\0")
    if signature == traitCardOptionsSignature then return end
    traitCardOptionsSignature = signature

    local selected = Config.SelectedTraitCards or { "All" }
    local refreshed = pcall(function()
        traitCardDropdown:Refresh(options, selected)
    end)
    if not refreshed then
        pcall(function() traitCardDropdown:Set(options) end)
    end
end

local function queueTraitCardDropdownRefresh()
    if traitRefreshQueued then return end
    traitRefreshQueued = true
    task.delay(0.2, function()
        traitRefreshQueued = false
        refreshTraitCardDropdown()
    end)
end

local function getTraitTarget()
    local targets = Config.TargetTraits
    if type(targets) == "string" then
        targets = targets ~= "" and { targets } or {}
    end
    if type(targets) ~= "table" or #targets == 0 then return nil end
    return targets
end

local function traitHasTarget(tool)
    if not tool then return false end
    local current = tostring(tool:GetAttribute("CardTrait") or "")
    for _, target in ipairs(getTraitTarget() or {}) do
        if current == tostring(target) then return true end
    end
    return false
end

local function stopTraitReroll(message)
    Config.AutoTraitRoll = false
    if Controls.AutoTraitRoll and Controls.AutoTraitRoll.Set then
        pcall(function() Controls.AutoTraitRoll:Set(false) end)
    end
    if message then notify("Traits", message) end
end

if TraitRollRE then
    TraitRollRE.OnClientEvent:Connect(function(action, data)
        if not traitRollPending or type(data) ~= "table" then return end
        if data.Tool and data.Tool ~= traitRollPendingTool then return end
        if action == "RollResult" or action == "RollFailed" then
            traitRollResponse = {
                action = action,
                data = data,
            }
        end
    end)
end

task.spawn(function()
    while true do
        task.wait(0.4)
        if rankCardDropdown then
            queueRankCardDropdownRefresh()
        end
        if traitCardDropdown then
            queueTraitCardDropdownRefresh()
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.15)
        if not Config.AutoRankRoll then continue end
        if not GradeRollRE then
            stopRankReroll("GradeRollRE was not found.")
            continue
        end

        local target = getRankTarget()
        if not target then
            stopRankReroll("Select a target ranking first.")
            continue
        end

        local cards = selectedRankCardTools()
        if #cards == 0 then
            stopRankReroll("No selected cards are currently in your backpack.")
            continue
        end

        local progressed = false
        local cardsRemaining = false
        for _, tool in ipairs(cards) do
            if not Config.AutoRankRoll then break end
            if not tool.Parent then continue end
            while Config.AutoRankRoll and tool.Parent
                and not rankCardHasTarget(tool) do
                cardsRemaining = true
                local currency = chooseRankCurrency(tool)
                if not currency then
                    stopRankReroll(
                        "Not enough " ..
                        (Config.RankUseGems and Config.RankUseCash
                            and "gems or cash."
                            or "currency.")
                    )
                    break
                end

                rankRollPending = true
                rankRollPendingTool = tool
                rankRollResponse = nil
                pcall(function()
                    GradeRollRE:FireServer("RollGrade", {
                        Tool = tool,
                        Currency = currency,
                    })
                end)

                local deadline = os.clock() + 8
                while Config.AutoRankRoll and rankRollPending
                    and not rankRollResponse and os.clock() < deadline do
                    task.wait(0.1)
                end

                local response = rankRollResponse
                rankRollPending = false
                rankRollPendingTool = nil
                rankRollResponse = nil

                if not response then
                    stopRankReroll("Rank roll timed out; reroll stopped safely.")
                    break
                end

                if response.action == "RollFailed" then
                    local reason = tostring(response.data.Reason or "UNKNOWN")
                    if reason == "NOT_ENOUGH_GEMS"
                        or reason == "NOT_ENOUGH_CASH"
                        or reason == "PAYMENT_FAILED" then
                        stopRankReroll("The selected currency is no longer available.")
                        break
                    end
                    task.wait(0.8)
                else
                    progressed = true
                    task.wait(0.2)
                end
            end
            if tool.Parent and not rankCardHasTarget(tool) then
                cardsRemaining = true
            end
        end

        if Config.AutoRankRoll and not cardsRemaining then
            local targetStr = target and table.concat(target, " / ") or "target"
            stopRankReroll("All selected cards reached " .. targetStr .. ".")
        elseif Config.AutoRankRoll and not progressed then
            task.wait(0.75)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.15)
        -- Trait and ranking rerolls use separate remotes and may run at the
        -- same time.  Do not use ActiveAutoRoll or the other script toggle as
        -- a shared mutex: the game's built-in auto-roll uses that attribute
        -- to coordinate only its own two UI workers.
        if not Config.AutoTraitRoll then
            continue
        end
        if not TraitRollRE then
            stopTraitReroll("TraitRollRE was not found.")
            continue
        end

        local targets = getTraitTarget()
        if not targets then
            stopTraitReroll("Select at least one target trait first.")
            continue
        end

        local cards = selectedTraitCardTools()
        if #cards == 0 then
            stopTraitReroll("No selected cards are currently in your backpack.")
            continue
        end

        local progressed = false
        local cardsRemaining = false
        for _, tool in ipairs(cards) do
            if not Config.AutoTraitRoll then break end
            if not tool.Parent then continue end
            while Config.AutoTraitRoll and tool.Parent
                and not traitHasTarget(tool) do
                cardsRemaining = true
                local gemCost = getTraitGemsCost()
                if getTraitGems() < gemCost then
                    stopTraitReroll("Not enough trait gems.")
                    break
                end

                traitRollPending = true
                traitRollPendingTool = tool
                traitRollResponse = nil
                pcall(function()
                    TraitRollRE:FireServer("RollTrait", { Tool = tool })
                end)

                local deadline = os.clock() + 8
                while Config.AutoTraitRoll and traitRollPending
                    and not traitRollResponse
                    and os.clock() < deadline do
                    task.wait(0.1)
                end

                local response = traitRollResponse
                traitRollPending = false
                traitRollPendingTool = nil
                traitRollResponse = nil

                if not response then
                    stopTraitReroll("Trait roll timed out; reroll stopped safely.")
                    break
                end

                if response.action == "RollFailed" then
                    local reason = tostring(response.data.Reason or "UNKNOWN")
                    if reason == "NOT_ENOUGH_GEMS"
                        or reason == "PAYMENT_FAILED" then
                        stopTraitReroll("Not enough trait gems.")
                        break
                    end
                    task.wait(0.8)
                else
                    progressed = true
                    task.wait(0.2)
                end
            end
            if tool.Parent and not traitHasTarget(tool) then
                cardsRemaining = true
            end
        end

        if Config.AutoTraitRoll and not cardsRemaining then
            stopTraitReroll(
                "All selected cards reached " .. table.concat(targets, " / ") .. "."
            )
        elseif Config.AutoTraitRoll and not progressed then
            task.wait(0.75)
        end
    end
end)

-- ── Auto Place Pack loop ──────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(1)
        if not Config.AutoPlacePack then continue end

        local char     = player.Character
        local root     = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not humanoid or not root then continue end

        local savedCFrame = root.CFrame
        local slots = getAvailableCardSlots()
        if #slots == 0 then
            pcall(function() humanoid:UnequipTools() end)
            continue
        end
        for _, slot in ipairs(slots) do
            if not Config.AutoPlacePack then break end
            -- Re-check after every placement because the server may replicate
            -- slot occupancy while this loop is still running.
            if slotIsOccupied(slot) then continue end

            local packs = getFilteredPacksInBackpack()
            if #packs == 0 then break end

            local pack = packs[1]
            pcall(function() humanoid:EquipTool(pack) end)
            for _ = 1, 12 do
                if pack.Parent == char then break end
                task.wait(0.1)
            end
            teleportNear(getCFrameOf(slot))
            task.wait(0.2)  -- let the server register the new position
            local btn = findSlotInteraction(slot, { "Place", "Insert", "Add" })
            local fired = false
            if btn then
                fired = fireSlotButton(btn)
            end

            if not fired then
                local slotIndex = getCardSlotIndex(slot)
                local cardSlotRE = findRemote("CardSlotRE")
                if slotIndex and cardSlotRE then
                    fired = fireRemote("CardSlotRE", "Place", {
                        SlotIndex = slotIndex,
                        Item = pack.Name,
                    })
                end
            end
            if fired then
                task.wait(math.max(0.5, Config.CardActionDelay))
            else
                warnOnce("AutoPlace:no-interaction",
                    "Auto Place Pack: no place interaction was found for "
                    .. tostring(slot.Name) .. ".")
            end
            pcall(function() humanoid:UnequipTools() end)
            task.wait(0.1)
        end

        local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if r then pcall(function() r.CFrame = savedCFrame end) end
    end
end)

-- ── Auto Use Time Potion for full plots ───────────────────────
-- Time potions are not category boosts.  They reduce pack cooldowns, so
-- they are handled separately from Misc > Auto Use Potions.
task.spawn(function()
    -- Inventory item ids have used both compact ids (TimePotion3) and
    -- display-style ids (Time Potion III) across game revisions. Keep the
    -- configured compact names, but send the exact key received from server.
    local function normalizePotionInventoryId(value)
        local text = string.lower(tostring(value or ""))
        text = string.gsub(text, "[^%w]", "")
        if string.sub(text, -3) == "iii" then
            text = string.sub(text, 1, -4) .. "3"
        elseif string.sub(text, -2) == "ii" then
            text = string.sub(text, 1, -3) .. "2"
        elseif string.sub(text, -1) == "i" then
            text = string.sub(text, 1, -2) .. "1"
        end
        return text
    end

    local function inventoryQuantity(value)
        if type(value) == "table" then
            return tonumber(
                value.Quantity or value.quantity
                    or value.Amount or value.amount
                    or value.Count or value.count
            ) or 0
        end
        return tonumber(value) or 0
    end

    local function findPotionInventoryItem(preferredId)
        local preferredKey = normalizePotionInventoryId(preferredId)
        local directQuantity = inventoryQuantity(
            potionInventoryCounts[preferredId]
        )
        if directQuantity > 0 then
            return preferredId, directQuantity
        end

        for itemId, quantity in pairs(potionInventoryCounts) do
            local amount = inventoryQuantity(quantity)
            if amount > 0
                and normalizePotionInventoryId(itemId) == preferredKey then
                return itemId, amount
            end
        end
        return nil, 0
    end

    local nextInventorySync = 0
    while true do
        task.wait(1)
        if not Config.AutoTimePotion then continue end
        if not ItemsREForAutomation then continue end

        local now = os.clock()
        -- Keep this feature independent from Misc > Auto Use Potions. The
        -- time-potion toggle can be enabled by itself and still receives
        -- current inventory data.
        if now >= nextInventorySync then
            pcall(function() ItemsREForAutomation:FireServer("Init") end)
            nextInventorySync = now + 5
        end

        -- Time Potions are only useful once every card slot is occupied.
        -- This prevents consuming them while Auto Place Pack still has an
        -- available slot, and also prevents them from being spammed on an
        -- empty or partially replicated plot.
        if not areAllCardSlotsOccupied() then continue end

        -- Time potions are consumables, not timed stat boosts. Submit one
        -- available potion per pass only while a pack is actively opening or
        -- on cooldown.
        local selectedPotion
        for _, potion in ipairs(TIME_POTIONS) do
            local inventoryItem, quantity = findPotionInventoryItem(potion)
            if inventoryItem and quantity > 0 then
                selectedPotion = inventoryItem
                break
            end
        end
        if not selectedPotion then continue end

        pcall(function()
            ItemsREForAutomation:FireServer("UseItem", {
                ItemId = selectedPotion,
                Amount = 1,
            })
        end)
        -- The one-second loop submits only one item per pass. It never waits
        -- for an active potion to expire.
    end
end)

-- ── Auto Open Pack loop ───────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(2)
        if not Config.AutoOpenPack then continue end

        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then continue end

        local savedCFrame = root.CFrame
        local slots = getAllCardSlots()
        for _, slot in ipairs(slots) do
            if not Config.AutoOpenPack then break end
            if slotIsOnCooldown(slot) then continue end
            local btn = findSlotButton(slot, "Open")
            if not btn then continue end
            teleportNear(getCFrameOf(slot))
            task.wait(0.2)  -- let the server register the new position
            local fired = fireSlotButton(btn)
            -- fallback: fire the remote directly if the button didn't work
            if not fired then
                local slotIndex = getCardSlotIndex(slot)
                if slotIndex then
                    fireRemote("CardSlotRE", "Open", { SlotIndex = slotIndex })
                end
            end
            task.wait(Config.CardActionDelay)
        end

        local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if r then pcall(function() r.CFrame = savedCFrame end) end
    end
end)

-- ── Equip Best Card ───────────────────────────────────────────
doEquipBestCards = function(slotLimit)
    local char     = player.Character
    local root     = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid or not root then return end

    local savedCFrame = root.CFrame

    local slots = getAllCardSlots()
    for _, slot in ipairs(slots) do
        local slotIndex = getCardSlotIndex(slot)
        if not slotIndex then continue end
        if slotLimit and slotIndex > slotLimit then continue end
        if slotIsOnCooldown(slot) then continue end
        local removeBtn = findSlotButton(slot, "Remove")
        if not removeBtn then continue end
        teleportNear(getCFrameOf(slot))
        task.wait(0.2)  -- let the server register the new position
        local didRemove = fireSlotButton(removeBtn)
        if not didRemove then
            local slotIndex2 = getCardSlotIndex(slot)
            if slotIndex2 then
                fireRemote("CardSlotRE", "Remove", { SlotIndex = slotIndex2 })
            end
        end
        task.wait(CARD_REMOVAL_DELAY)
    end
    task.wait(Config.CardActionDelay)

    local bestCards = getSortedCardsInBackpack()
    local cardIdx   = 1
    slots = getAllCardSlots()
    for _, slot in ipairs(slots) do
        local slotIndex = getCardSlotIndex(slot)
        if not slotIndex then continue end
        if slotLimit and slotIndex > slotLimit then continue end
        if cardIdx > #bestCards then break end
        if slotIsOccupied(slot) then continue end
        local card = bestCards[cardIdx].tool
        pcall(function() humanoid:EquipTool(card) end)
        task.wait(Config.CardActionDelay)
        teleportNear(getCFrameOf(slot))
        task.wait(0.2)  -- let the server register the new position
        local placeBtn = findSlotButton(slot, "Place")
        if placeBtn then
            fireSlotButton(placeBtn)
            task.wait(Config.CardActionDelay)
            if not slotIsOccupied(slot) then
                local retryPlaceBtn = findSlotButton(slot, "Place")
                if retryPlaceBtn then
                    fireSlotButton(retryPlaceBtn)
                    task.wait(CARD_REMOVAL_DELAY)
                end
            end
            if slotIsOccupied(slot) then
                cardIdx = cardIdx + 1
            end
        end
        pcall(function() humanoid:UnequipTools() end)
        task.wait(0.1)
    end

    restoreCharacterPosition(savedCFrame)
    local placedCount = cardIdx - 1
    notify("Equip Best Card", "Done! Placed " .. placedCount .. " card(s).")
    return placedCount
end

removeAllCards = function(limit, minimum)
    local char     = player.Character
    local root     = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid or not root then return 0 end

    local savedCFrame = root.CFrame
    local removed = 0

    local slots = getAllCardSlots()
    for _, slot in ipairs(slots) do
        local slotIndex = getCardSlotIndex(slot)
        if not slotIndex then continue end
        if minimum and slotIndex < minimum then continue end
        if limit and slotIndex > limit then continue end
        if slotIsOnCooldown(slot) then continue end
        local removeBtn = findSlotButton(slot, "Remove")
        if not removeBtn then continue end
        teleportNear(getCFrameOf(slot))
        task.wait(0.2)  -- let the server register the new position
        local didRemove = fireSlotButton(removeBtn)
        -- fallback: fire the remote directly if the button didn't work
        if not didRemove then
            local slotIndex = getCardSlotIndex(slot)
            if slotIndex then
                didRemove = fireRemote("CardSlotRE", "Remove", { SlotIndex = slotIndex })
            end
        end
        if didRemove then
            removed = removed + 1
        end
        task.wait(math.max(0.1, Config.CardActionDelay))
    end

    restoreCharacterPosition(savedCFrame)
    return removed
end

removeFirstFourCardSlots = function()
    return removeAllCards(4)
end

-- ── Combat GUI helpers ───────────────────────────────────────
local function findGuiByName(root, wantedName)
    if not root then return nil end
    if root.Name == wantedName then return root end
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant.Name == wantedName then
            return descendant
        end
    end
    return nil
end

local function getCombatGui(mode)
    local guiMid = playerGui:FindFirstChild("GuiMid")
    local candidates = {
        InfinityTower = { "InfinityTower", "InfinityTowerFrame" },
        BossRaid = { "BossRaid", "BossRaidFrame" },
        HideBattle = { "HideBattle" },
        HideBattleBoss = { "HideBattleBoss" },
    }
    local root
    for _, name in ipairs(candidates[mode] or { mode }) do
        root = guiMid and guiMid:FindFirstChild(name, true)
        if root then break end
        root = playerGui:FindFirstChild(name, true)
        if root then break end
    end
    return root
end

clickGuiButton = function(button)
    if not button or not button:IsA("GuiButton") then return false end
    -- Do not fire hidden duplicate buttons. Combat screens keep several
    -- copies of Exit/Battle controls in the hierarchy across UI states.
    if button:IsA("GuiObject") and not button.Visible then return false end
    if firesignal then
        local ok = pcall(firesignal, button.MouseButton1Click)
        if ok then return true end
    end
    return pcall(function() button:Activate() end)
end

-- Shared helper: find BossRaidReward root and its CLOSE button.
local function getRewardCloseButton()
    local guiMid = playerGui:FindFirstChild("GuiMid")
    local root = guiMid and guiMid:FindFirstChild("BossRaidReward", true)
    if not root then
        root = playerGui:FindFirstChild("BossRaidReward", true)
    end
    if not root then return nil, nil end
    -- Confirmed from BossRaidRewardClient:
    -- BossRaidReward.RaidFrameReward.TOP.CLOSE
    local raidFrame = root:FindFirstChild("RaidFrameReward", true)
    local top = raidFrame and raidFrame:FindFirstChild("TOP", true)
    local close = top and top:FindFirstChild("CLOSE")
    if not close then
        close = findGuiByName(root, "CLOSE")
    end
    return root, close
end

local function isGuiShown(instance)
    if not instance then return false end
    if instance:IsA("GuiObject") then return instance.Visible == true end
    if instance:IsA("LayerCollector") then return instance.Enabled == true end
    return false
end

-- Lightweight immediate check used by startCombatBattle as a gate.
-- The background watcher (below) is the one that actually does the
-- close + Auto Boss Raid pause/resume flow. This function just detects
-- whether the panel is currently up and fires the close button right now
-- so startCombatBattle does not proceed while rewards are showing.
closeBossRaidReward = function()
    local rewardRoot, closeButton = getRewardCloseButton()
    if not isGuiShown(rewardRoot) then
        return false
    end
    -- Panel is visible — click close immediately.
    if closeButton then
        clickGuiButton(closeButton)
    end
    return true
end

-- ── Background Raid-Reward Watcher ────────────────────────────────────────
-- Detects the Raid Rewards panel the instant it becomes visible and closes it
-- right away.  Combat mode selection is owned by the single priority
-- scheduler below; this watcher must not toggle either user setting.
task.spawn(function()
    while true do
        task.wait(0.1)
        if not Config.AutoRaid then continue end

        local rewardRoot, closeButton = getRewardCloseButton()
        if not isGuiShown(rewardRoot) then continue end
        if closeButton then
            clickGuiButton(closeButton)
        end
    end
end)

local function clickCombatButton(mode, names)
    local root = getCombatGui(mode)
    if root then
        for _, name in ipairs(names) do
            local button = findGuiByName(root, name)
            if button and clickGuiButton(button) then
                return true
            end
        end
    end

    for _, name in ipairs(names) do
        local button = findGuiByName(playerGui, name)
        if button and clickGuiButton(button) then
            return true
        end
    end
    return false
end

-- Boss Raid has priority over Infinity Tower.  The tower UI exposes an Exit
-- control while a run is active; use that control instead of trying to start
-- the raid while the tower attribute is still true.
exitInfinityTowerBattle = function()
    if player:GetAttribute("InfinityTowerInBattle") ~= true then
        return true
    end

    local hideBattleRoot = getCombatGui("HideBattle")

    local function activateButtonAndVerify(button, changed)
        if not button or not button:IsA("GuiButton")
            or (button:IsA("GuiObject") and not button.Visible) then
            return false
        end

        -- Activate first so buttons wired to Activated respond normally.
        pcall(function() button:Activate() end)
        task.wait(0.2)
        if changed() then return true end

        -- Some game revisions wire these controls only to MouseButton1Click.
        -- Use the signal as a fallback, then verify the state again.
        if firesignal then
            pcall(firesignal, button.MouseButton1Click)
            task.wait(0.2)
        end
        return changed()
    end

    -- Auto Hide Battle leaves the tower running behind the compact
    -- HideBattle control.  In that state the Exit button is not available
    -- until the same button is clicked to show the battle again.
    local showBattleClicked = false
    local hideBattleButton = hideBattleRoot
        and findGuiByName(hideBattleRoot, "Hide")
    if hideBattleButton and hideBattleButton:IsA("TextButton") then
        local buttonText = string.lower(tostring(hideBattleButton.Text or ""))
        local isShowBattle = string.find(buttonText, "show", 1, true) ~= nil
            and string.find(buttonText, "battle", 1, true) ~= nil
        if isShowBattle then
            -- This is the exact same HideBattle > Hide control used by
            -- Auto Hide Battle; do not search for a different button.
            showBattleClicked = activateButtonAndVerify(
                hideBattleButton,
                function()
                    local text = string.lower(
                        tostring(hideBattleButton.Text or "")
                    )
                    return string.find(text, "show", 1, true) == nil
                end
            )
        end
    end

    if showBattleClicked then
        -- Let the full battle controls replicate before looking for Exit.
        task.wait(0.25)
    end

    local roots = {
        getCombatGui("InfinityTower"),
        getCombatGui("HideBattle"),
    }
    local names = {
        "Exit", "EXIT", "ExitBattle", "ExitTower",
        "Leave", "LeaveBattle", "Quit",
    }
    local function activateExitButton(button)
        return activateButtonAndVerify(button, function()
            return player:GetAttribute("InfinityTowerInBattle") ~= true
        end)
    end

    for _, root in ipairs(roots) do
        if root then
            for _, name in ipairs(names) do
                local button = findGuiByName(root, name)
                if button and activateExitButton(button) then
                    return true
                end
            end

            -- Some versions keep the button's Instance name generic and only
            -- expose "Exit" through its Text property.
            for _, descendant in ipairs(root:GetDescendants()) do
                -- ImageButton inherits GuiButton but has no Text property.
                -- Reading descendant.Text on one raises and kills the
                -- combat scheduler, so only inspect text-bearing buttons.
                if descendant:IsA("TextButton") then
                    local text = string.lower(tostring(descendant.Text or ""))
                    if text == "exit" or text == "leave" or text == "quit" then
                        if activateExitButton(descendant) then
                            return true
                        end
                    end
                end
            end
        end
    end

    -- Some revisions place the battle controls under a generic frame rather
    -- than under InfinityTower. Search visible buttons globally as a final UI
    -- fallback, but only accept buttons whose name/text clearly means exit.
    for _, descendant in ipairs(playerGui:GetDescendants()) do
        if descendant:IsA("GuiButton")
            and descendant:IsA("GuiObject")
            and descendant.Visible then
            local buttonName = string.lower(tostring(descendant.Name or ""))
            local buttonText = descendant:IsA("TextButton")
                and string.lower(tostring(descendant.Text or ""))
                or ""
            local looksLikeExit = buttonName == "exit"
                or buttonName == "exitbattle"
                or buttonName == "exittower"
                or buttonName == "leave"
                or buttonName == "leavebattle"
                or buttonName == "quit"
                or buttonText == "exit"
                or buttonText == "leave"
                or buttonText == "quit"
            if looksLikeExit and activateExitButton(descendant) then
                return true
            end
        end
    end

    -- The UI button is the preferred path. A few game revisions expose the
    -- same action only through InfinityTowerRE; use it only after all visible
    -- button paths failed and verify the replicated battle attribute.
    local towerRemote = Remotes and Remotes:FindFirstChild("InfinityTowerRE")
    if towerRemote and towerRemote:IsA("RemoteEvent") then
        for _, action in ipairs({ "Exit", "ExitBattle", "Leave", "Quit" }) do
            pcall(function() towerRemote:FireServer(action) end)
            task.wait(0.25)
            if player:GetAttribute("InfinityTowerInBattle") ~= true then
                return true
            end
        end
    end
    return false
end

local function selectRaidDifficulty(difficulty)
    local root = getCombatGui("BossRaid")
    if not root then return false end

    local difficultyFrame = findGuiByName(root, "DifficultyFrame") or root
    local scrolling = findGuiByName(difficultyFrame, "ScrollingFrameDifficulty")
        or difficultyFrame
    local choice = scrolling:FindFirstChild(tostring(difficulty))
    if not choice then
        choice = findGuiByName(scrolling, tostring(difficulty))
    end
    if not choice then return false end

    local button = findGuiByName(choice, "FrameButton") or choice
    return clickGuiButton(button)
end

local function isCombatActive()
    return player:GetAttribute("InfinityTowerInBattle") == true
        or player:GetAttribute("BossRaidInBattle") == true
end

local function getRaidDifficultyOptions()
    local options = {}
    if BossRaidConfig and type(BossRaidConfig.DifficultyOrder) == "table" then
        for _, difficulty in ipairs(BossRaidConfig.DifficultyOrder) do
            table.insert(options, tostring(difficulty))
        end
    end

    if #options == 0 then
        local root = getCombatGui("BossRaid")
        local frame = root and (findGuiByName(root, "DifficultyFrame") or root)
        if frame then
            for _, child in ipairs(frame:GetChildren()) do
                if child:IsA("GuiObject")
                    and child.Name ~= "ScrollingFrameDifficulty" then
                    table.insert(options, child.Name)
                end
            end
        end
    end

    if #options == 0 then
        options = { "Normal" }
    end
    return options
end

-- Use the live config's order/names.  The hard-coded list used here before
-- could contain choices that do not exist in the current game revision, so
-- selectRaidDifficulty() would silently fail and BATTLE would be clicked with
-- no valid difficulty selected.
raidState.DifficultyOptions = getRaidDifficultyOptions()

local function normalizeRaidDifficulties(value)
    local selected = {}
    local selectedSet = {}
    local values = type(value) == "table" and value or { value }
    for _, difficulty in ipairs(values) do
        difficulty = tostring(difficulty or "")
        if difficulty ~= "" and not selectedSet[difficulty] then
            table.insert(selected, difficulty)
            selectedSet[difficulty] = true
        end
    end
    return selected
end

-- Boss Raid grants one attempt per hourly window. Keep the feature enabled
-- after the first click, but latch the attempt so the polling loops cannot
-- click again until the next window is detected.
local function getSelectedRaidDifficulties()
    local selected = normalizeRaidDifficulties(Config.RaidDifficulties)
    local selectedSet = {}
    for _, difficulty in ipairs(selected) do
        selectedSet[difficulty] = true
    end

    local ordered = {}
    for _, difficulty in ipairs(raidState.DifficultyOptions) do
        if selectedSet[difficulty] then
            table.insert(ordered, difficulty)
        end
    end
    if #ordered == 0 and raidState.DifficultyOptions[1] then
        ordered[1] = raidState.DifficultyOptions[1]
    end
    return ordered
end

local function getNextRaidDifficulty()
    for _, difficulty in ipairs(getSelectedRaidDifficulties()) do
        if not raidState.CompletedDifficulties[difficulty] then
            return difficulty
        end
    end
    return nil
end

local function clearCompletedRaidDifficulties()
    for difficulty in pairs(raidState.CompletedDifficulties) do
        raidState.CompletedDifficulties[difficulty] = nil
    end
end

local function getRaidRequirement(difficulty)
    if not BossRaidConfig or not BossRaidConfig.GetBossStats then
        return nil
    end
    if raidState.BossId == "" then return nil end
    local ok, stats = pcall(
        BossRaidConfig.GetBossStats,
        raidState.BossId,
        difficulty
    )
    if ok and type(stats) == "table" then
        return tonumber(stats.ReferenceDamage)
    end
    return nil
end

raidState.DifficultyInfo = {
    Easy = {
        damage = "2.1B",
        description = "At least 2.1B damage per card.",
    },
    Medium = {
        damage = "412.9Qn",
        description = "At least 412.9Qn damage per card.",
    },
    Hard = {
        damage = "617.7O",
        description = "At least 617.7O damage per card.",
    },
    Nightmare = {
        damage = "13.1O",
        description = "At least 13.1O damage per card.",
    },
}

local function getRaidDifficultyInfo(difficulty)
    local wanted = string.lower(tostring(difficulty or ""))
    for name, info in pairs(raidState.DifficultyInfo) do
        if string.lower(name) == wanted then
            return info
        end
    end
    return nil
end

raidState.UpdateInfoDisplay = function(difficulties)
    if not raidState.InfoParagraph or not raidState.InfoParagraph.Set then
        return
    end

    local selected = getSelectedRaidDifficulties()

    local lines = {}
    for _, difficulty in ipairs(selected) do
        local selectedInfo = getRaidDifficultyInfo(difficulty)
        if selectedInfo then
            table.insert(
                lines,
                difficulty .. " - " .. selectedInfo.damage
                    .. " Damage per card"
            )
        end
    end
    table.insert(lines, "Timer: " .. raidState.TimerText)

    pcall(function()
        raidState.InfoParagraph:Set({
            Title = "Boss Raid",
            Content = table.concat(lines, "\n"),
        })
    end)
end

raidState.ShowRequirement = function(difficulties)
    local selected = getSelectedRaidDifficulties()
    notify(
        "Boss Raid Difficulty",
        "Selected " .. table.concat(selected, ", ") .. "."
    )
    raidState.UpdateInfoDisplay(selected)
end

if BossRaidRE then
    BossRaidRE.OnClientEvent:Connect(function(eventName, payload)
        if eventName == "State" and type(payload) == "table" then
            raidState.Received = true
            raidState.Open = payload.Open == true
                or payload.IsOpen == true
                or payload.Available == true
            raidState.AlreadyUsed = payload.AlreadyUsed == true
                or payload.Used == true
            raidState.BossId = tostring(payload.BossId or "")
        end
    end)
    pcall(function() BossRaidRE:FireServer("RequestState") end)
end

raidState.ReadTimerText = function(timer)
    if not timer then return nil end

    local function read(instance)
        if instance:IsA("TextLabel") or instance:IsA("TextButton")
            or instance:IsA("TextBox") then
            local text = tostring(instance.Text or "")
            if text ~= "" then return text end
        elseif instance:IsA("ValueBase") then
            return tostring(instance.Value)
        end
        return nil
    end

    local direct = read(timer)
    if direct then return direct end

    for _, attributeName in ipairs({
        "Text", "Timer", "Time", "TimeLeft", "TimeRemaining",
    }) do
        local value = timer:GetAttribute(attributeName)
        if value ~= nil then return tostring(value) end
    end

    for _, descendant in ipairs(timer:GetDescendants()) do
        local value = read(descendant)
        if value then return value end
    end
    return nil
end

function findBossRaidTimer()
    local roots = {
        workspace:FindFirstChild("BossRaidModel", true),
        workspace:FindFirstChild("BossRaid", true),
        playerGui:FindFirstChild("BossRaidModel", true),
        playerGui:FindFirstChild("BossRaidGui", true),
        getCombatGui("BossRaid"),
    }
    local timerNames = {
        "Timer", "TimeLeft", "TimeRemaining", "Countdown",
    }

    for _, root in ipairs(roots) do
        if root then
            for _, name in ipairs(timerNames) do
                local timer = findGuiByName(root, name)
                    or root:FindFirstChild(name, true)
                if timer then return timer end
            end
        end
    end
    return nil
end

function isBossRaidOpen()
    -- BossRaidRE is the authoritative source used by BossRaidClient.  The
    -- timer is only presentation text and can be missing or belong to another
    -- UI during replication.
    if BossRaidRE then
        if raidState.Received and raidState.Open and not raidState.AlreadyUsed then
            return true
        end

        -- Older BossRaidClient revisions do not always deliver the State
        -- event to scripts that start after the raid window opened. The live
        -- countdown is still a valid readiness signal in that case.
        local timerText = string.lower(tostring(raidState.TimerText or ""))
        if not raidState.AlreadyUsed
            and string.find(timerText, "end in", 1, true) then
            return true
        end
        return false
    end

    -- Fallback for older game revisions that do not expose BossRaidRE.
    return string.find(
        string.lower(raidState.TimerText or ""),
        "end in",
        1,
        true
    ) ~= nil
end

task.spawn(function()
    local nextRaidStateRequest = 0
    while true do
        task.wait(0.5)
        local timer = findBossRaidTimer()
        local text = raidState.ReadTimerText(timer)
        if text and text ~= "" then
            raidState.TimerText = text
        elseif timer then
            raidState.TimerText = "Timer found, waiting for countdown..."
        else
            raidState.TimerText = "Boss Raid is currently unavailable"
        end

        -- Refresh the authoritative state periodically. This covers the
        -- transition where Infinity Tower ends without a BossRaid state
        -- event being delivered to this script.
        local now = os.clock()
        if BossRaidRE and now >= nextRaidStateRequest then
            pcall(function() BossRaidRE:FireServer("RequestState") end)
            nextRaidStateRequest = now + 5
        end

        -- Update the shared description value before checking readiness. The
        -- scheduler and the visible Boss Raid description now read the same
        -- timer text on every pass.
        if isBossRaidOpen() then
            raidState.ClosedSince = nil
        else
            raidState.ClosedSince = raidState.ClosedSince or now
            -- Require a stable closed state before re-arming. This avoids a brief
            -- timer/UI replication gap reopening the same hourly attempt.
            if now - raidState.ClosedSince >= 3 then
                raidState.AttemptConsumed = false
                clearCompletedRaidDifficulties()
            end
        end

        raidState.UpdateInfoDisplay(Config.RaidDifficulties)
    end
end)

startCombatBattle = function(mode, equipBest, hideBattle, difficulty)
    -- BossRaidRewardClient claims the reward from its CLOSE button. Never
    -- start the next tower/raid battle while that panel is still open.
    if closeBossRaidReward and closeBossRaidReward() then
        return false
    end
    if mode == "BossRaid" and not isBossRaidOpen() then
        return false
    end
    if mode == "BossRaid" and raidState.AttemptConsumed then
        return false
    end

    if mode == "BossRaid"
        and player:GetAttribute("InfinityTowerInBattle") == true then
        -- BossRaidClient rejects StartFight while the tower attribute is
        -- still true.  Clicking Exit once is not enough because the server
        -- may need a few replication frames to clear the attribute.
        for _ = 1, 3 do
            exitInfinityTowerBattle()
            for _ = 1, 15 do
                if player:GetAttribute("InfinityTowerInBattle") ~= true then
                    break
                end
                task.wait(0.1)
            end
            if player:GetAttribute("InfinityTowerInBattle") ~= true then
                break
            end
        end
        if player:GetAttribute("InfinityTowerInBattle") == true then
            return false
        end
    end
    if isCombatActive() then return false end

    if equipBest or mode == "InfinityTower" then
        local names = mode == "BossRaid"
            and { "EQUIPBEST", "EquipBest", "EQUIPEBEST" }
            or { "EQUIPEBEST", "EQUIPBEST", "EquipBest" }
        clickCombatButton(mode, names)
        task.wait(0.5)
    end

    local raidDifficulty
    if mode == "BossRaid" then
        if raidState.AlreadyUsed then
            return false
        end
        raidDifficulty = difficulty or getNextRaidDifficulty()
        if not raidDifficulty then return false end
        if not selectRaidDifficulty(raidDifficulty) then
            warn("[ACF] Boss Raid difficulty button not found: "
                .. tostring(raidDifficulty))
            return false
        end
        task.wait(0.25)
    end

    local started = clickCombatButton(mode, { "BATTLE", "Battle" })
    if not started then return false end

    if mode == "BossRaid" then
        -- Do not permanently consume the attempt until the server confirms
        -- the battle.  BossRaidClient can reject this click when the tower
        -- attribute has not replicated clear yet; that failure must remain
        -- retryable after a manual or delayed tower exit.
        raidState.AttemptConsumed = true
        local raidConfirmed = false
        for _ = 1, 20 do
            if player:GetAttribute("BossRaidInBattle") == true then
                raidConfirmed = true
                break
            end
            task.wait(0.15)
        end
        if raidConfirmed then
            raidState.RetryAt = 0
            raidState.CompletedDifficulties[raidDifficulty] = true
        else
            raidState.AttemptConsumed = false
            raidState.RetryAt = os.clock() + 3
            return false
        end
    else
        task.wait(0.75)
    end

    if hideBattle then
        clickCombatButton(
            mode == "BossRaid" and "HideBattleBoss" or "HideBattle",
            { "Hide" }
        )
    end
    return true
end

combatBusy = false

-- One scheduler owns both modes.  Boss Raid is evaluated first on every
-- pass, including while Tower is active, so "End in" cannot be missed.
task.spawn(function()
    while true do
        task.wait(0.5)
        if combatBusy then continue end

        local raidReady = Config.AutoRaid
            and isBossRaidOpen()
            and not raidState.AlreadyUsed
            and not raidState.AttemptConsumed
            and os.clock() >= raidState.RetryAt
            and getNextRaidDifficulty() ~= nil
        local towerEnabled = Config.AutoInfinityTower
        local towerActive = player:GetAttribute("InfinityTowerInBattle") == true
        local raidActive = player:GetAttribute("BossRaidInBattle") == true

        if raidReady and not raidActive then
            combatBusy = true

            if towerActive then
                for _ = 1, 3 do
                    exitInfinityTowerBattle()
                    for _ = 1, 15 do
                        if player:GetAttribute("InfinityTowerInBattle") ~= true then
                            break
                        end
                        task.wait(0.1)
                    end
                    if player:GetAttribute("InfinityTowerInBattle") ~= true then
                        break
                    end
                end
            end

            -- Never click Boss Raid while the tower is still active.  The
            -- game's BossRaidClient explicitly rejects that transition.
            if player:GetAttribute("InfinityTowerInBattle") ~= true
                and not isCombatActive() then
                if Config.AutoTeamCardCycle then
                    local cardsEquipped = false
                    for _ = 1, 2 do
                        local placed = doEquipBestCards(4)
                        if placed and placed > 0 then
                            cardsEquipped = true
                            break
                        end
                        task.wait(CARD_REMOVAL_DELAY)
                    end
                    if cardsEquipped then
                        startCombatBattle(
                            "BossRaid",
                            Config.AutoRaidEquip,
                            Config.AutoRaidHide
                        )
                    end
                else
                    startCombatBattle(
                        "BossRaid",
                        Config.AutoRaidEquip,
                        Config.AutoRaidHide
                    )
                end
            end

            combatBusy = false
            continue
        end

        if towerEnabled and not isCombatActive() then
            combatBusy = true
            -- The reward panel can briefly remain visible after the raid
            -- attribute clears. Close it before preparing the next tower run.
            if closeBossRaidReward and closeBossRaidReward() then
                combatBusy = false
                continue
            end
            if Config.AutoTeamCardCycle then
                local cardsEquipped = false
                for _ = 1, 2 do
                    local placed = doEquipBestCards(4)
                    if placed and placed > 0 then
                        cardsEquipped = true
                        break
                    end
                    task.wait(CARD_REMOVAL_DELAY)
                end
                if cardsEquipped then
                    startCombatBattle(
                        "InfinityTower",
                        Config.AutoInfinityEquip,
                        Config.AutoInfinityHide
                    )
                end
            else
                startCombatBattle(
                    "InfinityTower",
                    Config.AutoInfinityEquip,
                    Config.AutoInfinityHide
                )
            end
            combatBusy = false
        end
    end
end)

-- ══════════════════════════════════════════════════════════════
--  CARD CRAFT AUTOMATION
-- ══════════════════════════════════════════════════════════════
-- CardCraftClient confirms the server contract:
--   • RequestState
--   • StartCraft, { RecipeId = ..., Selections = { [requirement] = tools } }
--   • Claim
-- State.Job contains OutputCardName, StartedAt, ReadyAt and Duration.
-- The mutation list is a target/filter for the repeated craft setting. The
-- game rolls the output mutation server-side, so it is intentionally not
-- added to StartCraft as a fake client-controlled argument.
function cardCraftState.getRecipesSorted()
    local module = cardCraftState.Module
    if not module or type(module.GetRecipesSorted) ~= "function" then
        return {}
    end
    local ok, recipes = pcall(module.GetRecipesSorted)
    return ok and type(recipes) == "table" and recipes or {}
end

function cardCraftState.getRecipe(recipeId)
    local module = cardCraftState.Module
    if not module or type(module.GetRecipe) ~= "function" or recipeId == nil then
        return nil
    end
    local ok, recipe = pcall(module.GetRecipe, recipeId)
    return ok and type(recipe) == "table" and recipe or nil
end

function cardCraftState.refreshRecipes()
    local options = {}
    local map = {}
    for _, entry in ipairs(cardCraftState.getRecipesSorted()) do
        local recipe = entry.Recipe or entry
        local id = entry.Id or entry.RecipeId or recipe.Id
        local cardName = recipe and recipe.OutputCardName
        if id ~= nil and cardName ~= nil then
            local label = tostring(cardName)
            local key = string.lower(label)
            if not map[key] then
                map[key] = {
                    Id = id,
                    CardName = label,
                    Recipe = recipe,
                }
                table.insert(options, label)
            end
        end
    end
    if #options == 0 then
        options = { "No recipes found" }
    end
    cardCraftState.RecipeMap = map
    cardCraftState.RecipeOptions = options
    return options
end

function cardCraftState.selectedRecipe()
    local wantedId = Config.CardCraftRecipeId or cardCraftState.SelectedRecipeId
    local wantedCard = tostring(Config.CardCraftCard or "")
    if wantedId ~= nil then
        local recipe = cardCraftState.getRecipe(wantedId)
        if recipe then return wantedId, recipe end
    end
    if wantedCard ~= "" then
        local entry = cardCraftState.RecipeMap[string.lower(wantedCard)]
        if entry then
            Config.CardCraftRecipeId = entry.Id
            return entry.Id, entry.Recipe
        end
    end
    return nil, nil
end

function cardCraftState.refreshMutationOptions(recipeId)
    local options = { "All" }
    local recipe = cardCraftState.getRecipe(recipeId)
    local module = cardCraftState.Module
    if recipe and module and type(module.ComputeMutationChances) == "function" then
        local ok, chances = pcall(module.ComputeMutationChances, recipe, {})
        if ok and type(chances) == "table" then
            for _, entry in ipairs(chances) do
                local mutation = entry.Mutation or entry.Name
                if mutation ~= nil and tostring(mutation) ~= "" then
                    table.insert(options, tostring(mutation))
                end
            end
        end
    end
    if #options == 1 then
        for _, mutation in ipairs(MUTATIONS) do
            table.insert(options, mutation)
        end
    end
    cardCraftState.MutationOptions = options
    return options
end

function cardCraftState.normalizeMutations(value)
    local values = type(value) == "table" and value or { value }
    local selected = {}
    local seen = {}
    for _, mutation in ipairs(values) do
        mutation = tostring(mutation or "")
        if mutation == "All" then
            return { "All" }
        end
        if mutation ~= "" and not seen[mutation] then
            seen[mutation] = true
            table.insert(selected, mutation)
        end
    end
    return #selected > 0 and selected or { "All" }
end

function cardCraftState.now()
    return (tonumber(cardCraftState.ServerNow) or os.time())
        + (os.clock() - (tonumber(cardCraftState.LocalClock) or os.clock()))
end

function cardCraftState.formatDuration(seconds)
    local total = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local remainder = total % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainder)
end

function cardCraftState.amountFor(requirement)
    local amount = tonumber(requirement and requirement.Amount) or 1
    return math.max(1, math.floor(amount))
end

function cardCraftState.inventoryCounts()
    local now = os.clock()
    if now - cardCraftState.InventoryCacheAt < 0.75 then
        return cardCraftState.CachedInventory
    end

    local counts = {}
    for _, tool in ipairs(cardCraftState.availableCards()) do
        local cardName = tostring(tool:GetAttribute("CardName") or "")
        if cardName ~= "" then
            counts[cardName] = (counts[cardName] or 0) + 1
        end
    end
    cardCraftState.CachedInventory = counts
    cardCraftState.InventoryCacheAt = now
    return counts
end

function cardCraftState.updateStatus()
    local paragraph = cardCraftState.StatusParagraph
    if not paragraph or not paragraph.Set then return end

    local recipeId, recipe = cardCraftState.selectedRecipe()
    local job = cardCraftState.Job
    local cardName = (job and job.OutputCardName)
        or (recipe and recipe.OutputCardName)
        or Config.CardCraftCard
        or "No card selected"
    local lines = {}

    if cardCraftState.Active and type(job) == "table" then
        local now = cardCraftState.now()
        local startedAt = tonumber(job.StartedAt) or now
        local readyAt = tonumber(job.ReadyAt) or now
        local remaining = math.max(0, readyAt - now)
        local status = remaining <= 0 and "Ready to claim" or "Crafting"
        table.insert(lines, tostring(cardName) .. " - "
            .. cardCraftState.formatDuration(remaining) .. " - " .. status)

        local activeRecipe = recipe
        if not activeRecipe and recipeId then
            activeRecipe = cardCraftState.getRecipe(recipeId)
        end
        local inventory = cardCraftState.inventoryCounts()
        for index, requirement in ipairs(activeRecipe and activeRecipe.Requirements or {}) do
            local required = cardCraftState.amountFor(requirement)
            local owned = inventory[tostring(requirement.CardName or "")] or 0
            table.insert(lines, "Recipe " .. tostring(index) .. " - "
                .. tostring(requirement.CardName or "Card") .. " - "
                .. tostring(owned) .. "/" .. tostring(required))
        end
    else
        table.insert(lines, tostring(cardName)
            .. " - 00:00:00 - Idle")
        local inventory = cardCraftState.inventoryCounts()
        for index, requirement in ipairs(recipe and recipe.Requirements or {}) do
            local required = cardCraftState.amountFor(requirement)
            local owned = inventory[tostring(requirement.CardName or "")] or 0
            table.insert(lines, "Recipe " .. tostring(index) .. " - "
                .. tostring(requirement.CardName or "Card") .. " - "
                .. tostring(owned) .. "/" .. tostring(required))
        end
        table.insert(lines, "Target mutation: "
            .. table.concat(cardCraftState.normalizeMutations(
                Config.CardCraftMutations
            ), ", "))
        if cardCraftState.LastMessage then
            table.insert(lines, tostring(cardCraftState.LastMessage))
        end
    end

    local title = "Card Crafting"
    local content = table.concat(lines, "\n")
    if title == cardCraftState.LastStatusTitle
        and content == cardCraftState.LastStatusContent then
        return
    end

    cardCraftState.LastStatusTitle = title
    cardCraftState.LastStatusContent = content
    pcall(function()
        paragraph:Set({
            Title = title,
            Content = content,
        })
    end)
end

function cardCraftState.applyState(state)
    if type(state) ~= "table" then return end
    cardCraftState.Received = true
    cardCraftState.Active = state.Active == true
    cardCraftState.Job = type(state.Job) == "table" and state.Job or nil
    cardCraftState.ServerNow = tonumber(state.ServerNow) or os.time()
    cardCraftState.LocalClock = os.clock()
    if not cardCraftState.Active then
        cardCraftState.Claiming = false
    end
    cardCraftState.updateStatus()
end

function cardCraftState.availableCards()
    local result = {}
    local seen = {}
    local function collect(container)
        if not container then return end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and not seen[tool]
                and tool:GetAttribute("CardName") ~= nil
                and tool:GetAttribute("GiftPending") ~= true
                and tool:GetAttribute("InventoryOpLock") ~= true
                and tool:GetAttribute("BeingPlaced") ~= true
                and tool:GetAttribute("BeingSold") ~= true then
                seen[tool] = true
                table.insert(result, tool)
            end
        end
    end
    collect(player:FindFirstChild("Backpack"))
    collect(player.Character)
    return result
end

function cardCraftState.buildSelections(recipe)
    if not recipe or type(recipe.Requirements) ~= "table" then
        return nil, "Invalid recipe."
    end

    local byName = {}
    for _, tool in ipairs(cardCraftState.availableCards()) do
        local name = tostring(tool:GetAttribute("CardName") or "")
        byName[name] = byName[name] or {}
        table.insert(byName[name], tool)
    end

    local selections = {}
    local missing = {}
    for index, requirement in ipairs(recipe.Requirements) do
        local wanted = tostring(requirement.CardName or "")
        local available = byName[wanted] or {}
        local needed = cardCraftState.amountFor(requirement)
        if #available < needed then
            table.insert(missing, wanted .. " " .. tostring(#available)
                .. "/" .. tostring(needed))
        else
            selections[index] = {}
            for cardIndex = 1, needed do
                table.insert(selections[index], available[cardIndex])
            end
        end
    end
    if #missing > 0 then
        return nil, "Missing: " .. table.concat(missing, ", ")
    end
    return selections
end

function cardCraftState.requestState()
    local remote = cardCraftState.Remote
    if remote and remote:IsA("RemoteEvent") then
        pcall(function() remote:FireServer("RequestState") end)
    end
end

function cardCraftState.start()
    local remote = cardCraftState.Remote
    if not remote or not remote:IsA("RemoteEvent") then
        cardCraftState.LastMessage = "CardCraftRE was not found."
        return false
    end
    local recipeId, recipe = cardCraftState.selectedRecipe()
    if not recipe then
        cardCraftState.LastMessage = "Select a card to craft first."
        return false
    end
    local selections, reason = cardCraftState.buildSelections(recipe)
    if not selections then
        cardCraftState.LastMessage = reason
        return false
    end

    cardCraftState.Requesting = true
    cardCraftState.LastMessage = nil
    cardCraftState.InventoryCacheAt = 0
    pcall(function()
        remote:FireServer("StartCraft", {
            RecipeId = recipeId,
            Selections = selections,
        })
    end)
    task.delay(5, function()
        cardCraftState.Requesting = false
    end)
    return true
end

function cardCraftState.tryClaim()
    if not Config.AutoClaimCardCraft or not cardCraftState.Active
        or cardCraftState.Claiming or not cardCraftState.Job then
        return
    end
    local remaining = (tonumber(cardCraftState.Job.ReadyAt) or 0)
        - cardCraftState.now()
    if remaining > 0 then return end

    local remote = cardCraftState.Remote
    if not remote or not remote:IsA("RemoteEvent") then return end
    cardCraftState.Claiming = true
    pcall(function() remote:FireServer("Claim") end)
    task.delay(5, function()
        cardCraftState.Claiming = false
    end)
end

if cardCraftState.Remote and cardCraftState.Remote:IsA("RemoteEvent") then
    cardCraftState.Remote.OnClientEvent:Connect(function(eventName, payload)
        local data = type(payload) == "table" and payload or {}
        if eventName == "State" then
            cardCraftState.applyState(data)
        elseif eventName == "Started" then
            cardCraftState.Requesting = false
            if data.State then
                cardCraftState.applyState(data.State)
            else
                cardCraftState.requestState()
            end
        elseif eventName == "Claimed" then
            cardCraftState.Claiming = false
            if data.State then
                cardCraftState.applyState(data.State)
            else
                cardCraftState.requestState()
            end
        elseif eventName == "SkipApplied" then
            if data.State then cardCraftState.applyState(data.State) end
        elseif eventName == "Failed" then
            cardCraftState.Requesting = false
            cardCraftState.Claiming = false
            cardCraftState.LastMessage = tostring(data.Message or "Card craft request failed.")
        end
    end)
    task.delay(0.35, function() cardCraftState.requestState() end)
end

task.spawn(function()
    while true do
        task.wait(0.5)
        cardCraftState.updateStatus()
        if cardCraftState.Active then
            cardCraftState.tryClaim()
        elseif Config.AutoCardCraft and not cardCraftState.Requesting
            and os.clock() >= cardCraftState.NextAttemptAt then
            cardCraftState.NextAttemptAt = os.clock() + 1
            cardCraftState.start()
        end
    end
end)

-- ══════════════════════════════════════════════════════════════
--  Config Manager State & Helper Functions
-- ══════════════════════════════════════════════════════════════
-- Keep the complete UI/config construction in its own function scope.
-- Luau limits the number of local registers in the top-level chunk; without
-- this boundary the many UI controls added below make the whole script fail
-- during compilation with "Out of local registers".
function buildUserInterface()

-- Auto Remove Card is intentionally throttled to avoid scanning and
-- teleporting through the plot continuously.  Thirty minutes is the default
-- cleanup interval.
local AUTO_REMOVE_CARD_INTERVAL = 30 * 60

local AUTO_REMOVE_CARD_SLOT_OPTIONS = {
    "Slot 1-5",
    "Slot 6-10",
    "Slot 11-15",
    "Slot 16-20",
    "Slot 21-25",
    "Slot 26-30",
}

local function normalizeAutoRemoveCardSlot(value)
    if type(value) == "table" then value = value[1] end
    value = tostring(value or "")
    for _, option in ipairs(AUTO_REMOVE_CARD_SLOT_OPTIONS) do
        if value == option then return option end
    end
    return AUTO_REMOVE_CARD_SLOT_OPTIONS[1]
end

local function removeCardSlotsInRange(rangeLabel)
    local normalized = normalizeAutoRemoveCardSlot(rangeLabel)
    local firstSlot, lastSlot = string.match(
        normalized,
        "^Slot%s+(%d+)%-(%d+)$"
    )
    firstSlot = tonumber(firstSlot) or 1
    lastSlot = tonumber(lastSlot) or 5

    -- Reuse the same interaction, cooldown, teleport, and CardSlotRE
    -- fallback logic as the existing Remove All Cards action.
    return removeAllCards(lastSlot, firstSlot)
end

local ConfigManager = {
    ConfigName        = "",
    SelectedConfig    = nil,
    CurrentAutoload   = nil,
    IsLoading         = false,
    Dropdown          = nil,
    AutoloadParagraph = nil,
}

local CONFIG_ROOT   = "Jon Yuero Hub/Anime Card Farm"
local CONFIG_FOLDER = CONFIG_ROOT .. "/Settings"
local AUTOLOAD_FILE = CONFIG_ROOT .. "/autoload.json"

-- Check file system support
local FS_SUPPORTED = (
    type(makefolder) == "function" and
    type(isfolder)   == "function" and
    type(writefile)  == "function" and
    type(readfile)   == "function" and
    type(isfile)     == "function" and
    type(listfiles)  == "function" and
    type(delfile)    == "function"
)

local function sanitizeConfigName(name)
    name = tostring(name)
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub('[\\/:*?"<>|]', "_")
    name = name:gsub("%.%.", "_")
    name = name:gsub("^%.", ""):gsub("%.$", "")
    if #name > 40 then name = name:sub(1, 40) end
    return name
end

local function ensureConfigFolders()
    if not FS_SUPPORTED then return false end
    pcall(function()
        if not isfolder("Jon Yuero Hub")     then makefolder("Jon Yuero Hub")     end
        if not isfolder(CONFIG_ROOT)         then makefolder(CONFIG_ROOT)         end
        if not isfolder(CONFIG_FOLDER)       then makefolder(CONFIG_FOLDER)       end
    end)
    return true
end

-- Safely extract a plain string from whatever the dropdown callback returns
-- (Rayfield single-select sometimes still delivers a 1-element table)
local function resolveConfigName(v)
    if type(v) == "table" then
        v = v[1]
    end
    if type(v) ~= "string" then return nil end
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if v == "" then return nil end
    return v
end

local function buildSerializableConfig()
    return {
        AutoSpawnPack     = Config.AutoSpawnPack,
        SpawnDelay        = Config.SpawnDelay,
        AutoStopSpawn     = Config.AutoStopSpawn,
        AutoBuyMatching   = Config.AutoBuyMatching,
        AutoContinueSpawn = Config.AutoContinueSpawn,
        AutoCarryBox      = Config.AutoCarryBox,
        AutoSellBox       = Config.AutoSellBox,
        AutoSellDelay     = Config.AutoSellDelay,
        CardCraftRecipeId = Config.CardCraftRecipeId,
        CardCraftCard     = Config.CardCraftCard,
        CardCraftMutations = Config.CardCraftMutations,
        AutoCardCraft     = Config.AutoCardCraft,
        AutoClaimCardCraft = Config.AutoClaimCardCraft,
        SelectedRarities  = Config.SelectedRarities,
        SelectedMutations = Config.SelectedMutations,
        SelectedPacks     = Config.SelectedPacks,
        AutoUpgrade       = Config.AutoUpgrade,
        UpgradeDelay      = Config.UpgradeDelay,
        CardActionDelay   = Config.CardActionDelay,
        AutoTraitRoll     = Config.AutoTraitRoll,
        SelectedRankCards  = Config.SelectedRankCards,
        TargetRank         = Config.TargetRank,
        SelectedTraitCards = Config.SelectedTraitCards,
        TargetTraits       = Config.TargetTraits,
        RankUseGems        = Config.RankUseGems,
        RankUseCash        = Config.RankUseCash,
        AutoRankRoll       = Config.AutoRankRoll,
        AutoClaimPlaytime = Config.AutoClaimPlaytime,
        AutoClaimDaily    = Config.AutoClaimDaily,
        AutoPlacePack     = Config.AutoPlacePack,
        AutoOpenPack      = Config.AutoOpenPack,
        AutoTimePotion    = Config.AutoTimePotion,
        AutoBuyBoost      = Config.AutoBuyBoost,
        AutoUpgradeArtifact = Config.AutoUpgradeArtifact,
        AutoEquipArtifact = Config.AutoEquipArtifact,
        SelectedArtifactSlots = Config.SelectedArtifactSlots,
        SelectedArtifacts = Config.SelectedArtifacts,
        SelectedArtifactLevels = Config.SelectedArtifactLevels,
        AutoSellArtifacts = Config.AutoSellArtifacts,
        SelectedBossCard  = Config.SelectedBossCard,
        AutoEquipBossCard = Config.AutoEquipBossCard,
        AutoUpgradeBossCard = Config.AutoUpgradeBossCard,
        AutoRemoveCard    = Config.AutoRemoveCard,
        AutoRemoveCardSlot = Config.AutoRemoveCardSlot,
        FilteredSellMode  = Config.FilteredSellMode,
        FilteredSellCard  = Config.FilteredSellCard,
        FilteredSellMutation = Config.FilteredSellMutation,
        FilteredSellRanking = Config.FilteredSellRanking,
        FilteredSellTrait = Config.FilteredSellTrait,
        AutoFilteredSell  = Config.AutoFilteredSell,
        AutoInfinityEquip = Config.AutoInfinityEquip,
        AutoInfinityTower = Config.AutoInfinityTower,
        AutoInfinityHide  = Config.AutoInfinityHide,
        RaidDifficulties  = Config.RaidDifficulties,
        AutoRaidEquip     = Config.AutoRaidEquip,
        AutoRaid          = Config.AutoRaid,
        AutoRaidHide      = Config.AutoRaidHide,
        AutoTeamCardCycle = Config.AutoTeamCardCycle,
        AutoPotion        = Config.AutoPotion,
        SelectedPotions   = Config.SelectedPotions,
        SelectedBoosts    = Config.SelectedBoosts,
        AntiAfk           = Config.AntiAfk,
        UseCashReserve    = Config.UseCashReserve,
        CashReserve       = Config.CashReserve,
    }
end

local function configExists(name)
    if not FS_SUPPORTED then return false end
    return isfile(CONFIG_FOLDER .. "/" .. name .. ".json")
end

local function saveConfig(name, allowOverwrite)
    if not FS_SUPPORTED then
        Rayfield:Notify({
            Title    = "Unsupported Executor",
            Content  = "File storage is unavailable in this executor.",
            Duration = 5,
        })
        return false
    end
    ensureConfigFolders()
    local filePath = CONFIG_FOLDER .. "/" .. name .. ".json"
    if not allowOverwrite and isfile(filePath) then
        Rayfield:Notify({
            Title    = "Config Already Exists",
            Content  = name .. " already exists. Use Overwrite to replace it.",
            Duration = 4,
        })
        return false
    end
    local data = buildSerializableConfig()
    local HttpService = game:GetService("HttpService")
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then return false end
    pcall(writefile, filePath, encoded)
    return true
end

local function normalizeLoadedSelection(value)
    local values = type(value) == "table" and value or { value }
    local normalized = {}
    local seen = {}

    for _, option in ipairs(values) do
        option = tostring(option or "")
        option = option:gsub("^%s*(.-)%s*$", "%1")
        if option == "" or option == "Any" or option == "All" then
            return { "All" }
        end
        if not seen[option] then
            seen[option] = true
            table.insert(normalized, option)
        end
    end

    if #normalized == 0 then
        return { "All" }
    end
    return normalized
end

local function getAutoload()
    if not FS_SUPPORTED then return nil end
    if not isfile(AUTOLOAD_FILE) then return nil end
    local ok, raw = pcall(readfile, AUTOLOAD_FILE)
    if not ok or not raw or raw == "" then return nil end
    local HttpService = game:GetService("HttpService")
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(data) ~= "table" then return nil end
    local configName = data.config
    if type(configName) ~= "string" or configName == "" then return nil end
    return configName
end

local function refreshConfigList()
    if not FS_SUPPORTED then return end
    ensureConfigFolders()
    local files = {}
    pcall(function()
        files = listfiles(CONFIG_FOLDER) or {}
    end)
    local names = {}
    for _, filePath in ipairs(files) do
        local name = tostring(filePath):match("([^/\\]+)%.json$")
        if name then table.insert(names, name) end
    end
    table.sort(names)
    ConfigManager.ConfigNames = names

    if ConfigManager.Dropdown then
        -- Try Refresh (newer Rayfield) first, fall back to Set
        local ok = pcall(function()
            ConfigManager.Dropdown:Refresh(names, ConfigManager.SelectedConfig or "")
        end)
        if not ok then
            pcall(function()
                ConfigManager.Dropdown:Set(names)
            end)
        end
        -- Validate current selection still exists
        local current = ConfigManager.SelectedConfig
        if current then
            local found = false
            for _, n in ipairs(names) do
                if n == current then found = true ; break end
            end
            if not found then
                ConfigManager.SelectedConfig = nil
            end
        end
    end
end

local function loadConfig(name, isAutoload)
    if not FS_SUPPORTED then return false end
    if not name or name == "" then return false end
    local filePath = CONFIG_FOLDER .. "/" .. name .. ".json"
    if not isfile(filePath) then
        if not isAutoload then
            Rayfield:Notify({
                Title    = "Configuration Not Found",
                Content  = name .. " does not exist.",
                Duration = 4,
            })
        end
        return false
    end
    local ok, raw = pcall(readfile, filePath)
    if not ok or not raw or raw == "" then return false end
    local HttpService = game:GetService("HttpService")
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(data) ~= "table" then return false end

    ConfigManager.IsLoading = true

    local knownKeys = {
        "AutoSpawnPack", "SpawnDelay", "AutoStopSpawn", "AutoBuyMatching",
        "AutoCarryBox", "AutoSellBox", "AutoSellDelay",
        "CardCraftRecipeId", "CardCraftCard", "CardCraftMutations",
        "AutoCardCraft", "AutoClaimCardCraft",
        "SelectedRarities", "SelectedMutations", "SelectedPacks",
        "AutoUpgrade", "UpgradeDelay", "CardActionDelay",
        "AutoTraitRoll", "SelectedRankCards", "TargetRank",
        "SelectedTraitCards", "TargetTraits",
        "RankUseGems", "RankUseCash", "AutoRankRoll",
        "AutoClaimPlaytime", "AutoClaimDaily",
        "AutoPlacePack", "AutoOpenPack", "AutoTimePotion", "AutoBuyBoost",
        "AutoUpgradeArtifact", "AutoEquipArtifact", "SelectedArtifactSlots",
        "SelectedArtifacts", "SelectedArtifactLevels",
        "AutoSellArtifacts", "SelectedBossCard", "AutoEquipBossCard",
        "AutoUpgradeBossCard",
        "AutoRemoveCard", "AutoRemoveCardSlot",
        "FilteredSellMode", "FilteredSellCard",
        "FilteredSellMutation", "FilteredSellRanking", "FilteredSellTrait",
        "AutoFilteredSell",
        "AutoInfinityEquip", "AutoInfinityTower", "AutoInfinityHide",
        "RaidDifficulties", "AutoRaidEquip", "AutoRaid", "AutoRaidHide",
        "AutoTeamCardCycle", "AutoPotion", "SelectedPotions",
        "SelectedBoosts", "AntiAfk", "AutoContinueSpawn",
        "UseCashReserve", "CashReserve",
    }

    -- Older settings used Pack + Rarity for this feature. Do not silently
    -- turn an old filtered-sale profile into an unrestricted card sale.
    if data.FilteredSellCard == nil
        and (data.FilteredSellPack ~= nil or data.FilteredSellRarity ~= nil) then
        data.FilteredSellCard = "All"
        data.AutoFilteredSell = false
    end

    for _, key in ipairs(knownKeys) do
        if data[key] ~= nil then
            local value = data[key]
            if key == "SelectedPotions" then
                value = normalizeGeneralPotionSelection(value)
            end
            if key == "RaidDifficulties" then
                value = normalizeRaidDifficulties(value)
            end
            if key == "CardCraftMutations" then
                value = cardCraftState.normalizeMutations(value)
            end
            if key == "AutoRemoveCardSlot" then
                value = normalizeAutoRemoveCardSlot(value)
            end
            if key == "SelectedArtifacts" then
                value = collapseFullSelection(
                    value,
                    artifactState.ArtifactOptions
                )
            end
            if key == "SelectedArtifactSlots" then
                value = artifactState.normalizeArtifactSlotSelection(value)
            end
            if key == "SelectedArtifactLevels" then
                value = collapseFullSelection(
                    value,
                    artifactState.getArtifactLevelOptions()
                )
            end
            if key == "SelectedBossCard" then
                value = artifactState.getBossCardId(value)
            end
            if key == "FilteredSellCard"
                or key == "FilteredSellMutation"
                or key == "FilteredSellRanking"
                or key == "FilteredSellTrait" then
                value = normalizeLoadedSelection(value)
            end
            Config[key] = value
            local control = Controls[key]
            if control and control.Set then
                pcall(function() control:Set(value) end)
            end
        end
    end

    -- Loaded filter values must invalidate the conveyor filter cache too.
    markFilterCacheDirty()
    ConfigManager.IsLoading = false

    if not isAutoload then
        Rayfield:Notify({
            Title    = "Configuration Loaded",
            Content  = name .. " was loaded successfully.",
            Duration = 4,
        })
    end
    return true
end

local function deleteConfig(name)
    if not FS_SUPPORTED then return false end
    if not name or name == "" then return false end
    local filePath = CONFIG_FOLDER .. "/" .. name .. ".json"
    if not isfile(filePath) then return false end
    pcall(delfile, filePath)

    local currentAutoload = getAutoload()
    if currentAutoload == name then
        pcall(function()
            if isfile(AUTOLOAD_FILE) then
                delfile(AUTOLOAD_FILE)
            end
        end)
        ConfigManager.CurrentAutoload = nil
        if ConfigManager.AutoloadParagraph then
            pcall(function()
                ConfigManager.AutoloadParagraph:Set({
                    Title   = "Current Autoload",
                    Content = "None",
                })
            end)
        end
    end
    return true
end

local function setAutoload(name)
    if not FS_SUPPORTED then return false end
    if not name or name == "" then return false end
    local filePath = CONFIG_FOLDER .. "/" .. name .. ".json"
    if not isfile(filePath) then return false end
    ensureConfigFolders()
    local HttpService = game:GetService("HttpService")
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, { config = name })
    if not ok then return false end
    pcall(writefile, AUTOLOAD_FILE, encoded)
    ConfigManager.CurrentAutoload = name
    if ConfigManager.AutoloadParagraph then
        pcall(function()
            ConfigManager.AutoloadParagraph:Set({
                Title   = "Current Autoload",
                Content = name,
            })
        end)
    end
    return true
end

local function resetAutoload()
    if not FS_SUPPORTED then return end
    pcall(function()
        if isfile(AUTOLOAD_FILE) then
            delfile(AUTOLOAD_FILE)
        end
    end)
    ConfigManager.CurrentAutoload = nil
    if ConfigManager.AutoloadParagraph then
        pcall(function()
            ConfigManager.AutoloadParagraph:Set({
                Title   = "Current Autoload",
                Content = "None",
            })
        end)
    end
end

-- ══════════════════════════════════════════════════════════════
--  Rayfield Window
-- ══════════════════════════════════════════════════════════════
local windowTitle = isPremium
    and "👑 Jon Yuero Hub | Anime Card Farm"
    or  "Jon Yuero Hub | Anime Card Farm"

local Window = Rayfield:CreateWindow({
    Name            = windowTitle,
    LoadingTitle    = "Anime Card Farm",
    LoadingSubtitle = "Loading...",
    Icon            = 0,
    ConfigurationSaving = {
        Enabled = false,
    },
    Discord   = { Enabled = false },
    KeySystem = false,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 1 – Auto Spawn Pack
-- ══════════════════════════════════════════════════════════════
local spawnTab = Window:CreateTab("🃏 Auto Spawn Pack", 0)

spawnTab:CreateSection("Spawn Manager")

Controls.AutoSpawnPack = spawnTab:CreateToggle({
    Name         = "Auto Spawn Pack",
    CurrentValue = Config.AutoSpawnPack,
    Flag         = "AutoSpawnPack",
    Callback     = function(v)
        Config.AutoSpawnPack = v
        if v then autoStopHandled = false end   -- reset guard on manual re-enable
    end,
})

Controls.SpawnDelay = spawnTab:CreateSlider({
    Name         = "How Fast to Spawn (s)",
    Range        = { 0.05, 10 },
    Increment    = 0.05,
    Suffix       = "s",
    CurrentValue = Config.SpawnDelay,
    Flag         = "SpawnDelay",
    Callback     = function(v) Config.SpawnDelay = v end,
})

Controls.AutoStopSpawn = spawnTab:CreateToggle({
    Name         = "Auto Stop Spawn (on Filter Match)",
    CurrentValue = Config.AutoStopSpawn,
    Flag         = "AutoStopSpawn",
    Callback     = function(v) Config.AutoStopSpawn = v end,
})

Controls.AutoBuyMatching = spawnTab:CreateToggle({
    Name         = "Auto Buy Pack",
    CurrentValue = Config.AutoBuyMatching,
    Flag         = "AutoBuyMatching",
    Callback     = function(v)
        Config.AutoBuyMatching = v
        if v and reevaluateAutoBuy then
            reevaluateAutoBuy(true)
        end
    end,
})

Controls.AutoContinueSpawn = spawnTab:CreateToggle({
    Name         = "Auto Continue",
    CurrentValue = Config.AutoContinueSpawn,
    Flag         = "AutoContinueSpawn",
    Callback     = function(v) Config.AutoContinueSpawn = v end,
})

spawnTab:CreateSection("Filters")

local packOptions = { "Any" }
for _, p in ipairs(PACKS) do table.insert(packOptions, p) end

Controls.SelectedPacks = spawnTab:CreateDropdown({
    Name          = "Pack",
    Options       = packOptions,
    CurrentOption = #Config.SelectedPacks > 0
        and Config.SelectedPacks
        or { "Any" },
    MultipleOptions = true,
    Flag          = "FilterPack",
    Callback      = function(v)
        Config.SelectedPacks = type(v) == "table" and v or { v }
        markFilterCacheDirty()
    end,
})

local rarityOptions = { "Any" }
for _, rarity in ipairs(RARITIES) do table.insert(rarityOptions, rarity) end

Controls.SelectedRarities = spawnTab:CreateDropdown({
    Name          = "Rarity",
    Options       = rarityOptions,
    CurrentOption = #Config.SelectedRarities > 0
        and Config.SelectedRarities
        or { "Any" },
    MultipleOptions = true,
    Flag          = "RarityFilter",
    Callback      = function(v)
        Config.SelectedRarities = type(v) == "table" and v or { v }
        markFilterCacheDirty()
    end,
})

local mutationOptions = { "Any" }
for _, mutation in ipairs(MUTATIONS) do table.insert(mutationOptions, mutation) end

Controls.SelectedMutations = spawnTab:CreateDropdown({
    Name          = "Mutation",
    Options       = mutationOptions,
    CurrentOption = #Config.SelectedMutations > 0
        and Config.SelectedMutations
        or { "Any" },
    MultipleOptions = true,
    Flag          = "MutationFilter",
    Callback      = function(v)
        Config.SelectedMutations = type(v) == "table" and v or { v }
        markFilterCacheDirty()
    end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 2 – Cards
-- ══════════════════════════════════════════════════════════════
local cardsTab = Window:CreateTab("🃏 Cards", 0)

cardsTab:CreateSection("Card Management")

cardsTab:CreateParagraph({
    Title   = "Auto Place Pack Filter",
    Content = "Uses the same Pack / Rarity / Mutation filters set in the Auto Spawn Pack tab.",
})

cardsTab:CreateToggle({
    Name         = "Auto Place Pack",
    CurrentValue = Config.AutoPlacePack,
    Flag         = "AutoPlacePack",
    Callback     = function(v) Config.AutoPlacePack = v end,
})

cardsTab:CreateToggle({
    Name         = "Auto Open Pack",
    CurrentValue = Config.AutoOpenPack,
    Flag         = "AutoOpenPack",
    Callback     = function(v) Config.AutoOpenPack = v end,
})

Controls.AutoTimePotion = cardsTab:CreateToggle({
    Name         = "Auto Use Time Potion",
    CurrentValue = Config.AutoTimePotion,
    Flag         = "AutoTimePotion",
    Callback     = function(v) Config.AutoTimePotion = v end,
})

cardsTab:CreateButton({
    Name     = "Equip Best Cards",
    Callback = function()
        local ok = fireRemote("CardSlotRE", "EquipBest")
        notify(
            "Equip Best Cards",
            ok and "Equip Best request sent." or "Could not send Equip Best request."
        )
    end,
})

cardsTab:CreateSlider({
    Name         = "Remove / Place / Open Delay (s)",
    Range        = { 0.5, 5 },
    Increment    = 0.1,
    Suffix       = "s",
    CurrentValue = Config.CardActionDelay,
    Flag         = "CardActionDelay",
    Callback     = function(v) Config.CardActionDelay = math.max(0.5, v) end,
})

cardsTab:CreateSection("Auto Remove Card")

cardsTab:CreateButton({
    Name     = "Remove All Cards",
    Callback = function()
        task.spawn(function()
            local removed = removeAllCards()
            notify("Remove All Cards", "Removed " .. tostring(removed) .. " card(s).")
        end)
    end,
})

Controls.AutoRemoveCardSlot = cardsTab:CreateDropdown({
    Name            = "Slot Range",
    Options         = AUTO_REMOVE_CARD_SLOT_OPTIONS,
    CurrentOption   = normalizeAutoRemoveCardSlot(Config.AutoRemoveCardSlot),
    MultipleOptions = false,
    Flag            = "AutoRemoveCardSlot",
    Callback        = function(v)
        Config.AutoRemoveCardSlot = normalizeAutoRemoveCardSlot(v)
    end,
})

Controls.AutoRemoveCard = cardsTab:CreateToggle({
    Name         = "Auto Remove Card",
    CurrentValue = Config.AutoRemoveCard,
    Flag         = "AutoRemoveCard",
    Callback     = function(v) Config.AutoRemoveCard = v end,
})

task.spawn(function()
    local nextAutoRemoveAt = os.clock() + AUTO_REMOVE_CARD_INTERVAL
    while true do
        task.wait(1)
        if not Config.AutoRemoveCard then
            -- Start a fresh full interval whenever the toggle is re-enabled.
            nextAutoRemoveAt = os.clock() + AUTO_REMOVE_CARD_INTERVAL
            continue
        end

        local now = os.clock()
        if now < nextAutoRemoveAt then continue end

        local ok, removed = pcall(function()
            return removeCardSlotsInRange(Config.AutoRemoveCardSlot)
        end)
        if ok and removed > 0 then
            notify(
                "Auto Remove Card",
                "Removed " .. tostring(removed) .. " card(s) from "
                    .. normalizeAutoRemoveCardSlot(Config.AutoRemoveCardSlot)
            )
        elseif not ok then
            warn("[ACF] Auto Remove Card failed: " .. tostring(removed))
        end

        nextAutoRemoveAt = os.clock() + AUTO_REMOVE_CARD_INTERVAL
    end
end)

cardsTab:CreateSection("Upgrade")

Controls.AutoUpgrade = cardsTab:CreateToggle({
    Name         = "Auto Upgrade Cards",
    CurrentValue = Config.AutoUpgrade,
    Flag         = "AutoUpgrade",
    Callback     = function(v) Config.AutoUpgrade = v end,
})

Controls.UpgradeDelay = cardsTab:CreateSlider({
    Name         = "Upgrade Delay (s)",
    Range        = { 0, 5 },
    Increment    = 0.05,
    Suffix       = "s",
    CurrentValue = Config.UpgradeDelay,
    Flag         = "UpgradeDelay",
    Callback     = function(v) Config.UpgradeDelay = v end,
})

local sellConfirmationGui

local function closeSellConfirmation()
    if sellConfirmationGui then
        pcall(function() sellConfirmationGui:Destroy() end)
        sellConfirmationGui = nil
    end
end

local function confirmSellAction(label, action, onConfirmed, customMessage)
    closeSellConfirmation()

    local messageByAction = {
        SellAll = "Are you sure you want to sell all?",
        SellCards = "Are you sure you want to sell all cards?",
        SellPacks = "Are you sure you want to sell all packs?",
    }

    local confirmationGui = Instance.new("ScreenGui")
    confirmationGui.Name = "JYH_SellConfirmation"
    confirmationGui.DisplayOrder = 10000
    confirmationGui.ResetOnSpawn = false
    confirmationGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    confirmationGui.Parent = playerGui
    sellConfirmationGui = confirmationGui

    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.45
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Parent = confirmationGui

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromOffset(360, 170)
    panel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    panel.BorderSizePixel = 0
    panel.Parent = overlay

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 10)
    panelCorner.Parent = panel

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(20, 16)
    title.Size = UDim2.new(1, -40, 0, 28)
    title.Font = Enum.Font.GothamBold
    title.Text = "Confirm sale"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 20
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    local message = Instance.new("TextLabel")
    message.Name = "Message"
    message.BackgroundTransparency = 1
    message.Position = UDim2.fromOffset(20, 52)
    message.Size = UDim2.new(1, -40, 0, 40)
    message.Font = Enum.Font.Gotham
    message.Text = customMessage
        or messageByAction[action]
        or ("Are you sure you want to " .. label .. "?")
    message.TextColor3 = Color3.fromRGB(220, 220, 225)
    message.TextSize = 16
    message.TextWrapped = true
    message.TextXAlignment = Enum.TextXAlignment.Left
    message.Parent = panel

    local function makeButton(name, text, color, position)
        local button = Instance.new("TextButton")
        button.Name = name
        button.Position = position
        button.Size = UDim2.fromOffset(145, 38)
        button.BackgroundColor3 = color
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.Text = text
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.TextSize = 16
        button.Parent = panel

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 7)
        corner.Parent = button
        return button
    end

    local noButton = makeButton(
        "No",
        "No",
        Color3.fromRGB(75, 75, 85),
        UDim2.new(0, 20, 1, -54)
    )
    local yesButton = makeButton(
        "Yes",
        "Yes",
        Color3.fromRGB(205, 65, 75),
        UDim2.new(1, -165, 1, -54)
    )

    local finished = false
    local function finish(confirmed)
        if finished then return end
        finished = true
        closeSellConfirmation()
        if not confirmed then return end

        if onConfirmed then
            local ok, err = pcall(onConfirmed)
            if not ok then
                warn("[ACF] " .. label .. " failed: " .. tostring(err))
                notify(label, "Could not enable filtered selling.")
            end
            return
        end

        local ok = fireRemote("SellRE", action)
        notify(
            label,
            ok and "Sell request sent." or "Could not send sell request."
        )
    end

    yesButton.Activated:Connect(function() finish(true) end)
    noButton.Activated:Connect(function() finish(false) end)
end

cardsTab:CreateSection("Sell")

cardsTab:CreateButton({
    Name     = "Auto Sell All",
    Callback = function()
        confirmSellAction("Auto Sell All", "SellAll")
    end,
})

cardsTab:CreateButton({
    Name     = "Auto Sell Cards",
    Callback = function()
        confirmSellAction("Auto Sell Cards", "SellCards")
    end,
})

cardsTab:CreateButton({
    Name     = "Auto Sell Packs",
    Callback = function()
        confirmSellAction("Auto Sell Packs", "SellPacks")
    end,
})

cardsTab:CreateButton({
    Name     = "Auto Sell on Hand",
    Callback = function()
        local ok = fireRemote("SellRE", "SellHand")
        notify(
            "Auto Sell on Hand",
            ok and "Sell request sent." or "Could not send sell request."
        )
    end,
})

cardsTab:CreateSection("Auto Sell Cards")

local function resolveFilteredSellValue(value, fallback)
    if type(value) == "table" then
        value = value[1]
    end
    value = tostring(value or "")
    if value == "" or value == "Any" then
        return fallback
    end
    return value
end

local filteredSellCardOptions = { "All" }
for _, cardName in ipairs(cardCraftState.IndexCards) do
    table.insert(filteredSellCardOptions, cardName)
end

local function refreshFilteredSellCardOptions(query)
    local queryKey = filterCompareKey(query)
    if queryKey == "" then queryKey = nil end

    local selected = normalizeLoadedSelection(Config.FilteredSellCard)
    local selectedKeys = {}
    for _, cardName in ipairs(selected) do
        local cardKey = filterCompareKey(cardName)
        if cardKey then selectedKeys[cardKey] = true end
    end

    local options = { "All" }
    local added = { all = true }
    for _, cardName in ipairs(cardCraftState.IndexCards) do
        local cardKey = filterCompareKey(cardName)
        local matchesSearch = (
            not queryKey
            or (cardKey and string.find(cardKey, queryKey, 1, true))
            or selectedKeys[cardKey]
        )
        if cardKey and matchesSearch and not added[cardKey] then
            added[cardKey] = true
            table.insert(options, cardName)
        end
    end

    filteredSellCardOptions = options
    local dropdown = Controls.FilteredSellCard
    if dropdown and dropdown.Refresh then
        pcall(function()
            dropdown:Refresh(options)
            if dropdown.Set then dropdown:Set(selected) end
        end)
    end
end

local filteredSellMutationOptions = { "All" }
for _, mutationName in ipairs(MUTATIONS) do
    table.insert(filteredSellMutationOptions, mutationName)
end

local filteredSellRankingOptions = { "All" }
for _, rankingName in ipairs(getRankTargetOptions()) do
    table.insert(filteredSellRankingOptions, rankingName)
end

local filteredSellTraitOptions = { "All" }
for _, traitName in ipairs(getTraitOptions()) do
    table.insert(filteredSellTraitOptions, traitName)
end

Controls.FilteredSellMode = cardsTab:CreateDropdown({
    Name            = "Mode",
    Options         = { "Whitelist", "Blacklist" },
    CurrentOption   = resolveFilteredSellValue(
        Config.FilteredSellMode,
        "Whitelist"
    ),
    MultipleOptions = false,
    Flag            = "FilteredSellMode",
    Callback        = function(v)
        local mode = resolveFilteredSellValue(v, "Whitelist")
        if mode ~= "Blacklist" then mode = "Whitelist" end
        Config.FilteredSellMode = mode
    end,
})

Controls.FilteredSellCardSearch = cardsTab:CreateInput({
    Name                  = "Search Cards",
    CurrentValue          = "",
    PlaceholderText       = "Type a card name to filter the dropdown",
    RemoveTextAfterFocusLost = false,
    Callback              = function(text)
        refreshFilteredSellCardOptions(text)
    end,
})

Controls.FilteredSellCard = cardsTab:CreateDropdown({
    Name            = "Card",
    Options         = filteredSellCardOptions,
    CurrentOption   = normalizeLoadedSelection(Config.FilteredSellCard),
    MultipleOptions = true,
    Flag            = "FilteredSellCard",
    Callback        = function(v)
        Config.FilteredSellCard = normalizeLoadedSelection(v)
    end,
})

Controls.FilteredSellMutation = cardsTab:CreateDropdown({
    Name            = "Mutation",
    Options         = filteredSellMutationOptions,
    CurrentOption   = normalizeLoadedSelection(
        Config.FilteredSellMutation,
        "All"
    ),
    MultipleOptions = true,
    Flag            = "FilteredSellMutation",
    Callback        = function(v)
        Config.FilteredSellMutation = normalizeLoadedSelection(v)
    end,
})

Controls.FilteredSellRanking = cardsTab:CreateDropdown({
    Name            = "Ranking",
    Options         = filteredSellRankingOptions,
    CurrentOption   = normalizeLoadedSelection(
        Config.FilteredSellRanking,
        "All"
    ),
    MultipleOptions = true,
    Flag            = "FilteredSellRanking",
    Callback        = function(v)
        Config.FilteredSellRanking = normalizeLoadedSelection(v)
    end,
})

Controls.FilteredSellTrait = cardsTab:CreateDropdown({
    Name            = "Trait",
    Options         = filteredSellTraitOptions,
    CurrentOption   = normalizeLoadedSelection(Config.FilteredSellTrait),
    MultipleOptions = true,
    Flag            = "FilteredSellTrait",
    Callback        = function(v)
        Config.FilteredSellTrait = normalizeLoadedSelection(v)
    end,
})

local function filteredSellConfirmationMessage()
    if Config.FilteredSellMode == "Blacklist" then
        return "Are you sure you want to sell cards that do not match the filters?"
    end
    return "Are you sure you want to sell cards matching the filters?"
end

local updatingFilteredSellControl = false

Controls.AutoFilteredSell = cardsTab:CreateToggle({
    Name         = "Auto Sell Cards",
    CurrentValue = Config.AutoFilteredSell,
    Flag         = "AutoFilteredSell",
    Callback     = function(v)
        if updatingFilteredSellControl then return end
        if not v then
            Config.AutoFilteredSell = false
            return
        end

        -- Do not start selling until the user confirms this exact mode.
        Config.AutoFilteredSell = false
        if Controls.AutoFilteredSell and Controls.AutoFilteredSell.Set then
            updatingFilteredSellControl = true
            pcall(function() Controls.AutoFilteredSell:Set(false) end)
            updatingFilteredSellControl = false
        end

        confirmSellAction(
            "Auto Sell Cards",
            nil,
            function()
                Config.AutoFilteredSell = true
                if Controls.AutoFilteredSell
                    and Controls.AutoFilteredSell.Set then
                    updatingFilteredSellControl = true
                    pcall(function() Controls.AutoFilteredSell:Set(true) end)
                    updatingFilteredSellControl = false
                end
                notify("Auto Sell Cards", "Auto Sell Cards enabled.")
            end,
            filteredSellConfirmationMessage()
        )
    end,
})

task.spawn(function()
    while true do
        task.wait(0.75)
        if not Config.AutoFilteredSell then continue end

        local backpack = player:FindFirstChild("Backpack")
        local filteredCards = filteredSellState.getFilteredCards()
        for _, card in ipairs(filteredCards) do
            if not Config.AutoFilteredSell then break end
            if backpack and card.Parent == backpack then
                filteredSellState.sellCard(card)
                task.wait(math.max(0.5, Config.CardActionDelay))
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════════
--  TAB 3 – Box & Craft
-- ══════════════════════════════════════════════════════════════
local autoSellTab = Window:CreateTab("📦 Box & Craft", 0)

autoSellTab:CreateSection("Box Handling")

Controls.AutoCarryBox = autoSellTab:CreateToggle({
    Name         = "Auto Carry Box",
    CurrentValue = Config.AutoCarryBox,
    Flag         = "AutoCarryBox",
    Callback     = function(v) Config.AutoCarryBox = v end,
})

Controls.AutoSellBox = autoSellTab:CreateToggle({
    Name         = "Auto Sell Box",
    CurrentValue = Config.AutoSellBox,
    Flag         = "AutoSellBox",
    Callback     = function(v) Config.AutoSellBox = v end,
})

Controls.AutoSellDelay = autoSellTab:CreateSlider({
    Name         = "Carry & Sell Interval (s)",
    Range        = { 1, 60 },
    Increment    = 1,
    Suffix       = "s",
    CurrentValue = Config.AutoSellDelay,
    Flag         = "AutoSellDelay",
    Callback     = function(v) Config.AutoSellDelay = v end,
})

autoSellTab:CreateSection("Card Crafting")

local cardCraftCardOptions = cardCraftState.refreshRecipes()
local cardCraftInitialCard = Config.CardCraftCard
if type(cardCraftInitialCard) ~= "string" or cardCraftInitialCard == ""
    or not cardCraftState.RecipeMap[string.lower(cardCraftInitialCard)] then
    cardCraftInitialCard = cardCraftCardOptions[1]
    if cardCraftInitialCard == "No recipes found" then
        cardCraftInitialCard = ""
    end
    Config.CardCraftCard = cardCraftInitialCard
end

local cardCraftInitialEntry = cardCraftState.RecipeMap[
    string.lower(tostring(cardCraftInitialCard or ""))
]
if cardCraftInitialEntry then
    Config.CardCraftRecipeId = cardCraftInitialEntry.Id
end
cardCraftState.refreshMutationOptions(Config.CardCraftRecipeId)

cardCraftState.StatusParagraph = autoSellTab:CreateParagraph({
    Title   = "Card Crafting",
    Content = "Loading Card Craft state...",
})
cardCraftState.updateStatus()

Controls.CardCraftCard = autoSellTab:CreateDropdown({
    Name          = "Select Card",
    Options       = cardCraftCardOptions,
    CurrentOption = cardCraftInitialCard ~= "" and cardCraftInitialCard
        or cardCraftCardOptions[1],
    MultipleOptions = false,
    Flag          = "CardCraftCard",
    Callback      = function(value)
        if type(value) == "table" then value = value[1] end
        local cardName = tostring(value or "")
        local entry = cardCraftState.RecipeMap[string.lower(cardName)]
        if not entry then return end
        Config.CardCraftCard = entry.CardName
        Config.CardCraftRecipeId = entry.Id
        cardCraftState.SelectedRecipeId = entry.Id
        local mutationOptions = cardCraftState.refreshMutationOptions(entry.Id)
        Config.CardCraftMutations = { "All" }
        if Controls.CardCraftMutation and Controls.CardCraftMutation.Refresh then
            pcall(function()
                Controls.CardCraftMutation:Refresh(mutationOptions, { "All" })
            end)
        end
        if Controls.CardCraftMutation and Controls.CardCraftMutation.Set then
            pcall(function() Controls.CardCraftMutation:Set({ "All" }) end)
        end
        cardCraftState.updateStatus()
    end,
})

local cardCraftMutationOptions = cardCraftState.MutationOptions
local cardCraftInitialMutations = cardCraftState.normalizeMutations(
    Config.CardCraftMutations
)
Controls.CardCraftMutation = autoSellTab:CreateDropdown({
    Name          = "Mutation",
    Options       = cardCraftMutationOptions,
    CurrentOption = cardCraftInitialMutations,
    MultipleOptions = true,
    Flag          = "CardCraftMutations",
    Callback      = function(value)
        Config.CardCraftMutations = cardCraftState.normalizeMutations(value)
    end,
})

Controls.AutoCardCraft = autoSellTab:CreateToggle({
    Name         = "Auto Craft",
    CurrentValue = Config.AutoCardCraft,
    Flag         = "AutoCardCraft",
    Callback     = function(value)
        Config.AutoCardCraft = value == true
        if Config.AutoCardCraft then
            cardCraftState.LastMessage = nil
            cardCraftState.NextAttemptAt = 0
            if not cardCraftState.Remote then
                Config.AutoCardCraft = false
                if Controls.AutoCardCraft and Controls.AutoCardCraft.Set then
                    pcall(function() Controls.AutoCardCraft:Set(false) end)
                end
                notify("Card Crafting", "CardCraftRE was not found.")
            end
        end
    end,
})

Controls.AutoClaimCardCraft = autoSellTab:CreateToggle({
    Name         = "Auto Claim",
    CurrentValue = Config.AutoClaimCardCraft,
    Flag         = "AutoClaimCardCraft",
    Callback     = function(value)
        Config.AutoClaimCardCraft = value == true
    end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 4 – Combat
-- ══════════════════════════════════════════════════════════════
local combatTab = Window:CreateTab("⚔️ Combat", 0)

combatTab:CreateSection("Infinity Tower")

combatTab:CreateToggle({
    Name         = "Auto Equip Best Card",
    CurrentValue = Config.AutoInfinityEquip,
    Flag         = "AutoInfinityEquip",
    Callback     = function(v) Config.AutoInfinityEquip = v end,
})

Controls.AutoInfinityTower = combatTab:CreateToggle({
    Name         = "Auto Infinity Tower",
    CurrentValue = Config.AutoInfinityTower,
    Flag         = "AutoInfinityTower",
    Callback     = function(v) Config.AutoInfinityTower = v end,
})

combatTab:CreateToggle({
    Name         = "Auto Hide Battle",
    CurrentValue = Config.AutoInfinityHide,
    Flag         = "AutoInfinityHide",
    Callback     = function(v) Config.AutoInfinityHide = v end,
})

combatTab:CreateSection("Boss Raid")

raidState.InfoParagraph = combatTab:CreateParagraph({
    Title   = "Boss Raid",
    Content = "Loading Boss Raid information...",
})
raidState.UpdateInfoDisplay(Config.RaidDifficulties)

Controls.RaidDifficulties = combatTab:CreateDropdown({
    Name          = "Select Difficulty",
    Options       = raidState.DifficultyOptions,
    CurrentOption = Config.RaidDifficulties[1]
        or raidState.DifficultyOptions[1]
        or "Normal",
    MultipleOptions = false,
    Flag          = "RaidDifficulties",
    Callback      = function(v)
        local selected = normalizeRaidDifficulties(v)
        if #selected == 0 then
            selected = { raidState.DifficultyOptions[1] }
        end
        Config.RaidDifficulties = selected
        clearCompletedRaidDifficulties()
        raidState.ShowRequirement(selected)
    end,
})

combatTab:CreateToggle({
    Name         = "Auto Equip Best Card",
    CurrentValue = Config.AutoRaidEquip,
    Flag         = "AutoRaidEquip",
    Callback     = function(v) Config.AutoRaidEquip = v end,
})

Controls.AutoRaid = combatTab:CreateToggle({
    Name         = "Auto Boss Raid",
    CurrentValue = Config.AutoRaid,
    Flag         = "AutoRaid",
    Callback     = function(v)
        Config.AutoRaid = v
        if v then
            clearCompletedRaidDifficulties()
        end
    end,
})

combatTab:CreateToggle({
    Name         = "Auto Hide Battle",
    CurrentValue = Config.AutoRaidHide,
    Flag         = "AutoRaidHide",
    Callback     = function(v) Config.AutoRaidHide = v end,
})

combatTab:CreateSection("My Team Card")

combatTab:CreateParagraph({
    Title   = "How it works",
    Content = "When enabled, cards are removed from the first four slots and the strongest available cards are equipped only before starting an Auto Boss Raid or Auto Infinity Tower battle.",
})

combatTab:CreateToggle({
    Name         = "Auto Remove / Equip Best Card",
    CurrentValue = Config.AutoTeamCardCycle,
    Flag         = "AutoTeamCardCycle",
    Callback     = function(v) Config.AutoTeamCardCycle = v end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 5 – Reroll
-- ══════════════════════════════════════════════════════════════
local rerollTab = Window:CreateTab("🔄 Reroll", 0)

rerollTab:CreateParagraph({
    Title   = "⚠️ Before You Reroll",
    Content = "Do not hold or equip a card while rerolling is active. Held or equipped cards are skipped entirely.",
})

rerollTab:CreateSection("Card Ranking")

local initialRankCardOptions, initialRankCardMap = buildRankCardOptions()
rankCardOptionMap = initialRankCardMap
rankCardOptions = initialRankCardOptions

rankCardDropdown = rerollTab:CreateDropdown({
    Name            = "Select Card",
    Options         = initialRankCardOptions,
    CurrentOption   = Config.SelectedRankCards,
    MultipleOptions = true,
    Flag            = "SelectedRankCards",
    Callback        = function(v)
        Config.SelectedRankCards = collapseFullSelection(v, rankCardOptions)
    end,
})

local rankOptions = getRankTargetOptions()
-- Migrate legacy string to table and validate each entry.
if type(Config.TargetRank) == "string" then
    Config.TargetRank = Config.TargetRank ~= "" and { Config.TargetRank } or {}
end
if type(Config.TargetRank) ~= "table" then Config.TargetRank = {} end
local validRankSet = {}
for _, r in ipairs(rankOptions) do validRankSet[r] = true end
local validTargets = {}
for _, r in ipairs(Config.TargetRank) do
    if validRankSet[r] then table.insert(validTargets, r) end
end
Config.TargetRank = validTargets

Controls.TargetRank = rerollTab:CreateDropdown({
    Name            = "Target Ranking",
    Options         = rankOptions,
    CurrentOption   = Config.TargetRank,
    MultipleOptions = true,
    Flag            = "TargetRank",
    Callback        = function(v)
        if type(v) == "string" then v = { v } end
        Config.TargetRank = (type(v) == "table" and #v > 0) and v or {}
    end,
})

Controls.RankUseGems = rerollTab:CreateToggle({
    Name         = "Use Gems",
    CurrentValue = Config.RankUseGems,
    Flag         = "RankUseGems",
    Callback     = function(v) Config.RankUseGems = v end,
})

Controls.RankUseCash = rerollTab:CreateToggle({
    Name         = "Use Cash",
    CurrentValue = Config.RankUseCash,
    Flag         = "RankUseCash",
    Callback     = function(v) Config.RankUseCash = v end,
})

Controls.AutoRankRoll = rerollTab:CreateToggle({
    Name         = "Start Reroll",
    CurrentValue = Config.AutoRankRoll,
    Flag         = "AutoRankRoll",
    Callback     = function(v)
        Config.AutoRankRoll = v
        if v and not GradeRollRE then
            Config.AutoRankRoll = false
            if Controls.AutoRankRoll and Controls.AutoRankRoll.Set then
                pcall(function() Controls.AutoRankRoll:Set(false) end)
            end
            notify("Card Ranking", "GradeRollRE was not found.")
        end
    end,
})

rerollTab:CreateSection("Traits")

local initialTraitCardOptions, initialTraitCardMap = buildTraitCardOptions()
traitCardOptionMap = initialTraitCardMap
traitCardOptions = initialTraitCardOptions

Controls.SelectedTraitCards = rerollTab:CreateDropdown({
    Name            = "Select Card",
    Options         = initialTraitCardOptions,
    CurrentOption   = collapseFullSelection(
        Config.SelectedTraitCards,
        initialTraitCardOptions
    ),
    MultipleOptions = true,
    Flag            = "SelectedTraitCards",
    Callback        = function(v)
        Config.SelectedTraitCards = collapseFullSelection(
            v,
            traitCardOptions
        )
    end,
})
traitCardDropdown = Controls.SelectedTraitCards

local traitOptions = getTraitOptions()
if type(Config.TargetTraits) == "string" then
    Config.TargetTraits = Config.TargetTraits ~= ""
        and { Config.TargetTraits }
        or {}
end
if type(Config.TargetTraits) ~= "table" then Config.TargetTraits = {} end
local validTraitSet = {}
for _, trait in ipairs(traitOptions) do validTraitSet[trait] = true end
local validTraitTargets = {}
for _, trait in ipairs(Config.TargetTraits) do
    if validTraitSet[tostring(trait)] then
        table.insert(validTraitTargets, tostring(trait))
    end
end
Config.TargetTraits = validTraitTargets

Controls.TargetTraits = rerollTab:CreateDropdown({
    Name            = "Target Trait",
    Options         = traitOptions,
    CurrentOption   = Config.TargetTraits,
    MultipleOptions = true,
    Flag            = "TargetTraits",
    Callback        = function(v)
        if type(v) == "string" then v = { v } end
        Config.TargetTraits = type(v) == "table" and v or {}
    end,
})

Controls.AutoTraitRoll = rerollTab:CreateToggle({
    Name         = "Start Reroll",
    CurrentValue = Config.AutoTraitRoll,
    Flag         = "AutoTraitRoll",
    Callback     = function(v)
        Config.AutoTraitRoll = v
        if v and not TraitRollRE then
            Config.AutoTraitRoll = false
            if Controls.AutoTraitRoll and Controls.AutoTraitRoll.Set then
                pcall(function() Controls.AutoTraitRoll:Set(false) end)
            end
            notify("Traits", "TraitRollRE was not found.")
        end
    end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 6 – Misc
-- ══════════════════════════════════════════════════════════════
local miscTab = Window:CreateTab("🧪 Misc", 0)

miscTab:CreateSection("Potions")

local potionOptions = { "All" }
for _, potion in ipairs(POTIONS) do
    table.insert(potionOptions, potion)
end

Controls.SelectedPotions = miscTab:CreateDropdown({
    Name            = "Select Potion",
    Options         = potionOptions,
    CurrentOption   = collapseFullSelection(Config.SelectedPotions, POTIONS),
    MultipleOptions = true,
    Flag            = "SelectedPotions",
    Callback        = function(v)
        Config.SelectedPotions = collapseFullSelection(v, POTIONS)
    end,
})

Controls.AutoPotion = miscTab:CreateToggle({
    Name         = "Auto Use Potions",
    CurrentValue = Config.AutoPotion,
    Flag         = "AutoPotion",
    Callback     = function(v) Config.AutoPotion = v end,
})

miscTab:CreateSection("Auto Buy Boost")

local boostOptions = {}
table.insert(boostOptions, "All")
for _, boost in ipairs(BOOSTS) do
    table.insert(boostOptions, boost.label)
end

Controls.SelectedBoosts = miscTab:CreateDropdown({
    Name            = "Boosts to Buy",
    Options         = boostOptions,
    CurrentOption   = collapseFullSelection(Config.SelectedBoosts, {
        "Base Expansion", "Luck Boost", "Cash Boost", "Time Boost", "Speed Boost",
    }),
    MultipleOptions = true,
    Flag            = "SelectedBoosts",
    Callback        = function(v)
        Config.SelectedBoosts = collapseFullSelection(v, {
            "Base Expansion", "Luck Boost", "Cash Boost", "Time Boost", "Speed Boost",
        })
    end,
})

miscTab:CreateToggle({
    Name         = "Auto Buy",
    CurrentValue = Config.AutoBuyBoost,
    Flag         = "AutoBuyBoost",
    Callback     = function(v) Config.AutoBuyBoost = v end,
})

miscTab:CreateSection("Artifacts")

artifactState.ArtifactSelectParagraph = miscTab:CreateParagraph({
    Title   = "Selected Artifacts",
    Content = "No artifacts selected. Selection order maps to ArtifactSlot1, ArtifactSlot2, and ArtifactSlot3.",
})
artifactState.refreshArtifactOptions()

Controls.SelectedArtifactSlots = miscTab:CreateDropdown({
    Name            = "Select Artifact",
    Options         = artifactState.ArtifactSelectionOptions,
    CurrentOption   = artifactState.normalizeArtifactSlotSelection(
        Config.SelectedArtifactSlots
    ),
    MultipleOptions = true,
    Flag            = "SelectedArtifactSlots",
    Callback        = function(v)
        Config.SelectedArtifactSlots =
            artifactState.normalizeArtifactSlotSelection(v)
        artifactState.refreshArtifactOptions()
        artifactState.updateArtifactSelectionInfo()
    end,
})
artifactState.ArtifactDropdown = Controls.SelectedArtifactSlots
artifactState.updateArtifactSelectionInfo()

Controls.AutoEquipArtifact = miscTab:CreateToggle({
    Name         = "Auto Equip Artifact",
    CurrentValue = Config.AutoEquipArtifact,
    Flag         = "AutoEquipArtifact",
    Callback     = function(v) Config.AutoEquipArtifact = v end,
})

Controls.AutoUpgradeArtifact = miscTab:CreateToggle({
    Name         = "Auto Upgrade Artifact",
    CurrentValue = Config.AutoUpgradeArtifact,
    Flag         = "AutoUpgradeArtifact",
    Callback     = function(v) Config.AutoUpgradeArtifact = v end,
})

miscTab:CreateSection("Auto Sell Artifacts")

Controls.SelectedArtifacts = miscTab:CreateDropdown({
    Name            = "Artifact Filter",
    Options         = artifactState.ArtifactOptions,
    CurrentOption   = Config.SelectedArtifacts,
    MultipleOptions = true,
    Flag            = "SelectedArtifacts",
    Callback        = function(v)
        Config.SelectedArtifacts = collapseFullSelection(
            v,
            artifactState.ArtifactOptions
        )
        artifactState.refreshArtifactOptions()
    end,
})
artifactState.ArtifactSellDropdown = Controls.SelectedArtifacts

local artifactLevelOptions = { "All" }
for _, level in ipairs(artifactState.getArtifactLevelOptions()) do
    table.insert(artifactLevelOptions, level)
end

Controls.SelectedArtifactLevels = miscTab:CreateDropdown({
    Name            = "Level Filter",
    Options         = artifactLevelOptions,
    CurrentOption   = collapseFullSelection(
        Config.SelectedArtifactLevels,
        artifactState.getArtifactLevelOptions()
    ),
    MultipleOptions = true,
    Flag            = "SelectedArtifactLevels",
    Callback        = function(v)
        Config.SelectedArtifactLevels = collapseFullSelection(
            v,
            artifactState.getArtifactLevelOptions()
        )
    end,
})

Controls.AutoSellArtifacts = miscTab:CreateToggle({
    Name         = "Auto Sell Artifacts",
    CurrentValue = Config.AutoSellArtifacts,
    Flag         = "AutoSellArtifacts",
    Callback     = function(v) Config.AutoSellArtifacts = v end,
})

miscTab:CreateSection("Boss Card")

local bossCardLabels = {}
local bossCardLabelById = {}
for _, card in ipairs(artifactState.getBossCards()) do
    table.insert(bossCardLabels, card.Label)
    bossCardLabelById[card.Id] = card.Label
end

local selectedBossCardId = artifactState.getBossCardId(Config.SelectedBossCard)
Config.SelectedBossCard = selectedBossCardId

Controls.SelectedBossCard = miscTab:CreateDropdown({
    Name            = "Select Boss Card",
    Options         = bossCardLabels,
    CurrentOption   = bossCardLabelById[selectedBossCardId],
    MultipleOptions = false,
    Flag            = "SelectedBossCard",
    Callback        = function(v)
        Config.SelectedBossCard = artifactState.getBossCardId(v)
    end,
})

Controls.AutoEquipBossCard = miscTab:CreateToggle({
    Name         = "Auto Equip Boss Card",
    CurrentValue = Config.AutoEquipBossCard,
    Flag         = "AutoEquipBossCard",
    Callback     = function(v) Config.AutoEquipBossCard = v end,
})

Controls.AutoUpgradeBossCard = miscTab:CreateToggle({
    Name         = "Auto Upgrade Boss Card",
    CurrentValue = Config.AutoUpgradeBossCard,
    Flag         = "AutoUpgradeBossCard",
    Callback     = function(v) Config.AutoUpgradeBossCard = v end,
})

miscTab:CreateSection("Anti-AFK")

Controls.AntiAfk = miscTab:CreateToggle({
    Name         = "Anti-AFK",
    CurrentValue = Config.AntiAfk,
    Flag         = "AntiAfk",
    Callback     = function(v) Config.AntiAfk = v end,
})

miscTab:CreateSection("Player Rewards")

miscTab:CreateToggle({
    Name         = "Auto Claim Playtime Rewards",
    CurrentValue = Config.AutoClaimPlaytime,
    Flag         = "AutoClaimPlaytime",
    Callback     = function(v) Config.AutoClaimPlaytime = v end,
})

miscTab:CreateToggle({
    Name         = "Auto Claim Daily Rewards",
    CurrentValue = Config.AutoClaimDaily,
    Flag         = "AutoClaimDaily",
    Callback     = function(v) Config.AutoClaimDaily = v end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 7 – Settings
-- ══════════════════════════════════════════════════════════════
local settingsTab = Window:CreateTab("⚙️ Settings", 0)

settingsTab:CreateSection("Configuration Manager")

-- Config Name input
settingsTab:CreateInput({
    Name                     = "Config Name",
    PlaceholderText          = "Enter configuration name...",
    RemoveTextAfterFocusLost = false,
    Flag                     = "ConfigManagerName",
    Callback                 = function(v)
        v = tostring(v):gsub("^%s+", ""):gsub("%s+$", "")
        ConfigManager.ConfigName = v
    end,
})

-- Save button
settingsTab:CreateButton({
    Name     = "Save",
    Callback = function()
        local rawName = ConfigManager.ConfigName or ""
        rawName = rawName:gsub("^%s+", ""):gsub("%s+$", "")
        local name = sanitizeConfigName(rawName)
        if name == "" then
            Rayfield:Notify({
                Title    = "Invalid Name",
                Content  = "Enter a valid configuration name.",
                Duration = 4,
            })
            return
        end
        if not FS_SUPPORTED then
            Rayfield:Notify({
                Title    = "Unsupported Executor",
                Content  = "File storage is unavailable in this executor.",
                Duration = 5,
            })
            return
        end
        -- saveConfig(name, false) = do NOT overwrite if already exists
        if saveConfig(name, false) then
            refreshConfigList()
            ConfigManager.SelectedConfig = name
            Rayfield:Notify({
                Title    = "Configuration Saved",
                Content  = name .. " was saved successfully.",
                Duration = 4,
            })
        end
    end,
})

-- Load initial config names for the dropdown
local function getInitialConfigNames()
    if not FS_SUPPORTED then return {} end
    ensureConfigFolders()
    local files = {}
    pcall(function() files = listfiles(CONFIG_FOLDER) or {} end)
    local names = {}
    for _, filePath in ipairs(files) do
        local name = tostring(filePath):match("([^/\\]+)%.json$")
        if name then table.insert(names, name) end
    end
    table.sort(names)
    return names
end

-- Select Config dropdown
ConfigManager.Dropdown = settingsTab:CreateDropdown({
    Name            = "Select Config",
    Options         = getInitialConfigNames(),
    CurrentOption   = {},
    MultipleOptions = false,
    Flag            = "ConfigManagerSelected",
    Callback        = function(v)
        -- Rayfield single-select may still deliver a table; normalize to string
        ConfigManager.SelectedConfig = resolveConfigName(v)
    end,
})

-- Refresh List button
settingsTab:CreateButton({
    Name     = "Refresh List",
    Callback = function()
        refreshConfigList()
        Rayfield:Notify({
            Title    = "Config List Refreshed",
            Content  = "The configuration list has been updated.",
            Duration = 3,
        })
    end,
})

-- Load button
settingsTab:CreateButton({
    Name     = "Load",
    Callback = function()
        local name = resolveConfigName(ConfigManager.SelectedConfig)
        if not name then
            Rayfield:Notify({
                Title    = "No Configuration Selected",
                Content  = "Select a saved configuration first.",
                Duration = 4,
            })
            return
        end
        loadConfig(name, false)
    end,
})

-- Overwrite button
settingsTab:CreateButton({
    Name     = "Overwrite",
    Callback = function()
        local name = resolveConfigName(ConfigManager.SelectedConfig)
        if not name then
            Rayfield:Notify({
                Title    = "No Configuration Selected",
                Content  = "Select a saved configuration first.",
                Duration = 4,
            })
            return
        end
        if not FS_SUPPORTED then
            Rayfield:Notify({
                Title    = "Unsupported Executor",
                Content  = "File storage is unavailable in this executor.",
                Duration = 5,
            })
            return
        end
        -- saveConfig(name, true) = allow overwrite
        if saveConfig(name, true) then
            refreshConfigList()
            Rayfield:Notify({
                Title    = "Configuration Overwritten",
                Content  = name .. " was overwritten successfully.",
                Duration = 4,
            })
        end
    end,
})

-- Delete button
settingsTab:CreateButton({
    Name     = "Delete",
    Callback = function()
        local name = resolveConfigName(ConfigManager.SelectedConfig)
        if not name then
            Rayfield:Notify({
                Title    = "No Configuration Selected",
                Content  = "Select a saved configuration first.",
                Duration = 4,
            })
            return
        end
        if deleteConfig(name) then
            ConfigManager.SelectedConfig = nil
            refreshConfigList()
            Rayfield:Notify({
                Title    = "Configuration Deleted",
                Content  = name .. " was deleted.",
                Duration = 4,
            })
        end
    end,
})

-- Set as Autoload button
settingsTab:CreateButton({
    Name     = "Set as Autoload",
    Callback = function()
        local name = resolveConfigName(ConfigManager.SelectedConfig)
        if not name then
            Rayfield:Notify({
                Title    = "No Configuration Selected",
                Content  = "Select a saved configuration first.",
                Duration = 4,
            })
            return
        end
        if not FS_SUPPORTED then
            Rayfield:Notify({
                Title    = "Unsupported Executor",
                Content  = "File storage is unavailable in this executor.",
                Duration = 5,
            })
            return
        end
        if setAutoload(name) then
            Rayfield:Notify({
                Title    = "Autoload Enabled",
                Content  = name .. " will load automatically.",
                Duration = 4,
            })
        end
    end,
})

-- Reset Autoload button
settingsTab:CreateButton({
    Name     = "Reset Autoload",
    Callback = function()
        resetAutoload()
        Rayfield:Notify({
            Title    = "Autoload Reset",
            Content  = "No configuration will load automatically.",
            Duration = 4,
        })
    end,
})

-- Current Autoload paragraph
ConfigManager.AutoloadParagraph = settingsTab:CreateParagraph({
    Title   = "Current Autoload",
    Content = "None",
})

-- ── Post-UI startup: refresh config list and run autoload ─────
task.spawn(function()
    if not FS_SUPPORTED then
        Rayfield:Notify({
            Title    = "Unsupported Executor",
            Content  = "File storage is unavailable. Config saving is disabled.",
            Duration = 6,
        })
        return
    end

    refreshConfigList()

    local autoloadName = getAutoload()
    if autoloadName and autoloadName ~= "" then
        ConfigManager.CurrentAutoload = autoloadName
        if ConfigManager.AutoloadParagraph then
            pcall(function()
                ConfigManager.AutoloadParagraph:Set({
                    Title   = "Current Autoload",
                    Content = autoloadName,
                })
            end)
        end
        task.wait(1)
        if loadConfig(autoloadName, true) then
            notify("Configuration Loaded", autoloadName .. " loaded automatically.")
        end
    end
end)

-- ── Done ─────────────────────────────────────────────────────
task.wait(1)
notify("Anime Card Farm", "Loaded! (" .. userRole .. ")")

end

buildUserInterface()
