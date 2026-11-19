--!nonstrict

local ViewModel = require("./viewmodel")
local View = require("./view")

local vm = ViewModel.new()

vm.onChange = function()
    View.render(vm)
end

function onOpen()
    vm:resetAndRefresh()
end

function onIpc(event: string, payload: string?)
    if event == "refresh" then
        vm:refresh()
    elseif event == "switch" and payload then
        local target = tonumber(payload)
        if target then
            vm:switchToWorkspace(target)
        end
    end
end