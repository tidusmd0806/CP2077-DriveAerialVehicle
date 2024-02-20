LogLevel = {
    CRITICAL = 0,
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    TRACE = 4,
    DEBUG = 5,
    NOTSET = 6,
}

-- Force the log level to be the same for all instances
LogMasterLevel = LogLevel.NOTSET

local Log = {}
Log.__index = Log

function Log:new()
    local obj = {}
    obj.setting_level = LogLevel.INFO
    obj.setting_file_name = "No Settng"
    return setmetatable(obj, Log)
end

function Log:setLevel(level, file_name)
    if level < 0 or level > 5 or LogMasterLevel ~= LogLevel.NOTSET then
        self.setting_level = LogMasterLevel
        return false
    else
        self.setting_level = level
        self.setting_file_name = "[" .. file_name .. "]"
        return true
    end
end

function Log:record(level, message)
    if level > self.setting_level then
        return
    end
    if level == LogLevel.CRITICAL then
        spdlog.critical(self.setting_file_name .. "[CRITICAL] " .. message)
    elseif level == LogLevel.ERROR then
        spdlog.error(self.setting_file_name .. "[ERROR] " .. message)
    elseif level == LogLevel.WARN then
        spdlog.warn(self.setting_file_name .. "[WARN] " .. message)
    elseif level == LogLevel.INFO then
        spdlog.info(self.setting_file_name .. "[INFO] " .. message)
    elseif level == LogLevel.TRACE then
        spdlog.trace(self.setting_file_name .. "[TRACE] " .. message)
    elseif level == LogLevel.DEBUG then
        spdlog.debug(self.setting_file_name .. "[DEBUG] " .. message)
    else
        return
    end
end

return Log