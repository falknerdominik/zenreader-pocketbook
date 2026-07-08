local lfs = require("libs/libkoreader-lfs")
local PresetStore = require("config/preset_store")

local M = {}

local DEFAULT_QUOTES = require("modules/filebrowser/patches/home/quote_list")

local TEMPLATE = [[return {
    -- Add your quotes here. When this list is not empty, it replaces Zen UI defaults.
    -- { text = "Quote text", author = "Author" },
    -- "Plain quote without author",
}
]]

local function ensure_dir(path)
    if lfs.attributes(path, "mode") == "directory" then return true end
    return lfs.mkdir(path) == true or lfs.attributes(path, "mode") == "directory"
end

local function quotes_path()
    local root = PresetStore.rootDir()
    ensure_dir(root)
    return root .. "/quotes.lua"
end

local function ensure_template(path)
    if lfs.attributes(path, "mode") == "file" then return false end
    local f = io.open(path, "w")
    if not f then return false end
    f:write(TEMPLATE)
    f:close()
    return true
end

local function normalize(raw)
    local src = raw
    if type(raw) == "table" and type(raw.quotes) == "table" then src = raw.quotes end
    if type(src) ~= "table" then return {} end

    local out = {}
    for _i, item in ipairs(src) do
        local text, author
        if type(item) == "string" then
            text = item
            author = ""
        elseif type(item) == "table" then
            text = item.text or item[1]
            author = item.author or item[2] or ""
        end
        if type(text) == "string" then
            text = text:match("^%s*(.-)%s*$") or ""
            if text ~= "" then
                if type(author) ~= "string" then author = tostring(author or "") end
                out[#out + 1] = { text = text, author = author }
            end
        end
    end
    return out
end

function M.getQuotes()
    local path = quotes_path()
    ensure_template(path)
    local ok, raw = pcall(dofile, path)
    if ok then
        local user_quotes = normalize(raw)
        if #user_quotes > 0 then return user_quotes end
    end
    return DEFAULT_QUOTES
end

function M.ensureFile()
    return ensure_template(quotes_path())
end

function M.path()
    return quotes_path()
end

return M
