--------------------------------------------------------
-- Enhanced Logging System with Auto Caller Detection
--------------------------------------------------------
-- Usage Examples:
--   Basic logging (auto caller info for Error/Warning/Critical):
--     log_obj:Record(LogLevel.Error, "Failed to load") 
--     → [Core] [ERROR] [core.lua:123] Failed to load
--   
--   With context:
--     log_obj:Record(LogLevel.Error, "Failed to load model", "Core:Init")
--     → [Core] [ERROR] [Core:Init @ core.lua:123] Failed to load model
--   
--   Skip caller info for performance (high-frequency logs):
--     log_obj:Record(LogLevel.Trace, "Processing", nil, true)
--   
--   Info/Debug/Trace (no auto caller info for performance):
--     log_obj:Record(LogLevel.Info, "Vehicle spawned")
--     → [Core] [INFO] Vehicle spawned
--   
-- Output format:
--   [ModuleName] [LEVEL] [Context @ file.lua:line] Message
--
-- Auto caller info is added for: Critical, Error, Warning (not for Info/Debug/Trace)
--------------------------------------------------------

---@enum LogLevel
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
MasterLogLevel = LogLevel.Warning
-- Print debug messages to the console
PrintDebugMode = false

local Log = {}
Log.__index = Log

--- Constractor
---@return table
function Log:New()
    local obj = {}
    obj.setting_level = LogLevel.Info
    obj.setting_file_name = "No Setting"
    return setmetatable(obj, self)
end

--- Set the log level
---@param level LogLevel
---@param file_name string
---@return boolean
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

--- Record a message to the log file with automatic caller information
---@param level LogLevel
---@param message string
---@param context string|nil Optional context information (e.g., function name, operation)
---@param skip_caller boolean|nil If true, skip automatic caller info (for performance)
function Log:Record(level, message, context, skip_caller)
    local setting_level = self.setting_level
    if MasterLogLevel > setting_level then
        setting_level = MasterLogLevel
    end

    if level > setting_level then
        return
    end
    
    -- Determine level name
    local level_name = "UNKNOWN"
    if level <= LogLevel.Debug then
        level_name = "DEBUG"
        if level <= LogLevel.Trace then
            level_name = "TRACE"
            if level <= LogLevel.Info then
                level_name = "INFO"
                if level <= LogLevel.Warning then
                    level_name = "WARNING"
                    if level <= LogLevel.Error then
                        level_name = "ERROR"
                        if level <= LogLevel.Critical then
                            level_name = "CRITICAL"
                        end
                    end
                end
            end
        end
        
        -- Auto-add caller information for Error/Critical/Warning (unless skip_caller is true)
        local full_context = context
        if not skip_caller and (level <= LogLevel.Warning) then
            local debug_info = debug.getinfo(2, "Sl")
            if debug_info then
                local source = debug_info.source or "unknown"
                local line = debug_info.currentline or 0
                local filename = source:match("^.+\\(.+)$") or source:match("^.+/(.+)$") or source
                local caller_info = filename .. ":" .. line
                
                if full_context and full_context ~= "" then
                    full_context = full_context .. " @ " .. caller_info
                else
                    full_context = caller_info
                end
            end
        end
        
        -- Build context string
        local context_str = ""
        if full_context and full_context ~= "" then
            context_str = " [" .. full_context .. "]"
        end
        
        -- Build log message with enhanced format
        local log_msg = self.setting_file_name .. " [" .. level_name .. "]" .. context_str .. " " .. message
        
        spdlog.info(log_msg)
        if PrintDebugMode then
            print(log_msg)
        end
    end
end

return Log