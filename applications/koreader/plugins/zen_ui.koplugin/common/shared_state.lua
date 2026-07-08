local M = {}
local loaders = {}
local loading = {}

local function ensure_tables(plugin)
    if type(plugin) ~= "table" then return nil, nil end
    if type(plugin._zen_shared) ~= "table" then
        plugin._zen_shared = {}
    end
    if type(plugin._zen_shared_registry) ~= "table" then
        plugin._zen_shared_registry = {}
    end
    return plugin._zen_shared, plugin._zen_shared_registry
end

function M.register(plugin, entries)
    local shared, registry = ensure_tables(plugin)
    if not shared or type(entries) ~= "table" then return nil end
    for key, value in pairs(entries) do
        registry[key] = value
        shared[key] = value
    end
    return shared
end

function M.registerLoader(keys, loader)
    if type(loader) ~= "function" then return end
    if type(keys) == "string" then
        loaders[keys] = loader
    elseif type(keys) == "table" then
        for _i, key in ipairs(keys) do
            if type(key) == "string" then
                loaders[key] = loader
            end
        end
    end
end

local function run_loader(plugin, key)
    local loader = loaders[key]
    if not loader or loading[key] then return end
    loading[key] = true
    pcall(loader, plugin)
    loading[key] = nil
end

function M.restore(plugin)
    local shared, registry = ensure_tables(plugin)
    if not shared then return nil end
    for key, _loader in pairs(loaders) do
        if registry[key] == nil then
            run_loader(plugin, key)
        end
    end
    for key, value in pairs(registry) do
        shared[key] = value
    end
    return shared
end

function M.get(plugin, key)
    local shared, registry = ensure_tables(plugin)
    if not shared then return nil end
    if key ~= nil and registry[key] == nil then
        run_loader(plugin, key)
    end
    shared = M.restore(plugin)
    return shared and shared[key]
end

return M
