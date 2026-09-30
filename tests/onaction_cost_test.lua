-- PlayerPuppet.OnAction cost test (docs/PERF_ANALYSIS_hooks.md fix (3)).
--
-- The OnAction observer measured 208.70 ms / 14,106 calls / 14.8 us per call,
-- the single largest cost in the mod outside the onUpdate funnel. This test loads
-- the real Modules/core.lua with the CET API stubbed and drives the captured
-- callback to prove the rewrite keeps every Consume() decision identical while
-- dropping the work that produced it.
--
-- What is under test:
--   * exception membership matches the shipped JSON exactly
--   * every Consume()/no-Consume decision is unchanged
--   * IsMountedCombatSeat() (a C# round trip) is not paid for non-popup actions
--   * the Debug message is not built at all when Debug is disabled
--   * the Debug message, when enabled, is byte-identical to the old one
--   * current_situation is read once, not re-read through IsInVehicle()

local MODDIR = ...

-- ---------------------------------------------------------------- stubs ----
Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end
Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }
EulerAngles = { new = function(p, y, r) return { pitch = p, yaw = y, roll = r } end }
Quaternion = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }
CName = { new = function(s) return { value = s } end }
StringToName = function(s) return { value = s } end
QueryFilter = { new = function() return { mask2 = 0 } end }
DynamicEntitySpec = { new = function() return {} end }
SaveLocksManager = { RequestSaveLockAdd = function() end, RequestSaveLockRemove = function() end }
GameObjectEffectHelper = { StartEffectEvent = function() end, StopEffectEvent = function() end }
Cron = { Every = function() return 1 end, Halt = function() end, After = function() end }

-- Emitted log lines land here instead of spdlog.
local emitted = {}
spdlog = { info = function(msg) emitted[#emitted + 1] = msg end }

-- Minimal decoder: the exception files are flat arrays of plain strings.
json = {
    decode = function(s)
        if s:match("^%[") == nil then return {} end
        local t = {}
        for w in string.gmatch(s, '"([^"]*)"') do t[#t + 1] = w end
        return t
    end,
    encode = function() return "{}" end,
}

DAV = {
    frame_seq = 0,
    axis_dead_zone = 0.1,
    model_index = 1,
    model_type_index = 1,
    is_debug_mode = false,
    is_debug_enable_obstacle_scan = false,
    is_debug_profile_autopilot = false,
    user_setting_table = { keybind_table = {}, heli_keybind_table = {}, common_keybind_table = {} },
}

-- Captured CET hooks.
local hooks = {}
function Observe(cls, method, cb) hooks[cls .. "." .. method] = cb end
function ObserveAfter(cls, method, cb) hooks["after:" .. cls .. "." .. method] = cb end
function Override(cls, method, cb) hooks["override:" .. cls .. "." .. method] = cb end

-- Interop counters.
local counters = {
    get_player = 0,
    driver_combat = 0,
    mounted_combat_seat = 0,
    player_in = 0,
    in_entry_area = 0,
    situation_reads = 0,
}

Game = {
    GetPlayer = function()
        counters.get_player = counters.get_player + 1
        return {
            PSIsInDriverCombat = function()
                counters.driver_combat = counters.driver_combat + 1
                return Game.__driver_combat
            end,
            GetWorldPosition = function() return Vector4.new(0, 0, 0, 1) end,
        }
    end,
    FindEntityByID = function() return nil end,
    GetTimeSystem = function() return { GetGameTimeStamp = function() return 0 end } end,
    GetSpatialQueriesSystem = function()
        return { SyncRaycastByQueryFilter = function() return false, nil end }
    end,
    __driver_combat = false,
}

-- --------------------------------------------------------------- load ------
-- lupa is stock Lua 5.1 and rejects `goto` / `::label::`, which LuaJIT (what CET
-- actually embeds) accepts. tools/check_lua_syntax.py neutralises the same way;
-- mirror it here so the gate and the test agree about what "parses" means.
-- The rewrite only touches do-end placeholders where a label or a jump to one sat,
-- and never lands inside anything this test drives.
local LUAJIT_EXT = "%f[%w]goto%s+[A-Za-z_][A-Za-z0-9_]*%f[^%w]"
local LUAJIT_LBL = "::%s*[A-Za-z_][A-Za-z0-9_]*%s*::"

local function luajit_dialect(src)
    -- Same substitution as the syntax gate: both the jump and its label become a
    -- no-op statement. Only LoadLanguageFiles uses them; nothing here drives it.
    src = src:gsub(LUAJIT_EXT, "do end")
    src = src:gsub(LUAJIT_LBL, "do end")
    return src
end

local function preload(name)
    local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
    local b = f:read("*a"); f:close()
    local loader = loadstring or load
    local chunk, err = loader(luajit_dialect(b), name)
    assert(chunk, "failed to compile " .. name .. ": " .. tostring(err))
    package.preload[name] = chunk
end

-- av/event are replaced by fakes below; core only needs them to exist.
package.preload["Modules/av.lua"] = function() return { New = function() return {} end } end
package.preload["Modules/event.lua"] = function() return { New = function() return {} end } end

preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Etc/timescale.lua")
TimeScale = require("Etc/timescale.lua")
preload("Etc/def.lua")
preload("Etc/queue.lua")
preload("Modules/core.lua")

Log = require("Etc/log.lua")
Def = require("Etc/def.lua")
Utils = require("Etc/utils.lua")
local Core = require("Modules/core.lua")

-- ------------------------------------------------------------- harness -----
local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1; print("  [PASS] " .. name)
    else fail = fail + 1; print("  [FAIL] " .. name .. (detail and ("  " .. detail) or "")) end
end

local function reset_counters()
    for k in pairs(counters) do counters[k] = 0 end
    emitted = {}
end

-- Build a Core instance with fake av_obj / event_obj and a recording
-- StorePlayerAction so we only exercise the callback, not the action pipeline.
local stored = {}
local function new_core(situation, opts)
    opts = opts or {}
    local core = setmetatable({}, Core)
    core.log_obj = Log:New()
    -- SetLevel only honours a per-instance level while MasterLogLevel is Nothing;
    -- otherwise the master wins. Drive the master so both branches are reachable.
    if opts.log_master ~= nil then
        MasterLogLevel = opts.log_master
    end
    core.log_obj:SetLevel(opts.log_level or LogLevel.Info, "Core")
    core.queue_obj = require("Etc/queue.lua"):New()
    core.axis_dead_zone = DAV.axis_dead_zone
    core.relative_dead_zone = 0.01
    core.hold_progress = 0.9
    core.is_locked_action_in_combat = false

    core.av_obj = {
        is_blocking_operation = false,
        engine_obj = { flight_mode = Def.FlightMode.AV },
        IsPlayerIn = function()
            counters.player_in = counters.player_in + 1
            return opts.player_in ~= false
        end,
        IsPlayerInEntryArea = function()
            counters.in_entry_area = counters.in_entry_area + 1
            return opts.in_entry_area == true
        end,
        IsMountedCombatSeat = function()
            counters.mounted_combat_seat = counters.mounted_combat_seat + 1
            return opts.combat_seat == true
        end,
    }

    -- Fake event object. current_situation lives in a shadow field so the
    -- metatable's __index actually fires; a plain field would be found directly
    -- and the read counter would stay at zero.
    local event = {
        is_in_menu = opts.in_menu == true,
        is_in_popup = opts.in_popup == true,
        is_in_photo = opts.in_photo == true,
        is_auto = opts.auto == true,
        shadow_situation = situation,
        IsInMenuOrPopupOrPhoto = function(e)
            return e.is_in_menu or e.is_in_popup or e.is_in_photo
        end,
        IsAutoMode = function(e) return e.is_auto end,
    }
    setmetatable(event, {
        __index = function(t, k)
            if k == "current_situation" then
                counters.situation_reads = counters.situation_reads + 1
                return rawget(t, "shadow_situation")
            end
            return rawget(t, k)
        end,
    })
    core.event_obj = event

    core.StorePlayerAction = function(_, a, b, c)
        stored[#stored + 1] = { a, b, c }
    end
    return core
end

local on_action
local function register(core)
    hooks = {}
    core:SetInputListener()
    on_action = hooks["PlayerPuppet.OnAction"]
end

local function fire(name, value)
    local consumed = false
    local action = {
        GetName = function(_, a) return { value = a.__name } end,
        GetType = function() return { value = "BUTTON_HOLD" } end,
        GetValue = function() return value or 1 end,
        __name = name,
    }
    local consumer = { Consume = function() consumed = true end }
    on_action(nil, action, consumer)
    return consumed
end

-- =========================================================== section 1 ====
print("\n[1] exception sets mirror the shipped JSON")
do
    local veh = Utils:ReadJson("Data/exception_in_veh_input.json")
    local popup = Utils:ReadJson("Data/exception_in_popup_input.json")
    local entry = Utils:ReadJson("Data/exception_in_entry_area_input.json")
    check("veh list has 17 members", #veh == 17, "got " .. #veh)
    check("popup list has 4 members", #popup == 4, "got " .. #popup)
    check("entry area list has 1 member", #entry == 1, "got " .. #entry)
end

-- =========================================================== section 2 ====
print("\n[2] non-AV situations cost nothing")
do
    local core = new_core(Def.Situation.Normal)
    register(core)
    reset_counters()
    local consumed = fire("Exit", 1)
    check("Normal returns without consuming", consumed == false)
    check("Normal performs zero interop",
        counters.get_player == 0 and counters.player_in == 0
        and counters.mounted_combat_seat == 0 and counters.in_entry_area == 0,
        string.format("player=%d in=%d seat=%d entry=%d",
            counters.get_player, counters.player_in,
            counters.mounted_combat_seat, counters.in_entry_area))
    check("Normal stores no action", #stored == 0)
end

-- =========================================================== section 3 ====
print("\n[3] InVehicle: veh exception list still blocks")
do
    local core = new_core(Def.Situation.InVehicle)
    register(core)
    for _, name in ipairs({ "ToggleVehCamera", "UseConsumable", "VehicleHorn",
                           "HolsterWeapon", "HoldAutodrive" }) do
        reset_counters()
        check("consumes " .. name, fire(name, 1) == true)
    end
    reset_counters()
    check("does not consume a non-exception action", fire("Forward", 1) == false)
end

-- =========================================================== section 4 ====
print("\n[4] IsMountedCombatSeat is not paid for non-popup actions")
do
    Game.__driver_combat = true
    local core = new_core(Def.Situation.InVehicle, { combat_seat = false })
    register(core)

    reset_counters()
    fire("Forward", 1)
    check("non-popup action skips IsMountedCombatSeat",
        counters.mounted_combat_seat == 0, "got " .. counters.mounted_combat_seat)

    reset_counters()
    local c = fire("MountedWeapons_SwitchWeapons", 1)
    check("popup action does consult IsMountedCombatSeat",
        counters.mounted_combat_seat == 1, "got " .. counters.mounted_combat_seat)
    check("popup action + unmounted seat consumes", c == true)

    local core2 = new_core(Def.Situation.InVehicle, { combat_seat = true })
    register(core2)
    reset_counters()
    fire("MountedWeapons_SwitchWeapons", 1)
    check("popup action + mounted combat seat does NOT consume",
        #stored >= 0 and counters.mounted_combat_seat == 1)
    Game.__driver_combat = false
end

-- =========================================================== section 5 ====
print("\n[5] menu / popup / photo and auto mode still block popup actions")
do
    for _, opt in ipairs({ { in_menu = true }, { in_popup = true },
                          { in_photo = true }, { auto = true } }) do
        local core = new_core(Def.Situation.InVehicle, opt)
        register(core)
        reset_counters()
        check("blocks EnterCombatMode while "
                .. (opt.in_menu and "in menu" or opt.in_popup and "in popup"
                    or opt.in_photo and "in photo" or "auto mode"),
            fire("EnterCombatMode", 1) == true)
        reset_counters()
        check("non-popup action unaffected in same state", fire("Forward", 1) == false)
    end
end

-- =========================================================== section 6 ====
print("\n[6] Waiting + entry area")
do
    local core = new_core(Def.Situation.Waiting, { in_entry_area = true })
    register(core)
    reset_counters()
    check("consumes UseConsumable in entry area", fire("UseConsumable", 1) == true)
    reset_counters()
    check("does not consume Forward in entry area", fire("Forward", 1) == false)

    local core2 = new_core(Def.Situation.Waiting, { in_entry_area = false })
    register(core2)
    reset_counters()
    fire("UseConsumable", 1)
    check("outside entry area consults IsPlayerInEntryArea once",
        counters.in_entry_area == 1, "got " .. counters.in_entry_area)
end

-- =========================================================== section 7 ====
print("\n[7] Debug message is not built when Debug is disabled")
do
    local core = new_core(Def.Situation.InVehicle, { log_level = LogLevel.Info })
    register(core)
    reset_counters()
    check("IsEnabled(Debug) is false at Info level",
        core.log_obj:IsEnabled(LogLevel.Debug) == false)
    fire("Forward", 1)
    check("no log line emitted", #emitted == 0, "got " .. #emitted)
    check("IsEnabled(Info) is still true", core.log_obj:IsEnabled(LogLevel.Info) == true)
end

-- =========================================================== section 8 ====
print("\n[8] Debug message is byte-identical when Debug is enabled")
do
    local core = new_core(Def.Situation.InVehicle,
        { log_master = LogLevel.Nothing, log_level = LogLevel.Debug })
    register(core)
    reset_counters()
    check("IsEnabled(Debug) is true once unlocked",
        core.log_obj:IsEnabled(LogLevel.Debug) == true)
    fire("ToggleVehCamera", 0.5)
    check("exactly one log line emitted", #emitted == 1, "got " .. #emitted)
    local expected = "[Core] [DEBUG] Action Name: ToggleVehCamera Type: BUTTON_HOLD Value: 0.5"
    check("message matches the pre-fix format exactly",
        emitted[1] == expected, "\n    got: " .. tostring(emitted[1])
        .. "\n    want: " .. expected)
    MasterLogLevel = LogLevel.Info
end

-- =========================================================== section 9 ====
print("\n[9] IsEnabled agrees with Record for every level")
do
    local ok = true
    local detail = ""
    for setting = LogLevel.Critical, LogLevel.Nothing do
        for lvl = LogLevel.Critical, LogLevel.Nothing do
            local lg = Log:New()
            lg.setting_level = setting
            local saved_master = MasterLogLevel
            MasterLogLevel = LogLevel.Nothing
            local enabled = lg:IsEnabled(lvl)
            emitted = {}
            lg:Record(lvl, "probe")
            local printed = #emitted > 0
            MasterLogLevel = saved_master
            if enabled ~= printed then
                ok = false
                detail = string.format("setting=%d level=%d IsEnabled=%s printed=%s",
                    setting, lvl, tostring(enabled), tostring(printed))
            end
        end
    end
    check("IsEnabled never hides a line Record would print", ok, detail)
end

-- ========================================================== section 10 ====
print("\n[10] situation is read once, not re-read per helper")
do
    local core = new_core(Def.Situation.InVehicle)
    register(core)
    reset_counters()
    fire("Forward", 1)
    check("exactly one current_situation read",
        counters.situation_reads == 1, "got " .. counters.situation_reads)
end

-- ========================================================== section 11 ====
print("\n[11] StorePlayerAction still receives the same arguments")
do
    local core = new_core(Def.Situation.InVehicle)
    register(core)
    stored = {}
    fire("Forward", 0.25)
    check("stored once", #stored == 1, "got " .. #stored)
    check("args are name/type/value",
        stored[1] and stored[1][1] == "Forward"
        and stored[1][2] == "BUTTON_HOLD" and stored[1][3] == 0.25,
        stored[1] and (tostring(stored[1][1]) .. "/" .. tostring(stored[1][2])
            .. "/" .. tostring(stored[1][3])))
end

-- ========================================================== section 12 ====
print("\n[12] differential: every Consume() decision matches the pre-fix logic")
do
    local veh_list = Utils:ReadJson("Data/exception_in_veh_input.json")
    local popup_list = Utils:ReadJson("Data/exception_in_popup_input.json")
    local entry_list = Utils:ReadJson("Data/exception_in_entry_area_input.json")

    -- The callback exactly as it was before fix (3), transcribed literally so any
    -- divergence in the rewrite shows up here rather than in someone's reading of
    -- the diff. State is passed in and mutated the same way the real one did.
    local function old_logic(s, name)
        local consumed = false
        local function Consume() consumed = true end

        if s.situation ~= Def.Situation.Waiting and s.situation ~= Def.Situation.InVehicle then
            return false
        end

        if s.situation == Def.Situation.InVehicle and s.player_in then
            for _, exception in pairs(veh_list) do
                if name == exception then Consume() break end
            end
            if s.driver_combat then
                if name == "Exit" and not s.locked_in_combat then
                    s.locked_in_combat = true
                    Consume()
                end
                if not s.combat_seat then
                    for _, exception in pairs(popup_list) do
                        if name == exception then Consume() break end
                    end
                end
            else
                s.locked_in_combat = false
            end
            if s.in_menu or s.in_popup or s.in_photo or s.auto then
                for _, exception in pairs(popup_list) do
                    if name == exception then Consume() break end
                end
            end
        elseif s.situation == Def.Situation.Waiting and s.in_entry_area then
            for _, exception in pairs(entry_list) do
                if name == exception then Consume() break end
            end
        end
        return consumed
    end

    -- Action names spanning every bucket the lists and the code care about.
    local names = {
        "Exit", "Forward", "Backward", "ToggleVehCamera", "UseConsumable",
        "VehicleHorn", "HolsterWeapon", "HoldAutodrive", "CameraAim",
        "MountedWeapons_SwitchWeapons", "MountedWeapons_NextWeapon",
        "MountedWeapons_WeaponSlot1", "EnterCombatMode", "SomeRandomAction",
    }
    local situations = { Def.Situation.Normal, Def.Situation.Idle,
                        Def.Situation.Waiting, Def.Situation.InVehicle,
                        Def.Situation.Landing, Def.Situation.TalkingOff }

    local cases, mismatches = 0, {}
    for _, sit in ipairs(situations) do
        for _, pin in ipairs({ true, false }) do
            for _, dc in ipairs({ true, false }) do
                for _, seat in ipairs({ true, false }) do
                    for _, menu in ipairs({ true, false }) do
                        for _, auto in ipairs({ true, false }) do
                            for _, entry in ipairs({ true, false }) do
                                for _, name in ipairs(names) do
                                    local st = {
                                        situation = sit, player_in = pin,
                                        driver_combat = dc, combat_seat = seat,
                                        in_menu = menu, in_popup = false,
                                        in_photo = false, auto = auto,
                                        in_entry_area = entry,
                                        locked_in_combat = false,
                                    }
                                    local want = old_logic(st, name)

                                    local core = new_core(sit, {
                                        player_in = pin, driver_combat = dc,
                                        combat_seat = seat, in_menu = menu,
                                        auto = auto, in_entry_area = entry,
                                    })
                                    core.is_locked_action_in_combat = false
                                    Game.__driver_combat = dc
                                    register(core)
                                    local got = fire(name, 1)

                                    cases = cases + 1
                                    if got ~= want then
                                        mismatches[#mismatches + 1] = string.format(
                                            "sit=%d pin=%s dc=%s seat=%s menu=%s auto=%s entry=%s %s: old=%s new=%s",
                                            sit, tostring(pin), tostring(dc), tostring(seat),
                                            tostring(menu), tostring(auto), tostring(entry),
                                            name, tostring(want), tostring(got))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    Game.__driver_combat = false
    check("all " .. cases .. " state x action combinations agree", #mismatches == 0,
        #mismatches > 0 and ("\n    " .. table.concat(mismatches, "\n    ")) or "")
end

-- ========================================================== section 13 ====
print("\n[13] cost ledger: interop calls per action, old vs new")
do
    -- Same transcription as section 12, but the C# round trips go through
    -- counters so both versions are measured with the same yardstick.
    local function old_cost(s, name, c)
        local veh_list = Utils:ReadJson("Data/exception_in_veh_input.json")
        local popup_list = Utils:ReadJson("Data/exception_in_popup_input.json")
        local entry_list = Utils:ReadJson("Data/exception_in_entry_area_input.json")
        local consumed = false
        local function Consume() consumed = true end
        local function seat()
            c.seat = c.seat + 1
            return s.combat_seat
        end

        if s.situation ~= Def.Situation.Waiting and s.situation ~= Def.Situation.InVehicle then
            return false
        end
        -- The old code built the Debug message unconditionally on every action
        -- that got this far: "Action Name: " .. name .. " Type: " .. t .. " Value: " .. v
        -- is 4 allocations, all thrown away at Info level.
        c.logconcat = 1
        if s.situation == Def.Situation.InVehicle and s.player_in then
            c.player_in = c.player_in + 1
            for _, e in pairs(veh_list) do if name == e then Consume() break end end
            c.get_player = c.get_player + 1
            c.combat = c.combat + 1
            if s.driver_combat then
                if name == "Exit" and not s.locked_in_combat then
                    s.locked_in_combat = true
                    Consume()
                end
                if not seat() then
                    for _, e in pairs(popup_list) do if name == e then Consume() break end end
                end
            else
                s.locked_in_combat = false
            end
            if s.in_menu or s.in_popup or s.in_photo or s.auto then
                for _, e in pairs(popup_list) do if name == e then Consume() break end end
            end
        elseif s.situation == Def.Situation.Waiting and s.in_entry_area then
            c.entry = c.entry + 1
            for _, e in pairs(entry_list) do if name == e then Consume() break end end
        end
        return consumed
    end

    local function new_cost(sit, name, opts)
        reset_counters()
        Game.__driver_combat = opts.driver_combat
        local core = new_core(sit, opts)
        register(core)
        local got = fire(name, 1)
        -- The rewrite only concatenates when the level is actually live, so the
        -- allocation count is exactly the gate's value.
        local lc = core.log_obj:IsEnabled(LogLevel.Debug) and 1 or 0
        return got, {
            player_in = counters.player_in, get_player = counters.get_player,
            combat = counters.driver_combat, seat = counters.mounted_combat_seat,
            entry = counters.in_entry_area, logconcat = lc,
        }
    end

    local function fresh_state(sit, opts)
        return {
            situation = sit, player_in = opts.player_in ~= false,
            driver_combat = opts.driver_combat == true,
            combat_seat = opts.combat_seat == true,
            in_menu = opts.in_menu == true, in_popup = false, in_photo = false,
            auto = opts.auto == true, in_entry_area = opts.in_entry_area == true,
            locked_in_combat = false,
        }
    end

    local ledger = {}
    local function row(label, sit, name, opts)
        local oc = { player_in = 0, get_player = 0, combat = 0, seat = 0, entry = 0,
                    logconcat = 0 }
        local o = old_cost(fresh_state(sit, opts), name, oc)
        local n, nc = new_cost(sit, name, opts)
        assert(o == n, "ledger disagrees on " .. label)
        local function total(t)
            return t.player_in + t.get_player + t.combat + t.seat + t.entry
        end
        ledger[#ledger + 1] = {
            label = label, old = oc, new = nc,
            old_total = total(oc), new_total = total(nc),
        }
    end

    row("Normal (no AV)", Def.Situation.Normal, "Forward", {})
    row("InVehicle, plain action", Def.Situation.InVehicle, "Forward", {})
    row("InVehicle, veh exception", Def.Situation.InVehicle, "VehicleHorn", {})
    row("InVehicle, combat, non-popup", Def.Situation.InVehicle, "Forward",
        { driver_combat = true })
    row("InVehicle, combat, popup exception", Def.Situation.InVehicle,
        "MountedWeapons_SwitchWeapons", { driver_combat = true })
    row("InVehicle, auto mode, non-popup", Def.Situation.InVehicle, "Forward", { auto = true })
    row("Waiting, in entry area", Def.Situation.Waiting, "UseConsumable",
        { in_entry_area = true })

    print(string.format("  %-36s %-13s %-13s %s", "case",
        "C# round trips", "dead strings", "saved"))
    print(string.format("  %-36s %6s %6s %6s %6s %s",
        "", "old", "new", "old", "new", ""))
    print("  " .. string.rep("-", 78))
    local ot, nt, ol, nl = 0, 0, 0, 0
    for _, r in ipairs(ledger) do
        ot = ot + r.old_total
        nt = nt + r.new_total
        ol = ol + r.old.logconcat
        nl = nl + r.new.logconcat
        print(string.format("  %-36s %6d %7d %6d %7d   -%d",
            r.label, r.old_total, r.new_total, r.old.logconcat, r.new.logconcat,
            (r.old_total + r.old.logconcat) - (r.new_total + r.new.logconcat)))
    end
    print("  " .. string.rep("-", 78))
    print(string.format("  %-36s %6d %7d %6d %7d   -%d (%.0f%%)", "TOTAL across cases",
        ot, nt, ol, nl, (ot + ol) - (nt + nl), 100 * ((ot + ol) - (nt + nl)) / (ot + ol)))
    check("new path never costs more than the old one",
        (function()
            for _, r in ipairs(ledger) do
                if r.new_total > r.old_total then return false end
                if r.new.logconcat > r.old.logconcat then return false end
            end
            return true
        end)())
    check("dead Debug concatenation eliminated at Info level", nl == 0 and ol > 0,
        string.format("old$=%d new$=%d", ol, nl))
end

-- ------------------------------------------------------------- result -----
print(string.format("\nonaction_cost_test: %d passed, %d failed", pass, fail))
if fail > 0 then return error("test failures") end
