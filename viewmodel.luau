--!nonstrict

local Logger = require("./utils/logger.luau")
local Model = require("./model.luau")

export type WindowInfo = Model.WindowInfo
export type WorkspaceInfo = Model.WorkspaceInfo

export type ViewModel = {
    compositor: string?,
    workspaces: { WorkspaceInfo },
    selectedWindow: WindowInfo?,
    errorMessage: string?,
    onChange: (() -> ())?,

    notify: (self: ViewModel) -> (),
    resetAndRefresh: (self: ViewModel) -> (),
    refresh: (self: ViewModel) -> (),
    switchToWorkspace: (self: ViewModel, wsId: number) -> (),
    focusWindow: (self: ViewModel, win: WindowInfo) -> (),
    handleWorkspaceClick: (self: ViewModel, wsId: number) -> (),
    handleWindowClick: (self: ViewModel, win: WindowInfo) -> (),
    toggleSelectWindow: (self: ViewModel, win: WindowInfo) -> (),
    cancelSelection: (self: ViewModel) -> (),
    getStatusText: (self: ViewModel) -> string,
}

local ViewModel = {}
ViewModel.__index = ViewModel

function ViewModel.new(onChange: (() -> ())?): ViewModel
    local self = setmetatable({
        compositor = nil,
        workspaces = {},
        selectedWindow = nil,
        errorMessage = nil,
        onChange = onChange,
    }, ViewModel)
    return (self :: any) :: ViewModel
end

function ViewModel:notify()
    if self.onChange then
        self.onChange()
    end
end

function ViewModel:resetAndRefresh()
    self.selectedWindow = nil
    if #self.workspaces == 0 then
        self.workspaces = Model.buildEmptyGrid()
    end
    self:refresh()
end

function ViewModel:refresh()
    self.errorMessage = nil
    if #self.workspaces == 0 then
        self.workspaces = Model.buildEmptyGrid()
    end

    self.compositor = Model.detectCompositor()
    Logger.info("refresh() -> compositor=" .. tostring(self.compositor))

    Model.fetchWorkspaces(
        self.compositor,
        function(workspaces: { WorkspaceInfo })
            self.workspaces = workspaces
            self:notify()
        end,
        function(errMsg: string)
            Logger.error("fetchWorkspaces falhou: " .. tostring(errMsg))
            self.errorMessage = errMsg
            self:notify()
        end
    )
end

function ViewModel:switchToWorkspace(wsId: number)
    Logger.info("switchToWorkspace -> wsId=" .. tostring(wsId))
    Model.switchToWorkspace(self.compositor, wsId, function(ok: boolean)
        Logger.info("switchToWorkspace resultado -> ok=" .. tostring(ok))
        if not ok then
            self.errorMessage = "Failed to switch to workspace " .. tostring(wsId)
            self:notify()
            return
        end
        if Model.shouldCloseOnSwitch() then
            panel.close()
        else
            self:refresh()
        end
    end)
end

function ViewModel:focusWindow(win: WindowInfo)
    Logger.info("focusWindow -> id=" .. tostring(win.id) .. " app=" .. tostring(win.appId))
    Model.focusWindow(self.compositor, win, function(ok: boolean)
        Logger.info("focusWindow resultado -> ok=" .. tostring(ok))
        if not ok then
            self.errorMessage = "Failed to focus window '" .. win.title .. "'."
            self:notify()
            return
        end
        if Model.shouldCloseOnSwitch() then
            panel.close()
        else
            self:refresh()
        end
    end)
end

function ViewModel:handleWorkspaceClick(wsId: number)
    Logger.info("handleWorkspaceClick -> wsId=" .. tostring(wsId))
    local sel = self.selectedWindow
    if sel ~= nil then
        if sel.workspaceId ~= wsId then
            Logger.info("Moving window " .. tostring(sel.id) .. " to workspace " .. tostring(wsId))
            Model.moveWindowToWorkspace(self.compositor, sel, wsId, function(ok: boolean)
                Logger.info("moveWindowToWorkspace resultado -> ok=" .. tostring(ok))
                if not ok then
                    self.errorMessage = "Failed to move window."
                    self:notify()
                    return
                end
                self.selectedWindow = nil
                self:refresh()
            end)
        else
            Logger.info("Same workspace clicked; canceling selection.")
            self.selectedWindow = nil
            self:notify()
        end
    else
        self:switchToWorkspace(wsId)
    end
end

function ViewModel:handleWindowClick(win: WindowInfo)
    Logger.info("handleWindowClick -> id=" .. tostring(win.id) .. " ws=" .. tostring(win.workspaceId))
    local sel = self.selectedWindow
    if sel ~= nil then
        self:handleWorkspaceClick(win.workspaceId)
    else
        self:focusWindow(win)
    end
end

function ViewModel:toggleSelectWindow(win: WindowInfo)
    Logger.info("toggleSelectWindow -> id=" .. tostring(win.id))
    if self.selectedWindow ~= nil and self.selectedWindow.id == win.id then
        self.selectedWindow = nil
    else
        self.selectedWindow = win
    end
    self:notify()
end

function ViewModel:cancelSelection()
    Logger.info("cancelSelection")
    self.selectedWindow = nil
    self:notify()
end

function ViewModel:getStatusText(): string
    if self.errorMessage then
        return self.errorMessage
    end
    if self.selectedWindow then
        local title = self.selectedWindow.title
        if #title > 24 then
            title = string.sub(title, 1, 22) .. ".."
        end
        return "Moving '" .. title .. "' — click on the destination workspace."
    end
    return "Click on a program to focus it • Use ✥ to move it to another workspace"
end

return ViewModel