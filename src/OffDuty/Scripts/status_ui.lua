-- In-mission debuff text and icons.
--
-- The tactical status lists (Inspect panel Debuffs; the icons beside the health bar) name a status by
-- its StatusEffectTag's tag UI view model. Each tier effect's tag (OffDuty.Status.<Tier>, shipped in
-- OffDutyTags_P.pak) has no game UI data, so the game finds no view model and the status shows blank.
-- When a list is read we build one for each of our statuses: name, description, and the Zzz icon.
-- Verified in game 2026-10-09 (docs/phase0-findings.md). Hard rules from that work:
-- - build a fresh view model per status, never cache it in Lua (a freed one crashed the HUD);
-- - set the brush's hard ResourceObject and BrushType None; never write its soft pointer
--   (WeakResourceObject writes crash UE4SS 3.0.1; with type Texture2D the game reloads the soft
--   pointer over ours).
local Rules = require("rules")

local M = {}

local STATUS_LIST = "/Script/BitReactorGame.BRG_ActiveStatusEffectsListViewModel:GetStatusEffects"
local TAG_VM_CLASS = "/Script/BitReactorGame.BitReactorTagUIDataViewModel"
local TAG_VM_CDO = "/Script/BitReactorGame.Default__BitReactorTagUIDataViewModel"
local BRUSH_DONOR = "BitReactor.Status.Character.Lethargy" -- size, draw type and tint to copy
local BRUSH_TYPE_NONE = 0

function M.new(ctx)
    local g, log, icons = ctx.game, ctx.log, ctx.icons
    local self = {}
    local busy = false -- GetStatusEffects below re-enters the hook
    local logged = {}

    local function tier_of(status_vm)
        local ok, container = pcall(function() return status_vm.AssetTags end)
        if not ok then return nil end
        for _, tag in ipairs(g.tag_names(container)) do
            local name = tag:match("^OffDuty%.Status%.(%a+)$")
            if name then return Rules.tier_by_id(name:lower()) end
        end
        return nil
    end

    local function build_tag_vm(tier)
        local class = select(2, pcall(StaticFindObject, TAG_VM_CLASS))
        local ok, vm = pcall(StaticConstructObject, class, g.find_live("BrunoGameInstance"))
        if not ok or not g.valid(vm) then return nil, "could not construct a tag view model: " .. tostring(vm) end
        local errors = {}
        local function set(field, value)
            local set_ok, err = pcall(function() vm[field] = value end)
            if not set_ok then errors[#errors + 1] = field .. ": " .. tostring(err) end
        end
        set("DisplayName", FText(tier.name))
        set("TagDescription", FText(Rules.status_description(tier)))
        local donor = (g.call(g.cdo(TAG_VM_CDO), "FindOrCreateTagUIDataViewModel", g.world_context(),
            { TagName = FName(BRUSH_DONOR) }))
        if g.valid(donor) then
            set("TagBrush", donor.TagBrush) -- whole-struct copy of the same type
            local icon = icons.texture(tier.level)
            if icon then
                local r_ok, r_err = pcall(function() vm.TagBrush.ResourceObject = icon end)
                if not r_ok then errors[#errors + 1] = "ResourceObject: " .. tostring(r_err) end
                local t_ok, t_err = pcall(function() vm.TagBrush.BrushType = BRUSH_TYPE_NONE end)
                if not t_ok then errors[#errors + 1] = "BrushType: " .. tostring(t_err) end
            end
        end
        return vm, #errors > 0 and table.concat(errors, " | ") or nil
    end

    local function patch_list(list)
        for _, active in ipairs(g.to_list((g.call(list, "GetStatusEffects")))) do
            local status_vm = select(2, pcall(function() return active.StatusEffectVM end))
            local tier = g.valid(status_vm) and tier_of(status_vm) or nil
            if tier and g.text((g.call(status_vm, "GetStatusEffectName"))) ~= tier.name then
                local vm, err = build_tag_vm(tier)
                local ok = vm ~= nil and pcall(function() status_vm.StatusEffectTagVM = vm end)
                if not logged[tier.id] or err or not ok then
                    logged[tier.id] = true
                    log("Status UI | %s | %s%s", tier.name, ok and "attached" or "NOT attached", err and (" | " .. err) or "")
                end
            end
        end
    end

    local function on_list_read(context)
        if busy then return end
        local list = g.unwrap(context)
        if not g.live(list) then return end
        busy = true
        local ok, err = pcall(patch_list, list)
        busy = false
        if not ok then log("ERROR: status UI | %s", tostring(err)) end
    end

    function self:install()
        local ok, err = pcall(function() ctx.runtime:register_hook(STATUS_LIST, function() end, on_list_read) end)
        log("%s | %s%s", ok and "Hooked" or "ERROR: hook failed", STATUS_LIST, ok and "" or (" | " .. tostring(err)))
    end

    return self
end

return M
