--!nonstrict

local Logger = require("./utils/logger.luau")

export type WindowInfo = {
    id: string,
    title: string,
    appId: string,
    workspaceId: number,
    focused: boolean,
}

export type WorkspaceInfo = {
    id: number,
    name: string,
    focused: boolean,
    windows: { WindowInfo },
}

local Model = {}

function Model.isNonEmpty(val: any): boolean
    return type(val) == "string" and #val > 0
end

-- Optimized JSON parser in Luau (uses string.find in C to avoid exceeding CPU budget)
local function parseJsonFast(str: string): any
    local pos = 1
    local len = #str

    local function skipWhitespace()
        local _, e = string.find(str, "^[ \t\n\r]+", pos)
        if e then
            pos = e + 1
        end
    end

    local parseValue: () -> any

    local function parseString(): string
        pos += 1 -- skips '"'
        local startPos = pos
        local out: { string }? = nil

        while pos <= len do
            local idx = string.find(str, '["\\]', pos)
            if not idx then
                break
            end
            local c = string.sub(str, idx, idx)
            if c == '"' then
                if out then
                    if idx > startPos then
                        table.insert(out, string.sub(str, startPos, idx - 1))
                    end
                    pos = idx + 1
                    return table.concat(out)
                else
                    pos = idx + 1
                    return string.sub(str, startPos, idx - 1)
                end
            else
                -- Caráter de escape '\'
                if not out then
                    out = {}
                end
                if idx > startPos then
                    table.insert(out, string.sub(str, startPos, idx - 1))
                end
                local esc = string.sub(str, idx + 1, idx + 1)
                if esc == "n" then
                    table.insert(out, "\n")
                elseif esc == "r" then
                    table.insert(out, "\r")
                elseif esc == "t" then
                    table.insert(out, "\t")
                elseif esc == "u" then
                    idx += 4
                else
                    table.insert(out, esc)
                end
                pos = idx + 2
                startPos = pos
            end
        end
        return out and table.concat(out) or string.sub(str, startPos, len)
    end

    local function parseNumber(): number
        local _, e = string.find(str, "^[%d%+%-%.eE]+", pos)
        if not e then
            pos += 1
            return 0
        end
        local numStr = string.sub(str, pos, e)
        pos = e + 1
        return tonumber(numStr) or 0
    end

    local function parseArray(): { any }
        pos += 1 -- salta '['
        local arr = {}
        skipWhitespace()
        if string.sub(str, pos, pos) == "]" then
            pos += 1
            return arr
        end
        while pos <= len do
            skipWhitespace()
            table.insert(arr, parseValue())
            skipWhitespace()
            local c = string.sub(str, pos, pos)
            if c == "," then
                pos += 1
            elseif c == "]" then
                pos += 1
                break
            else
                break
            end
        end
        return arr
    end

    local function parseObject(): { [string]: any }
        pos += 1 -- skips '{'
        local obj: { [string]: any } = {}
        skipWhitespace()
        if string.sub(str, pos, pos) == "}" then
            pos += 1
            return obj
        end
        while pos <= len do
            skipWhitespace()
            if string.sub(str, pos, pos) ~= '"' then
                break
            end
            local key = parseString()
            skipWhitespace()
            if string.sub(str, pos, pos) == ":" then
                pos += 1
            end
            skipWhitespace()
            obj[key] = parseValue()
            skipWhitespace()
            local c = string.sub(str, pos, pos)
            if c == "," then
                pos += 1
            elseif c == "}" then
                pos += 1
                break
            else
                break
            end
        end
        return obj
    end

    parseValue = function(): any
        skipWhitespace()
        local c = string.sub(str, pos, pos)
        if c == '"' then
            return parseString()
        elseif c == "{" then
            return parseObject()
        elseif c == "[" then
            return parseArray()
        elseif c == "t" then
            pos += 4
            return true
        elseif c == "f" then
            pos += 5
            return false
        elseif c == "n" then
            pos += 4
            return nil
        else
            return parseNumber()
        end
    end

    local ok, result = pcall(parseValue)
    if ok then
        return result
    end
    Logger.error("parseJsonFast falhou: " .. tostring(result))
    return nil
end

function Model.decodeJson(raw: string?): any
    if not Model.isNonEmpty(raw) then
        return nil
    end

    -- Try native decoders (C/Rust) if they exist in the runtime
    -- this avoids "exceeded its CPU budget" errors in Luau for large JSON strings
    if type(json) == "table" and type(json.decode) == "function" then
        local ok, res = pcall(json.decode, raw :: string)
        if ok and type(res) == "table" then
            return res
        end
    end
    if type(noctalia) == "table" then
        if type(noctalia.json) == "table" and type(noctalia.json.decode) == "function" then
            local ok, res = pcall(noctalia.json.decode, raw :: string)
            if ok and type(res) == "table" then
                return res
            end
        elseif type(noctalia.jsonDecode) == "function" then
            local ok, res = pcall(noctalia.jsonDecode, raw :: string)
            if ok and type(res) == "table" then
                return res
            end
        end
    end

    -- Fallback to a fast Luau parser for JSON
    return parseJsonFast(raw :: string)
end

function Model.detectCompositor(): string?
    if Model.isNonEmpty(noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE")) and noctalia.commandExists("hyprctl") then
        return "hyprland"
    elseif Model.isNonEmpty(noctalia.getenv("NIRI_SOCKET")) and noctalia.commandExists("niri") then
        return "niri"
    elseif Model.isNonEmpty(noctalia.getenv("SWAYSOCK")) and noctalia.commandExists("swaymsg") then
        return "sway"
    elseif noctalia.commandExists("hyprctl") then
        return "hyprland"
    elseif noctalia.commandExists("niri") then
        return "niri"
    elseif noctalia.commandExists("swaymsg") then
        return "sway"
    end
    return nil
end

function Model.getMaxWorkspaces(): number
    local val = noctalia.getConfig("max_workspaces")
    if type(val) == "number" and val >= 4 and val <= 20 then
        return math.floor(val)
    end
    return 10
end

function Model.shouldCloseOnSwitch(): boolean
    local val = noctalia.getConfig("close_on_switch")
    if type(val) == "boolean" then
        return val
    end
    return true
end

function Model.buildEmptyGrid(): { WorkspaceInfo }
    local total = Model.getMaxWorkspaces()
    local list: { WorkspaceInfo } = {}
    for i = 1, total do
        table.insert(list, {
            id = i,
            name = tostring(i),
            focused = (i == 1),
            windows = {},
        })
    end
    return list
end

local function mergeWorkspaces(
    rawWs: { [number]: { name: string, focused: boolean } },
    windows: { WindowInfo }
): { WorkspaceInfo }
    local total = Model.getMaxWorkspaces()
    for id, _ in pairs(rawWs) do
        if id > total and id <= 20 then
            total = id
        end
    end
    for _, w in ipairs(windows) do
        if w.workspaceId > total and w.workspaceId <= 20 then
            total = w.workspaceId
        end
    end

    local map: { [number]: WorkspaceInfo } = {}
    for i = 1, total do
        local info = rawWs[i]
        map[i] = {
            id = i,
            name = (info and info.name) or tostring(i),
            focused = (info and info.focused) == true,
            windows = {},
        }
    end

    for _, win in ipairs(windows) do
        local target = map[win.workspaceId]
        if target then
            table.insert(target.windows, win)
        end
    end

    local result: { WorkspaceInfo } = {}
    for i = 1, total do
        table.insert(result, map[i])
    end
    return result
end

function Model.fetchWorkspaces(
    compositor: string?,
    onSuccess: ({ WorkspaceInfo }) -> (),
    onError: (string) -> ()
)
    if compositor == "hyprland" then
        noctalia.runAsync({ "hyprctl", "activeworkspace", "-j" }, function(actRes)
            noctalia.runAsync({ "hyprctl", "clients", "-j" }, function(cliRes)
                local actWs = Model.decodeJson(actRes.stdout)
                local cliList = Model.decodeJson(cliRes.stdout)

                if type(cliList) ~= "table" then
                    onError("Erro ao ler janelas do Hyprland.")
                    return
                end

                local activeId = (type(actWs) == "table" and type(actWs.id) == "number") and math.floor(actWs.id) or 1
                local rawWs: { [number]: { name: string, focused: boolean } } = {}
                rawWs[activeId] = { name = tostring(activeId), focused = true }

                local windows: { WindowInfo } = {}
                for _, c in ipairs(cliList) do
                    local wsId = -1
                    if type(c.workspace) == "table" and type(c.workspace.id) == "number" then
                        wsId = math.floor(c.workspace.id)
                    end

                    local appClass = tostring(c.class or c.initialClass or "")
                    if wsId > 0 and Model.isNonEmpty(c.address) and c.mapped ~= false and appClass ~= "noctalia" then
                        if not rawWs[wsId] then
                            rawWs[wsId] = { name = tostring(wsId), focused = (wsId == activeId) }
                        end
                        table.insert(windows, {
                            id = tostring(c.address),
                            title = tostring(c.title or c.initialTitle or appClass),
                            appId = appClass ~= "" and appClass or "application",
                            workspaceId = wsId,
                            focused = (c.focusHistoryID == 0),
                        })
                    end
                end

                onSuccess(mergeWorkspaces(rawWs, windows))
            end)
        end)
    elseif compositor == "niri" then
        noctalia.runAsync({ "niri", "msg", "-j", "workspaces" }, function(wsRes)
            noctalia.runAsync({ "niri", "msg", "-j", "windows" }, function(winRes)
                local wsList = Model.decodeJson(wsRes.stdout)
                local winList = Model.decodeJson(winRes.stdout)

                if type(wsList) ~= "table" or type(winList) ~= "table" then
                    onError("Erro ao ler janelas do Niri.")
                    return
                end

                local rawWs: { [number]: { name: string, focused: boolean } } = {}
                local idToIdx: { [string]: number } = {}

                for _, w in ipairs(wsList) do
                    local idx = (type(w.idx) == "number" and math.floor(w.idx))
                        or (type(w.id) == "number" and math.floor(w.id))
                        or 1
                    if idx > 0 then
                        if w.id ~= nil then
                            idToIdx[tostring(w.id)] = idx
                        end
                        rawWs[idx] = {
                            name = tostring(w.name or idx),
                            focused = (w.is_focused == true or w.is_active == true),
                        }
                    end
                end

                local windows: { WindowInfo } = {}
                for _, win in ipairs(winList) do
                    local rawWsId = tostring(win.workspace_id or "")
                    local wsIdx = idToIdx[rawWsId] or tonumber(rawWsId) or 1
                    if wsIdx > 0 and win.id ~= nil then
                        table.insert(windows, {
                            id = tostring(win.id),
                            title = tostring(win.title or win.app_id or "Janela"),
                            appId = tostring(win.app_id or "application"),
                            workspaceId = math.floor(wsIdx),
                            focused = (win.is_focused == true),
                        })
                    end
                end

                onSuccess(mergeWorkspaces(rawWs, windows))
            end)
        end)
    else
        onError("Compositor não suportado.")
    end
end

function Model.switchToWorkspace(compositor: string?, wsId: number, onDone: (boolean) -> ())
    if not compositor then
        onDone(false)
        return
    end

    local cmd: { string } = {}
    if compositor == "hyprland" then
        cmd = { "hyprctl", "dispatch", "workspace", tostring(wsId) }
    elseif compositor == "niri" then
        cmd = { "niri", "msg", "action", "focus-workspace", tostring(wsId) }
    elseif compositor == "sway" then
        cmd = { "swaymsg", "workspace", "number", tostring(wsId) }
    end

    if #cmd > 0 then
        noctalia.runAsync(cmd, function(res)
            if res.exitCode ~= 0 then
                Logger.logCommandFailure(cmd, res)
            end
            onDone(res.exitCode == 0)
        end)
    else
        onDone(false)
    end
end

function Model.focusWindow(compositor: string?, win: WindowInfo, onDone: (boolean) -> ())
    if not compositor then
        onDone(false)
        return
    end

    local cmd: { string } = {}
    if compositor == "hyprland" then
        cmd = { "hyprctl", "dispatch", "focuswindow", "address:" .. win.id }
    elseif compositor == "niri" then
        cmd = { "niri", "msg", "action", "focus-window", "--id", win.id }
    elseif compositor == "sway" then
        cmd = { "swaymsg", "[con_id=" .. win.id .. "]", "focus" }
    end

    if #cmd > 0 then
        noctalia.runAsync(cmd, function(res)
            if res.exitCode ~= 0 then
                Logger.logCommandFailure(cmd, res)
            end
            onDone(res.exitCode == 0)
        end)
    else
        onDone(false)
    end
end

function Model.moveWindowToWorkspace(
    compositor: string?,
    win: WindowInfo,
    targetWsId: number,
    onDone: (boolean) -> ()
)
    if not compositor then
        onDone(false)
        return
    end

    local cmd: { string } = {}
    if compositor == "hyprland" then
        cmd = {
            "hyprctl",
            "dispatch",
            "movetoworkspacesilent",
            tostring(targetWsId) .. ",address:" .. win.id,
        }
    elseif compositor == "niri" then
        cmd = {
            "niri",
            "msg",
            "action",
            "move-window-to-workspace",
            "--focus",
            "false",
            "--window-id",
            win.id,
            tostring(targetWsId),
        }
    elseif compositor == "sway" then
        cmd = {
            "swaymsg",
            "[con_id=" .. win.id .. "]",
            "move",
            "container",
            "to",
            "workspace",
            "number",
            tostring(targetWsId),
        }
    end

    if #cmd > 0 then
        noctalia.runAsync(cmd, function(res)
            if res.exitCode ~= 0 then
                Logger.logCommandFailure(cmd, res)
            end
            onDone(res.exitCode == 0)
        end)
    else
        onDone(false)
    end
end

return Model