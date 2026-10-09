-- Squad select (and roster screens): a fatigue banner under each slot's injury banner, and a Zzz marker
-- on each portrait tile. Prototyped and verified in the probe (docs/phase0-findings.md, 2026-10-08/09).
--
-- Both are copies of the game's own widgets (no new art): the banner copies WBP_InjuryWarningEntry, the
-- marker copies WBP_HeroInjuries. The copies have no view model, so Off Duty sets their text, icon,
-- colour and tooltip. Their state animations re-apply injury red every frame: stop them, then recolour on
-- a later frame (stopping restores the design colours on the next frame, overwriting a same-frame tint).
--
-- Triggers (Blueprint functions, so hookable): a slot changing operator (FilledSlotState, EmptySlotState,
-- the FullName notify) and a tile receiving its operator (OnListItemObjectSet). Each refreshes only that
-- widget, debounced. Our copies are found again by class among the native widget's siblings, so a hot
-- reload adopts them instead of adding more.
local Rules = require("rules")
local Game = require("game")

local M = {}

local SLOT = "/Game/Game/UI/Strategy/SquadSelect/Widgets/WBP_CharacterSlot.WBP_CharacterSlot_C"
local TILE = "/Game/Game/UI/Strategy/_Common/Widgets/WBP_RosterTile.WBP_RosterTile_C"
local SLOT_EVENTS = {
    "FilledSlotState", "EmptySlotState",
    "BndEvt__WBP_CharacterSlot_BrunoCharacterViewModel_MDVMNode_ViewModelFieldNotify_13_FullName",
}
local TILE_EVENTS = { "OnListItemObjectSet" }
local INSTALL_RETRY_MS = { 1000, 5000, 15000, 60000 }
local REFRESH_DELAY_MS = 50
local STOP_DELAY_MS, RECOLOUR_DELAY_MS = 100, 150

-- The game sizes the banner's Sizer box at runtime (250x34 with "1 INJURY", text 76 wide); a copy keeps
-- the design default 380x36. Widen by however much longer our label is.
local BANNER_SIZE, BANNER_TEXT_WIDTH = { 250, 34 }, 76
-- Banner parts and their brightness relative to the tier colour (as the red version has them).
local BANNER_PARTS = { Back = 1.0, PillBack = 1.0, EndCapBG = 1.0, GlowBack = 0.64, PillBack_Highlight = 1.6 }
local VISIBLE, COLLAPSED, HIDDEN, SELF_HIT_TEST_INVISIBLE = 0, 1, 2, 4
local ALIGN_RIGHT = 3

function M.new(ctx)
    local g, log, actions, icons = ctx.game, ctx.log, ctx.actions, ctx.icons
    local self = {}
    local warned = {}

    local function warn_once(key, fmt, ...)
        if warned[key] then return end
        warned[key] = true
        log("WARNING: squad UI | " .. fmt, ...)
    end

    -- Widgets ---------------------------------------------------------------------------------------

    local function widget_name(widget)
        local ok, name = pcall(function() return widget:GetFName():ToString() end)
        return ok and tostring(name) or "?"
    end

    -- Designer widgets that aren't "Is Variable" have no property: walk the tree by name.
    local function parts_of(user_widget)
        local parts = {}
        local root = g.read(user_widget, "WidgetTree")
        root = root and g.read(root, "RootWidget")
        local function walk(widget, depth)
            if not g.valid(widget) or depth > 12 then return end
            parts[widget_name(widget)] = widget
            local count = tonumber((g.call(widget, "GetChildrenCount"))) or 0
            for i = 0, count - 1 do walk((g.call(widget, "GetChildAt", i)), depth + 1) end
        end
        walk(root, 0)
        return parts
    end

    local function class_path(object)
        local class = (g.call(object, "GetClass"))
        return g.full_name(class):match("%s(%S+)$") or ""
    end

    -- Our copies: siblings of `native` with the same class (the native one is excluded).
    local function our_copies(parent, native)
        local copies = {}
        local native_class, native_address = class_path(native), g.address(native)
        local count = tonumber((g.call(parent, "GetChildrenCount"))) or 0
        for i = 0, count - 1 do
            local child = (g.call(parent, "GetChildAt", i))
            if g.valid(child) and g.address(child) ~= native_address and class_path(child) == native_class then
                copies[#copies + 1] = child
            end
        end
        return copies
    end

    local function remove_copies(parent, native)
        for _, copy in ipairs(our_copies(parent, native)) do pcall(function() copy:RemoveFromParent() end) end
    end

    -- A copy of `native` in `parent`: an existing one (adopted) or a new one laid out like the native.
    local function ensure_copy(owner, parent, native)
        local copies = our_copies(parent, native)
        for i = 2, #copies do pcall(function() copies[i]:RemoveFromParent() end) end -- keep one
        if copies[1] then return copies[1], false end
        local library = g.cdo("/Script/UMG.Default__WidgetBlueprintLibrary")
        local copy, err = g.call(library, "Create", owner, (g.call(native, "GetClass")), (g.call(native, "GetOwningPlayer")))
        if not g.valid(copy) then return nil, err or "Create failed" end
        local new_slot = (g.call(parent, "AddChild", copy))
        local native_slot = g.read(native, "Slot")
        if g.valid(new_slot) and g.valid(native_slot) then
            for _, pair in ipairs({ { "Padding", "SetPadding" }, { "HorizontalAlignment", "SetHorizontalAlignment" },
                                    { "VerticalAlignment", "SetVerticalAlignment" }, { "Size", "SetSize" } }) do
                pcall(function() new_slot[pair[2]](new_slot, native_slot[pair[1]]) end)
            end
        end
        return copy, true
    end

    -- Colours and text --------------------------------------------------------------------------------

    local function colour_of(tier)
        if type(tier.colour) == "table" then return tier.colour end
        local bank = g.cdo("/Script/BitReactorGame.Default__BitReactorColorBank")
        local c = (g.call(bank, "GetColor", { TagName = FName(tier.colour) }))
        local ok, out = pcall(function() return { R = c.R, G = c.G, B = c.B, A = c.A } end)
        if ok and type(out.R) == "number" then return out end
        return { R = 0.98, G = 0.45, B = 0.07, A = 1.0 }
    end

    local function set_tooltip(box, tier, points)
        if not g.valid(box) then return end
        g.call(box, "SetTooltipPayloadTags", {})
        g.call(box, "SetTooltipPayloadObjects", {})
        g.call(box, "SetTooltipPayloadEntries", {
            { HeaderText = FText(tier.label), BodyText = FText(Rules.tooltip(tier, points, ctx.settings())) } })
        g.call(box, "SetDisplayTooltop", true)
    end

    local function tooltip_box(parts)
        for name, widget in pairs(parts) do
            if name == "WarningTooltip" or name:find("^BitReactorTooltipBox") then return widget end
        end
        return nil
    end

    -- Stop the copy's state animation, then tint on a later frame.
    local function tint_later(copy, tint)
        actions:schedule_after("squad_ui_tint", STOP_DELAY_MS, function()
            g.call(copy, "StopAllAnimations")
            actions:schedule_after("squad_ui_tint", RECOLOUR_DELAY_MS, tint, copy)
        end, copy)
    end

    -- Fatigue lookup --------------------------------------------------------------------------------

    local function fatigue_by_operator()
        local by_name, by_id = {}, {}
        local wco = g.world_context()
        local class = g.effect_class(Game.FATIGUE)
        if not wco or not class then return by_name, by_id end
        for _, member in ipairs(g.roster(wco)) do
            local asc = member.actor and g.asc(member.actor)
            if asc then
                local points = g.effect_count(asc, class)
                local name = g.character_name(member.actor)
                if name then by_name[name:upper()] = points end
                if member.id then by_id[member.id] = points end
            end
        end
        return by_name, by_id
    end

    local function current_tier(points)
        return points and Rules.tier(points, Rules.normalise(ctx.settings()).preset) or nil
    end

    -- Squad slots ---------------------------------------------------------------------------------------

    local function refresh_slot(slot)
        if not g.live(slot) then return end
        local native = g.read(slot, "WBP_InjuryWarningEntry")
        local parent = g.valid(native) and (g.call(native, "GetParent")) or nil
        if not g.valid(parent) then warn_once("slot_parent", "slot has no injury banner parent") return end
        local full_name = g.read(slot, "FullName")
        local name = g.plain(g.text(full_name and (g.call(full_name, "GetText"))) or ""):upper()
        local points = name ~= "" and (fatigue_by_operator())[name] or nil
        local tier = current_tier(points)
        if not tier then remove_copies(parent, native) return end

        local banner, created = ensure_copy(slot, parent, native)
        if not banner then warn_once("banner_create", "could not create a banner | %s", tostring(created)) return end
        local parts = parts_of(banner)
        g.call(parts.HeaderText or g.read(banner, "HeaderText"), "SetText", FText(tier.label))
        -- The game shows Injury_1 for one injury and adds Injury_2 for two; ours shows the tier's Zzz icon.
        g.call(parts.Injury_1, "SetVisibility", SELF_HIT_TEST_INVISIBLE)
        g.call(parts.Injury_2, "SetVisibility", HIDDEN)
        local icon = icons.texture(tier.level)
        if icon then g.call(parts.Injury_1, "SetBrushFromTexture", icon, false) end
        g.call(parts.Sizer, "SetWidthOverride", BANNER_SIZE[1])
        g.call(parts.Sizer, "SetHeightOverride", BANNER_SIZE[2])
        set_tooltip(tooltip_box(parts), tier, points)
        g.call(banner, "SetVisibility", SELF_HIT_TEST_INVISIBLE)

        local colour = colour_of(tier)
        tint_later(banner, function()
            for part, scale in pairs(BANNER_PARTS) do
                g.call(parts[part], "SetColorAndOpacity", { R = math.min(1, colour.R * scale),
                    G = math.min(1, colour.G * scale), B = math.min(1, colour.B * scale), A = colour.A })
            end
            local ok, width = pcall(function() return parts.HeaderText:GetDesiredSize().X end)
            if ok and type(width) == "number" then
                g.call(parts.Sizer, "SetWidthOverride", BANNER_SIZE[1] + math.max(0, width - BANNER_TEXT_WIDTH))
            end
        end)
    end

    -- Portrait tiles ------------------------------------------------------------------------------------

    local function refresh_tile(tile)
        if not g.live(tile) then return end
        local native = g.read(tile, "WBP_HeroInjuries")
        local parent = g.valid(native) and (g.call(native, "GetParent")) or nil
        if not g.valid(parent) then return end -- tiles without an injury marker slot
        local list_library = g.cdo("/Script/UMG.Default__UserObjectListEntryLibrary")
        local item = (g.call(list_library, "GetListItemObject", tile))
        local id = item and g.guid_string((g.call(item, "GetCharacterID"))) or nil
        local _, by_id = fatigue_by_operator()
        local points = id and by_id[id] or nil
        local tier = current_tier(points)
        if not tier then remove_copies(parent, native) return end

        local marker, created = ensure_copy(tile, parent, native)
        if not marker then warn_once("marker_create", "could not create a portrait marker | %s", tostring(created)) return end
        if created then
            local slot = g.read(marker, "Slot")
            g.call(slot, "SetHorizontalAlignment", ALIGN_RIGHT) -- the injury marker sits bottom left
        end
        local parts = parts_of(marker)
        g.call(parts.Injury_2, "SetVisibility", COLLAPSED)
        g.call(parts.Injury_1, "SetVisibility", SELF_HIT_TEST_INVISIBLE)
        local icon = icons.texture(tier.level)
        if icon then g.call(parts.Injury_1, "SetBrushFromTexture", icon, false) end
        set_tooltip(tooltip_box(parts), tier, points)
        g.call(marker, "SetVisibility", SELF_HIT_TEST_INVISIBLE)
        local colour = colour_of(tier)
        tint_later(marker, function() g.call(parts.Injury_1, "SetColorAndOpacity", colour) end)
    end

    -- Hooks -----------------------------------------------------------------------------------------------

    local function schedule_refresh(kind, widget, refresh)
        local address = g.address(widget)
        if not address then return end
        local group = kind .. ":" .. tostring(address)
        actions:cancel_group(group, "superseded")
        actions:schedule_after(group, REFRESH_DELAY_MS, g.safe(kind .. " refresh", function() refresh(widget) end), widget)
    end

    local installed = {}
    local function install_hooks(reason)
        local missing = 0
        for class, events in pairs({ [SLOT] = SLOT_EVENTS, [TILE] = TILE_EVENTS }) do
            for _, event in ipairs(events) do
                local path = class .. ":" .. event
                if not installed[path] then
                    local is_slot = class == SLOT
                    local callback = g.safe(event, function(context)
                        local widget = g.unwrap(context)
                        if is_slot then schedule_refresh("slot", widget, refresh_slot)
                        else schedule_refresh("tile", widget, refresh_tile) end
                    end)
                    local ok = pcall(function() ctx.runtime:register_hook(path, function() end, callback) end)
                    if ok then installed[path] = true; log("Hooked | %s", path) else missing = missing + 1 end
                end
            end
        end
        if missing > 0 then log("Squad UI | %d hook(s) not ready (%s); will retry", missing, reason) end
        return missing == 0
    end

    function self:install()
        if install_hooks("startup") then return end
        for _, delay in ipairs(INSTALL_RETRY_MS) do
            actions:schedule_after("squad_ui_install", delay, g.safe("squad UI install", function()
                if install_hooks("retry") then actions:cancel_group("squad_ui_install", "installed") end
            end))
        end
    end

    -- Refresh everything on screen (e.g. after settings change).
    function self:refresh_all()
        for _, class_name in ipairs({ "WBP_CharacterSlot_C", "WBP_RosterTile_C" }) do
            local ok, widgets = pcall(FindAllOf, class_name)
            for _, widget in pairs(ok and widgets or {}) do
                if g.live(widget) then
                    if class_name == "WBP_CharacterSlot_C" then schedule_refresh("slot", widget, refresh_slot)
                    else schedule_refresh("tile", widget, refresh_tile) end
                end
            end
        end
    end

    return self
end

return M
