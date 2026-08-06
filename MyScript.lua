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
local MY_SCRIPT_URL = "https://raw.githubusercontent.com/JonYuero/JYH-Test/refs/heads/main/MyScript.lua"

local VALID_LICENSE_TYPES = { FREE = true, ["30D"] = true, LIFETIME = true }

-- ── Environment ───────────────────────────────────────────────
local ENV = getgenv()

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

    -- 6. UserId must match
    local LocalPlayer = game:GetService("Players").LocalPlayer
    if session.userId ~= LocalPlayer.UserId then
        return false, "Session UserId does not match current player"
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
    if session.scriptUrl ~= nil and session.scriptUrl ~= MY_SCRIPT_URL then
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
local PlayTimeRewardRE = Remotes:FindFirstChild("PlayTimeRewardRE")
local DailyRewardRE    = Remotes:FindFirstChild("DailyRewardRE")
local UpgradesRE       = Remotes:FindFirstChild("UpgradesRE")
local BossRaidRE = Remotes:FindFirstChild("BossRaidRE")
local GradeRollRE      = Remotes:FindFirstChild("GradeRollRE")
local Modules    = ReplicatedStorage:FindFirstChild("Modules")
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
local currentRaidBossId = ""

-- ── Data lists ───────────────────────────────────────────────
local RARITIES = {
    "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Secret", "Divine",
    "Transcendent", "Shadow", "Emperor", "Demon",
    "Manga", "Celestial", "Heavenly", "Corrupted",
    "Striker", "Sacred", "Paradox", "Founder",
    "Evolved", "Magic", "Oni", "Chaos",
    "Ruin", "Limited",
}

local MUTATIONS = {
    "Normal", "Golden", "Venomous", "Diamond",
    "Rainbow", "Sakura", "Candy", "Blessed",
    "Radioactive", "Glitch", "Starfallen", "Admin", "Unknown",
}

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
    "Devour Pack",
}

local POTIONS = {
    "LuckPotion1", "LuckPotion2", "LuckPotion3",
    "CashPotion1", "CashPotion2", "CashPotion3",
    "TimePotion1", "TimePotion2",
    "MutationPotion1",
    "ProductionPotion1", "ProductionPotion2",
}

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
    PlotNumber      = 1,    -- will be overwritten by auto-detect at startup

    -- Filter
    SelectedRarities  = {},
    SelectedMutations = {},
    SelectedPacks     = {},

    -- Cards
    AutoUpgrade       = false,
    UpgradeDelay      = 0.15,
    CardActionDelay   = 0.6,
    AutoSell          = false,
    AutoTraitRoll     = false,
    SelectedRankCards = { "All" },
    TargetRank        = { "UR" },
    RankUseGems       = true,
    RankUseCash       = false,
    AutoRankRoll      = false,
    AutoClaimPlaytime = false,
    AutoClaimDaily    = false,
    AutoPlacePack     = false,
    AutoOpenPack      = false,
    AutoBuyBoost      = false,

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

-- Playtime state is pushed by the game's client remote.
local playtimeReadyRewards = {}
local playtimeStateReceived = false

-- Forward declarations
local clickGuiButton
local startCombatBattle
local removeAllCards
local removeFirstFourCardSlots
local doEquipBestCards

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

    local click = part:FindFirstChildOfClass("ClickDetector")
               or part:FindFirstChild("ClickDetector")
    if click then
        if fireclickdetector then
            pcall(fireclickdetector, click)
            return true
        end
        pcall(function() click.MouseClick:Fire(player.Character) end)
        return true
    end

    local prompt = part:FindFirstChildOfClass("ProximityPrompt")
    if prompt then
        if fireproximityprompt then
            pcall(fireproximityprompt, prompt)
            return true
        end
        if firetouchinterest then
            pcall(firetouchinterest, part, player.Character, 0)
            return true
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
    return string.lower(string.gsub(tostring(value), "^%s*(.-)%s*$", "%1"))
end

local function normalizeFilterSelection(value)
    local selected = {}

    if type(value) ~= "table" then
        value = value == nil and {} or { value }
    end

    local function add(option)
        local normalized = normalizeFilterValue(option)
        if normalized and normalized ~= "any" and normalized ~= "all" then
            selected[normalized] = true
        end
    end

    local hadArrayValues = false
    for _, option in ipairs(value) do
        hadArrayValues = true
        add(option)
    end
    if not hadArrayValues then
        for option, enabled in pairs(value) do
            if enabled then add(option) end
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

-- Decode compact cash strings like "$500.0K", "$159.83M", "$2.5B", "$1T".
-- Returns a number on success, nil on failure.
local function parseCompactCash(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub(",", ""):gsub("%s+", "")  -- strip commas and spaces
    text = text:gsub("^%$", "")                -- strip leading $
    if text == "" then return nil end

    local suffixMap = {
        k  = 1e3,  K  = 1e3,
        m  = 1e6,  M  = 1e6,
        b  = 1e9,  B  = 1e9,
        t  = 1e12, T  = 1e12,
        qa = 1e15, Qa = 1e15, QA = 1e15,
        qd = 1e15, Qd = 1e15, QD = 1e15,  -- alternate quadrillion spelling used by some games
        qi = 1e18, Qi = 1e18, QI = 1e18,
        sx = 1e21, Sx = 1e21, SX = 1e21,
        sp = 1e24, Sp = 1e24, SP = 1e24,
        oc = 1e27, Oc = 1e27, OC = 1e27,
        no = 1e30, No = 1e30, NO = 1e30,
        dc = 1e33, Dc = 1e33, DC = 1e33,
        ud = 1e36, Ud = 1e36, UD = 1e36,  -- undecillion
        dd = 1e39, Dd = 1e39, DD = 1e39,  -- duodecillion
        td = 1e42, Td = 1e42, TD = 1e42,  -- tredecillion
    }

    -- Try two-letter suffix first, then one-letter suffix, then plain number.
    local num, suffix2 = text:match("^([%d%.]+)([A-Za-z][A-Za-z])$")
    if num and suffix2 then
        local mult = suffixMap[suffix2] or suffixMap[suffix2:lower()]
        if mult then return (tonumber(num) or 0) * mult end
    end

    local num1, suffix1 = text:match("^([%d%.]+)([A-Za-z])$")
    if num1 and suffix1 then
        local mult = suffixMap[suffix1] or suffixMap[suffix1:lower()]
        if mult then return (tonumber(num1) or 0) * mult end
    end

    -- Plain number with no suffix.
    local plain = text:match("^([%d%.]+)$")
    if plain then return tonumber(plain) end

    return nil
end

-- Get the player's current exact cash as a number.
-- Primary source: Players.LocalPlayer.CashValue (NumberValue or IntValue).
-- Fallback: leaderstats.Cash text parsed through parseCompactCash.
local function getPlayerCash()
    local cv = player:FindFirstChild("CashValue")
    if cv and (cv:IsA("NumberValue") or cv:IsA("IntValue")) then
        return tonumber(cv.Value)
    end
    -- Fallback: try leaderstats.Cash as a numeric attribute or parsed text.
    local ls = player:FindFirstChild("leaderstats")
    local cashObj = ls and ls:FindFirstChild("Cash")
    if cashObj then
        if cashObj:IsA("NumberValue") or cashObj:IsA("IntValue") then
            return tonumber(cashObj.Value)
        end
        -- Try to parse formatted text like "$159.83M"
        local parsed = parseCompactCash(tostring(cashObj.Value or ""))
        if parsed then return parsed end
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

-- CONFIRMED GAME STRUCTURE (from screenshots):
--   packModel.GuiHolder.BillboardGuiInfo.Price   → TextLabel with Text "$500.0K"
--   packModel.GuiHolder.BillboardGuiInfo.Rarity  → child named after rarity (e.g. "Epic")
--   packModel.GuiHolder.BillboardGuiInfo.Mutation → child named after mutation (e.g. "Normal")

-- Get the raw price text from the pack's billboard GUI (used only as last resort).
local function getPackPriceText(packModel)
    if not packModel then return nil end
    local gui = packModel:FindFirstChild("GuiHolder")
    local info = gui and gui:FindFirstChild("BillboardGuiInfo")
    local priceContainer = info and info:FindFirstChild("Price")
    if priceContainer then
        -- Try TextLabel/TextButton text first (confirmed in screenshots).
        for _, child in ipairs(priceContainer:GetChildren()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                local t = tostring(child.Text or ""):gsub("^%s*(.-)%s*$", "%1")
                if t ~= "" then return t end
            end
        end
        -- The price container itself might be a TextLabel.
        if priceContainer:IsA("TextLabel") or priceContainer:IsA("TextButton") then
            local t = tostring(priceContainer.Text or ""):gsub("^%s*(.-)%s*$", "%1")
            if t ~= "" then return t end
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
    end

    -- 2. NumberValue / IntValue children (direct or one level deep).
    local function searchValueObjects(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("NumberValue") or child:IsA("IntValue") then
                local n = child.Name:lower()
                for _, attrName in ipairs(PRICE_ATTR_NAMES) do
                    if n == attrName:lower() then
                        local v = tonumber(child.Value)
                        if v and v > 0 then return v end
                    end
                end
            end
        end
        -- One level deeper (e.g. values inside a "Values" folder).
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") or child:IsA("Configuration") then
                for _, grandchild in ipairs(child:GetChildren()) do
                    if grandchild:IsA("NumberValue") or grandchild:IsA("IntValue") then
                        local n = grandchild.Name:lower()
                        for _, attrName in ipairs(PRICE_ATTR_NAMES) do
                            if n == attrName:lower() then
                                local v = tonumber(grandchild.Value)
                                if v and v > 0 then return v end
                            end
                        end
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
    -- Confirmed exact path from screenshots.
    local main = packModel:FindFirstChild("Main")
    if main then
        local prompt = main:FindFirstChild("ProximityPrompt")
        if prompt and prompt:IsA("ProximityPrompt") then
            -- Accept even if Enabled==false so we can watch it become true.
            return prompt
        end
    end
    -- Recursive fallback: scan all descendants.
    local firstAny = nil
    for _, desc in ipairs(packModel:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            if isBuyPrompt(desc) then return desc end
            if not firstAny then firstAny = desc end
        end
    end
    return firstAny
end

-- Legacy alias used by prompt-watcher helpers below.
local findBestBuyPrompt = getBuyPrompt

-- ── Cash safety check ─────────────────────────────────────────────────
-- Returns true when the player has enough cash (and enough reserve) to buy.
-- Returns false, reason string on any failure.
local function canBuyWithCash(record)
    local cash = getPlayerCash()
    if cash == nil then
        return false, "MissingCashValue"
    end
    local price = record.price
    if price == nil then
        return false, "InvalidPrice"
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
    -- Pack name comes from the model name itself.
    record.packName = record.model.Name

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

    if Config.AutoBuyMatching and purchaseWindowOpen then
        queuePurchase(record)
    end
end

-- ── Purchase queue ────────────────────────────────────────────────────
queuePurchase = function(record)
    if not record or record.state ~= "WaitingForPurchaseWindow" or record.filterPassed ~= true or PurchaseQueued[record] or os.clock() < (record.retryNotBefore or 0) then
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
-- SAFETY RULE:  never fire when cash < price; never fire when price is nil.
tryBuyRecord = function(record)
    if not record or not record.model or record.state ~= "Queued" then
        return false
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
        packName            = packModel.Name,
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
task.spawn(function()
    while true do
        task.wait(0.2)
        rebindConveyorContainerInner()

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

-- Auto Spawn uses this as a coordination gate. A matching pack stays
-- registered while box handling is active, but spawning yields while a
-- purchase is queued or awaiting confirmation.
autoBuyHasPending = function()
    if not Config.AutoBuyMatching then return false end
    for _, record in pairs(ConveyorRecords) do
        if record.state == "Queued" or record.state == "Buying"
            or (record.state == "WaitingForPurchaseWindow" and record.filterPassed == true) then
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
    if record.itemId ~= nil then
        return "id:" .. tostring(record.itemId)
    end
    return "model:" .. record.model:GetFullName()
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

-- Auto Spawn Pack
task.spawn(function()
    while true do
        task.wait(math.max(0.05, Config.SpawnDelay))
        if not Config.AutoSpawnPack then continue end
        if boxHandlingActive then continue end
        if Config.AutoStopSpawn and autoBuyHasPending and autoBuyHasPending() then continue end
        if autoStopHandled then continue end

        local previousIds
        if Config.AutoStopSpawn then
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
            end
        end
        fireButton(spawnBtn)

        if Config.AutoStopSpawn then
            local capturedIds = previousIds
            task.spawn(function()
                if autoStopHandled then return end

                -- ── Step 1: collect ALL new packs (up to 3 s) ───────────
                -- With admin events two packs can spawn at once; we must
                -- check every new pack for a filter match, not just the first.
                local newRecords = {}
                for _ = 1, 30 do
                    newRecords = {}
                    for _, record in ipairs(getConveyorPacks()) do
                        if not capturedIds[getPackKey(record)] then
                            table.insert(newRecords, record)
                        end
                    end
                    if #newRecords > 0 then break end
                    task.wait(0.1)
                end

                if #newRecords == 0 then
                    warnOnce("AutoStop:no-new-pack",
                        "Auto Stop did not detect a new conveyor pack after spawning.")
                    return
                end

                -- ── Step 2: wait for metadata to replicate, find a match ─
                -- Rarity/mutation may not be replicated yet the moment the
                -- model appears. Poll up to 2 s so the filter sees real data.
                --
                -- NOTE: refreshRecordMetadata is local to the conveyor do-block
                -- and is not in scope here. Instead read rarity/mutation directly
                -- via getPackRarity/getPackMutation (declared before the block)
                -- and build a fresh info table for the filter check.
                local spawnedRecord = nil
                for _ = 1, 20 do
                    task.wait(0.1)
                    for _, record in ipairs(newRecords) do
                        if not record.model:IsDescendantOf(workspace) then continue end
                        local freshInfo = {
                            pack     = record.packName or record.model.Name,
                            rarity   = getPackRarity(record.model),
                            mutation = getPackMutation(record.model),
                        }
                        if passesFilter(freshInfo) then
                            spawnedRecord = record
                            break
                        end
                    end
                    if spawnedRecord then break end
                end

                if not spawnedRecord then return end  -- no match among new packs

                -- ── Step 3: stop spawning ────────────────────────────────
                if autoStopHandled then return end
                autoStopHandled = true

                Config.AutoSpawnPack = false
                if Controls.AutoSpawnPack and Controls.AutoSpawnPack.Set then
                    pcall(function() Controls.AutoSpawnPack:Set(false) end)
                end
                notify("Auto Spawn Pack", "Stopped — filter match found!")

                -- ── Step 4: Auto Continue watcher ───────────────────────
                -- Always launch when AutoContinueSpawn is on, regardless of
                -- whether AutoBuyMatching is on — the pack may be removed by
                -- the game, expire, or be bought manually, and we still need
                -- to detect that and resume spawning.
                if Config.AutoContinueSpawn then
                    local watchedRecord = spawnedRecord
                    task.spawn(function()
                        -- Wait up to 30 s for a terminal outcome.
                        local deadline = os.clock() + 30
                        while os.clock() < deadline do
                            task.wait(0.2)
                            local st = watchedRecord.state
                            if st == "BoughtAndRemove" or st == "Removed"
                                or not watchedRecord.model:IsDescendantOf(workspace) then
                                -- Pack was purchased or left workspace — resume spawning.
                                if Config.AutoContinueSpawn then
                                    Config.AutoSpawnPack = true
                                    if Controls.AutoSpawnPack and Controls.AutoSpawnPack.Set then
                                        pcall(function() Controls.AutoSpawnPack:Set(true) end)
                                    end
                                    notify("Spawn Manager", "Resumed — pack purchased or removed!")
                                end
                                autoStopHandled = false
                                return
                            elseif st == "FilterRejected" then
                                -- Pack didn't pass the filter after all; unlock
                                -- without resuming — let the next spawn decide.
                                autoStopHandled = false
                                return
                            end
                        end
                        -- Hard timeout (30 s): pack was never confirmed bought or
                        -- removed. Re-enable spawning so the user isn't stuck —
                        -- 30 s is long enough for the belt to have cycled.
                        warn("[ACF] Auto Continue: 30 s timeout waiting for pack outcome — resuming spawn.")
                        if Config.AutoContinueSpawn then
                            Config.AutoSpawnPack = true
                            if Controls.AutoSpawnPack and Controls.AutoSpawnPack.Set then
                                pcall(function() Controls.AutoSpawnPack:Set(true) end)
                            end
                            notify("Spawn Manager", "Resumed — timeout waiting for pack.")
                        end
                        autoStopHandled = false
                    end)
                end
            end)
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

        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            boxHandlingActive = false
            continue
        end

        local savedCFrame = root.CFrame

        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            boxHandlingActive = false
            continue
        end

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

        local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if r then pcall(function() r.CFrame = savedCFrame end) end

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

-- Auto Sell
task.spawn(function()
    while true do
        task.wait(0.75)
        if not Config.AutoSell then continue end
        local backpack = player:FindFirstChild("Backpack")
        if not backpack then continue end
        for _, item in ipairs(backpack:GetChildren()) do
            local lvl = item:FindFirstChild("CardLevel")
            if lvl and lvl.Value >= MAX_CARD_LEVEL then
                fireRemote("CardSlotRE", "Sell", item.Name)
                task.wait(0.1)
            end
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
        -- activeBoosts[stat]   = true while that boost is running
        local potionCounts = {}
        local activeBoosts = {}
        local confirmationBusy = false

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

        local function potionDetails(itemId)
            local name = string.lower(tostring(itemId or ""))
            local family
            if string.find(name, "luckpotion", 1, true) then
                family = "luck"
            elseif string.find(name, "cashpotion", 1, true) then
                family = "cash"
            elseif string.find(name, "timepotion", 1, true) then
                family = "time"
            elseif string.find(name, "mutationpotion", 1, true) then
                family = "mutation"
            elseif string.find(name, "productionpotion", 1, true) then
                family = "production"
            end
            if not family then return nil, nil end
            return family, tonumber(string.match(name, "(%d+)$"))
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
                if type(info) == "table" and (tonumber(info.Remaining) or 0) > 0 then
                    local family, tier = boostDetails(stat, info)
                    activeBoosts[stat] = {
                        family = family,
                        tier = tier,
                    }
                end
            end
        end

        local function isBoostActive()
            for _, v in pairs(activeBoosts) do
                if v then return true end
            end
            return false
        end

        local function canUsePotion(itemId)
            local family, tier = potionDetails(itemId)
            if not family then return false end

            for _, active in pairs(activeBoosts) do
                -- Preserve the existing one-active-potion behavior for
                -- unrelated families, but allow a higher tier to replace
                -- the currently active lower tier in the same family.
                if active.family ~= family then
                    return false
                end
                if active.tier and tier and active.tier >= tier then
                    return false
                end
            end
            return true
        end

        -- Mirror the same event the ItemsClient script handles
        ItemsRE.OnClientEvent:Connect(function(action, data)
            if action == "FullInventory" and type(data) == "table" then
                potionCounts = {}
                if type(data.Items) == "table" then
                    for itemId, qty in pairs(data.Items) do
                        potionCounts[itemId] = qty
                    end
                end
                applyBoosts(data.Boosts)

            elseif action == "ItemUpdate" and type(data) == "table" then
                potionCounts[data.ItemId] = data.Quantity or 0

            elseif action == "BoostUpdate" then
                applyBoosts(data)
            end
        end)

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
                if not Config.AutoPotion then continue end

                local selected = Config.SelectedPotions
                for _, potion in ipairs(POTIONS) do
                    if not selectionIncludes(selected, potion) then continue end
                    if (potionCounts[potion] or 0) <= 0 then continue end
                    if not canUsePotion(potion) then continue end
                    pcall(function()
                        ItemsRE:FireServer("UseItem", { ItemId = potion, Amount = 1 })
                    end)
                    -- Give the game's ItemsClient time to create the warning,
                    -- then accept it if this was a tier replacement.
                    for _ = 1, 12 do
                        task.wait(0.1)
                        if acceptPotionReplacementConfirmation() then break end
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

-- Auto Trait Roll
task.spawn(function()
    while true do
        task.wait(0.25)
        if Config.AutoTraitRoll then fireRemote("TraitRollRE", "Roll") end
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
        if not isPack then continue end
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

local function getSortedCardsInBackpack()
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

task.spawn(function()
    while true do
        task.wait(0.4)
        if rankCardDropdown then
            queueRankCardDropdownRefresh()
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
        local slots = getAllCardSlots()
        for _, slot in ipairs(slots) do
            if not Config.AutoPlacePack then break end
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

removeAllCards = function(limit)
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
    if firesignal then
        local ok = pcall(firesignal, button.MouseButton1Click)
        if ok then return true end
    end
    if button:IsA("GuiObject") and not button.Visible then return false end
    return pcall(function() button:Activate() end)
end

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

local raidDifficultyOptions = { "Easy", "Medium", "Hard", "Nightmare" }
local raidDifficultySet = {}
for _, difficulty in ipairs(raidDifficultyOptions) do
    raidDifficultySet[difficulty] = true
end
local completedRaidDifficulties = {}

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

local function getSelectedRaidDifficulties()
    local selected = normalizeRaidDifficulties(Config.RaidDifficulties)
    local selectedSet = {}
    for _, difficulty in ipairs(selected) do
        selectedSet[difficulty] = true
    end

    local ordered = {}
    for _, difficulty in ipairs(raidDifficultyOptions) do
        if selectedSet[difficulty] then
            table.insert(ordered, difficulty)
        end
    end
    return ordered
end

local function getNextRaidDifficulty()
    for _, difficulty in ipairs(getSelectedRaidDifficulties()) do
        if not completedRaidDifficulties[difficulty] then
            return difficulty
        end
    end
    return nil
end

local function clearCompletedRaidDifficulties()
    for difficulty in pairs(completedRaidDifficulties) do
        completedRaidDifficulties[difficulty] = nil
    end
end

local function getRaidRequirement(difficulty)
    if not BossRaidConfig or not BossRaidConfig.GetBossStats then
        return nil
    end
    if currentRaidBossId == "" then return nil end
    local ok, stats = pcall(
        BossRaidConfig.GetBossStats,
        currentRaidBossId,
        difficulty
    )
    if ok and type(stats) == "table" then
        return tonumber(stats.ReferenceDamage)
    end
    return nil
end

local RAID_DIFFICULTY_INFO = {
    Easy = {
        damage = "1.3B",
        description = "At least 1.3B damage per card.",
    },
    Medium = {
        damage = "24.4Qn",
        description = "At least 24.4Qn damage per card.",
    },
    Hard = {
        damage = "4.7O",
        description = "At least 4.7O damage per card.",
    },
    Nightmare = {
        damage = "13.1O",
        description = "At least 13.1O damage per card.",
    },
}

local raidInfoParagraph
local raidTimerText = "Searching for Boss Raid timer..."

local function getRaidDifficultyInfo(difficulty)
    local wanted = string.lower(tostring(difficulty or ""))
    for name, info in pairs(RAID_DIFFICULTY_INFO) do
        if string.lower(name) == wanted then
            return info
        end
    end
    return nil
end

local function updateRaidInfoDisplay(difficulties)
    if not raidInfoParagraph or not raidInfoParagraph.Set then return end

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
    table.insert(lines, "Timer: " .. raidTimerText)

    pcall(function()
        raidInfoParagraph:Set({
            Title = "Boss Raid",
            Content = table.concat(lines, "\n"),
        })
    end)
end

local function showRaidRequirement(difficulties)
    local selected = getSelectedRaidDifficulties()
    notify(
        "Boss Raid Difficulty",
        "Selected " .. table.concat(selected, ", ") .. "."
    )
    updateRaidInfoDisplay(selected)
end

if BossRaidRE then
    BossRaidRE.OnClientEvent:Connect(function(eventName, payload)
        if eventName == "State" and type(payload) == "table" then
            currentRaidBossId = tostring(payload.BossId or "")
        end
    end)
    pcall(function() BossRaidRE:FireServer("RequestState") end)
end

local function readRaidTimerText(timer)
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

local function findBossRaidTimer()
    local bossRaidModel = workspace:FindFirstChild("BossRaidModel", true)
    if not bossRaidModel then
        bossRaidModel = playerGui:FindFirstChild("BossRaidModel", true)
    end
    return bossRaidModel and bossRaidModel:FindFirstChild("Timer", true)
end

local function isBossRaidOpen()
    local timer = findBossRaidTimer()
    local text = readRaidTimerText(timer)
    if not text then return false end

    local normalized = string.lower(text)
    return string.find(normalized, "end in", 1, true) ~= nil
end

task.spawn(function()
    while true do
        task.wait(0.5)
        local timer = findBossRaidTimer()
        local text = readRaidTimerText(timer)
        if text and text ~= "" then
            raidTimerText = text
        elseif timer then
            raidTimerText = "Timer found, waiting for countdown..."
        else
            raidTimerText = "Boss Raid is currently unavailable"
        end
        updateRaidInfoDisplay(Config.RaidDifficulties)
    end
end)

local function clickBackpackEquipBest()
    return doEquipBestCards(4) ~= nil
end

local function equipBestCardsWithRetry()
    for _ = 1, 2 do
        local placed = doEquipBestCards(4)
        if placed and placed > 0 then
            return true
        end
        task.wait(CARD_REMOVAL_DELAY)
    end
    return false
end

local function finishAutoRaidIfComplete()
    if getNextRaidDifficulty() then return false end
    Config.AutoRaid = false
    if Controls.AutoRaid and Controls.AutoRaid.Set then
        pcall(function() Controls.AutoRaid:Set(false) end)
    end
end

local function waitForBossRaidConfirmation()
    for _ = 1, 20 do
        if player:GetAttribute("BossRaidInBattle") == true then
            return true
        end
        task.wait(0.15)
    end
    return false
end

startCombatBattle = function(mode, equipBest, hideBattle, difficulty)
    if mode == "BossRaid" and not isBossRaidOpen() then
        return false
    end

    if mode == "BossRaid"
        and player:GetAttribute("InfinityTowerInBattle") == true then
        return false
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
        raidDifficulty = difficulty or getNextRaidDifficulty()
        if not raidDifficulty then return false end
        selectRaidDifficulty(raidDifficulty)
        task.wait(0.25)
    end

    local started = clickCombatButton(mode, { "BATTLE", "Battle" })
    if not started then return false end

    if mode == "BossRaid" then
        if waitForBossRaidConfirmation() then
            completedRaidDifficulties[raidDifficulty] = true
            finishAutoRaidIfComplete()
        else
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

local combatBusy = false

task.spawn(function()
    while true do
        task.wait(1.5)
        if combatBusy or Config.AutoTeamCardCycle then continue end
        if not Config.AutoInfinityTower then continue end
        if Config.AutoRaid and isBossRaidOpen() then
            continue
        end
        if not isCombatActive() then
            combatBusy = true
            startCombatBattle(
                "InfinityTower",
                Config.AutoInfinityEquip,
                Config.AutoInfinityHide
            )
            combatBusy = false
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(1.5)
        if combatBusy or Config.AutoTeamCardCycle then continue end
        if not Config.AutoRaid then continue end
        if not isBossRaidOpen() then continue end
        if not isCombatActive() then
            combatBusy = true
            startCombatBattle(
                "BossRaid",
                Config.AutoRaidEquip,
                Config.AutoRaidHide
            )
            combatBusy = false
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(2)
        if combatBusy or not Config.AutoTeamCardCycle then continue end
        if isCombatActive() then continue end

        local combatMode
        if Config.AutoRaid and isBossRaidOpen() then
            combatMode = "BossRaid"
        elseif Config.AutoInfinityTower then
            combatMode = "InfinityTower"
        end
        if not combatMode then continue end

        combatBusy = true
        if not equipBestCardsWithRetry() then
            combatBusy = false
            continue
        end

        if combatMode == "BossRaid" then
            startCombatBattle("BossRaid", Config.AutoRaidEquip, Config.AutoRaidHide)
        elseif combatMode == "InfinityTower" then
            startCombatBattle(
                "InfinityTower",
                Config.AutoInfinityEquip,
                Config.AutoInfinityHide
            )
        end
        combatBusy = false
    end
end)

-- ══════════════════════════════════════════════════════════════
--  Config Manager State & Helper Functions
-- ══════════════════════════════════════════════════════════════
-- Keep the complete UI/config construction in its own function scope.
-- Luau limits the number of local registers in the top-level chunk; without
-- this boundary the many UI controls added below make the whole script fail
-- during compilation with "Out of local registers".
local function buildUserInterface()

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
        SelectedRarities  = Config.SelectedRarities,
        SelectedMutations = Config.SelectedMutations,
        SelectedPacks     = Config.SelectedPacks,
        AutoUpgrade       = Config.AutoUpgrade,
        UpgradeDelay      = Config.UpgradeDelay,
        CardActionDelay   = Config.CardActionDelay,
        AutoSell          = Config.AutoSell,
        AutoTraitRoll     = Config.AutoTraitRoll,
        SelectedRankCards  = Config.SelectedRankCards,
        TargetRank         = Config.TargetRank,
        RankUseGems        = Config.RankUseGems,
        RankUseCash        = Config.RankUseCash,
        AutoRankRoll       = Config.AutoRankRoll,
        AutoClaimPlaytime = Config.AutoClaimPlaytime,
        AutoClaimDaily    = Config.AutoClaimDaily,
        AutoPlacePack     = Config.AutoPlacePack,
        AutoOpenPack      = Config.AutoOpenPack,
        AutoBuyBoost      = Config.AutoBuyBoost,
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
    if type(value) == "table" then return value end
    if value == nil then return {} end
    return { tostring(value) }
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
        "SelectedRarities", "SelectedMutations", "SelectedPacks",
        "AutoUpgrade", "UpgradeDelay", "CardActionDelay", "AutoSell",
        "AutoTraitRoll", "SelectedRankCards", "TargetRank",
        "RankUseGems", "RankUseCash", "AutoRankRoll",
        "AutoClaimPlaytime", "AutoClaimDaily",
        "AutoPlacePack", "AutoOpenPack", "AutoBuyBoost",
        "AutoInfinityEquip", "AutoInfinityTower", "AutoInfinityHide",
        "RaidDifficulties", "AutoRaidEquip", "AutoRaid", "AutoRaidHide",
        "AutoTeamCardCycle", "AutoPotion", "SelectedPotions",
        "SelectedBoosts", "AntiAfk", "AutoContinueSpawn",
        "UseCashReserve", "CashReserve",
    }

    for _, key in ipairs(knownKeys) do
        if data[key] ~= nil then
            local value = data[key]
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
local cardsTab = Window:CreateTab("⬆️ Cards", 0)

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

cardsTab:CreateButton({
    Name     = "Remove All Cards",
    Callback = function()
        task.spawn(function()
            local removed = removeAllCards()
            notify("Remove All Cards", "Removed " .. tostring(removed) .. " card(s).")
        end)
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

-- ══════════════════════════════════════════════════════════════
--  TAB 3 – Auto Sell
-- ══════════════════════════════════════════════════════════════
local autoSellTab = Window:CreateTab("📦 Auto Sell", 0)

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

autoSellTab:CreateSection("Cards")

autoSellTab:CreateToggle({
    Name         = "Auto Sell Cards",
    CurrentValue = Config.AutoSell,
    Flag         = "AutoSell",
    Callback     = function(v) Config.AutoSell = v end,
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

raidInfoParagraph = combatTab:CreateParagraph({
    Title   = "Boss Raid",
    Content = "Loading Boss Raid information...",
})
updateRaidInfoDisplay(Config.RaidDifficulties)

Controls.RaidDifficulties = combatTab:CreateDropdown({
    Name          = "Select Difficulty",
    Options       = raidDifficultyOptions,
    CurrentOption = Config.RaidDifficulties[1] or "Easy",
    MultipleOptions = false,
    Flag          = "RaidDifficulties",
    Callback      = function(v)
        local selected = normalizeRaidDifficulties(v)
        if #selected == 0 then
            selected = { raidDifficultyOptions[1] }
        end
        Config.RaidDifficulties = selected
        clearCompletedRaidDifficulties()
        showRaidRequirement(selected)
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
    Content = "Do not hold or equip a card while rerolling is active. Held or equipped cards are removed from your backpack, making them invisible to the script — those cards will be skipped entirely until you put them away.",
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
Config.TargetRank = #validTargets > 0 and validTargets or { rankOptions[1] or "UR" }

Controls.TargetRank = rerollTab:CreateDropdown({
    Name            = "Target Ranking",
    Options         = rankOptions,
    CurrentOption   = Config.TargetRank,
    MultipleOptions = true,
    Flag            = "TargetRank",
    Callback        = function(v)
        if type(v) == "string" then v = { v } end
        Config.TargetRank = (type(v) == "table" and #v > 0) and v or { rankOptions[1] or "UR" }
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

rerollTab:CreateParagraph({
    Title   = "Card Ranking behavior",
    Content = "Selected cards are rerolled one at a time until they reach the target ranking. Gems are used first; cash is used only after gems reach zero.",
})

rerollTab:CreateSection("Traits")

Controls.AutoTraitRoll = rerollTab:CreateToggle({
    Name         = "Auto Trait Roll",
    CurrentValue = Config.AutoTraitRoll,
    Flag         = "AutoTraitRoll",
    Callback     = function(v) Config.AutoTraitRoll = v end,
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

miscTab:CreateParagraph({
    Title   = "Potion behavior",
    Content = "Only selected potions that you own are used. The next potion waits until no active potion effect remains.",
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
