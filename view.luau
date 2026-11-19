--!nonstrict

local ViewModelModule = require("./viewmodel")

type ViewModel = ViewModelModule.ViewModel
type WindowInfo = ViewModelModule.WindowInfo
type WorkspaceInfo = ViewModelModule.WorkspaceInfo

local View = {}

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

local function renderMiniWindow(vm: ViewModel, win: WindowInfo, w: number, h: number)
    local isSelected = vm.selectedWindow ~= nil and vm.selectedWindow.id == win.id
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
            vm:handleWorkspaceClick(win.workspaceId)
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
                    vm:toggleSelectWindow(win)
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

local function renderWorkspaceTile(vm: ViewModel, ws: WorkspaceInfo)
    local tileW = 204
    local tileH = 166
    local innerW = tileW - 12
    local innerH = tileH - 12

    local hasSelection = vm.selectedWindow ~= nil
    local isMoveTarget = hasSelection and (vm.selectedWindow :: WindowInfo).workspaceId ~= ws.id

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
        contentNode = renderMiniWindow(vm, ws.windows[1], innerW, innerH)
    elseif count == 2 then
        local halfW = math.floor((innerW - 6) / 2)
        contentNode = ui.row({
            gap = 6,
            width = innerW,
            height = innerH,
        }, {
            renderMiniWindow(vm, ws.windows[1], halfW, innerH),
            renderMiniWindow(vm, ws.windows[2], halfW, innerH),
        })
    elseif count == 3 then
        local halfW = math.floor((innerW - 6) / 2)
        local halfH = math.floor((innerH - 6) / 2)
        contentNode = ui.row({
            gap = 6,
            width = innerW,
            height = innerH,
        }, {
            renderMiniWindow(vm, ws.windows[1], halfW, innerH),
            ui.column({
                gap = 6,
                width = halfW,
                height = innerH,
            }, {
                renderMiniWindow(vm, ws.windows[2], halfW, halfH),
                renderMiniWindow(vm, ws.windows[3], halfW, halfH),
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
                renderMiniWindow(vm, ws.windows[1], halfW, halfH),
                renderMiniWindow(vm, ws.windows[2], halfW, halfH),
            }),
            ui.row({ gap = 6 }, {
                renderMiniWindow(vm, ws.windows[3], halfW, halfH),
                renderMiniWindow(vm, ws.windows[4], halfW, halfH),
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
            vm:handleWorkspaceClick(ws.id)
        end,
    }, {
        contentNode,
    })
end

function View.render(vm: ViewModel)
    local colsPerRow = 5
    local rows = {}
    local currentRow = {}

    for idx, ws in ipairs(vm.workspaces) do
        table.insert(currentRow, renderWorkspaceTile(vm, ws))
        if #currentRow == colsPerRow or idx == #vm.workspaces then
            table.insert(rows, ui.row({
                gap = 10,
                align = "center",
                justify = "center",
            }, currentRow))
            currentRow = {}
        end
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
                text = vm:getStatusText(),
                fontSize = 12,
                color = vm.selectedWindow and COLOR_WS_BORDER_TARGET or COLOR_TEXT_DIM,
            }),
            ui.row({ gap = 6, align = "center" }, {
                if vm.selectedWindow
                    then ui.button({
                        text = "Cancel",
                        glyph = "x",
                        controlSize = "sm",
                        variant = "primary",
                        onClick = function()
                            vm:cancelSelection()
                        end,
                    })
                    else ui.button({
                        glyph = "refresh",
                        controlSize = "sm",
                        variant = "ghost",
                        onClick = function()
                            vm:refresh()
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

return View