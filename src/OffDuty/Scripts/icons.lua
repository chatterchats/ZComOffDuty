-- Off Duty's Zzz tier icons: PNGs in the mod's icons/ folder (drawn by unreal/scripts/draw_icons.py),
-- imported at runtime with KismetRenderingLibrary.ImportFileAsTexture2D. A texture cooked on Linux
-- doesn't load in the Windows game. Each call imports a new transient texture; whatever brush it's set
-- on keeps it alive, so nothing is cached in Lua.
local M = {}

-- Resolved at load time, outside pcall (inside it, debug.getinfo level 1 is pcall itself).
local SOURCE = (debug.getinfo(1, "S").source or ""):gsub("^@", "")

function M.new(ctx)
    local g, log = ctx.game, ctx.log
    local self = {}
    local failure_logged, success_logged = false, false

    local function candidates(file)
        local paths = {}
        local scripts = SOURCE:match("^(.*)[/\\][^/\\]+$")
        if scripts then
            local mod = (scripts:match("^(.*)[/\\][Ss]cripts$") or scripts):gsub("\\", "/")
            paths[#paths + 1] = mod .. "/icons/" .. file
        end
        -- Relative to the game's working directory (Binaries/Win64).
        paths[#paths + 1] = "ue4ss/Mods/" .. ctx.mod_folder .. "/icons/" .. file
        paths[#paths + 1] = "Mods/" .. ctx.mod_folder .. "/icons/" .. file
        return paths
    end

    -- level: 1 Tired, 2 Exhausted, 3 Spent.
    function self.texture(level)
        local rendering = g.cdo("/Script/Engine.Default__KismetRenderingLibrary")
        local tried = {}
        for _, path in ipairs(candidates("T_OffDuty_Fatigue_" .. level .. ".png")) do
            local texture, err = g.call(rendering, "ImportFileAsTexture2D", g.world_context(), path)
            if g.valid(texture) then
                if not success_logged then success_logged = true; log("Icons | loading from %s", path) end
                return texture
            end
            tried[#tried + 1] = path .. (err and (" (" .. err .. ")") or "")
        end
        if not failure_logged then
            failure_logged = true
            log("WARNING: icons | could not import tier %d icon; using the game's | tried %s", level, table.concat(tried, " | "))
        end
        return nil
    end

    return self
end

return M
