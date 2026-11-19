--!nonstrict

local Logger = require("./utils/logger")
local ViewModel = require("./viewmodel")
local View = require("./view")

local vm = ViewModel.new()

vm.onChange = function()
    Logger.safeCall("View.render", function()
        View.render(vm)
    end)
end

function onOpen()
    Logger.info("Painel aberto (onOpen)")
    Logger.safeCall("onOpen", function()
        vm:resetAndRefresh()
    end)
end

function onIpc(event: string, payload: string?)
    Logger.info(string.format("IPC recebido: event='%s' payload='%s'", tostring(event), tostring(payload)))
    Logger.safeCall("onIpc", function()
        if event == "refresh" then
            vm:refresh()
        elseif event == "switch" and payload then
            local target = tonumber(payload)
            if target then
                vm:switchToWorkspace(target)
            else
                Logger.warn("IPC 'switch' com payload inválido: " .. tostring(payload))
            end
        end
    end)
end