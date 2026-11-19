--!nonstrict

local Model = require("./model")

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
    Model.fetchWorkspaces(
        self.compositor,
        function(workspaces: { WorkspaceInfo })
            self.workspaces = workspaces
            self:notify()
        end,
        function(errMsg: string)
            self.errorMessage = errMsg
            self:notify()
        end
    )
end

function ViewModel:switchToWorkspace(wsId: number)
    Model.switchToWorkspace(self.compositor, wsId, function(ok: boolean)
        if ok and Model.shouldCloseOnSwitch() then
            panel.close()
        else
            self:refresh()
        end
    end)
end

function ViewModel:focusWindow(win: WindowInfo)
    Model.focusWindow(self.compositor, win, function(ok: boolean)
        if ok and Model.shouldCloseOnSwitch() then
            panel.close()
        else
            self:refresh()
        end
    end)
end

function ViewModel:handleWorkspaceClick(wsId: number)
    local sel = self.selectedWindow
    if sel ~= nil then
        if sel.workspaceId ~= wsId then
            Model.moveWindowToWorkspace(self.compositor, sel, wsId, function(ok: boolean)
                if not ok then
                    self.errorMessage = "Falha ao mover janela."
                    self:notify()
                    return
                end
                self.selectedWindow = nil
                self:refresh()
            end)
        else
            self.selectedWindow = nil
            self:notify()
        end
    else
        self:switchToWorkspace(wsId)
    end
end

function ViewModel:toggleSelectWindow(win: WindowInfo)
    if self.selectedWindow ~= nil and self.selectedWindow.id == win.id then
        self.selectedWindow = nil
    else
        self.selectedWindow = win
    end
    self:notify()
end

function ViewModel:cancelSelection()
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
    return "Click on a workspace to switch to it • Use the ✥ button on a window to move it to another workspace"
end

return ViewModel