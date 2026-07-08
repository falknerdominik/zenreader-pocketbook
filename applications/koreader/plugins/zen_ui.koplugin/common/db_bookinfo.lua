-- common/db_bookinfo.lua
-- Queries KOReader's bookinfo_cache.sqlite3 to group books by author or series.
-- Used by the Authors and Series navbar tabs.

local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local paths = require("common/paths")
local bimOk, BookInfoManager = pcall(require, "bookinfomanager")

local M = {}

-- Returns the authors string as-is (no splitting) so multi-author books
-- are grouped under their combined author string.
local function splitAuthors(authors_str)
    if not authors_str or authors_str == "" then return {} end
    local trimmed = authors_str:match("^%s*(.-)%s*$")
    if trimmed == "" then return {} end
    return { trimmed }
end

-- Returns a sorted list of author groups:
--   { { author="Name", files={"/abs/path", ...} }, ... }
-- Only includes books within home_dir that still exist on disk.
-- Each book appears under every author it has (multi-author support).
function M.getGroupedByAuthor()
    if not bimOk then
        logger.warn("zen-ui getGroupedByAuthor: BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn

    local home_dir = paths.getHomeDir()

    local author_map = {}  -- author -> { files }

    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename, authors
            FROM bookinfo
            WHERE in_progress = 0
              AND authors IS NOT NULL
              AND authors != ''
            ORDER BY authors
        ]]
        local res = conn:exec(sql)
        if not res then return end

        local dirs      = res[1] or {}
        local filenames = res[2] or {}
        local authors_col = res[3] or {}
        logger.info("zen-ui db_bookinfo: getGroupedByAuthor rows from SQL:", #dirs)

        for i = 1, #dirs do
            local dir    = dirs[i]
            local fname  = filenames[i]
            local authors_str = authors_col[i]

            if not dir or not fname or not authors_str then goto continue end

            local raw_filepath  = dir .. fname
            local norm_filepath = paths.normPath(raw_filepath)

            -- Skip if outside home_dir (compare normalized to handle /sdcard symlink)
            if home_dir and not paths.isInHomeDir(norm_filepath) then
                goto continue
            end

            -- Skip if file no longer exists on disk (use normalized path for safety on Android).
            if lfs.attributes(norm_filepath, "mode") ~= "file" then
                goto continue
            end

            -- Keep raw path so BookInfoManager can find the SQLite entry by its key.
            local author_list = splitAuthors(authors_str)
            for _i, author in ipairs(author_list) do
                if not author_map[author] then
                    author_map[author] = {}
                end
                table.insert(author_map[author], raw_filepath)
            end

            ::continue::
        end
    end)

    if not ok2 then
        logger.warn("zen-ui db_bookinfo: query error:", err)
        return {}
    end

    -- Build sorted list
    local groups = {}
    for author, files in pairs(author_map) do
        table.insert(groups, { author = author, files = files })
    end
    table.sort(groups, function(a, b)
        return a.author < b.author
    end)

    logger.dbg("zen-ui db_bookinfo: getGroupedByAuthor result:", #groups, "authors")
    return groups
end

-- Returns a sorted list of series groups:
--   { { series="Name", items={ {file="/abs/path", series_index=N}, ... } }, ... }
-- Items within each series are sorted by series_index (then filename as tiebreak).
-- Only includes books within home_dir that still exist on disk.
function M.getGroupedBySeries()
    if not bimOk then
        logger.warn("zen-ui automatic_series_grouping: BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn
    local home_dir = paths.getHomeDir()

    local series_map = {}  -- series_name -> { {file, series_index, filename} }

    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename, series, series_index
            FROM bookinfo
            WHERE in_progress = 0
              AND series IS NOT NULL
              AND series != ''
            ORDER BY series, series_index
        ]]
        local res = conn:exec(sql)
        if not res then return end

        local dirs         = res[1] or {}
        local filenames    = res[2] or {}
        local series_col   = res[3] or {}
        local idx_col      = res[4] or {}
        logger.dbg("zen-ui db_bookinfo: getGroupedBySeries rows from SQL:", #dirs)

        for i = 1, #dirs do
            local dir    = dirs[i]
            local fname  = filenames[i]
            local series = series_col[i]
            local sidx   = tonumber(idx_col[i])

            if not dir or not fname or not series then goto continue end

            local raw_filepath  = dir .. fname
            local norm_filepath = paths.normPath(raw_filepath)

            if home_dir and not paths.isInHomeDir(norm_filepath) then
                goto continue
            end

            if lfs.attributes(norm_filepath, "mode") ~= "file" then
                goto continue
            end

            if not series_map[series] then
                series_map[series] = {}
            end
            -- Keep raw path so BookInfoManager can find the SQLite entry by its key.
            table.insert(series_map[series], {
                file         = raw_filepath,
                series_index = sidx,
                filename     = fname,
            })

            ::continue::
        end
    end)

    if not ok2 then
        logger.warn("zen-ui db_bookinfo: query error:", err)
        return {}
    end

    local groups = {}
    for series, items in pairs(series_map) do
        -- Sort by series_index, then by filename as tiebreak
        table.sort(items, function(a, b)
            local ia = a.series_index or 0
            local ib = b.series_index or 0
            if ia ~= ib then return ia < ib end
            return (a.filename or "") < (b.filename or "")
        end)
        table.insert(groups, { series = series, items = items })
    end
    table.sort(groups, function(a, b)
        return a.series < b.series
    end)

    logger.dbg("zen-ui db_bookinfo: getGroupedBySeries result:", #groups, "series")
    return groups
end

-- Returns explicit TBR books plus computed-New books when configured.
function M.getTBRBooks()
    if not bimOk then
        logger.warn("zen-ui automatic_series_grouping: BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn
    local home_dir = paths.getHomeDir()

    local candidates = {}

    local ok2, err = pcall(function()
        -- Query all books, not just in_progress=0.  Bookshelf (and other
        -- plugins) can set DocSettings status to "abandoned" without
        -- updating the CoverBrowser cache, so a previously-in-progress
        -- book may still have in_progress=1 here.  The authoritative
        -- filter is the sidecar check below.
        local sql = [[
            SELECT directory, filename
            FROM bookinfo
            ORDER BY filename
        ]]
        local res = conn:exec(sql)
        if not res then return end

        local dirs      = res[1] or {}
        local filenames = res[2] or {}

        for i = 1, #dirs do
            local dir   = dirs[i]
            local fname = filenames[i]
            if not dir or not fname then goto continue end
            local raw_filepath  = dir .. fname
            local norm_filepath = paths.normPath(raw_filepath)
            if home_dir and not paths.isInHomeDir(norm_filepath) then
                goto continue
            end
            if lfs.attributes(norm_filepath, "mode") ~= "file" then
                goto continue
            end
            -- Keep raw path so DocSettings sidecar lookup matches the stored key.
            table.insert(candidates, raw_filepath)
            ::continue::
        end
    end)


    if not ok2 then
        logger.warn("zen-ui db_bookinfo: getTBRBooks query error:", err)
        return {}
    end

    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not ok_ds then return {} end

    local BookStatus = require("common/book_status")
    local include_new = BookStatus.includeNewInTBREnabled()
    local result = {}
    for _i, filepath in ipairs(candidates) do
        if DocSettings:hasSidecarFile(filepath) then
            local ok3, doc = pcall(DocSettings.open, DocSettings, filepath)
            if ok3 and doc then
                local summary = doc:readSetting("summary")
                local status = summary and summary.status
                status = BookStatus.migrateLegacyMarker(filepath, status, doc)
                local effective_status = BookStatus.getComputedStatus(
                    filepath, status, doc:readSetting("percent_finished"), doc
                )
                if status == "abandoned"
                        or (include_new and effective_status == "new"
                            and not BookStatus.isImageFile(filepath)) then
                    table.insert(result, filepath)
                end
            end
        elseif include_new and not BookStatus.isImageFile(filepath) then
            table.insert(result, filepath)
        end
    end

    logger.dbg("zen-ui db_bookinfo: getTBRBooks result:", #result, "books")
    return result
end

-- Returns a sorted list of tag groups from the keywords (Calibre tags) column:
--   { { tag="Name", files={"/abs/path", ...} }, ... }
-- Books may appear under multiple tags. Tags are split by comma and trimmed.
-- Only includes books within home_dir that still exist on disk.
function M.getGroupedByTags()
    if not bimOk then
        logger.warn("zen-ui automatic_series_grouping: BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn
    local home_dir = paths.getHomeDir()

    local tag_map = {}  -- tag_name -> { file_paths }

    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename, keywords
            FROM bookinfo
            WHERE keywords IS NOT NULL
              AND keywords != ''
            ORDER BY filename
        ]]
        local res = conn:exec(sql)
        if not res then return end

        local dirs      = res[1] or {}
        local filenames = res[2] or {}
        local kw_col    = res[3] or {}

        for i = 1, #dirs do
            local dir   = dirs[i]
            local fname = filenames[i]
            local kw    = kw_col[i]
            if not dir or not fname or not kw then goto continue end

            local raw_filepath  = dir .. fname
            local norm_filepath = paths.normPath(raw_filepath)

            if home_dir and not paths.isInHomeDir(norm_filepath) then
                goto continue
            end
            if lfs.attributes(norm_filepath, "mode") ~= "file" then
                goto continue
            end

            -- Split newline-separated tags (KOReader default) and also handle comma-separated.
            -- Replace commas with newlines so one gmatch handles both formats.
            local normalized = kw:gsub(",", "\n")
            for tag in normalized:gmatch("[^\n]+") do
                local trimmed = tag:match("^%s*(.-)%s*$")
                if trimmed and trimmed ~= "" then
                    if not tag_map[trimmed] then
                        tag_map[trimmed] = {}
                    end
                    table.insert(tag_map[trimmed], raw_filepath)
                end
            end

            ::continue::
        end
    end)


    if not ok2 then
        logger.warn("zen-ui db_bookinfo: getGroupedByTags query error:", err)
        return {}
    end

    local groups = {}
    for tag, files in pairs(tag_map) do
        table.insert(groups, { tag = tag, files = files })
    end
    table.sort(groups, function(a, b)
        return a.tag < b.tag
    end)

    logger.dbg("zen-ui db_bookinfo: getGroupedByTags result:", #groups, "tags")
    return groups
end

-- Returns the total number of fully-indexed books in the bookinfo cache,
-- across all directories. Uses a SQL COUNT so no lfs calls are made.
function M.getTotalBookCount()
    if not bimOk then
        logger.warn("zen-ui automatic_series_grouping: BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn

    local count = 0
    local ok2, err = pcall(function()
        local row = conn:rowexec("SELECT COUNT(*) FROM bookinfo WHERE in_progress = 0;")
        count = tonumber(row) or 0
    end)
    if not ok2 then
        logger.warn("zen-ui db_bookinfo: getTotalBookCount error:", err)
    end
    logger.info("zen-ui db_bookinfo: total_book_count=", count)
    return count
end

return M
