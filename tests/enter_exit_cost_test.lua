-- =============================================================================
-- Enter / exit cost + non-AV vehicle impact test
--
-- Two questions, one harness:
--
--   1. "車両の乗り降りで画面がカクつく" -- what does the mod actually spend at
--      the moment of boarding and alighting?  Every step of the enter/exit path
--      is driven here and every Lua -> C# transition is counted, so the answer
--      is a ledger and not a guess.
--
--   2. "AV以外の車両に影響が出ていないか" -- every Override/Observe the mod
--      installs is captured instead of being a no-op, then driven with a
--      NON-AV vehicle in the seat.  Each hook must either be inert or return
--      exactly what the game would have produced on its own.
--
-- Run:  python tests/run_enter_exit_cost_test.py
-- =============================================================================

local MODDIR = ...

-- ------------------------------------------------------------- counters -----
local T = { total = 0, by = {} }
local function count(key)
    T.total = T.total + 1
    T.by[key] = (T.by[key] or 0) + 1
end
local function reset_count() T.total = 0; T.by = {} end
local function n(key) return T.by[key] or 0 end

-- ------------------------------------------------------- hook capture -------
-- The real Override/Observe/ObserveAfter become a registry, so the tests can
-- enumerate what the mod hooks and drive each one by hand.
local hooks = {}
function Observe(cls, method, cb) hooks["Observe:" .. cls .. "." .. method] = cb end
function ObserveAfter(cls, method, cb) hooks["ObserveAfter:" .. cls .. "." .. method] = cb end
function Override(cls, method, cb) hooks["Override:" .. cls .. "." .. method] = cb end
local function hook_keys()
    local keys = {}
    for k in pairs(hooks) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- ----------------------------------------------------------- stub types -----
Vector4 = {}
Vector4.__index = Vector4
function Vector4.new(x, y, z, w)
    return setmetatable({ x = x, y = y, z = z, w = w or 1 }, Vector4)
end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Vector3To4(v) return Vector4.new(v.x, v.y, v.z, 0) end
function Vector4.IsZero(v) count("vec4.IsZero"); return v.x == 0 and v.y == 0 and v.z == 0 end
function Vector4.ToRotation(v) return Quaternion.new(v.x, v.y, v.z, v.w) end
function Vector4.RotateAxis(a, b, c) return a end
function Vector4.Distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end
Vector3 = { new = function(x, y, z) count("Vector3.new"); return { x = x, y = y, z = z } end }

local EulerAnglesMT = {}
function EulerAnglesMT.ToQuat(self)
    count("euler.ToQuat")
    return Quaternion.new(0, 0, 0, 1)
end
EulerAngles = {
    new = function(p, y, r)
        return setmetatable({ pitch = p, yaw = y, roll = r }, { __index = EulerAnglesMT })
    end,
    ToQuat = function(e) count("euler.ToQuat"); return Quaternion.new(0, 0, 0, 1) end,
}
Quaternion = {
    new = function(x, y, z, w)
        return { x = x, y = y, z = z, w = w, r = w or 1, i = x or 0, j = y or 0, k = z or 0 }
    end,
}
-- CName is interned in the real game (compared by hash), so the stub interns too:
-- CName.new("X") == CName.new("X") has to hold for the source/action
-- comparisons in the input-hint observers to be testable.
local CNAME_INTERN = {}
CName = { new = function(s)
    count("api.CName.new")
    local existing = CNAME_INTERN[s]
    if existing == nil then
        existing = { value = s, hash = tostring(s) }
        CNAME_INTERN[s] = existing
    end
    return existing
end }
StringToName = function(s) count("api.StringToName"); return s end
ResRef = { FromName = function(s) return { name = s } end }
QueryFilter = { new = function() return { mask2 = 0 } end, AddGroup = function() return { mask2 = 1 } end }
DynamicEntitySpec = { new = function() return {} end }
MountEventData = { new = function() count("api.MountEventData.new"); return {} end }
MountingSlotId = { new = function() count("api.MountingSlotId.new"); return {} end }
MountingInfo = { new = function() count("api.MountingInfo.new"); return {} end }
MountingRequest = { new = function() count("api.MountingRequest.new"); return {} end }
VehicleDoorOpen = { new = function() count("api.VehicleDoorOpen.new"); return { kind = "open" } end }
VehicleDoorClose = { new = function() count("api.VehicleDoorClose.new"); return { kind = "close" } end }
VehicleDoorState = { Closed = 1, Open = 2, Opening = 3, Closing = 4 }
EVehicleDoor = {
    seat_front_left = 1, seat_front_right = 2,
    seat_back_left = 3, seat_back_right = 4, trunk = 5, hood = 6,
}
inkInputHintHoldIndicationType = { Hold = 1, Press = 2, FromInputConfig = 3 }
-- Ink enums: the values are opaque to the mod, only the names matter.
local function any_enum()
    return setmetatable({}, { __index = function(t, k) return k end })
end
for _, enum_name in ipairs({
    "inkEAnchor", "inkEChildOrder", "inkEHorizontalAlign", "inkESizeRule",
    "inkEVerticalAlign", "textHorizontalAlignment", "textJustificationType",
    "textVerticalAlignment",
}) do
    _G[enum_name] = any_enum()
end
inkTextRef = { SetText = function(w, v) count("inkTextRef.SetText"); w.text = v end }
GameObjectEffectHelper = {
    StartEffectEvent = function() count("fx.StartEffectEvent") end,
    StopEffectEvent = function() count("fx.StopEffectEvent") end,
}
SaveLocksManager = {
    RequestSaveLockAdd = function() count("SaveLocks.Add") end,
    RequestSaveLockRemove = function() count("SaveLocks.Remove") end,
}
Codeware = { Version = function() return "1.17.0" end }
spdlog = { info = function() end }

-- JSON fixtures. A faithful decode is not what is under test; what matters is
-- how often the mod hits the disk and how much downstream work each hit
-- triggers, so the decoded shape is a fixture picked by a content marker.
local FIXTURE_INPUT_HINT = {
    { source = "DrawWeapon", action = "MountedWeapons_SwitchWeapons",
      localizedLabel = "LocKey#52471", sortingPriority = 8,
      holdIndicationType = "FromInputConfig", enableHoldAnimation = false,
      mode = -1, usage = "Both" },
    { source = "DAV_Up", action = "DAV_Up",
      localizedLabel = "LocKey#10001-LocKey#10002", sortingPriority = 20,
      holdIndicationType = "Hold", enableHoldAnimation = true,
      mode = 0, usage = "keyboard" },
    { source = "DAV_PadOnly", action = "DAV_PadOnly",
      localizedLabel = "LocKey#10003", sortingPriority = 21,
      holdIndicationType = "Press", enableHoldAnimation = false,
      mode = 0, usage = "gamepad" },
    { source = "DAV_HeliOnly", action = "DAV_HeliOnly",
      localizedLabel = "LocKey#20001", sortingPriority = 22,
      holdIndicationType = "Hold", enableHoldAnimation = true,
      mode = 1, usage = "Both" },
}
local FIXTURE_HINT_OVERRIDE = {
    AV = {
        { no = 1, title = "hud_input_hint_av_vertical_movement", actions = { "move_up", "move_down" } },
        { no = 2, title = "hud_input_hint_av_horizontal_movement", actions = { "move_left", "move_right" } },
        { no = 3, title = "hud_input_hint_av_forward_backward", actions = { "move_forward", "move_backward" } },
    },
    Helicopter = {
        { no = 1, title = "hud_input_hint_helicopter_vertical_movement", actions = { "ascend", "descend" } },
    },
}
local FIXTURE_MAPPING = {
    keyboard = { IK_W = "key_w", IK_A = "key_a" },
    gamepad = { IK_Pad_X_SQUARE = "pad_square" },
}
local FIXTURE_EXCEPTION_HINT = { "UI_FakeDriverCombatControllerVisionActivation" }

local JSON_FIXTURES = {
    { "MountedWeapons_SwitchWeapons", FIXTURE_INPUT_HINT },
    { "hud_input_hint_av_vertical_movement", FIXTURE_HINT_OVERRIDE },
    { "IK_Pad_X_SQUARE", FIXTURE_MAPPING },
    { "UI_FakeDriverCombatControllerVisionActivation", FIXTURE_EXCEPTION_HINT },
}
local function fixture_deep_copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = fixture_deep_copy(v) end
    return c
end
DISK_OPENS = 0
json = {
    decode = function(s)
        for _, pair in ipairs(JSON_FIXTURES) do
            if string.find(s, pair[1], 1, true) then
                return fixture_deep_copy(pair[2])
            end
        end
        return {}
    end,
    encode = function() return "{}" end,
}

-- Every file open is counted: that is the disk hit the boarding path pays.
local real_io_open = io.open
io.open = function(path, mode)
    DISK_OPENS = DISK_OPENS + 1
    return real_io_open(path, mode)
end
local function disk_opens() return DISK_OPENS end
local function reset_disk() DISK_OPENS = 0 end

-- --------------------------------------------------------- stub timers ------
-- Timers are recorded, not run, so the "+1.5s" / "+3.0s" boarding groups can
-- be measured as groups.
TIMER_LOG = {}
Cron = {
    Every = function(interval, data, cb)
        if cb == nil then cb = data; data = nil end
        TIMER_LOG[#TIMER_LOG + 1] = { kind = "every", interval = interval, cb = cb, data = data }
        return { id = #TIMER_LOG }
    end,
    After = function(delay, cb)
        TIMER_LOG[#TIMER_LOG + 1] = { kind = "after", delay = delay, cb = cb }
        return { id = #TIMER_LOG }
    end,
    Halt = function(t) end,
}
local function last_timer() return TIMER_LOG[#TIMER_LOG] end
local function clear_timers() TIMER_LOG = {} end

-- ------------------------------------------------------- stub game API ------
local world = {
    player_x = 1, player_y = 0, player_z = 0,
    av_x = 0, av_y = 0, av_z = 2,
    ground_z = 0,
    mounted = false,
    destroyed = false,
    engine_on = true,
    door_state = VehicleDoorState.Closed,
    entity_alive = true,
    on_ground = true,
    -- Backs the batched GetFlightState stub.
    velocity = { x = 0, y = 0, z = 0 },
    angular_velocity = { x = 0, y = 0, z = 0 },
    gravity = false,
    physics_off = false,
}

-- Mirrors DAVStateFlags in the plugin: bit0 on-ground, bit1 gravity,
-- bit2 physics disabled, bit3 handle valid.
local function pack_state()
    local flags = 8
    if world.on_ground then flags = flags + 1 end
    if world.gravity then flags = flags + 2 end
    if world.physics_off then flags = flags + 4 end
    return flags
end

local fly_av = {}
function fly_av.SetVehicle(self, h) count("flyav.SetVehicle") end
function fly_av.GetMass(self) count("flyav.GetMass"); return 5000 end
function fly_av.GetPhysicsState(self) count("flyav.GetPhysicsState"); return 0 end
function fly_av.UnsetPhysicsState(self) count("flyav.UnsetPhysicsState") end
function fly_av.EnableOriginalPhysics(self, on) count("flyav.EnableOriginalPhysics") end
function fly_av.HasGravity(self) count("flyav.HasGravity"); return false end
function fly_av.EnableGravity(self, on) count("flyav.EnableGravity") end
function fly_av.IsOnGround(self) count("flyav.IsOnGround"); return world.on_ground end
function fly_av.GetVelocity(self) count("flyav.GetVelocity"); return Vector3.new(world.velocity.x, world.velocity.y, world.velocity.z) end
function fly_av.GetAngularVelocity(self) count("flyav.GetAngularVelocity"); return Vector3.new(world.angular_velocity.x, world.angular_velocity.y, world.angular_velocity.z) end
function fly_av.AddForce(self, f, t) count("flyav.AddForce") end
function fly_av.ChangeVelocity(self, v, a, k) count("flyav.ChangeVelocity") end
function fly_av.GetFlightState(self)
    count("flyav.GetFlightState")
    local v = world.velocity
    return Vector4.new(v.x, v.y, v.z, pack_state())
end
function fly_av.AddForceTracked(self, force, target_angular, gain)
    count("flyav.AddForceTracked")
    local a = world.angular_velocity
    return Vector3.new((target_angular.x - a.x) * gain,
                      (target_angular.y - a.y) * gain,
                      (target_angular.z - a.z) * gain)
end
FlyAVSystem = { new = function() return setmetatable({}, { __index = fly_av }) end }

local vehicle_ps = {}
function vehicle_ps.GetDoorState(self, d) count("vehicle_ps.GetDoorState"); return world.door_state end
function vehicle_ps.QueuePSEvent(self, a, ev)
    count("vehicle_ps.QueuePSEvent")
    if ev ~= nil and ev.kind == "open" then
        world.door_state = VehicleDoorState.Opening
    elseif ev ~= nil and ev.kind == "close" then
        world.door_state = VehicleDoorState.Closing
    end
end
function vehicle_ps.UnlockAllVehDoors(self) count("vehicle_ps.Unlock") end
function vehicle_ps.QuestLockAllVehDoors(self) count("vehicle_ps.QuestLock") end
function vehicle_ps.DisableAllVehInteractions(self) count("vehicle_ps.DisableAll") end

local orientation = {
    x = 0, y = 0, z = 0, w = 1, r = 1, i = 0, j = 0, k = 0,
    ToEulerAngles = function(self) count("euler.ToEulerAngles"); return EulerAngles.new(0, 0, 0) end,
}

local entity_stub = {}
function entity_stub.IsPlayerMounted(self) count("entity.IsPlayerMounted"); return world.mounted end
function entity_stub.IsDestroyed(self) count("entity.IsDestroyed"); return world.destroyed end
function entity_stub.IsEngineTurnedOn(self) count("entity.IsEngineTurnedOn"); return world.engine_on end
function entity_stub.GetWorldPosition(self)
    count("entity.GetWorldPosition")
    return Vector4.new(world.av_x, world.av_y, world.av_z, 1)
end
function entity_stub.GetWorldForward(self) count("entity.GetWorldForward"); return Vector4.new(1, 0, 0, 0) end
function entity_stub.GetWorldRight(self) count("entity.GetWorldRight"); return Vector4.new(0, 1, 0, 0) end
function entity_stub.GetWorldUp(self) count("entity.GetWorldUp"); return Vector4.new(0, 0, 1, 0) end
function entity_stub.GetWorldOrientation(self) count("entity.GetWorldOrientation"); return orientation end
function entity_stub.GetVehiclePS(self) count("entity.GetVehiclePS"); return vehicle_ps end
function entity_stub.FindComponentByName(self, name)
    count("entity.FindComponentByName")
    return {
        SetLocalPosition = function(w, p) count("widget.SetLocalPosition") end,
        SetLocalOrientation = function(w, q) count("widget.SetLocalOrientation") end,
        Toggle = function(w, on) count("widget.Toggle") end,
    }
end
function entity_stub.IsRadioReceiverActive(self) count("entity.IsRadioReceiverActive"); return false end
function entity_stub.NextRadioReceiverStation(self) count("entity.NextRadio") end
function entity_stub.ToggleRadioReceiver(self, on) count("entity.ToggleRadio") end
function entity_stub.ScheduleAppearanceChange(self, a) count("entity.ScheduleAppearanceChange") end
function entity_stub.TurnEngineOn(self, on) count("entity.TurnEngineOn") end
function entity_stub.GetEntityID(self) count("entity.GetEntityID"); return { hash = 1 } end

local player_stub = {
    GetWorldPosition = function(self)
        count("player.GetWorldPosition")
        return Vector4.new(world.player_x, world.player_y, world.player_z, 1)
    end,
    PSIsInDriverCombat = function(self) count("player.PSIsInDriverCombat"); return false end,
    GetEntityID = function(self) count("player.GetEntityID"); return { hash = 2 } end,
    QueueEvent = function(self, e) count("player.QueueEvent") end,
    FindVehicleCameraManager = function(self) count("player.FindVehicleCameraManager"); return nil end,
}

TELEPORTS = 0
Game = {
    FindEntityByID = function(id) count("Game.FindEntityByID"); return world.entity_alive and entity_stub or nil end,
    GetPlayer = function() count("Game.GetPlayer"); return player_stub end,
    GetTimeSystem = function() return { GetGameTimeStamp = function() count("time.GetGameTimeStamp"); return 0 end } end,
    GetSpatialQueriesSystem = function()
        return {
            SyncRaycastByQueryFilter = function(sys, a, b, f, c, d)
                count("raycast")
                return true, { position = Vector4.new(0, 0, world.ground_z, 1) }
            end,
        }
    end,
    GetDynamicEntitySystem = function()
        return { CreateEntity = function(s, spec) count("entities.CreateEntity"); return { hash = 1 } end,
                 DeleteEntity = function(s, id) count("entities.DeleteEntity") end }
    end,
    GetVehicleSystem = function()
        return { GetPlayerUnlockedVehicles = function() count("veh.GetUnlocked"); return {} end }
    end,
    GetBlackboardSystem = function()
        return {
            Get = function(sys, def)
                count("bb.Get")
                return {
                    SetInt = function(bb, k, v) count("bb.SetInt"); bb.active_hub = v end,
                    GetInt = function(bb, k) count("bb.GetInt"); return bb.active_hub end,
                    GetVariant = function(bb, k) count("bb.GetVariant"); return { variant = k } end,
                }
            end,
        }
    end,
    GetMountingFacility = function()
        return { Mount = function(f, r) count("mount.Mount") end,
                 Unmount = function(f, r) count("mount.Unmount") end }
    end,
    GetTeleportationFacility = function()
        return { Teleport = function(f, who, pos, ang)
            TELEPORTS = TELEPORTS + 1
            count("teleport")
        end }
    end,
    GetUISystem = function()
        return {
            QueueEvent = function(sys, ev) count("uisystem.QueueEvent") end,
            GetLayer = function(sys, name) count("uisystem.GetLayer"); return nil end,
        }
    end,
    GetInkSystem = function()
        return {
            GetLayer = function(sys, name)
                count("ink.GetLayer")
                return {
                    GetGameControllers = function(l)
                        count("ink.GetGameControllers")
                        return { { ToString = function(c) return "gameuiInputHintManagerGameController" end } }
                    end,
                }
            end,
        }
    end,
    IsSavingLocked = function() count("Game.IsSavingLocked"); return false, nil end,
    GetCallbackSystem = function()
        return { RegisterCallback = function() end, UnregisterCallback = function() end }
    end,
}

GetLocalizedText = function(k) count("GetLocalizedText"); return "L" end
GetAllBlackboardDefs = function()
    count("GetAllBlackboardDefs")
    return { UIInteractions = { ActiveChoiceHubID = 11, DialogChoiceHubs = 12 } }
end
TweakDBInterface = {
    GetChoiceCaptionIconPartRecord = function(r) count("tweakdb.GetChoiceCaptionIconPartRecord"); return { rec = r } end,
}
gameinteractionsvisEVisualizerActivityState = { Active = 1 }
gameinteractionsChoiceType = { Selected = 2 }
gameinteractionsvisListChoiceHubData = { new = function() count("gi.HubData.new"); return { choices = {} } end }
gameinteractionsChoiceTypeWrapper = {
    new = function() count("gi.TypeWrapper.new"); return { SetType = function(s, t) count("gi.SetType") end } end,
}
gameinteractionsChoiceCaption = {
    new = function() count("gi.Caption.new"); return { AddPartFromRecord = function(s, r) count("gi.AddPartFromRecord") end } end,
}
gameinteractionsvisListChoiceData = { new = function() count("gi.ChoiceData.new"); return {} end }
FromVariant = function(v) count("FromVariant"); return v end
ToVariant = function(v) count("ToVariant"); return v end

-- TweakDB: SetPerspective() writes 48 flats per call.
TWEAK_WRITES = 0
TweakDB = {
    SetFlat = function(id, v) TWEAK_WRITES = TWEAK_WRITES + 1; count("tweakdb.SetFlat") end,
    GetRecord = function(id) return {} end,
    CloneRecord = function(a, b) end,
}
TweakDBID = { new = function(s) count("tweakdb.id.new"); return { value = s, hash = s } end }

-- Widget / input-hint classes. Any method on them is a C# call; the auto stub
-- counts it and returns nothing, which is all the callers need.
WIDGET_CREATIONS = 0
local function make_auto_widget(name)
    local w = { Children = {}, visible = true }
    setmetatable(w, {
        __index = function(t, k)
            return function(...) count("widget." .. name .. "." .. tostring(k)) end
        end,
    })
    return w
end
for _, cls in ipairs({
    "inkCanvas", "inkFlex", "inkHorizontalPanel", "inkImage", "inkText",
    "UpdateInputHintEvent", "UpdateInputHintMultipleEvent", "InputHintData",
    "DeleteInputHintBySourceEvent",
}) do
    _G[cls] = {
        new = function()
            WIDGET_CREATIONS = WIDGET_CREATIONS + 1
            count("widget." .. cls .. ".new")
            return make_auto_widget(cls)
        end,
    }
end

-- Fakes for modules the enter/exit path must not really run.
package.preload["External/GameHUD.lua"] = function()
    return { Initialize = function() count("GameHUD.Initialize") end,
             ShowMessage = function() end, ShowWarning = function() end }
end
package.preload["External/GameSettings.lua"] = function()
    return { Get = function(k) count("GameSettings.Get"); return "UI-Settings-UnitMetric" end }
end
package.preload["External/GameUI.lua"] = function()
    return { Observe = function(name, cb) return { name = name, cb = cb } end }
end
local fake_module_mt = {
    __index = function(self, key)
        return function(...) count("fake." .. tostring(key)) end
    end,
}
package.preload["Modules/sound.lua"] = function()
    return { New = function(cls) return setmetatable({}, fake_module_mt) end }
end
package.preload["Modules/ui.lua"] = function()
    return { New = function(cls) return setmetatable({}, fake_module_mt) end }
end

-- --------------------------------------------------------- load the mod -----
local LUAJIT_EXT = "%f[%w]goto%s+[A-Za-z_][A-Za-z0-9_]*%f[^%w]"
local LUAJIT_LBL = "::%s*[A-Za-z_][A-Za-z0-9_]*%s*::"

local function preload(name)
    local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
    local b = f:read("*a"); f:close()
    b = b:gsub(LUAJIT_EXT, "do end")
    b = b:gsub(LUAJIT_LBL, "do end")
    local chunk, err = (loadstring or load)(b, name)
    if not chunk then error("cannot compile " .. name .. ": " .. tostring(err)) end
    package.preload[name] = chunk
end

preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Etc/timescale.lua")
TimeScale = require("Etc/timescale.lua")
preload("Etc/def.lua")
preload("Etc/queue.lua")
preload("Modules/profprobe.lua")
preload("Modules/obstacle_grid.lua")
preload("Modules/camera.lua")
preload("Modules/engine.lua")
preload("Modules/navigation.lua")
preload("Modules/av.lua")
preload("Modules/hud.lua")
preload("Modules/event.lua")
preload("Modules/core.lua")

Log = require("Etc/log.lua")
Def = require("Etc/def.lua")
local AV = require("Modules/av.lua")
local Event = require("Modules/event.lua")
local Core = require("Modules/core.lua")
local HUD = require("Modules/hud.lua")
local Camera = require("Modules/camera.lua")

-- ------------------------------------------------------------- world --------
local SEATS = { "seat_front_left", "seat_front_right", "seat_back_left" }

local all_models = {
    [1] = {
        tweakdb_id = "Vehicle.av_test_dav",
        type = { "appearance_base" },
        display_name_lockey = 4242,
        flight_mode = Def.FlightMode.AV,
        actual_allocated_seat = SEATS,
        active_seat = SEATS,
        actual_allocated_door = { "seat_front_left", "seat_front_right" },
        exit_duration = 1.0,
        combat_door = { "None" },
        crystal_dome = false,
        landing_vfx = true,
        projection_offset = { x = 0, y = 0, z = 0 },
        engine_audio_name = "test_engine_audio",
        manual_rpm_meter = false,
        armed = true,
        engine_component_name = { "EngFL", "EngFR", "EngBL", "EngBR" },
        engine_component_offset = {
            { x = 1, y = 1, z = 0 }, { x = 1, y = -1, z = 0 },
            { x = -1, y = 1, z = 0 }, { x = -1, y = -1, z = 0 },
        },
        thruster_fx_name = { "ThrFL", "ThrFR", "ThrBL", "ThrBR" },
        thruster_fx_offset = {
            { x = 1, y = 1, z = 0 }, { x = 1, y = -1, z = 0 },
            { x = -1, y = 1, z = 0 }, { x = -1, y = -1, z = 0 },
        },
        thruster_angle_max = 30,
        destroy_app = "destroyed",
        entry_point = { x = 1, y = 0, z = 0 },
        entry_area_radius = 2.0,
        exit_point = { x = -1, y = 0, z = 0 },
        minimum_distance_to_ground = 1.2,
        collision_check_side_distance = 1.0,
        fpp_camera = true,
        camera_distance_ratio = { 1, 1, 1 },
        camera_center_offset = {
            { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 },
        },
    },
}

DAV = {
    frame_seq = 0,
    time_resolution = 0.01,
    is_ready = false,            -- let Init() register hooks so we can capture them
    is_debug_mode = false,
    is_debug_enable_obstacle_scan = false,
    is_debug_profile_autopilot = false,
    is_debug_situation_ledger = false,
    model_index = 1,
    model_type_index = 1,
    axis_dead_zone = 0.1,
    user_setting_table = {
        language_index = 1,
        is_enable_landing_vfx = true,
        is_enable_idle_gravity = true,
        is_enable_obstacle_recording = false,
        max_speed = 60,
        acceleration = 5, vertical_acceleration = 5, left_right_acceleration = 5,
        roll_change_amount = 1, pitch_change_amount = 1, yaw_change_amount = 1,
        rotate_roll_change_amount = 1,
        roll_restore_amount = 1, pitch_restore_amount = 1,
        h_roll_change_amount = 1, h_pitch_change_amount = 1, h_yaw_change_amount = 1,
        h_acceleration = 5, h_ascend_acceleration = 5, h_descend_acceleration = 5,
        h_lift_idle_acceleration = 0, h_roll_restore_amount = 1, h_pitch_restore_amount = 1,
        horizontal_air_resistance_const = 0.1,
        vertical_air_resistance_const = 0.1,
        garage_info_list = { { type_index = 1 } },
        keybind_table = { { name = "move_up", key = "IK_G", pad = "IK_Pad_X_SQUARE", is_hold = true } },
        heli_keybind_table = {},
        common_keybind_table = {},
    },
}

local core = Core:New()
core.all_models = all_models
core.translation_table_list = {
    {
        hud_interaction_seat_seat_front_left = "Front Left",
        hud_interaction_seat_seat_front_right = "Front Right",
        hud_interaction_seat_seat_back_left = "Back Left",
        hud_input_hint_av_vertical_movement = "Vertical",
        hud_input_hint_av_horizontal_movement = "Horizontal",
        hud_input_hint_av_forward_backward = "Fwd/Back",
        hud_input_hint_helicopter_vertical_movement = "Heli Vertical",
    },
}
DAV.core_obj = core

local av = AV:New(core)
av:Init()
av.entity_id = { hash = 1 }
av.is_available_thruster = true
av.is_landed = true
av.spawn_time = -100
core.av_obj = av
av.engine_obj:Init({ hash = 1 })

-- Register the hooks by hand (Init guards on DAV.is_ready).
local event = Event:New()
event.av_obj = av
event.ui_obj = {
    Init = function() end,
    -- What UI:Init() would have built; SpawnActivePlayerVehicle matches on it.
    av_record_list = { { value = "Vehicle.av_test_dav", hash = "Vehicle.av_test_dav" } },
}
event.hud_obj = HUD:New()
event.hud_obj:Init(av)
event.sound_obj = setmetatable({}, fake_module_mt)
event:SetObserve()
event:SetOverride()
core.event_obj = event
core:SetInputListener()
core:SetSummonTrigger()
core:SetMappinController()
DAV.is_ready = true

event.hud_obj.interaction_ui_base = {
    OnDialogsSelectIndex = function(u, i) count("ui_base.OnDialogsSelectIndex") end,
    OnDialogsData = function(u, d) count("ui_base.OnDialogsData") end,
    OnInteractionsChanged = function(u) count("ui_base.OnInteractionsChanged") end,
    UpdateListBlackboard = function(u) count("ui_base.UpdateListBlackboard") end,
    OnDialogsActivateHub = function(u, id) count("ui_base.OnDialogsActivateHub") end,
}

local mph_widget = { SetText = function(w, t) count("widget.mph.SetText") end }
local function widget_node(children)
    return { GetWidget = function(self, name) count("widget.GetWidget"); return children[name] end }
end
event.hud_obj.hud_car_controller = {
    SpeedValue = {},
    RPMValue = {},
    GetRootCompoundWidget = function(self)
        count("widget.GetRootCompoundWidget")
        return widget_node({
            maindashcontainer = widget_node({
                dynamic = widget_node({ mph_text = mph_widget }),
            }),
        })
    end,
    ShowRequest = function() count("widget.ShowRequest") end,
    OnCameraModeChanged = function(s, m) count("widget.OnCameraModeChanged") end,
    EvaluateRPMMeterWidget = function(self, v) count("widget.EvaluateRPMMeterWidget") end,
}
event.hud_obj.hud_consumable_controller = {
    GetRootCompoundWidget = function(self)
        count("widget.GetRootCompoundWidget")
        return { visible = false, SetVisible = function(w, v) count("widget.SetVisible") end }
    end,
}

-- ------------------------------------------------------- virtual clock ------
local virtual_time = 0
os.clock = function() return virtual_time end
local function advance(dt) virtual_time = virtual_time + dt end

-- ------------------------------------------------------- assertions ---------
local pass, fail = 0, 0
local function check(ok, msg, detail)
    if ok then
        pass = pass + 1
        print("  [PASS] " .. msg)
    else
        fail = fail + 1
        print("  [FAIL] " .. msg .. (detail and ("   <-- " .. tostring(detail)) or ""))
    end
end
local function report(fmt, ...) print("    " .. string.format(fmt, ...)) end

-- ======================================================================
print("== 1. harness sanity ==")
-- ======================================================================
check(event ~= nil and av ~= nil and core ~= nil, "real modules loaded")
check(#hook_keys() > 10, "hooks were captured instead of dropped", #hook_keys())
report("captured %d hooks", #hook_keys())

-- ======================================================================
print("== 2. the full list of global hooks this mod installs ==")
-- ======================================================================
-- Anything registered against a shared game class fires for every instance in
-- the world, AV or not.  Pinning the list here means a newly added global hook
-- cannot slip in unnoticed.
-- Note: init.lua registers one more global hook, `Observe:SettingsSelector
-- ControllerKeyBinding.ListenForInput` (it remembers the keybind widget that is
-- listening for a pad input).  init.lua is the CET entry point and is not
-- loaded by this harness; it is audited by hand in
-- docs/AUDIT_non_av_vehicles.md.
local EXPECTED_GLOBAL_HOOKS = {
    "Override:InteractionUIBase.OnDialogsData",
    "Override:InteractionUIBase.OnDialogsSelectIndex",
    "Override:PlayerPuppet.ActivateIconicCyberware",
    "Override:VehicleComponentPS.GetHasAnyDoorOpen",
    "Override:VehicleSystem.SpawnActivePlayerVehicle",
    "Override:VehicleTransition.IsUnmountDirectionClosest",
    "Override:VehicleTransition.IsUnmountDirectionOpposite",
    "Override:hudCarController.OnRpmValueChanged",
    "Override:hudCarController.OnSpeedValueChanged",
    "Override:dialogWidgetGameController.OnDialogsActivateHub",
    "ObserveAfter:BaseMappinBaseController.IsTracked",
    "ObserveAfter:BaseMappinBaseController.UpdateRootState",
    "ObserveAfter:Entity.ScheduleAppearanceChange",
    "ObserveAfter:UISystem.QueueEvent",
    "ObserveAfter:gameuiPhotoModeMenuController.OnPhotoModeLastInputDeviceEvent",
    "Observe:HotkeyConsumableWidgetController.OnInitialize",
    "Observe:InteractionUIBase.OnDialogsData",
    "Observe:InteractionUIBase.OnInitialize",
    "Observe:PhoneHotkeyController.Initialize",
    "Observe:PlayerPuppet.OnAction",
    "Observe:PopupsManager.OnPlayerAttach",
    "Observe:UISystem.QueueEvent",
    "Observe:VehicleComponent.ReactToHPChange",
    "Observe:hudCarController.OnInitialize",
    "Observe:hudCarController.OnMountingEvent",
}
local seen = {}
for _, k in ipairs(hook_keys()) do seen[k] = true end
local missing, extra = {}, {}
for _, k in ipairs(EXPECTED_GLOBAL_HOOKS) do
    if not seen[k] then missing[#missing + 1] = k end
end
for _, k in ipairs(hook_keys()) do
    local known = false
    for _, e in ipairs(EXPECTED_GLOBAL_HOOKS) do if e == k then known = true end end
    if not known then extra[#extra + 1] = k end
end
check(#missing == 0, "every expected global hook is installed",
      table.concat(missing, ", "))
if #extra > 0 then
    report("NEW global hooks beyond the audited list: %s", table.concat(extra, ", "))
end
check(#extra == 0, "no unaudited global hooks were added", table.concat(extra, ", "))

-- ======================================================================
print("== 3. a NON-AV vehicle drives every vehicle-facing hook unchanged ==")
-- ======================================================================
-- World state: the AV is not the vehicle under test.  Each hook must give the
-- answer the game would have given with the mod uninstalled.
local function reset_to_non_av()
    world.mounted = false
    world.destroyed = false
    world.door_state = VehicleDoorState.Closed
    world.entity_alive = true
    av.entity_id = nil
    av:InvalidateEntityCache()
    event.current_situation = Def.Situation.Normal
    event.hud_obj.is_manually_setting_speed = false
    event.hud_obj.is_manually_setting_rpm = false
    clear_timers()
    reset_count()
end

-- 3a. a door query on somebody else's car
reset_to_non_av()
local wrapped_calls = 0
local door_hook = hooks["Override:VehicleComponentPS.GetHasAnyDoorOpen"]
local answer = door_hook({ GetEntityID = function() return { hash = 99 } end }, function()
    wrapped_calls = wrapped_calls + 1
    return "game_says_open"
end)
check(answer == "game_says_open", "GetHasAnyDoorOpen: the game's own answer comes back")
check(wrapped_calls == 1, "GetHasAnyDoorOpen: wrapped method runs exactly once")
report("no AV at all: %d transitions (IsPlayerMounted=%d, FindEntityByID=%d)",
       T.total, n("entity.IsPlayerMounted"), n("Game.FindEntityByID"))
check(n("entity.IsPlayerMounted") == 0 and n("Game.FindEntityByID") == 0,
      "GetHasAnyDoorOpen: another car's door query never reaches into the AV",
      T.total)

-- 3b. same query while the AV exists but the player is not in it
reset_to_non_av()
av.entity_id = { hash = 1 }
wrapped_calls = 0
answer = door_hook({ GetEntityID = function() return { hash = 99 } end }, function()
    wrapped_calls = wrapped_calls + 1
    return "game_says_open"
end)
check(answer == "game_says_open" and wrapped_calls == 1,
      "GetHasAnyDoorOpen: a parked AV does not suppress another car's door state")
report("AV parked, player outside: %d transitions (IsPlayerMounted=%d)",
       T.total, n("entity.IsPlayerMounted"))
check(n("entity.IsPlayerMounted") == 0,
      "GetHasAnyDoorOpen: a parked AV is not probed for another car's doors",
      n("entity.IsPlayerMounted"))

-- 3c. the AV's own door IS suppressed while driving it
reset_to_non_av()
av.entity_id = { hash = 1 }
world.mounted = true
event.current_situation = Def.Situation.InVehicle
wrapped_calls = 0
answer = door_hook({ GetEntityID = function() return { hash = 1 } end }, function()
    wrapped_calls = wrapped_calls + 1
    return "game_says_open"
end)
check(answer == false and wrapped_calls == 0,
      "GetHasAnyDoorOpen: still suppressed for the AV while the player drives it")

-- 3d. unmount transitions of another vehicle must not touch the AV
reset_to_non_av()
local unmount_called = false
local real_unmount = AV.Unmount
AV.Unmount = function(self) unmount_called = true; return true end
local closest = hooks["Override:VehicleTransition.IsUnmountDirectionClosest"]
local opposite = hooks["Override:VehicleTransition.IsUnmountDirectionOpposite"]
local closest_ret = closest({}, "ctx", "dir", function(a, b) return "wrapped_closest" end)
local opposite_ret = opposite({}, "ctx", "dir", function(a, b) return "wrapped_opposite" end)
check(closest_ret == "wrapped_closest" and opposite_ret == "wrapped_opposite",
      "VehicleTransition: both hooks pass through for a non-AV unmount")
check(not unmount_called, "VehicleTransition: AV:Unmount() is NOT called for a non-AV unmount")
report("non-AV unmount: %d transitions (GetPlayer=%d)", T.total, n("Game.GetPlayer"))
check(T.total == 0, "VehicleTransition: a non-AV unmount costs nothing at all", T.total)
AV.Unmount = real_unmount

-- 3e. iconic cyberware while driving something else
reset_to_non_av()
local cyber_ran = 0
hooks["Override:PlayerPuppet.ActivateIconicCyberware"]({}, function() cyber_ran = cyber_ran + 1 end)
check(cyber_ran == 1, "ActivateIconicCyberware: not blocked outside the AV")

-- 3f. the game spawning a non-DAV active vehicle
reset_to_non_av()
local spawn_wrapped = 0
local spawn_hook = hooks["Override:VehicleSystem.SpawnActivePlayerVehicle"]
local ret = spawn_hook({
    GetActivePlayerVehicle = function(s, t)
        return { recordID = { value = "Vehicle.quartz_asterion", hash = 555 } }
    end,
}, 1, function(t) spawn_wrapped = spawn_wrapped + 1; return "spawned_by_game" end)
check(spawn_wrapped == 1, "SpawnActivePlayerVehicle: a non-DAV record falls through")
report("non-DAV active vehicle: %d transitions", T.total)

reset_to_non_av()
spawn_wrapped = 0
spawn_hook({ GetActivePlayerVehicle = function(s, t) return nil end }, 1,
          function(t) spawn_wrapped = spawn_wrapped + 1; return "spawned_by_game" end)
check(spawn_wrapped == 1, "SpawnActivePlayerVehicle: a nil active vehicle still falls through")

-- 3g. another vehicle's car HUD keeps its own speed / rpm paint
reset_to_non_av()
local speed_wrapped, rpm_wrapped = 0, 0
hooks["Override:hudCarController.OnSpeedValueChanged"](
    {}, 42, function(v) speed_wrapped = speed_wrapped + 1; return true end)
hooks["Override:hudCarController.OnRpmValueChanged"](
    {}, 3000, function(v) rpm_wrapped = rpm_wrapped + 1; return true end)
check(speed_wrapped == 1 and rpm_wrapped == 1,
      "hudCarController: speed/rpm reach the game handler outside the AV")

-- 3h. the same HUD hooks with the manual-meter flag left over from a destroyed
--     AV.  CheckDestroyed() never calls EnableManualMeter(false, ...), so this
--     combination is reachable in a real game; the situation check is what
--     keeps another car's speedometer from freezing.
reset_to_non_av()
event.hud_obj.is_manually_setting_speed = true
event.hud_obj.is_manually_setting_rpm = true
speed_wrapped, rpm_wrapped = 0, 0
hooks["Override:hudCarController.OnSpeedValueChanged"](
    {}, 42, function(v) speed_wrapped = speed_wrapped + 1; return true end)
hooks["Override:hudCarController.OnRpmValueChanged"](
    {}, 3000, function(v) rpm_wrapped = rpm_wrapped + 1; return true end)
check(speed_wrapped == 1 and rpm_wrapped == 1,
      "hudCarController: a stale manual-meter flag cannot freeze another car's HUD")

-- 3i. input actions while walking / driving something else
reset_to_non_av()
local consumed = 0
local on_action = hooks["Observe:PlayerPuppet.OnAction"]
on_action({}, {
    GetName = function(a, s) return { value = "Exit" } end,
    GetType = function(a, s) return { value = "BUTTON_PRESS" } end,
    GetValue = function(a, s) return 1 end,
}, { Consume = function() consumed = consumed + 1 end })
check(consumed == 0, "OnAction: nothing is consumed in the Normal situation")
report("OnAction in Normal: %d transitions", T.total)

-- ======================================================================
print("== 4. boarding: what the enter path spends ==")
-- ======================================================================
-- The player is standing at the door of a landed AV.  Every step below is a
-- step the real mod takes between pressing the key and being able to drive.
local function setup_boarding()
    world.mounted = false
    world.destroyed = false
    world.door_state = VehicleDoorState.Closed
    world.entity_alive = true
    world.player_x, world.player_y, world.player_z = 1, 0, 0
    av.entity_id = { hash = 1 }
    av:InvalidateEntityCache()
    av.is_landed = true
    av.seat_index = 1
    av.is_unmounting = false
    event.current_situation = Def.Situation.Waiting
    event.selected_seat_index = 1
    clear_timers()
    reset_count()
    reset_disk()
    TWEAK_WRITES = 0
    WIDGET_CREATIONS = 0
end

-- 4a. AV:Mount() -- the instant the player commits to boarding
setup_boarding()
av:Mount()
local mount_total = T.total
report("AV:Mount(): %d transitions | TweakDB writes=%d | TweakDBID allocs=%d | Vector3 allocs=%d",
       mount_total, TWEAK_WRITES, n("tweakdb.id.new"), n("Vector3.new"))
check(n("mount.Mount") == 1, "AV:Mount(): the game mount request is issued once")

-- 4b. mounting again with the same seat must not rewrite the camera
setup_boarding()
av:Mount()
report("AV:Mount() again, same seat: %d transitions | TweakDB writes=%d", T.total, TWEAK_WRITES)
check(TWEAK_WRITES == 0,
      "AV:Mount(): a repeat mount with an unchanged seat writes no camera flat",
      TWEAK_WRITES)

-- 4c. a different seat must still write
setup_boarding()
av.seat_index = 2
av:Mount()
check(TWEAK_WRITES > 0,
      "AV:Mount(): a different seat still writes the camera flats", TWEAK_WRITES)
report("different seat: %d TweakDB writes", TWEAK_WRITES)

-- 4d. the Waiting -> InVehicle transition tick
setup_boarding()
world.mounted = true
event:CheckInAV()
report("Waiting->InVehicle tick: %d transitions | save-lock=%d | original-physics=%d | timers=%d",
       T.total, n("SaveLocks.Add"), n("flyav.EnableOriginalPhysics"), #TIMER_LOG)
check(event.current_situation == Def.Situation.InVehicle, "situation is now InVehicle")

-- 4e. the +1.5 s group: ForceShowMeter + ShowLeftBottomHUD (HP widgets)
local outer_timer = last_timer()
check(outer_timer ~= nil and outer_timer.kind == "after",
      "the enter tick armed the delayed HUD group")
reset_count()
outer_timer.cb()
local hud_group = T.total
report("+1.5s group (meter + left-bottom HUD): %d transitions | widgets created=%d",
       hud_group, WIDGET_CREATIONS)

-- 4f. the +3.0 s group: ShowCustomHint
local inner_timer = last_timer()
reset_count()
local disk_before = disk_opens()
inner_timer.cb()
local hint_group = T.total
report("+3.0s group (ShowCustomHint, first time this session): %d transitions | disk opens=%d | localized=%d",
       hint_group, disk_opens() - disk_before, n("GetLocalizedText"))
-- The very first boarding of a session still has to read the config once.
-- What must not happen any more is one read per boarding / per device change.
check(disk_opens() - disk_before <= 1,
      "ShowCustomHint(): the hint config is read at most once per session",
      disk_opens() - disk_before)

-- 4g. boarding again later: the hint work must be cached, not re-read
reset_count()
reset_disk()
event.hud_obj:ShowCustomHint()
report("ShowCustomHint() second time: %d transitions | disk opens=%d | localized=%d",
       T.total, disk_opens(), n("GetLocalizedText"))
check(disk_opens() == 0, "ShowCustomHint(): repeat call reads no file", disk_opens())
check(n("GetLocalizedText") == 0,
      "ShowCustomHint(): repeat call re-localises nothing", n("GetLocalizedText"))

-- ======================================================================
print("== 5. alighting: what the exit path spends ==")
-- ======================================================================
local function setup_alighting()
    world.mounted = true
    world.destroyed = false
    world.door_state = VehicleDoorState.Closed
    av.entity_id = { hash = 1 }
    av:InvalidateEntityCache()
    av.is_unmounting = false
    event.current_situation = Def.Situation.InVehicle
    clear_timers()
    reset_count()
    reset_disk()
    TELEPORTS = 0
end

-- 5a. AV:Unmount() -- crystal dome, doors, delayed poll
setup_alighting()
AV.Unmount(av)
report("AV:Unmount(): %d transitions | door PS events=%d | timers=%d",
       T.total, n("vehicle_ps.QueuePSEvent"), #TIMER_LOG)
check(T.total > 0, "AV:Unmount() does the door work it is supposed to")

-- 5b. the delayed poll that actually teleports the player out
local unmount_timer = last_timer()
world.mounted = false          -- the player has left the seat
reset_count()
unmount_timer.cb()             -- the Cron.Every body
local first_poll = last_timer()
if first_poll and first_poll.kind == "every" then first_poll.cb(first_poll.data) end
report("unmount poll tick: %d transitions | teleports=%d", T.total, TELEPORTS)

-- 5c. the InVehicle -> Waiting transition tick
setup_alighting()
world.mounted = false          -- the seat is empty; the check notices
event:CheckInAV()
report("InVehicle->Waiting tick: %d transitions | save-lock remove=%d | original-physics=%d",
       T.total, n("SaveLocks.Remove"), n("flyav.EnableOriginalPhysics"))
check(event.current_situation == Def.Situation.Waiting, "situation is back to Waiting")

-- ======================================================================
print("== 6. the 2 s input-hint refresh that lands right after boarding ==")
-- ======================================================================
-- Event:CheckInput() calls SetInputHintController() + IsVisibleCustomInputHints()
-- every 2 s while driving, and ReconstructInputHint() when they disagree.
local hint_children = {}
local hints_widget = widget_node(hint_children)
local main_container = widget_node({ hints = hints_widget })
local hint_root = widget_node({ mainContainer = main_container })
local hint_controller = {
    GetRootCompoundWidget = function()
        count("widget.GetRootCompoundWidget")
        return hint_root
    end,
}

-- Cold resolve: the ink layer walk is what this costs when nothing is cached.
event.hud_obj.input_hint_controller = nil
reset_count()
local resolved = event.hud_obj:SetInputHintController()
report("SetInputHintController cold: %d transitions | ink layer walks=%d | controller walks=%d",
       T.total, n("ink.GetLayer"), n("ink.GetGameControllers"))
check(resolved == true and event.hud_obj.input_hint_controller ~= nil,
      "SetInputHintController() resolves the hint manager")

-- Warm resolve: same handle, so there is nothing to go and look for.
event.hud_obj.input_hint_controller = hint_controller
reset_count()
event.hud_obj:SetInputHintController()
report("SetInputHintController cached: %d transitions | controller walks=%d",
       T.total, n("ink.GetGameControllers"))
check(n("ink.GetGameControllers") == 0,
      "SetInputHintController(): no controller walk when the handle is cached",
      n("ink.GetGameControllers"))

reset_count()
reset_disk()
event.hud_obj:GetExpectedHintTexts()
local first_expected = T.total
report("GetExpectedHintTexts first call: %d transitions | disk opens=%d | localized=%d",
       first_expected, disk_opens(), n("GetLocalizedText"))

reset_count()
reset_disk()
local again = event.hud_obj:GetExpectedHintTexts()
report("GetExpectedHintTexts repeat: %d transitions | disk opens=%d | localized=%d",
       T.total, disk_opens(), n("GetLocalizedText"))
check(disk_opens() == 0, "GetExpectedHintTexts(): repeat call reads no file", disk_opens())
check(n("GetLocalizedText") == 0,
      "GetExpectedHintTexts(): repeat call re-localises nothing", n("GetLocalizedText"))
check(#again > 0, "the expected hint list is not empty", #again)
check(n("entity.IsPlayerMounted") == 0,
      "GetExpectedHintTexts(): never asks the C# side about the combat seat",
      n("entity.IsPlayerMounted"))

-- Both pipelines start from the same resolved handle so the numbers below are
-- comparable: the only difference is where the config comes from.
event.hud_obj.input_hint_controller = hint_controller
WIDGET_CREATIONS = 0
reset_count()
reset_disk()
event.hud_obj:ReconstructInputHint()
report("ReconstructInputHint: %d transitions | disk opens=%d | widgets created=%d",
       T.total, disk_opens(), WIDGET_CREATIONS)
check(WIDGET_CREATIONS > 0,
      "ReconstructInputHint() really reached the widget build (so the read below is real)",
      WIDGET_CREATIONS)
check(disk_opens() == 0,
      "ReconstructInputHint(): the override config comes from cache", disk_opens())

-- A new input device is a new state key: the work must be redone once.
event.hud_obj.is_keyboard_input = false
reset_count()
reset_disk()
local pad_texts = event.hud_obj:GetExpectedHintTexts()
report("after switching to gamepad: %d transitions | disk opens=%d | entries=%d",
       T.total, disk_opens(), #pad_texts)
check(T.total > 0, "a device change is not served from the old cache")

-- ======================================================================
print("== 7. the cached hint pipeline yields exactly what the old one did ==")
-- ======================================================================
-- The fix caches what SetCustomHint() used to recompute from disk every call.
-- This is the equivalence proof: the pre-fix body, transcribed verbatim, run
-- against the same fixture, must agree with GetPreparedCustomHints() on every
-- field, for every (flight mode, input device, seat) combination.
local HINT_FIELDS = { "source", "action", "holdIndicationType",
                      "sortingPriority", "localizedLabel" }

local function old_prepare(flight_mode, is_keyboard_input)
    local hint_table = fixture_deep_copy(FIXTURE_INPUT_HINT)
    for index = #hint_table, 1, -1 do
        local hint = hint_table[index]
        if hint.mode ~= flight_mode and hint.mode ~= -1 then
            table.remove(hint_table, index)
        else
            if is_keyboard_input then
                if hint.usage == "gamepad" then
                    table.remove(hint_table, index)
                end
            else
                if hint.usage == "keyboard" then
                    table.remove(hint_table, index)
                end
            end
            if not av:IsMountedCombatSeat() and hint.source == "DrawWeapon" then
                table.remove(hint_table, index)
            end
        end
    end
    local out = {}
    for _, hint in ipairs(hint_table) do
        local keys = string.gmatch(hint.localizedLabel, "LocKey#(%d+)")
        local localizedLabels = {}
        for key_token in keys do
            table.insert(localizedLabels, GetLocalizedText("LocKey#" .. key_token))
        end
        out[#out + 1] = {
            source = hint.source,
            action = hint.action,
            holdIndicationType = hint.holdIndicationType,
            sortingPriority = hint.sortingPriority,
            localizedLabel = table.concat(localizedLabels, "-"),
        }
    end
    return out
end

local combos = {
    { Def.FlightMode.AV,         true,  1 },
    { Def.FlightMode.AV,         true,  2 },
    { Def.FlightMode.AV,         false, 1 },
    { Def.FlightMode.AV,         false, 2 },
    { Def.FlightMode.Helicopter, true,  1 },
    { Def.FlightMode.Helicopter, false, 2 },
}
for _, c in ipairs(combos) do
    local mode, keyboard, seat = c[1], c[2], c[3]
    av.entity_id = { hash = 1 }
    world.mounted = true
    av.is_armed = true
    av.seat_index = seat
    av.engine_obj.flight_mode = mode
    event.hud_obj.is_keyboard_input = keyboard

    local got = event.hud_obj:GetPreparedCustomHints()
    local want = old_prepare(mode, keyboard)
    local same = (#got == #want)
    local why = ""
    if same then
        for i = 1, #want do
            for _, field in ipairs(HINT_FIELDS) do
                if got[i][field] ~= want[i][field] then
                    same = false
                    why = string.format("hint %d field %s: %s vs %s", i, field,
                                      tostring(got[i][field]), tostring(want[i][field]))
                end
            end
        end
    else
        why = string.format("%d hints vs %d", #got, #want)
    end
    check(same, string.format("identical hints: mode=%s keyboard=%s seat=%d",
                             tostring(mode), tostring(keyboard), seat), why)
end
report("%d state combinations compared field by field", #combos)

-- The cache must not let one state's answer leak into another.
av.engine_obj.flight_mode = Def.FlightMode.AV
event.hud_obj.is_keyboard_input = true
local av_keyboard = event.hud_obj:GetPreparedCustomHints()
av.engine_obj.flight_mode = Def.FlightMode.Helicopter
event.hud_obj.is_keyboard_input = true
local heli_keyboard = event.hud_obj:GetPreparedCustomHints()
check(av_keyboard ~= heli_keyboard,
      "different state keys do not share a cached table")
check(#av_keyboard > 0 and #heli_keyboard > 0,
      "both states produced a non-empty hint list")

-- ======================================================================
print("== 8. the one cross-vehicle side effect that is real ==")
-- ======================================================================
-- While the player is in the AV, or standing in its entry area, the mod
-- deletes the game's own "VehicleDriver" input hint.  The suppression is
-- keyed on the hint SOURCE, not on the vehicle entity -- so an ordinary car
-- parked next to the AV loses its "Enter" hint too.  That is intended for
-- the AV and an unavoidable consequence for its neighbours; it is pinned
-- here so it is a known quantity instead of a surprise.
local function make_hint_event(source_name, action_name)
    return {
        kind = "gameuiUpdateInputHintEvent",
        IsA = function(self, name) return self.kind == name end,
        data = { source = CName.new(source_name), action = CName.new(action_name or "Enter") },
        show = true,
    }
end

local ui_observer = hooks["Observe:UISystem.QueueEvent"]
local function make_ui_system()
    local sys = { queued = {} }
    function sys.QueueEvent(s, ev) s.queued[#s.queued + 1] = ev end
    return sys
end

local function drive(source_name)
    local sys = make_ui_system()
    ui_observer(sys, make_hint_event(source_name))
    return sys
end

-- Waiting, player standing in the AV entry area
world.mounted = false
world.player_x, world.player_y, world.player_z = 1, 0, 0
av.entity_id = { hash = 1 }
av:InvalidateEntityCache()
event.current_situation = Def.Situation.Waiting
local sys = drive("VehicleDriver")
check(#sys.queued == 1,
      "in the AV entry area: the VehicleDriver hint is deleted", #sys.queued)

-- Same position, but the hint belongs to a pedestrian interaction
sys = drive("FootDriver")
check(#sys.queued == 0,
      "a hint from another source is left alone", #sys.queued)

-- Waiting, player well away from the AV
world.player_x = 500
av:InvalidateEntityCache()
sys = drive("VehicleDriver")
check(#sys.queued == 0,
      "away from the AV: the VehicleDriver hint is NOT deleted", #sys.queued)

-- Normal situation (no AV in play)
event.current_situation = Def.Situation.Normal
sys = drive("VehicleDriver")
check(#sys.queued == 0,
      "Normal situation: the VehicleDriver hint is NOT deleted", #sys.queued)

-- The exception-action observer only fires inside the AV.
local after_observer = hooks["ObserveAfter:UISystem.QueueEvent"]
local EXCEPTION_ACTION = "UI_FakeDriverCombatControllerVisionActivation"

event.current_situation = Def.Situation.Normal
local ev = make_hint_event("VehicleDriver", EXCEPTION_ACTION)
after_observer(make_ui_system(), ev)
check(ev.show == true,
      "outside the AV: the exception-action observer does not hide anything")

event.current_situation = Def.Situation.InVehicle
world.mounted = true
ev = make_hint_event("VehicleDriver", EXCEPTION_ACTION)
local sys2 = make_ui_system()
after_observer(sys2, ev)
check(ev.show == false and #sys2.queued == 1,
      "inside the AV: the exception hint is hidden and re-queued")
report("cross-vehicle suppression is source-scoped: a car parked next to the AV")
report("loses its Enter hint while the player stands in the AV entry radius (%.1fm)",
       av.entry_area_radius)

-- TEST_SECTIONS_CONTINUE_HERE

print(string.format("\nenter_exit_cost_test: %d passed, %d failed", pass, fail))
return fail == 0
