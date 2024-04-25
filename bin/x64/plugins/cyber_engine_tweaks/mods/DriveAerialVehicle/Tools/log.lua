LogLevel = {
    Critical = 0,
    Error = 1,
    Warning = 2,
    Info = 3,
    Trace = 4,
    Debug = 5,
    Nothing = 6
}

-- Force the log level to be the same for all instances
MasterLogLevel = LogLevel.Error
-- Print debug messages to the console
PrintDebugMode = false

local Log = {}
Log.__index = Log

function Log:New()
    local obj = {}
    obj.setting_level = LogLevel.INFO
    obj.setting_file_name = "No Setting"
    return setmetatable(obj, self)
end

function Log:SetLevel(level, file_name)

    if level < 0 or level > 5 or MasterLogLevel ~= LogLevel.Nothing then
        self.setting_level = MasterLogLevel
        self.setting_file_name = "[" .. file_name .. "]"
        return false
    else
        self.setting_level = level
        self.setting_file_name = "[" .. file_name .. "]"
        return true
    end

end

function Log:Record(level, message)

    local setting_level = self.setting_level
    if MasterLogLevel > setting_level then
        setting_level = MasterLogLevel
    end

    if level > setting_level then
        return
    end
    if PrintDebugMode then
        print(self.setting_file_name .. "[" .. level .."]" .. message)
    end
    if level == LogLevel.Critical then
        spdlog.critical(self.setting_file_name .. "[CRITICAL] " .. message)
    elseif level == LogLevel.Error then
        spdlog.error(self.setting_file_name .. "[ERROR] " .. message)
    elseif level == LogLevel.Warning then
        spdlog.warning(self.setting_file_name .. "[WARNING] " .. message)
    elseif level == LogLevel.Info then
        spdlog.info(self.setting_file_name .. "[INFO] " .. message)
    elseif level == LogLevel.Trace then
        spdlog.trace(self.setting_file_name .. "[TRACE] " .. message)
    elseif level == LogLevel.Debug then
        spdlog.debug(self.setting_file_name .. "[DEBUG] " .. message)
    else
        return
    end

end

return Log