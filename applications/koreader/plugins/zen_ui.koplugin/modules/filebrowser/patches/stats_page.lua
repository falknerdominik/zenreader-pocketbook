-- Zen UI Stats Page
-- Fullscreen reading stats display with up to 5 configurable rows.
-- Tap-and-hold a row to change it.

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local StandalonePage = require("modules/filebrowser/patches/standalone_page")
local SharedState = require("common/shared_state")
local Screen = Device.screen
local _ = require("gettext")

-- Format seconds as "Xh Ym" or "Ym"
local function formatTime(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return "0m" end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        return h .. "h " .. m .. "m"
    else
        return m .. "m"
    end
end

-- Format with day-scale support: "Xd Xh", "Xh Ym", or "Ym"
local function formatLongTime(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return "0m" end
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    local m = math.floor((secs % 3600) / 60)
    if d > 0 then
        return h > 0 and (d .. "d " .. h .. "h") or (d .. "d")
    elseif h > 0 then
        return h .. "h " .. m .. "m"
    else
        return m .. "m"
    end
end

-- Peak date label helpers
local function fmtPeakDay(ts)
    if not ts then return "" end
    return os.date("%b %d", ts):gsub(" 0(%d)", " %1")
end

local function fmtPeakWeek(ts)
    if not ts then return "" end
    local t = os.date("*t", ts)
    local days_to_mon = (t.wday - 2) % 7
    local mon_ts = ts - days_to_mon * 86400
    local sun_ts = mon_ts + 6 * 86400
    local mon_str = os.date("%b %d", mon_ts):gsub(" 0(%d)", " %1")
    if os.date("%m", mon_ts) == os.date("%m", sun_ts) then
        return mon_str .. "\u{2013}" .. os.date("%d", sun_ts):gsub("^0", "")
    else
        return mon_str .. "\u{2013}" .. os.date("%b %d", sun_ts):gsub(" 0(%d)", " %1")
    end
end

local function fmtPeakMonth(ts)
    if not ts then return "" end
    return os.date("%b %Y", ts)
end

local StatsDB       = require("common/db_stats")
local LibraryDB     = require("common/db_library")
local BookInfoDB    = require("common/db_bookinfo")
local ConfigManager = require("config/manager")
local active_stats_menus = {}

local MAX_ROWS = 5

-- All available row type IDs, in the order shown in the selection menu.
local ALL_ROW_TYPES = {
    "today", "this_week", "this_month", "this_year",
    "all_time", "personal_records", "library",
}

-- Human-readable title for a row type (shown in the change/add menus).
local function rowTitle(type_id)
    local titles = {
        today            = _("Today"),
        this_week        = _("This Week"),
        this_month       = _("This Month"),
        this_year        = _("This Year"),
        all_time         = _("All Time"),
        personal_records = _("Personal Records"),
        library          = _("Library"),
    }
    return titles[type_id] or type_id
end

-- Load/save the rows array from the plugin config.
local function loadRowsConfig()
    local defaults = { "today", "this_month", "this_year", "all_time", "library" }
    -- build a lookup for valid types
    local valid = {}
    for _i, rt in ipairs(ALL_ROW_TYPES) do valid[rt] = true end

    local ok, cfg = pcall(ConfigManager.load)
    if ok and type(cfg) == "table"
       and cfg.stats_page and type(cfg.stats_page.rows) == "table" then
        local rows = {}
        for _i, rt in ipairs(cfg.stats_page.rows) do
            if valid[rt] then
                rows[#rows + 1] = rt
            end
            if #rows >= MAX_ROWS then break end
        end
        if #rows >= MAX_ROWS then return rows end
        -- backfill with defaults for any missing slots
        local used = {}
        for _i, rt in ipairs(rows) do used[rt] = true end
        for _i, rt in ipairs(defaults) do
            if not used[rt] then
                rows[#rows + 1] = rt
                if #rows >= MAX_ROWS then break end
            end
        end
        return rows
    end
    return defaults
end

local function saveRowsConfig(rows)
    local ok, cfg = pcall(ConfigManager.load)
    if not ok or type(cfg) ~= "table" then return end
    cfg.stats_page      = cfg.stats_page or {}
    cfg.stats_page.rows = rows
    pcall(ConfigManager.save, cfg)
end

-- ─── Stats query ───────────────────────────────────────────────────

local StatsPage = {}

local function queryStats()
    local stats = StatsDB.queryStats()
    local book_counts = LibraryDB.getBookCounts()
    stats.books_finished = book_counts.finished
    stats.books_reading  = book_counts.reading
    -- use bookinfo cache for total count: covers all books regardless of read status
    stats.total_books = BookInfoDB.getTotalBookCount()
    return stats
end

-- ─── Card widget ───────────────────────────────────────────────────

local function createCard(opts)
    local card_w     = opts.width
    local card_h     = opts.height
    local value_font = Font:getFace("infofont",      opts.value_size  or 28)
    local label_font = Font:getFace("smallinfofont", opts.label_size  or 16)
    local hdr_font   = Font:getFace("smallinfofont", opts.header_size or 16)

    local padding = Screen:scaleBySize(8)
    local margin  = Screen:scaleBySize(4)
    local inner_w = card_w - (margin + padding) * 2

    local content_items = { align = "center" }
    if (opts.header or "") ~= "" then
        content_items[#content_items + 1] = TextWidget:new{
            text      = opts.header,
            face      = hdr_font,
            fgcolor   = Blitbuffer.Color8(0x66),
            max_width = inner_w,
        }
        content_items[#content_items + 1] = VerticalSpan:new{ width = Screen:scaleBySize(2) }
    end
    content_items[#content_items + 1] = TextWidget:new{
        text      = opts.value or "",
        face      = value_font,
        max_width = inner_w,
    }
    content_items[#content_items + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
    content_items[#content_items + 1] = TextWidget:new{
        text      = opts.label or "",
        face      = label_font,
        fgcolor   = Blitbuffer.Color8(0x66),
        max_width = inner_w,
    }

    local content  = VerticalGroup:new(content_items)
    local chrome_h = (margin + padding) * 2
    local actual_h = math.max(card_h, content:getSize().h + chrome_h)

    return FrameContainer:new{
        width      = card_w,
        height     = actual_h,
        padding    = padding,
        margin     = margin,
        bordersize = 0,
        radius     = Screen:scaleBySize(8),
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = actual_h - chrome_h },
            content,
        },
    }
end

-- ─── Content builder ───────────────────────────────────────────────
-- Returns (VerticalGroup, row_hits).
-- row_hits[i] = { row_idx=i, y_start=N, y_end=N } (y relative to content top).

local function buildContent(sc, rows_config, stats, page_w, h_padding)
    local function sz(x) return math.floor(Screen:scaleBySize(x) * sc) end
    local function fsz(base) return math.max(8, math.floor(base * sc)) end

    local content_w = page_w - h_padding * 2

    local function card(opts)
        opts.value_size  = fsz(opts.value_size  or 28)
        opts.label_size  = fsz(opts.label_size  or 16)
        opts.header_size = fsz(opts.header_size or 16)
        return createCard(opts)
    end

    local function makeRow(cards)
        local row_h = 0
        for _i, c in ipairs(cards) do
            local h = c:getSize().h
            if h > row_h then row_h = h end
        end
        local hg = HorizontalGroup:new{ align = "center" }
        for i, c in ipairs(cards) do
            hg[#hg + 1] = c
            if i < #cards then
                hg[#hg + 1] = LineWidget:new{
                    dimen      = Geom:new{ w = 1, h = row_h },
                    background = Blitbuffer.COLOR_BLACK,
                }
            end
        end
        return CenterContainer:new{
            dimen = Geom:new{ w = page_w, h = row_h + sz(8) },
            hg,
        }
    end

    local function hdr(text)
        return LeftContainer:new{
            dimen = Geom:new{ w = page_w, h = sz(28) },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = h_padding },
                TextWidget:new{
                    text = text,
                    face = Font:getFace("smallinfofontbold", fsz(18)),
                },
            },
        }
    end

    local c3_w = math.floor((content_w - sz(8)) / 3)
    local c4_w = math.floor((content_w - sz(8)) / 4)
    local c3_h = sz(80)
    local c4_h = sz(80)
    local c2_h = sz(60)

    local now_t           = os.date("*t")
    local days_this_month = math.max(1, now_t.day)
    local days_this_year  = math.max(1, now_t.yday)

    -- Per-row builder functions (closures over layout vars and stats)
    local ROW_BUILD = {
        today = function()
            return makeRow{
                card{ width=c3_w, height=c3_h,
                      value=tostring(stats.today_pages),      label=_("pages today") },
                card{ width=c3_w, height=c3_h,
                      value=formatTime(stats.today_duration), label=_("read today") },
                card{ width=c3_w, height=c3_h,
                      value=tostring(stats.streak),           label=_("day streak") },
            }
        end,
        this_week = function()
            local avg_p = stats.week_pages    > 0 and math.floor(stats.week_pages    / 7) or 0
            local avg_t = stats.week_duration > 0 and math.floor(stats.week_duration / 7) or 0
            return makeRow{
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=tostring(stats.week_pages),       label=_("pages") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=tostring(avg_p),                  label=_("avg pages/day") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=formatTime(avg_t),                label=_("avg time/day") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=formatTime(stats.week_duration),  label=_("total time") },
            }
        end,
        this_month = function()
            local mp    = stats.month_pages    or 0
            local md    = stats.month_duration or 0
            local avg_p = math.floor(mp / days_this_month)
            local avg_t = math.floor(md / days_this_month)
            return makeRow{
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=tostring(mp),        label=_("pages") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=tostring(avg_p),     label=_("avg pages/day") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=formatTime(avg_t),   label=_("avg time/day") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=formatTime(md),      label=_("total time") },
            }
        end,
        this_year = function()
            local yp    = stats.year_pages    or 0
            local yd    = stats.year_duration or 0
            local avg_t = math.floor(yd / days_this_year)
            return makeRow{
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=tostring(yp),                          label=_("pages") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=formatTime(avg_t),                     label=_("avg time/day") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=formatTime(yd),                        label=_("total time") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=tostring(stats.books_this_year  or 0),  label=_("books read") },
            }
        end,
        all_time = function()
            return makeRow{
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=tostring(stats.lifetime_pages),           label=_("total pages read") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=formatTime(stats.avg_time_per_book),      label=_("avg time/book") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=formatLongTime(stats.lifetime_read_time), label=_("total read time") },
                card{ width=c4_w, height=c4_h, value_size=24,
                      value=tostring(stats.books_finished),         label=_("books finished") },
            }
        end,
        personal_records = function()
            return makeRow{
                card{ width=c3_w, height=c4_h, value_size=24,
                      header=_("best day"),   value=formatTime(stats.peak_day_duration),
                      label=fmtPeakDay(stats.peak_day_ts) },
                card{ width=c3_w, height=c4_h, value_size=24,
                      header=_("best week"),  value=formatTime(stats.peak_week_duration),
                      label=fmtPeakWeek(stats.peak_week_ts) },
                card{ width=c3_w, height=c4_h, value_size=24,
                      header=_("best month"), value=formatLongTime(stats.peak_month_duration),
                      label=fmtPeakMonth(stats.peak_month_ts) },
            }
        end,
        library = function()
            return makeRow{
                card{ width=c3_w, height=c2_h,
                      value=tostring(stats.total_books),    label=_("total books") },
                card{ width=c3_w, height=c2_h,
                      value=tostring(stats.books_reading),  label=_("reading") },
                card{ width=c3_w, height=c2_h,
                      value=tostring(stats.books_finished), label=_("finished") },
            }
        end,
    }

    -- Assemble rows, tracking y hit-test positions
    local items   = { align = "center" }
    local row_hits = {}
    local y_acc   = sz(10)
    items[#items + 1] = VerticalSpan:new{ width = sz(10) }

    for i, row_type in ipairs(rows_config) do
        local builder = ROW_BUILD[row_type]
        if builder then
            local span_h = sz(4)
            items[#items + 1] = hdr(rowTitle(row_type))
            items[#items + 1] = VerticalSpan:new{ width = span_h }
            y_acc = y_acc + sz(28) + span_h

            local row_w = builder()
            local row_h = row_w:getSize().h
            items[#items + 1] = row_w
            row_hits[#row_hits + 1] = {
                row_idx = i,
                y_start = y_acc,
                y_end   = y_acc + row_h,
            }
            y_acc = y_acc + row_h

            if i < #rows_config then
                local gap_h = sz(12)
                items[#items + 1] = VerticalSpan:new{ width = gap_h }
                y_acc = y_acc + gap_h
            end
        end
    end

    return VerticalGroup:new(items), row_hits
end

-- ─── Menu factory ──────────────────────────────────────────────────

--- Create and return a fully-configured stats page Menu.
-- @param createStatusRow  function from zen_shared (or nil)
-- @param repaintTitleBar  function from zen_shared (or nil)
-- @return Menu widget ready for injectStandaloneNavbar + UIManager:show
function StatsPage.create(createStatusRow, repaintTitleBar)
    local stats      = queryStats()
    local rows_config = loadRowsConfig()

    local menu = StandalonePage.create_menu{
        name = "stats",
        title = " ",
    }
    StandalonePage.prepare_shell(menu)
    StandalonePage.apply_status_row(menu, {
        createStatusRow = createStatusRow,
        repaintTitleBar = repaintTitleBar,
    })
    local tb = menu.title_bar

    -- Layout dimensions (fixed for the lifetime of this page)
    local tb_h      = tb and tb:getSize().h or 0
    local body_h    = (menu.inner_dimen and menu.inner_dimen.h or menu.dimen.h) - tb_h
    local page_w    = menu.inner_dimen and menu.inner_dimen.w or Screen:getWidth()
    local h_padding = Screen:scaleBySize(16)

    -- Build active rows with scaling to fit body_h.
    local sc = 1.0
    local content, row_hits = buildContent(sc, rows_config, stats, page_w, h_padding)
    local content_h = content:getSize().h
    for _i = 1, 3 do
        if content_h <= body_h then break end
        sc = sc * body_h / content_h
        content, row_hits = buildContent(sc, rows_config, stats, page_w, h_padding)
        content_h = content:getSize().h
    end

    -- Append remaining vertical space below active rows.
    local remaining = body_h - content_h
    if remaining > 0 then
        content[#content + 1] = VerticalSpan:new{ width = remaining }
        content:resetLayout()
    end

    -- Rebuild active + empty content in-place (called after config changes).
    local function rebuildStats()
        local new_sc = 1.0
        local new_content, new_row_hits =
            buildContent(new_sc, rows_config, stats, page_w, h_padding)
        local new_h = new_content:getSize().h
        for _i = 1, 3 do
            if new_h <= body_h then break end
            new_sc = new_sc * body_h / new_h
            new_content, new_row_hits =
                buildContent(new_sc, rows_config, stats, page_w, h_padding)
            new_h = new_content:getSize().h
        end
        local rem = body_h - new_h
        if rem > 0 then
            new_content[#new_content + 1] = VerticalSpan:new{ width = rem }
            new_content:resetLayout()
        end

        StandalonePage.mount_body(menu, new_content)

        row_hits = new_row_hits
        UIManager:setDirty(menu, "ui")
    end

    -- ── Hold gesture dialogs ──────────────────────────────────────────

    local function showRowChangeMenu(row_idx)
        local current_type = rows_config[row_idx]
        local used = {}
        for _i, rt in ipairs(rows_config) do used[rt] = true end

        local buttons = {}
        for _i, type_id in ipairs(ALL_ROW_TYPES) do
            local is_current = type_id == current_type
            local is_taken   = used[type_id] and not is_current
            local tid = type_id
            buttons[#buttons + 1] = {{
                text     = rowTitle(tid) .. (is_current and "  \u{2713}" or ""),
                align    = "left",
                enabled  = not is_current and not is_taken,
                callback = function()
                    UIManager:close(menu._zen_row_dlg)
                    rows_config[row_idx] = tid
                    saveRowsConfig(rows_config)
                    rebuildStats()
                end,
            }}
        end

        menu._zen_row_dlg = ButtonDialog:new{
            title       = _("Change Row"),
            title_align = "center",
            buttons     = buttons,
        }
        UIManager:show(menu._zen_row_dlg)
    end

    -- Register a screen-wide hold gesture on the menu widget.
    if not menu.ges_events then menu.ges_events = {} end
    menu.ges_events.ZenStatsHold = {
        GestureRange:new{
            ges   = "hold",
            range = Geom:new{ x = 0, y = 0,
                              w = Screen:getWidth(), h = Screen:getHeight() },
        },
    }
    function menu:onZenStatsHold(_ges_event, ges)
        local offset_y  = self.dimen and self.dimen.y or 0
        local content_y = ges.pos.y - offset_y - tb_h
        if content_y < 0 then return false end  -- hold in title bar

        for _i, rp in ipairs(row_hits) do
            if content_y >= rp.y_start and content_y < rp.y_end then
                showRowChangeMenu(rp.row_idx)
                return true
            end
        end
        return false
    end

    -- ── Populate item_group ───────────────────────────────────────────
    StandalonePage.mount_body(menu, content)

    if menu.page_info then
        while #menu.page_info > 0 do table.remove(menu.page_info) end
        menu.page_info:resetLayout()
    end

    -- Periodic clock updates are driven by status_bar.lua autoRefresh.
    menu.close_callback = function()
        UIManager:close(menu)
    end

    active_stats_menus[#active_stats_menus + 1] = menu
    local orig_onCloseWidget = menu.onCloseWidget
    function menu:onCloseWidget(...)
        for i = #active_stats_menus, 1, -1 do
            if rawequal(active_stats_menus[i], self) then
                table.remove(active_stats_menus, i)
                break
            end
        end
        if self._zen_row_dlg then
            UIManager:close(self._zen_row_dlg)
            self._zen_row_dlg = nil
        end
        if orig_onCloseWidget then
            return orig_onCloseWidget(self, ...)
        end
    end

    -- Flash-refresh once after the widget is painted for the first time.
    UIManager:scheduleIn(0, function()
        UIManager:setDirty(menu, "flashui")
    end)

    return menu
end

function StatsPage.closeAll()
    for i = #active_stats_menus, 1, -1 do
        local menu = active_stats_menus[i]
        if menu then
            if menu._zen_row_dlg then
                UIManager:close(menu._zen_row_dlg)
                menu._zen_row_dlg = nil
            end
            UIManager:close(menu)
        end
        active_stats_menus[i] = nil
    end
end

local function register_stats_api(zen_plugin)
    if not zen_plugin or type(zen_plugin.config) ~= "table" then return end
    SharedState.register(zen_plugin, { stats = StatsPage })
end

SharedState.registerLoader("stats", register_stats_api)

return StatsPage
