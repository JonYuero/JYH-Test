-- ============================================================
--  Anime Card Farm — Loader
--  JonYueroHub  ·  Rayfield key-system + per-game script launcher
-- ============================================================

-- ── URL constants (single source of truth) ───────────────────
local LOADER_URL    = "https://raw.githubusercontent.com/JonYuero/JYH-Test/refs/heads/main/Loader.lua"
local ANIME_CARD_FARM_URL = "https://raw.githubusercontent.com/JonYuero/JYH-Test/refs/heads/main/MyScript.lua"
local SCRIPT_VERSION = "v 1.0"

-- ── Environment / duplicate-loader guard ─────────────────────
local ENV = getgenv()

if ENV.JYH_LOADER_RUNNING == true then
    -- A loader UI is already open in this executor session; do not create
    -- another one.  The existing window handles key input.
    return
end

ENV.JYH_LOADER_RUNNING    = true
ENV.JYH_RETURNING_TO_LOADER = nil   -- clear redirect flag on fresh start

-- Clear any stale launch session left from a previous run.
-- The user must authenticate again; the old token must not be reused.
ENV.JYH_SESSION           = nil
ENV.JYH_GAME_SCRIPT_RUNNING = nil

-- ── Services ─────────────────────────────────────────────────
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local StarterGui  = game:GetService("StarterGui")

local player = Players.LocalPlayer

-- ── Core notify (fallback before Rayfield is ready) ──────────
local function coreNotify(title, text)
    pcall(StarterGui.SetCore, StarterGui, "SendNotification", {
        Title = title, Text = text, Duration = 5,
    })
end

-- ── Auth constants ────────────────────────────────────────────
local AUTH_ENDPOINT = "https://api.jonyuerohub-api.workers.dev/api/v1/key/authenticate"
local GET_KEY_URL   = "https://api.jonyuerohub-api.workers.dev/api/v1/key/free-start"

-- ── Game ID → hosted script URL ──────────────────────────────
-- Add one entry per game the loader should support.
local GAME_SCRIPTS = {
    [125039473548047] = ANIME_CARD_FARM_URL,
    -- [PLACE_ID] = "https://...",
}

-- ── Local key persistence ─────────────────────────────────────
-- The key is saved only after the authentication server accepts it.
-- It is stored in the same hub folder used by the game script's configs.
local KEY_ROOT = "Jon Yuero Hub/Anime Card Farm"
local KEY_FILE = KEY_ROOT .. "/LicenseKey.json"

-- The device ID is global to JonYueroHub, not specific to one game.
-- This is a persistent device-installation ID, not an unbreakable
-- hardware fingerprint. Executor file resets or copying this file can
-- change or imitate the installation identity.
local DEVICE_ROOT = "Jon Yuero Hub"
local DEVICE_FILE = DEVICE_ROOT .. "/DeviceId.txt"

local FS_SUPPORTED = (
    type(makefolder) == "function" and type(isfolder) == "function"
    and type(writefile) == "function" and type(readfile) == "function"
    and type(isfile) == "function" and type(delfile) == "function"
)

local DEVICE_FS_SUPPORTED = (
    type(makefolder) == "function" and type(isfolder) == "function"
    and type(writefile) == "function" and type(readfile) == "function"
    and type(isfile) == "function"
)

local function getPersistentDeviceId()
    -- Compatibility fallback for executors without file APIs. This keeps
    -- the loader from crashing, but remains account-based on that executor.
    local fallback = "ROBLOX-USER-" .. tostring(player.UserId)
    if not DEVICE_FS_SUPPORTED then
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

local CLIENT_ID = getPersistentDeviceId()

local function ensureKeyFolder()
    if not FS_SUPPORTED then return false end
    pcall(function()
        if not isfolder("Jon Yuero Hub") then makefolder("Jon Yuero Hub") end
        if not isfolder(KEY_ROOT) then makefolder(KEY_ROOT) end
    end)
    return isfolder(KEY_ROOT)
end

local function saveLicenseKey(key)
    if not FS_SUPPORTED or type(key) ~= "string" or key == "" then
        return false
    end
    if not ensureKeyFolder() then return false end

    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, {
        licenseKey = key,
        userId = player.UserId,
        savedAt = os.time(),
    })
    if not ok then return false end
    return pcall(writefile, KEY_FILE, encoded)
end

local function loadSavedLicenseKey()
    if not FS_SUPPORTED or not ensureKeyFolder() or not isfile(KEY_FILE) then
        return nil
    end

    local ok, raw = pcall(readfile, KEY_FILE)
    if not ok or type(raw) ~= "string" or raw == "" then return nil end

    local decodedOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodedOk or type(data) ~= "table"
        or type(data.licenseKey) ~= "string"
        or data.licenseKey == "" then
        return nil
    end
    return data.licenseKey
end

local function clearSavedLicenseKey()
    if FS_SUPPORTED and isfile(KEY_FILE) then
        pcall(delfile, KEY_FILE)
    end
end

-- ── Load Rayfield ─────────────────────────────────────────────
local Rayfield
for _, url in ipairs({
    "https://sirius.menu/rayfield",
    "https://raw.githubusercontent.com/UI-Hub/Rayfield/main/source",
    "https://raw.githubusercontent.com/shlexware/Rayfield/main/source",
}) do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(url, true))()
    end)
    if ok and result then Rayfield = result ; break end
end
if not Rayfield then
    coreNotify("Loader Error", "Could not load Rayfield. Check executor HTTP settings.")
    ENV.JYH_LOADER_RUNNING = nil
    error("[Loader] Could not load Rayfield from any source.")
end

-- ── Cross-executor HTTP helper ────────────────────────────────
local function httpRequest(opts)
    if syn   and syn.request   then return syn.request(opts)   end
    if request                 then return request(opts)        end
    if http  and http.request  then return http.request(opts)   end
    if http_request            then return http_request(opts)   end
    return nil
end

-- ── Safe Lua source fetcher ───────────────────────────────────
-- Returns a compiled function on success, or nil + reason on failure.
-- Rejects HTML, 404, rate-limit, and empty responses before compiling.
local function fetchLua(url)
    local ok, raw = pcall(game.HttpGet, game, url, true)
    if not ok or type(raw) ~= "string" or raw == "" then
        return nil, "HttpGet failed: " .. tostring(raw)
    end
    -- Reject non-Lua content (GitHub error pages, CDN rate-limits, etc.)
    local head = raw:sub(1, 300):lower()
    if head:find("<!doctype", 1, true)
    or head:find("<html",     1, true)
    or head:find("404: not found", 1, true)
    or head:find("rate limit",     1, true)
    or head:find("access denied",  1, true) then
        return nil, "Server returned an HTML or error page instead of Lua source"
    end
    local fn, err = loadstring(raw)
    if not fn then
        return nil, "Compile error: " .. tostring(err)
    end
    return fn
end

-- ── Expiry display helper ─────────────────────────────────────
-- Returns a human-readable expiry string.
-- Accepts an ISO-8601 date string, a Unix timestamp string, or "Never".
local function formatExpiry(expiresAt, licenseType)
    local t = tostring(expiresAt or "")

    if licenseType == "LIFETIME"
    or t == "" or t == "Never" or t == "never" then
        return "Never"
    end

    -- Try Unix timestamp (seconds since epoch) — use os.time(), not tick()
    local unix = tonumber(t)
    if unix then
        local remaining = unix - os.time()
        if remaining <= 0 then return "Expired" end
        local days  = math.floor(remaining / 86400)
        local hours = math.floor((remaining % 86400) / 3600)
        if days > 0 then
            return t .. "  (" .. days .. "d " .. hours .. "h remaining)"
        else
            return t .. "  (" .. hours .. "h remaining)"
        end
    end

    -- ISO-8601 rough parse: "2025-08-05T12:00:00Z"
    local y, mo, d, h, mi = t:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
    if y then
        return d .. "/" .. mo .. "/" .. y .. " " .. h .. ":" .. mi .. " UTC"
    end

    return t   -- unknown format — show as-is
end

-- ── Script launcher ───────────────────────────────────────────
-- Validates the place, downloads and compiles MyScript, creates JYH_SESSION,
-- destroys the loader window, then runs the compiled function.
-- Returns true on success or false + errorMessage on failure.
--
-- Required order (per spec §5):
--   1. Validate PlaceId has a configured script URL.
--   2. Fetch MyScript source.
--   3. Verify non-empty, reject HTML.
--   4. Compile with loadstring.
--   5. Create JYH_SESSION.
--   6. Destroy loader interface.
--   7. Run compiled game script.
--   8. On execution failure: clear JYH_SESSION so a retry is clean.
local function launchScript(Window, licType, expiresAt)
    local placeId   = game.PlaceId
    local scriptUrl = GAME_SCRIPTS[placeId]

    if not scriptUrl then
        local msg = "No script configured for Place ID " .. tostring(placeId)
                 .. ". Add it to GAME_SCRIPTS in Loader.lua."
        coreNotify("Loader", msg)
        warn("[Loader] " .. msg)
        return false, msg
    end

    -- Step 2-4: fetch and compile
    local fn, fetchErr = fetchLua(scriptUrl)
    if not fn then
        local msg = "Could not load game script: " .. tostring(fetchErr)
        coreNotify("Loader Error", msg)
        warn("[Loader] " .. msg)
        return false, msg
    end

    -- Step 5: create the short-lived launch session BEFORE running anything
    ENV.JYH_SESSION = {
        authenticated  = true,

        licenseType    = licType,
        expiresAt      = expiresAt,

        issuedAt       = os.time(),

        placeId        = placeId,
        userId         = player.UserId,

        clientId       = CLIENT_ID,
        deviceId       = CLIENT_ID,
        currentGame    = "Anime Card Farm",
        scriptVersion  = SCRIPT_VERSION,

        loaderUrl      = LOADER_URL,
        scriptUrl      = scriptUrl,
    }

    -- Also clear redirect flags so MyScript does not see stale state
    ENV.JYH_RETURNING_TO_LOADER = nil
    ENV.JYH_GAME_SCRIPT_RUNNING = nil

    -- Step 6: close the loader interface
    pcall(function() Window:Destroy() end)
    task.wait(0.3)

    -- Step 7: run the compiled game script
    local ok, runErr = pcall(fn)
    if not ok then
        -- Step 8: clean up so a fresh Loader run can try again
        ENV.JYH_SESSION = nil
        ENV.JYH_GAME_SCRIPT_RUNNING = nil
        warn("[Loader] Game script crashed on startup: " .. tostring(runErr))
        -- Cannot reopen the same Window after Destroy(); notify via StarterGui.
        coreNotify("Loader Error",
            "Game script failed to start. Run Loader.lua again to retry.")
        -- Mark loader as no longer running so the user can restart it.
        ENV.JYH_LOADER_RUNNING = nil
        return false, tostring(runErr)
    end

    -- Success: loader is done; clear the running flag so a future Loader
    -- run (e.g. after a game rejoin) can start fresh.
    ENV.JYH_LOADER_RUNNING = nil
    return true
end

-- ══════════════════════════════════════════════════════════════
--  Rayfield Window  (key system; farming UI opens after auth)
-- ══════════════════════════════════════════════════════════════
local Window = Rayfield:CreateWindow({
    Name                = "Jon Yuero Hub",
    LoadingTitle        = "Jon Yuero Hub",
    LoadingSubtitle     = "License Required",
    ConfigurationSaving = { Enabled = false },
    Discord             = { Enabled = false },
    KeySystem           = false,
})

local savedLicenseKey = loadSavedLicenseKey()
-- ── Authentication request helper ─────────────────────────────
-- This runs before the key-system tab is created when a saved key exists.
local function requestAuthentication(key)
    local encOk, payloadOrErr = pcall(HttpService.JSONEncode, HttpService, {
        licenseKey = key,
        clientId   = CLIENT_ID,
        deviceId   = CLIENT_ID,
    })
    if not encOk then
        return {
            ok = false,
            kind = "internal",
            title = "Internal Error",
            content = "Failed to encode request. See output log.",
            detail = payloadOrErr,
        }
    end

    local response
    local reqOk, reqErr = pcall(function()
        response = httpRequest({
            Url     = AUTH_ENDPOINT,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = payloadOrErr,
        })
    end)
    if not reqOk or not response then
        return {
            ok = false,
            kind = "network",
            title = "License server unavailable",
            content = "Could not reach the authentication server.\n"
                .. "Check executor HTTP permissions and try again.",
            detail = reqErr,
        }
    end

    local data
    local parseOk, parseErr = pcall(function()
        data = HttpService:JSONDecode(response.Body or "{}")
    end)
    if not parseOk or type(data) ~= "table" then
        return {
            ok = false,
            kind = "response",
            title = "Invalid server response",
            content = "The server returned an unexpected response. Try again.",
            detail = parseErr,
            response = response,
        }
    end

    if data.success ~= true then
        return {
            ok = false,
            kind = "rejected",
            data = data,
            response = response,
        }
    end

    return { ok = true, data = data, response = response }
end

local function getRejectedStatus(result, savedKey)
    local data = result.data or {}
    local errCode = tostring(data.error or data.message or ""):lower()

    if errCode:find("expired") then
        return "Key expired",
            (savedKey and "Your saved FREE key has expired. "
                or "This key has expired. ")
            .. "Click 'Get Key' below. Complete Work.ink and the SAME FREE key will be renewed."
    elseif errCode:find("revok") then
        return "Key revoked",
            (savedKey and "Your saved key was revoked. "
                or "This key was revoked. ")
            .. "Obtain a new key to continue."
    elseif errCode:find("device") or errCode:find("bound") then
        return "Bound to another device",
            (savedKey and "Your saved key is bound"
                or "This key is bound")
            .. " to a different device."
    end

    return "Invalid key",
        (savedKey and "The saved key is no longer valid. "
            or "The key is not valid. ")
        .. "Enter a new key and try again."
end

local function getLicenseType(data)
    local rawType = tostring(data.licenseType or data.type or data.plan or "")
    local licType = rawType:upper()
    if licType ~= "FREE" and licType ~= "30D" and licType ~= "LIFETIME" then
        return nil, rawType
    end
    return licType
end

local function showKeySystem(initialTitle, initialContent)
    local KeyTab = Window:CreateTab("🔑 Key System", 0)

    local statusParagraph = KeyTab:CreateParagraph({
        Title   = initialTitle or "Status",
        Content = initialContent
            or "Enter your license key and click Authenticate.",
    })

    local function setStatus(title, content)
        pcall(function()
            statusParagraph:Set({ Title = title, Content = content })
        end)
    end

    KeyTab:CreateSection("Authentication")

    local keyInput = savedLicenseKey or ""
    local authenticationInProgress = false

    KeyTab:CreateInput({
        Name                     = "License Key",
        PlaceholderText          = "Paste your key here...",
        RemoveTextAfterFocusLost = false,
        Flag                     = "LicenseKey",
        Callback = function(v)
            keyInput = tostring(v or ""):match("^%s*(.-)%s*$")
        end,
    })

    local function authenticateKey(rawKey)
        if authenticationInProgress then return end

        local key = tostring(rawKey or ""):match("^%s*(.-)%s*$")
        if key == "" then
            setStatus("No Key Entered",
                "Paste your license key into the input above first.")
            return
        end

        authenticationInProgress = true
        setStatus("Checking license…",
            "Contacting authentication server — please wait.")

        task.spawn(function()
            local result = requestAuthentication(key)
            if not result.ok then
                local savedKeyRejected = key == savedLicenseKey
                local rejectedText = tostring(
                    result.data and (result.data.error or result.data.message) or ""
                ):lower()

                -- Keep an expired saved key so /get-key can renew that same key.
                -- Invalid/revoked/bound keys are still cleared as before.
                if savedKeyRejected
                    and result.kind == "rejected"
                    and not rejectedText:find("expired") then
                    clearSavedLicenseKey()
                    savedLicenseKey = nil
                end

                local title, content
                if result.kind == "rejected" then
                    title, content = getRejectedStatus(result, savedKeyRejected)
                    warn("[Loader] Auth failed — HTTP "
                        .. tostring(result.response and result.response.StatusCode)
                        .. "  body=" .. tostring(result.response and result.response.Body))
                else
                    title, content = result.title, result.content
                    warn("[Loader] Authentication error: " .. tostring(result.detail))
                end
                setStatus(title, content)
                authenticationInProgress = false
                return
            end

            local data = result.data
            local licType, rawType = getLicenseType(data)
            if not licType then
                if key == savedLicenseKey then
                    clearSavedLicenseKey()
                    savedLicenseKey = nil
                end
                setStatus("Unknown license type",
                    "The server returned an unrecognised license type: '"
                    .. rawType .. "'.\n"
                    .. "Contact support — the launcher will not start with an unknown type.")
                warn("[Loader] Auth succeeded but license type is unknown: " .. rawType)
                authenticationInProgress = false
                return
            end

            saveLicenseKey(key)
            savedLicenseKey = key

            local expiresAt = data.expiresAt or data.expires_at or data.expiry
            local expiryStr = formatExpiry(expiresAt, licType)
            local typeLabel = licType == "LIFETIME" and "Lifetime"
                           or licType == "30D"       and "30-Day"
                           or "FREE (24h)"

            setStatus("License authenticated",
                "License: " .. typeLabel .. "\n"
                .. "Expires: " .. expiryStr)

            Rayfield:Notify({
                Title    = "Access Granted",
                Content  = "License: " .. typeLabel .. "  ·  Expires: " .. expiryStr,
                Duration = 5,
            })

            warn("[Loader] " .. player.Name .. " authenticated — Type=" .. licType
                .. "  Expires=" .. expiryStr)

            task.wait(1.5)
            local ok, err = launchScript(Window, licType, expiresAt)
            if not ok then
                warn("[Loader] Launch failed: " .. tostring(err))
            end
            authenticationInProgress = false
        end)
    end

    KeyTab:CreateButton({
        Name     = "Authenticate",
        Callback = function()
            authenticateKey(keyInput)
        end,
    })

    KeyTab:CreateButton({
        Name     = "Get Key",
        Callback = function()
            local keyUrl = GET_KEY_URL

            -- If the loader still has a saved key, pass it to the backend.
            -- The backend will renew it when it is an existing FREE key.
            if savedLicenseKey and savedLicenseKey ~= "" then
                keyUrl = GET_KEY_URL
                    .. "?key="
                    .. HttpService:UrlEncode(savedLicenseKey)
            end

            if setclipboard then
                pcall(setclipboard, keyUrl)
                Rayfield:Notify({
                    Title    = "Link Copied",
                    Content  = "Key link copied to clipboard.\n"
                        .. "Open it in a browser to get your key.",
                    Duration = 6,
                })
                setStatus("Key link copied", keyUrl)
            else
                setStatus("Get your key at", keyUrl)
                Rayfield:Notify({
                    Title    = "Get Key",
                    Content  = keyUrl,
                    Duration = 10,
                })
            end
        end,
    })
end

local function validateSavedKeyBeforeShowingTab()
    coreNotify("JonYueroHub", "Checking saved license…")
    task.spawn(function()
        local result = requestAuthentication(savedLicenseKey)
        if not result.ok then
            local title, content
            if result.kind == "rejected" then
                title, content = getRejectedStatus(result, true)

                local rejectedText = tostring(
                    result.data and (result.data.error or result.data.message) or ""
                ):lower()

                -- Do not delete an expired FREE key. It is needed by Get Key
                -- so Work.ink can renew the same database key.
                if not rejectedText:find("expired") then
                    clearSavedLicenseKey()
                    savedLicenseKey = nil
                end

                warn("[Loader] Saved key rejected — HTTP "
                    .. tostring(result.response and result.response.StatusCode)
                    .. "  body=" .. tostring(result.response and result.response.Body))
            else
                title, content = result.title, result.content
                warn("[Loader] Saved-key check failed: " .. tostring(result.detail))
            end
            showKeySystem(title, content)
            return
        end

        local data = result.data
        local licType, rawType = getLicenseType(data)
        if not licType then
            clearSavedLicenseKey()
            savedLicenseKey = nil
            showKeySystem("Unknown license type",
                "The server returned an unrecognised license type: '"
                .. rawType .. "'.\n"
                .. "Contact support — the launcher will not start with an unknown type.")
            warn("[Loader] Saved key returned unknown license type: " .. rawType)
            return
        end

        local expiresAt = data.expiresAt or data.expires_at or data.expiry
        local expiryStr = formatExpiry(expiresAt, licType)
        local typeLabel = licType == "LIFETIME" and "Lifetime"
                       or licType == "30D"       and "30-Day"
                       or "FREE (24h)"

        saveLicenseKey(savedLicenseKey)
        Rayfield:Notify({
            Title    = "Access Granted",
            Content  = "License: " .. typeLabel .. "  ·  Expires: " .. expiryStr,
            Duration = 5,
        })
        warn("[Loader] Saved key authenticated — Type=" .. licType
            .. "  Expires=" .. expiryStr)

        task.wait(0.3)
        local ok, err = launchScript(Window, licType, expiresAt)
        if not ok then
            warn("[Loader] Launch failed: " .. tostring(err))
        end
    end)
end

-- Check the saved key before creating the key-system tab. A valid key
-- goes directly to the configured game script; invalid or missing keys
-- receive the normal authentication and Get Key controls.
if savedLicenseKey then
    validateSavedKeyBeforeShowingTab()
else
    showKeySystem()
end
