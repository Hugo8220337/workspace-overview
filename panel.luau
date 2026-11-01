--!nonstrict

type WindowInfo = {
    id: string,
    title: string,
    appId: string,
    workspaceId: number,
    focused: boolean,
}

type WorkspaceInfo = {
    id: number,
    name: string,
    focused: boolean,
    windows: { WindowInfo },
}

type State = {
    compositor: string?,
    workspaces: { WorkspaceInfo },
    selectedWindow: WindowInfo?,
    errorMessage: string?,
}

local state: State = {
    compositor = nil,
    workspaces = {},
    selectedWindow = nil,
    errorMessage = nil,
}

local COLOR_WS_EMPTY = "surface_container_low"
local COLOR_WS_ACTIVE = "surface_container_high"
local COLOR_WS_BORDER = "outline_variant"
local COLOR_WS_BORDER_FOCUSED = "primary"
local COLOR_WS_BORDER_TARGET = "tertiary"
local COLOR_WIN_BG = "surface"
local COLOR_WIN_FOCUSED = "secondary_container"
local COLOR_WIN_SELECTED = "primary_container"
local COLOR_TEXT_MAIN = "on_surface"
local COLOR_TEXT_DIM = "on_surface_variant"

local renderUI: () -> ()
local refreshState: () -> ()

local function truncate(text: any, maxLen: number): string
    if type(text) ~= "string" or text == "" then
        return "App"
    end
    if #text > maxLen then
        return string.sub(text, 1, maxLen - 2) .. ".."
    end
    return text
end

local function isNonEmpty(val: any): boolean
    return type(val) == "string" and #val > 0
end

local function parseJsonPure(str: string): any
    local pos = 1
    local len = #str

    local function skipWhitespace()
        while pos <= len do
            local c = string.sub(str, pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos += 1
            else
                break
            end
        end
    end

    local parseValue: () -> any

    local function parseString(): string
        pos += 1
        local out = {}
        while pos <= len do
            local c = string.sub(str, pos, pos)
            if c == '"' then
                pos += 1
                return table.concat(out)
            elseif c == "\\" then
                pos += 1
                local esc = string.sub(str, pos, pos)
                table.insert(out, esc)
                pos += 1
            else
                table.insert(out, c)
                pos += 1
            end
        end
        return table.concat(out)
    end

    local function parseNumber(): number
        local startPos = pos
        while pos <= len do
            local c = string.sub(str, pos, pos)
            if string.match(c, "[%d%+%-%.eE]") then
                pos += 1
            else
                break
            end
        end
        return tonumber(string.sub(str, startPos, pos - 1)) or 0
    end

    local function parseArray(): { any }
        pos += 1
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
        pos += 1
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
        elseif c == "t" and string.sub(str, pos, pos + 3) == "true" then
            pos += 4
            return true
        elseif c == "f" and string.sub(str, pos, pos + 4) == "false" then
            pos += 5
            return false
        elseif c == "n" and string.sub(str, pos, pos + 3) == "null" then
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
    return nil
end

local function decodeJson(raw: string?): any
    if not isNonEmpty(raw) then
        return nil
    end
    if type(noctalia) == "table" and type(noctalia.json) == "table" and type(noctalia.json.decode) == "function" then
        local ok, res = pcall(noctalia.json.decode, raw :: string)
        if ok and type(res) == "table" then
            return res
        end
    end
    return parseJsonPure(raw :: string)
end

local function detectCompositor(): string?
    if isNonEmpty(noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE")) and noctalia.commandExists("hyprctl") then
        return "hyprland"
    elseif isNonEmpty(noctalia.getenv("NIRI_SOCKET")) and noctalia.commandExists("niri") then
        return "niri"
    elseif isNonEmpty(noctalia.getenv("SWAYSOCK")) and noctalia.commandExists("swaymsg") then
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

local function getMaxWorkspaces(): number
    local val = noctalia.getConfig("max_workspaces")
    if type(val) == "number" and val >= 4 and val <= 20 then
        return math.floor(val)
    end
    return 10
end

local function shouldCloseOnSwitch(): boolean
    local val = noctalia.getConfig("close_on_switch")
    if type(val) == "boolean" then
        return val
    end
    return true
end

local function buildEmptyGrid(): { WorkspaceInfo }
    local total = getMaxWorkspaces()
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
    local total = getMaxWorkspaces()
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

local function switchToWorkspace(wsId: number)
    local comp = state.compositor
    if not comp then
        return
    end

    local cmd: { string } = {}
    if comp == "hyprland" then
        cmd = { "hyprctl", "dispatch", "workspace", tostring(wsId) }
    elseif comp == "niri" then
        cmd = { "niri", "msg", "action", "focus-workspace", tostring(wsId) }
    elseif comp == "sway" then
        cmd = { "swaymsg", "workspace", "number", tostring(wsId) }
    end

    if #cmd > 0 then
        noctalia.runAsync(cmd, function(res)
            if res.exitCode == 0 and shouldCloseOnSwitch() then
                panel.close()
            else
                refreshState()
            end
        end)
    end
end

local function focusWindow(win: WindowInfo)
    local comp = state.compositor
    if not comp then
        return
    end

    local cmd: { string } = {}
    if comp == "hyprland" then
        cmd = { "hyprctl", "dispatch", "focuswindow", "address:" .. win.id }
    elseif comp == "niri" then
        cmd = { "niri", "msg", "action", "focus-window", "--id", win.id }
    elseif comp == "sway" then
        cmd = { "swaymsg", "[con_id=" .. win.id .. "]", "focus" }
    end

    if #cmd > 0 then
        noctalia.runAsync(cmd, function(res)
            if res.exitCode == 0 and shouldCloseOnSwitch() then
                panel.close()
            else
                refreshState()
            end
        end)
    end
end

-- Move the window to the target workspace without switching to it
local function moveWindowToWorkspace(win: WindowInfo, targetWsId: number)
    local comp = state.compositor
    if not comp then
        return
    end

    local cmd: { string } = {}
    if comp == "hyprland" then
        cmd = {
            "hyprctl",
            "dispatch",
            "movetoworkspacesilent",
            tostring(targetWsId) .. ",address:" .. win.id,
        }
    elseif comp == "niri" then
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
    elseif comp == "sway" then
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
                state.errorMessage = "Falha ao mover janela."
                renderUI()
                return
            end
            state.selectedWindow = nil
            refreshState()
        end)
    end
end

local function fetchHyprland()
    noctalia.runAsync({ "hyprctl", "activeworkspace", "-j" }, function(actRes)
        noctalia.runAsync({ "hyprctl", "clients", "-j" }, function(cliRes)
            local actWs = decodeJson(actRes.stdout)
            local cliList = decodeJson(cliRes.stdout)

            if type(cliList) ~= "table" then
                state.errorMessage = "Erro ao ler janelas do Hyprland."
                renderUI()
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
                if wsId > 0 and isNonEmpty(c.address) and c.mapped ~= false and appClass ~= "noctalia" then
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

            state.workspaces = mergeWorkspaces(rawWs, windows)
            renderUI()
        end)
    end)
end

local function fetchNiri()
    noctalia.runAsync({ "niri", "msg", "-j", "workspaces" }, function(wsRes)
        noctalia.runAsync({ "niri", "msg", "-j", "windows" }, function(winRes)
            local wsList = decodeJson(wsRes.stdout)
            local winList = decodeJson(winRes.stdout)

            if type(wsList) ~= "table" or type(winList) ~= "table" then
                state.errorMessage = "Erro ao ler janelas do Niri."
                renderUI()
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

            state.workspaces = mergeWorkspaces(rawWs, windows)
            renderUI()
        end)
    end)
end

refreshState = function()
    state.errorMessage = nil
    if #state.workspaces == 0 then
        state.workspaces = buildEmptyGrid()
    end

    state.compositor = detectCompositor()
    if state.compositor == "hyprland" then
        fetchHyprland()
    elseif state.compositor == "niri" then
        fetchNiri()
    else
        state.errorMessage = "Compositor não suportado."
        renderUI()
    end
end

-- Click on a workspace (or a window within it):
-- * no window selected -> switch to this workspace
-- * with window selected -> move it there (without changing the current workspace)
local function handleWorkspaceClick(wsId: number)
    local sel = state.selectedWindow
    if sel ~= nil then
        if sel.workspaceId ~= wsId then
            moveWindowToWorkspace(sel, wsId)
        else
            state.selectedWindow = nil
            renderUI()
        end
    else
        switchToWorkspace(wsId)
    end
end

local function renderMiniWindow(win: WindowInfo, w: number, h: number)
    local isSelected = state.selectedWindow ~= nil and state.selectedWindow.id == win.id
    local iconPath = noctalia.appIconPath(win.appId, 48)

    local centerIcon
    if isNonEmpty(iconPath) then
        centerIcon = ui.image({
            path = iconPath,
            width = 28,
            height = 28,
        })
    else
        centerIcon = ui.glyph({
            name = "app-window",
            size = 24,
            color = COLOR_TEXT_MAIN,
        })
    end

    local bgFill = COLOR_WIN_BG
    local borderCol = COLOR_WS_BORDER
    if isSelected then
        bgFill = COLOR_WIN_SELECTED
        borderCol = COLOR_WS_BORDER_TARGET
    elseif win.focused then
        bgFill = COLOR_WIN_FOCUSED
        borderCol = COLOR_WS_BORDER_FOCUSED
    end

    return ui.column({
        key = "win_" .. win.id,
        width = w,
        height = h,
        padding = 5,
        radius = 6,
        fill = bgFill,
        border = borderCol,
        borderWidth = isSelected and 2 or 1,
        align = "center",
        justify = "space_between",
        onClick = function()
            handleWorkspaceClick(win.workspaceId)
        end,
    }, {
        ui.row({
            width = math.max(20, w - 10),
            align = "center",
            justify = "space_between",
        }, {
            ui.label({
                text = truncate(win.appId, math.max(6, math.floor(w / 9))),
                fontSize = 10,
                fontWeight = "bold",
                color = COLOR_TEXT_MAIN,
            }),
            ui.button({
                glyph = "arrows-move",
                glyphSize = 10,
                controlSize = "sm",
                variant = isSelected and "primary" or "ghost",
                onClick = function()
                    -- Select (or deselect) the window to move
                    if isSelected then
                        state.selectedWindow = nil
                    else
                        state.selectedWindow = win
                    end
                    renderUI()
                end,
            }),
        }),
        centerIcon,
        ui.label({
            text = truncate(win.title, math.max(8, math.floor(w / 8))),
            fontSize = 10,
            color = COLOR_TEXT_DIM,
        }),
    })
end

local function renderWorkspaceTile(ws: WorkspaceInfo)
    local tileW = 204
    local tileH = 166
    local innerW = tileW - 12
    local innerH = tileH - 12

    local hasSelection = state.selectedWindow ~= nil
    local isMoveTarget = hasSelection and state.selectedWindow.workspaceId ~= ws.id

    local borderCol = COLOR_WS_BORDER
    local borderW = 1
    if isMoveTarget then
        borderCol = COLOR_WS_BORDER_TARGET
        borderW = 2
    elseif ws.focused then
        borderCol = COLOR_WS_BORDER_FOCUSED
        borderW = 2
    end

    local count = #ws.windows
    local contentNode

    if count == 0 then
        contentNode = ui.column({
            width = innerW,
            height = innerH,
            align = "center",
            justify = "center",
        }, {
            ui.label({
                text = ws.name,
                fontSize = 32,
                fontWeight = "bold",
                color = ws.focused and COLOR_TEXT_MAIN or COLOR_TEXT_DIM,
            }),
        })
    elseif count == 1 then
        contentNode = renderMiniWindow(ws.windows[1], innerW, innerH)
    elseif count == 2 then
        local halfW = math.floor((innerW - 6) / 2)
        contentNode = ui.row({
            gap = 6,
            width = innerW,
            height = innerH,
        }, {
            renderMiniWindow(ws.windows[1], halfW, innerH),
            renderMiniWindow(ws.windows[2], halfW, innerH),
        })
    elseif count == 3 then
        local halfW = math.floor((innerW - 6) / 2)
        local halfH = math.floor((innerH - 6) / 2)
        contentNode = ui.row({
            gap = 6,
            width = innerW,
            height = innerH,
        }, {
            renderMiniWindow(ws.windows[1], halfW, innerH),
            ui.column({
                gap = 6,
                width = halfW,
                height = innerH,
            }, {
                renderMiniWindow(ws.windows[2], halfW, halfH),
                renderMiniWindow(ws.windows[3], halfW, halfH),
            }),
        })
    else
        local halfW = math.floor((innerW - 6) / 2)
        local halfH = math.floor((innerH - 6) / 2)
        contentNode = ui.column({
            gap = 6,
            width = innerW,
            height = innerH,
        }, {
            ui.row({ gap = 6 }, {
                renderMiniWindow(ws.windows[1], halfW, halfH),
                renderMiniWindow(ws.windows[2], halfW, halfH),
            }),
            ui.row({ gap = 6 }, {
                renderMiniWindow(ws.windows[3], halfW, halfH),
                renderMiniWindow(ws.windows[4], halfW, halfH),
            }),
        })
    end

    return ui.column({
        key = "ws_" .. tostring(ws.id),
        width = tileW,
        height = tileH,
        padding = 6,
        radius = 8,
        fill = ws.focused and COLOR_WS_ACTIVE or COLOR_WS_EMPTY,
        border = borderCol,
        borderWidth = borderW,
        align = "center",
        justify = "center",
        onClick = function()
            handleWorkspaceClick(ws.id)
        end,
    }, {
        contentNode,
    })
end

renderUI = function()
    local colsPerRow = 5
    local rows = {}
    local currentRow = {}

    for idx, ws in ipairs(state.workspaces) do
        table.insert(currentRow, renderWorkspaceTile(ws))
        if #currentRow == colsPerRow or idx == #state.workspaces then
            table.insert(rows, ui.row({
                gap = 10,
                align = "center",
                justify = "center",
            }, currentRow))
            currentRow = {}
        end
    end

    local statusText = "Click on a workspace to switch to it • Use the ✥ button on a window to move it to another workspace"
    if state.errorMessage then
        statusText = state.errorMessage
    elseif state.selectedWindow then
        statusText = "Moving '" .. truncate(state.selectedWindow.title, 24) .. "' — click on the destination workspace."
    end

    panel.render(ui.column({
        padding = 12,
        gap = 10,
    }, {
        ui.row({
            align = "center",
            justify = "space_between",
        }, {
            ui.label({
                text = statusText,
                fontSize = 12,
                color = state.selectedWindow and COLOR_WS_BORDER_TARGET or COLOR_TEXT_DIM,
            }),
            ui.row({ gap = 6, align = "center" }, {
                if state.selectedWindow
                    then ui.button({
                        text = "Cancel",
                        glyph = "x",
                        controlSize = "sm",
                        variant = "primary",
                        onClick = function()
                            state.selectedWindow = nil
                            renderUI()
                        end,
                    })
                    else ui.button({
                        glyph = "refresh",
                        controlSize = "sm",
                        variant = "ghost",
                        onClick = function()
                            refreshState()
                        end,
                    }),
            }),
        }),
        ui.column({
            gap = 10,
            align = "center",
            justify = "center",
        }, rows),
    }))
end

function onOpen()
    state.selectedWindow = nil
    if #state.workspaces == 0 then
        state.workspaces = buildEmptyGrid()
    end
    refreshState()
end

function onIpc(event: string, payload: string?)
    if event == "refresh" then
        refreshState()
    elseif event == "switch" and payload then
        local target = tonumber(payload)
        if target then
            switchToWorkspace(target)
        end
    end
end