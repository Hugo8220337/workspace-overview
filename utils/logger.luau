--!nonstrict

local Logger = {}

local PREFIX = "[workspace-overview]"

local function writeLog(level: string, message: string)
    local formatted = string.format("%s [%s] %s", PREFIX, level, tostring(message))
    if type(noctalia) == "table" and type(noctalia.log) == "function" then
        noctalia.log(formatted)
    elseif type(print) == "function" then
        print(formatted)
    end
end

function Logger.info(message: string)
    writeLog("INFO", message)
end

function Logger.warn(message: string)
    writeLog("WARN", message)
end

function Logger.error(message: string)
    writeLog("ERROR", message)
end

-- Automatically logs failures of commands executed with noctalia.runAsync
function Logger.logCommandFailure(cmd: { string }, res: any)
    local cmdStr = table.concat(cmd, " ")
    local code = (type(res) == "table" and res.exitCode ~= nil) and tostring(res.exitCode) or "unknown"
    local stderr = (type(res) == "table" and type(res.stderr) == "string" and res.stderr ~= "")
        and res.stderr
        or "(sem stderr)"
    Logger.error(string.format("Command failed (exit %s): '%s' -> %s", code, cmdStr, stderr))
end

-- Executes any function protected against silent Luau crashes
function Logger.safeCall(context: string, fn: () -> ())
    local ok, err = pcall(fn)
    if not ok then
        Logger.error(string.format("Exception in '%s': %s", context, tostring(err)))
    end
end

return Logger