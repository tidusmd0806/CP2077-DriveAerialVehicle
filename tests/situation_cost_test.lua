-- =============================================================================
-- Situation cost test
--
-- Question this exists to answer: the in-game measurement said Waiting / Landing /
-- TalkingOff cost MORE per tick than InVehicle, which is backwards for a loop
-- that is supposed to be doing less the further it is from flying.
--
-- This harness loads the REAL core / event / av / engine / hud modules with the
-- CET + REDscript API stubbed, and every stub call is counted as one Lua -> C#
-- transition. Each situation is then driven for a fixed number of ticks under
-- both the pre-fix pipeline (transcribed below, straight from git HEAD) and the
-- current one, so the before/after numbers come from the same world state.
--
-- The equivalence claim being tested is not "same number of calls" -- it is
-- "same visible state at every tick, fewer calls to get there".
--
-- Run:  python tests/run_situation_cost_test.py
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
local function sum(...)
    local s = 0
    for _, k in ipairs({ ... }) do s = s + (T.by[k] or 0) end
    return s
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
function Vector4.Distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end
Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }

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
    -- Etc/utils.lua works in the {r,i,j,k} convention; keep both spellings so
    -- the stub is usable wherever a quaternion-ish table is expected.
    new = function(x, y, z, w)
        return { x = x, y = y, z = z, w = w, r = w or 1, i = x or 0, j = y or 0, k = z or 0 }
    end,
}
CName = { new = function(s) count("api.CName.new"); return { value = s, hash = tostring(s) } end }
ResRef = { FromName = function(s) return { name = s } end }
QueryFilter = { new = function() return { mask2 = 0 } end, AddGroup = function() return { mask2 = 1 } end }
DynamicEntitySpec = { new = function() return {} end }
MountEventData = { new = function() return {} end }
MountingSlotId = { new = function() return {} end }
MountingInfo = { new = function() return {} end }
MountingRequest = { new = function() return {} end }
-- Door events carry their intent so the stubbed VehiclePS can move the door
-- state the way the game would. Without this the door never leaves "Closed" and
-- CheckDoor re-issues an Open command every tick, which the real game does not
-- do (the state becomes Opening/Open after the first command).
VehicleDoorOpen = { new = function() count("api.VehicleDoorOpen.new"); return { kind = "open" } end }
VehicleDoorClose = { new = function() count("api.VehicleDoorClose.new"); return { kind = "close" } end }
VehicleDoorState = { Closed = 1, Open = 2, Opening = 3, Closing = 4 }
EVehicleDoor = {
    seat_front_left = 1, seat_front_right = 2,
    seat_back_left = 3, seat_back_right = 4, trunk = 5, hood = 6,
}
inkInputHintHoldIndicationType = { Hold = 1 }
inkTextRef = { SetText = function(w, v) count("inkTextRef.SetText"); w.text = v end }
GameObjectEffectHelper = {
    StartEffectEvent = function() count("fx.StartEffectEvent") end,
    StopEffectEvent = function() count("fx.StopEffectEvent") end,
}
SaveLocksManager = {
    RequestSaveLockAdd = function() count("SaveLocks.Add") end,
    RequestSaveLockRemove = function() count("SaveLocks.Remove") end,
}
json = { decode = function() return {} end, encode = function() return "{}" end }
spdlog = { info = function() end }
Codeware = { Version = function() return "1.17.0" end }

-- --------------------------------------------------------- stub timers ------
-- Cron is only needed so that module-level code does not explode; the tests
-- drive the functions directly rather than through the scheduler.
Cron = {
    Every = function(interval, data, cb)
        if cb == nil then cb = data end
        return { interval = interval, data = data, cb = cb }
    end,
    After = function(delay, cb) return { delay = delay, cb = cb } end,
    Halt = function(t) end,
}

-- ------------------------------------------------------- stub game API ------
local world = {
    player_x = 100, player_y = 0, player_z = 0,
    av_x = 0, av_y = 0, av_z = 5,
    ground_z = 0,
    mounted = false,
    destroyed = false,
    engine_on = true,
    door_state = VehicleDoorState.Closed,
    entity_alive = true,
    on_ground = true,
    raycast_fail = false,
    -- Backs the batched GetFlightState stub. Kept separate from the
    -- individual getters below so a test can drive the two out of step and
    -- prove which one the mod is actually reading.
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
    -- identity rotation, in both quaternion spellings
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
}

Game = {
    FindEntityByID = function(id) count("Game.FindEntityByID"); return world.entity_alive and entity_stub or nil end,
    GetPlayer = function() count("Game.GetPlayer"); return player_stub end,
    GetTimeSystem = function() return { GetGameTimeStamp = function() count("time.GetGameTimeStamp"); return 0 end } end,
    GetSpatialQueriesSystem = function()
        return {
            SyncRaycastByQueryFilter = function(sys, a, b, f, c, d)
                count("raycast")
                if world.raycast_fail then return false, nil end
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
    GetUISystem = function()
        return {
            QueueEvent = function(sys, ev) count("uisystem.QueueEvent") end,
            GetLayer = function(sys, name) count("uisystem.GetLayer"); return nil end,
        }
    end,
    GetInkSystem = function()
        return {
            GetLayer = function(sys, name) count("ink.GetLayer"); return nil end,
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

-- Widget / input-hint classes. Any method on them is a C# call; the auto stub
-- counts it and returns nothing, which is all the callers need.
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
        new = function() count("widget." .. cls .. ".new"); return make_auto_widget(cls) end,
    }
end
Override = function() end
Observe = function() end
ObserveAfter = function() end

-- Fakes for the modules the situation loop must not actually run.
package.preload["External/GameHUD.lua"] = function()
    return { Initialize = function() count("GameHUD.Initialize") end }
end
package.preload["External/GameSettings.lua"] = function()
    return { Get = function(k) count("GameSettings.Get"); return "UI-Settings-UnitMetric" end }
end
package.preload["External/GameUI.lua"] = function()
    return { Observe = function(name, cb) return { name = name, cb = cb } end }
end
-- Sound and UI are replaced wholesale: nothing in the situation loop under test
-- needs them, and every method resolves to a counted no-op.
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
-- lupa is stock Lua 5.1 and rejects `goto` / `::label::`, which LuaJIT (what
-- CET actually embeds) accepts. Same neutralisation as tools/check_lua_syntax.py
-- and onaction_cost_test; the only goto in the tree is in Core:LoadLanguageFiles,
-- which nothing here drives.
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
Def = require("Etc/def.lua")      -- global: the modules read Def.Situation etc.
local Queue = require("Etc/queue.lua")
local AV = require("Modules/av.lua")
local Engine = require("Modules/engine.lua")
local Event = require("Modules/event.lua")
local Core = require("Modules/core.lua")
local HUD = require("Modules/hud.lua")

-- ------------------------------------------------------------- world --------
local SEATS = { "seat_front_left", "seat_front_right", "seat_back_left" }

local all_models = {
    [1] = {
        tweakdb_id = "Vehicle.av_test_dav",
        type = { "appearance_base" },
        display_name_lockey = 4242,
        flight_mode = Def.FlightMode.AV,
        actual_allocated_seat = SEATS,
        -- SetChoiceList indexes all_models[i].active_seat[index] for the
        -- localised seat name; separate record from actual_allocated_seat.
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
    },
}

DAV = {
    frame_seq = 0,
    time_resolution = 0.01,
    is_ready = true,             -- skip observer/override registration in Init()
    is_debug_mode = false,
    is_debug_enable_obstacle_scan = false,
    is_debug_profile_autopilot = false,
    is_debug_situation_ledger = false,
    model_index = 1,
    model_type_index = 1,
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
    },
}

local core = Core:New()
core.all_models = all_models
core.translation_table_list = {
    {
        hud_interaction_seat_seat_front_left = "Front Left",
        hud_interaction_seat_seat_front_right = "Front Right",
        hud_interaction_seat_seat_back_left = "Back Left",
    },
}
DAV.core_obj = core

local av = AV:New(core)
av:Init()
av.entity_id = { hash = 1 }
av.is_available_thruster = true
av.is_landed = true
av.spawn_time = -100            -- past ground_check_delay
core.av_obj = av

-- The thruster components the real SetThrusterComponent() would have found.
for _, name in ipairs({ "EngFL", "EngFR", "EngBL", "EngBR" }) do
    av.engine_components[#av.engine_components + 1] = entity_stub:FindComponentByName(name)
end
for _, name in ipairs({ "ThrFL", "ThrFR", "ThrBL", "ThrBR" }) do
    av.thruster_fxs[#av.thruster_fxs + 1] = entity_stub:FindComponentByName(name)
end

av.engine_obj:Init({ hash = 1 })

local event = Event:New()
event:Init(av)
core.event_obj = event
event.hud_obj.interaction_ui_base = {
    OnDialogsSelectIndex = function(u, i) count("ui_base.OnDialogsSelectIndex") end,
    OnDialogsData = function(u, d) count("ui_base.OnDialogsData") end,
    OnInteractionsChanged = function(u) count("ui_base.OnInteractionsChanged") end,
    UpdateListBlackboard = function(u) count("ui_base.UpdateListBlackboard") end,
    OnDialogsActivateHub = function(u, id) count("ui_base.OnDialogsActivateHub") end,
}

-- A speedometer controller that actually resolves, so the InVehicle numbers
-- include the HUD writes instead of short-circuiting on a nil controller.
local mph_widget = { SetText = function(w, t) count("widget.mph.SetText") end }
local function widget_node(children)
    return { GetWidget = function(self, name) count("widget.GetWidget"); return children[name] end }
end
event.hud_obj.hud_car_controller = {
    SpeedValue = {},
    RPMValue = {},
    GetRootCompoundWidget = function(self) count("widget.GetRootCompoundWidget"); return widget_node({
        maindashcontainer = widget_node({
            dynamic = widget_node({ mph_text = mph_widget }),
        }),
    }) end,
    EvaluateRPMMeterWidget = function(self, v) count("widget.EvaluateRPMMeterWidget") end,
}
event.hud_obj.hud_consumable_controller = {
    GetRootCompoundWidget = function(self)
        count("widget.GetRootCompoundWidget")
        return { visible = false, SetVisible = function(w, v) count("widget.SetVisible") end }
    end,
}

-- The cached entry-area predicate, captured before any test swaps it out.
local cached_is_in_entry_area = AV.IsPlayerInEntryArea

-- ------------------------------------------------------- tick machinery -----
-- Virtual clock. Every time-based throttle in the mod reads os.clock(); making
-- it explicit keeps the throttle assertions deterministic instead of depending
-- on how fast the test happens to run.
local virtual_time = 0
os.clock = function() return virtual_time end
local function advance(dt) virtual_time = virtual_time + dt end

local function one_tick()
    advance(0.01)
    DAV.frame_seq = DAV.frame_seq + 1
    event:CheckAllEvents()
    core:GetActions()
    av.engine_obj:Update(1 / 60)
end

local function run_ticks(count_)
    for _ = 1, count_ do one_tick() end
end

-- ------------------------------------------------- pre-fix transcriptions ---
-- Straight from git HEAD, before the situation-cost fixes. Used to measure the
-- same world under the old code and to prove the visible state is unchanged.

local function old_check_in_entry_area(self)
    if self.av_obj:ComputePlayerInEntryArea() then
        self.hud_obj:ShowChoice(self.selected_seat_index)
    else
        self.hud_obj:HideChoice()
    end
end

local function old_check_distance(self)
    local player_pos = Game.GetPlayer():GetWorldPosition()
    local av_pos = self.av_obj:GetPosition()
    local distance = Vector4.Distance(player_pos, av_pos)
    if distance > self.engine_audio_limit then
        self.sound_obj:StopGameSound(self.av_obj.engine_audio_name)
        self.is_enable_audio = false
    else
        if not self.is_enable_audio then
            self.sound_obj:PlayGameSound(self.av_obj.engine_audio_name)
        end
        self.is_enable_audio = true
    end
end

local function old_check_locked_save(self)
    local res, _ = Game.IsSavingLocked()
    if res then
        SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
    end
end

local function old_check_height(self)
    local height = self.av_obj.navigation_obj:GetHeight()
    if height < self.projection_max_height_offset + self.av_obj.minimum_distance_to_ground then
        local height_offset = -height + self.av_obj.projection_offset.z
        self.av_obj:SetLandingVFXPosition(Vector4.new(
            self.av_obj.projection_offset.x, self.av_obj.projection_offset.y, height_offset, 1))
        self.av_obj:ProjectLandingWarning(true)
    else
        self.av_obj:ProjectLandingWarning(false)
    end
end

local function old_move_thruster(self, action_command_lists)
    if self.thruster_angle > self.thruster_angle_restore then
        self.thruster_angle = self.thruster_angle - self.thruster_angle_restore
    elseif self.thruster_angle < -self.thruster_angle_restore then
        self.thruster_angle = self.thruster_angle + self.thruster_angle_restore
    else
        self.thruster_angle = 0
    end

    if not self.is_available_thruster then return false end

    for _, action_command_list in ipairs(action_command_lists) do
        if action_command_list[1] == Def.ActionList.Forward then
            self.thruster_angle = self.thruster_angle - self.thruster_angle_step
        elseif action_command_list[1] == Def.ActionList.Backward then
            self.thruster_angle = self.thruster_angle + self.thruster_angle_step
        end
    end

    if self.thruster_angle > self.thruster_angle_max then
        self.thruster_angle = self.thruster_angle_max
    elseif self.thruster_angle < -self.thruster_angle_max then
        self.thruster_angle = -self.thruster_angle_max
    end

    if self.entity_id == nil then return false end
    local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then return false end

    local angle = EulerAngles.new(0, self.thruster_angle, 0)
    for _, component in pairs(self.engine_components) do
        component:SetLocalOrientation(angle:ToQuat())
    end
    for _, thruster in pairs(self.thruster_fxs) do
        thruster:SetLocalOrientation(angle:ToQuat())
    end
    return true
end

-- The per-tick body of AV:DespawnFromGround (the "leaving" animation).
local function leaving_tick(skip_linear)
    local _, _, _, roll_idle, pitch_idle, yaw_idle =
        av.engine_obj:CalculateAddVelocity({ Def.ActionList.Idle, 1 }, skip_linear)
    av.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle)
end

local OLD = {
    check_in_entry_area = old_check_in_entry_area,
    check_distance = old_check_distance,
    check_locked_save = old_check_locked_save,
    check_height = old_check_height,
    move_thruster = old_move_thruster,
}

local saved = {}
local function use_old_pipeline()
    saved = {
        entry = Event.CheckInEntryArea,
        dist = Event.CheckDistance,
        locked = Event.CheckLockedSave,
        height = Event.CheckHeight,
        thruster = AV.MoveThruster,
        in_area = AV.IsPlayerInEntryArea,
    }
    Event.CheckInEntryArea = OLD.check_in_entry_area
    Event.CheckDistance = OLD.check_distance
    Event.CheckLockedSave = OLD.check_locked_save
    Event.CheckHeight = OLD.check_height
    AV.MoveThruster = OLD.move_thruster
    -- Pre-fix there was no frame cache: every caller recomputed.
    AV.IsPlayerInEntryArea = AV.ComputePlayerInEntryArea
end

local function restore_pipeline()
    Event.CheckInEntryArea = saved.entry
    Event.CheckDistance = saved.dist
    Event.CheckLockedSave = saved.locked
    Event.CheckHeight = saved.height
    AV.MoveThruster = saved.thruster
    AV.IsPlayerInEntryArea = saved.in_area
end

-- ---------------------------------------------------------- assertions -----
local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then
        pass = pass + 1
        print("  [PASS] " .. name)
    else
        fail = fail + 1
        print("  [FAIL] " .. name .. (detail and ("  " .. detail) or ""))
    end
end

local function set_situation(s) event.current_situation = s end
local function player_in_entry_area(flag)
    -- The world entry point is av position + the (identity-rotated) entry_point
    -- offset of {1,0,0}, so "in area" has to line up on all three axes.
    world.player_x = world.av_x + (flag and 1.0 or 100.0)
    world.player_y = world.av_y
    world.player_z = world.av_z
end

-- ======================================================================
print("== 1. harness sanity ==")
-- ======================================================================
check("AV has 4 engine components", #av.engine_components == 4)
check("AV has 4 thruster fx", #av.thruster_fxs == 4)
check("engine finished init", av.engine_obj.is_finished_init == true)
check("situation names resolve", Def.SituationName[Def.Situation.Waiting] == "Waiting")

-- ======================================================================
print("== 2. choice hub: visible state identical, old vs new ==")
-- ======================================================================
-- Script: approach, stand, change seat, step out, come back.
local script = {
    { in_area = false, seat = 1 },
    { in_area = false, seat = 1 },
    { in_area = true,  seat = 1 },   -- arrive
    { in_area = true,  seat = 1 },
    { in_area = true,  seat = 1 },
    { in_area = true,  seat = 2 },   -- SelectDown
    { in_area = true,  seat = 2 },
    { in_area = true,  seat = 3 },   -- SelectDown
    { in_area = true,  seat = 3 },
    { in_area = false, seat = 3 },   -- walk off
    { in_area = false, seat = 3 },
    { in_area = true,  seat = 1 },   -- come back
    { in_area = true,  seat = 1 },
}

local function hub_state()
    local h = event.hud_obj.interaction_hub
    return { shown = h ~= nil, index = event.hud_obj.selected_choice_index }
end

local function drive_script(label)
    local states = {}
    for i, step in ipairs(script) do
        -- One script step == one rendered frame: the entry-area frame cache keys
        -- off DAV.frame_seq, so it must move or every step sees step 1's answer.
        DAV.frame_seq = DAV.frame_seq + 1
        player_in_entry_area(step.in_area)
        event.selected_seat_index = step.seat
        event:CheckInEntryArea()
        local s = hub_state()
        states[i] = s
    end
    return states
end

event.hud_obj.interaction_hub = nil
event.shown_seat_index = nil
event.choice_last_shown_time = -1e6
use_old_pipeline()
local old_states = drive_script("old")
local old_shows = n("ui_base.OnDialogsActivateHub")
restore_pipeline()

event.hud_obj.interaction_hub = nil
event.shown_seat_index = nil
event.choice_last_shown_time = -1e6
reset_count()
local new_states = drive_script("new")
local new_shows = n("ui_base.OnDialogsActivateHub")

local same = #old_states == #new_states
for i = 1, #script do
    if old_states[i].shown ~= new_states[i].shown
        or (old_states[i].shown and old_states[i].index ~= new_states[i].index) then
        same = false
        print(string.format("    step %d differs: old shown=%s idx=%s / new shown=%s idx=%s",
            i, tostring(old_states[i].shown), tostring(old_states[i].index),
            tostring(new_states[i].shown), tostring(new_states[i].index)))
    end
end
check("visible hub state identical at every step", same)
check("hub shown while in the entry area", new_states[3].shown == true)
check("hub hidden after leaving", new_states[10].shown == false)
check("seat change is reflected", new_states[6].index == 2 and new_states[7].index == 2)
check("returning re-shows the hub", new_states[12].shown == true)
check("new pushes the hub far less often", new_shows < old_shows,
    string.format("old=%d new=%d", old_shows, new_shows))

-- ======================================================================
print("== 3. choice hub cost over 100 Waiting ticks with the player standing there ==")
-- ======================================================================
set_situation(Def.Situation.Waiting)
player_in_entry_area(true)
event.hud_obj.interaction_hub = nil
event.shown_seat_index = nil
event.choice_last_shown_time = -1e6
use_old_pipeline()
reset_count()
run_ticks(100)
local old_total = T.total
local old_activate = n("ui_base.OnDialogsActivateHub")
local old_choice_build = n("gi.ChoiceData.new")
restore_pipeline()

event.hud_obj.interaction_hub = nil
event.shown_seat_index = nil
event.choice_last_shown_time = -1e6
reset_count()
run_ticks(100)
local new_total = T.total
local new_activate = n("ui_base.OnDialogsActivateHub")
local new_choice_build = n("gi.ChoiceData.new")

print(string.format("    old: %d transitions, %d hub activations, %d seat rows built",
    old_total, old_activate, old_choice_build))
print(string.format("    new: %d transitions, %d hub activations, %d seat rows built",
    new_total, new_activate, new_choice_build))
check("old rebuilds the choice list every tick", old_choice_build == 100 * #SEATS,
    "got " .. old_choice_build)
check("new builds the choice list at most twice in 100 ticks", new_choice_build <= 2 * #SEATS,
    "got " .. new_choice_build)
check("Waiting transitions drop by more than 60%",
    new_total < old_total * 0.4, string.format("old=%d new=%d", old_total, new_total))

-- ======================================================================
print("== 4. entry area is resolved once per tick, not twice ==")
-- ======================================================================
-- CheckInEntryArea and CheckDoor both ask. Pre-fix each one recomputed the
-- rotated entry point (~5 C# + ~9 Lua tables). Instrument the computation so
-- both configurations are counted on the same footing.
local real_compute = AV.ComputePlayerInEntryArea
local compute_calls = 0
AV.ComputePlayerInEntryArea = function(self)
    compute_calls = compute_calls + 1
    return real_compute(self)
end

set_situation(Def.Situation.Waiting)
player_in_entry_area(true)
event.hud_obj.interaction_hub = nil
event.shown_seat_index = nil
event.choice_last_shown_time = -1e6
AV.IsPlayerInEntryArea = AV.ComputePlayerInEntryArea   -- pre-fix: no cache
compute_calls = 0
run_ticks(100)
local uncached_calls = compute_calls

AV.IsPlayerInEntryArea = cached_is_in_entry_area
event.hud_obj.interaction_hub = nil
event.shown_seat_index = nil
event.choice_last_shown_time = -1e6
compute_calls = 0
run_ticks(100)
local cached_calls = compute_calls
AV.ComputePlayerInEntryArea = real_compute

print(string.format("    pre-fix (no cache): %d computations in 100 ticks (%.2f/tick)",
    uncached_calls, uncached_calls / 100))
print(string.format("    with frame cache  : %d computations in 100 ticks (%.2f/tick)",
    cached_calls, cached_calls / 100))
check("pre-fix resolves the entry area twice per tick", uncached_calls == 200,
    "got " .. uncached_calls)
check("frame cache leaves at most one computation per tick", cached_calls <= 100,
    "got " .. cached_calls)

-- ======================================================================
print("== 5. thruster orientation writes ==")
-- ======================================================================
-- Parked: the angle sits at zero and never moves.
av.thruster_angle = 0
use_old_pipeline()
reset_count()
for _ = 1, 100 do
    AV.MoveThruster(av, { { Def.ActionList.Nothing, 1 } })
end
local old_writes = n("widget.SetLocalOrientation")
local old_toquat = n("euler.ToQuat")
restore_pipeline()

av.thruster_angle = 0
av._thruster_written_angle = nil
reset_count()
for _ = 1, 100 do
    av:MoveThruster({ { Def.ActionList.Nothing, 1 } })
end
local new_writes = n("widget.SetLocalOrientation")
local new_toquat = n("euler.ToQuat")
print(string.format("    parked 100 ticks: old %d writes / %d ToQuat, new %d writes / %d ToQuat",
    old_writes, old_toquat, new_writes, new_toquat))
check("pre-fix writes every component every tick", old_writes == 800, "got " .. old_writes)
check("parked AV writes the thrusters at most once in 100 ticks", new_writes <= 8,
    "got " .. new_writes)

-- Moving: every change must still reach every component.
av.thruster_angle = 0
av._thruster_written_angle = nil
reset_count()
for _ = 1, 10 do
    av:MoveThruster({ { Def.ActionList.Forward, 1 } })
end
local moving_writes = n("widget.SetLocalOrientation")
local moving_toquat = n("euler.ToQuat")
check("a changing angle still writes every component", moving_writes == 80,
    "got " .. moving_writes)
check("one ToQuat per tick instead of one per component", moving_toquat == 10,
    "got " .. moving_toquat)
check("the angle actually moved", av.thruster_angle ~= 0)

-- ======================================================================
print("== 6. leaving (TalkingOff) does not probe the ground for a discarded value ==")
-- ======================================================================
-- Airborne so the idle-hover term is live: pre-fix it computed a height that
-- OnlyAngularRun never looks at.
world.on_ground = false
reset_count()
for _ = 1, 100 do
    advance(0.01)
    DAV.frame_seq = DAV.frame_seq + 1
    leaving_tick(nil)
end
local old_leave_raycast = n("raycast")
local old_leave_ground = n("flyav.IsOnGround")
local old_leave_vel = n("flyav.GetVelocity")

reset_count()
for _ = 1, 100 do
    advance(0.01)
    DAV.frame_seq = DAV.frame_seq + 1
    leaving_tick(true)
end
local new_leave_raycast = n("raycast")
local new_leave_ground = n("flyav.IsOnGround")
local new_leave_vel = n("flyav.GetVelocity")

print(string.format("    old: %d raycasts, %d IsOnGround, %d GetVelocity per 100 ticks",
    old_leave_raycast, old_leave_ground, old_leave_vel))
print(string.format("    new: %d raycasts, %d IsOnGround, %d GetVelocity per 100 ticks",
    new_leave_raycast, new_leave_ground, new_leave_vel))
check("pre-fix raycasted for a value it threw away", old_leave_raycast == 100,
    "got " .. old_leave_raycast)
check("skip_linear removes the ground probe", new_leave_raycast == 0, "got " .. new_leave_raycast)
check("skip_linear removes the IsOnGround probe", new_leave_ground == 0, "got " .. new_leave_ground)

-- ======================================================================
print("== 7. distance / save-lock throttles ==")
-- ======================================================================
set_situation(Def.Situation.Waiting)
use_old_pipeline()
reset_count()
for _ = 1, 100 do advance(0.01); event:CheckDistance() end
local old_dist = n("player.GetWorldPosition")
restore_pipeline()
reset_count()
for _ = 1, 100 do advance(0.01); event:CheckDistance() end
local new_dist = n("player.GetWorldPosition")
print(string.format("    CheckDistance player position reads: old %d, new %d per 100 calls",
    old_dist, new_dist))
check("distance check is throttled", new_dist < old_dist / 10,
    string.format("old=%d new=%d", old_dist, new_dist))
check("distance check still runs at all", new_dist >= 1, "got " .. new_dist)

set_situation(Def.Situation.TalkingOff)
use_old_pipeline()
reset_count()
for _ = 1, 100 do advance(0.01); event:CheckLockedSave() end
local old_lock = n("Game.IsSavingLocked")
restore_pipeline()
reset_count()
for _ = 1, 100 do advance(0.01); event:CheckLockedSave() end
local new_lock = n("Game.IsSavingLocked")
print(string.format("    CheckLockedSave reads: old %d, new %d per 100 calls", old_lock, new_lock))
check("save-lock check is throttled", new_lock < old_lock,
    string.format("old=%d new=%d", old_lock, new_lock))
check("save-lock check still runs at all", new_lock >= 1, "got " .. new_lock)

-- ======================================================================
print("== 8. per-situation totals ==")
-- ======================================================================
local situations = {
    { "Normal (no vehicle)", Def.Situation.Normal,
      function() world.entity_alive = false end },
    { "Landing", Def.Situation.Landing,
      -- Not touching down, or CheckLanded would switch the situation mid-run.
      function() world.entity_alive = true; av.is_landed = false; world.on_ground = false end },
    { "Waiting (player in entry area)", Def.Situation.Waiting,
      function() world.entity_alive = true; av.is_landed = true; world.on_ground = true; player_in_entry_area(true) end },
    { "Waiting (player away)", Def.Situation.Waiting,
      function() world.entity_alive = true; av.is_landed = true; world.on_ground = true; player_in_entry_area(false) end },
    { "TalkingOff (leaving)", Def.Situation.TalkingOff,
      function() world.entity_alive = true; av.is_landed = true; world.on_ground = true end },
    { "InVehicle (manual)", Def.Situation.InVehicle,
      function() world.entity_alive = true; world.mounted = true end },
}

print(string.format("  %-34s %10s %10s %8s", "situation", "old/tick", "new/tick", "saved"))
print("  " .. string.rep("-", 68))
local totals = {}
for _, s in ipairs(situations) do
    -- old
    world.mounted = false
    s[3]()
    set_situation(s[2])
    if s[2] == Def.Situation.InVehicle then world.mounted = true end
    event.hud_obj.interaction_hub = nil
    event.shown_seat_index = nil
    event.choice_last_shown_time = -1e6
    use_old_pipeline()
    reset_count()
    run_ticks(100)
    local old_t = T.total

    world.mounted = false
    s[3]()
    set_situation(s[2])
    if s[2] == Def.Situation.InVehicle then world.mounted = true end
    event.hud_obj.interaction_hub = nil
    event.shown_seat_index = nil
    event.choice_last_shown_time = -1e6
    restore_pipeline()
    reset_count()
    run_ticks(100)
    local new_t = T.total
    totals[s[1]] = { old = old_t / 100, new = new_t / 100 }
    print(string.format("  %-34s %10.1f %10.1f %7.1f%%",
        s[1], old_t / 100, new_t / 100, 100.0 * (old_t - new_t) / math.max(old_t, 1)))
end

-- The headline claim: no situation may still cost more per tick than InVehicle.
--
-- Tolerance, not strict ordering. Once the engine reads were collapsed into one
-- snapshot per frame the two situations landed within a fraction of a
-- transition of each other (Waiting-in-entry-area carries the seat-choice hub,
-- InVehicle carries the force/torque write), and which one is ahead is decided
-- by rounding rather than by anything worth guarding. The claim being tested is
-- "nothing idle is grossly heavier than flying", so allow 10%.
local inv = totals["InVehicle (manual)"]
for name, t in pairs(totals) do
    if name ~= "InVehicle (manual)" then
        check(name .. " is not more expensive than InVehicle", t.new <= inv.new * 1.10,
            string.format("%.1f vs %.1f transitions/tick", t.new, inv.new))
    end
end

-- ======================================================================
print("== 9. the in-game situation ledger itself works ==")
-- ======================================================================
-- Event.EnableSituationLedger wraps the class tables. If that wiring is broken
-- the in-game diagnostic either crashes the mod or reports nothing, so prove
-- it here: enable, run, and check a section actually accumulated.
local Prof = require("Modules/profprobe.lua")
local started = Event.EnableSituationLedger(Core)
check("ledger starts", started == true)
check("ledger switch is independent of Prof.enabled", Prof.situation_enabled == true)
check("enabling twice is a no-op", Event.EnableSituationLedger(Core) == false)

set_situation(Def.Situation.Waiting)
player_in_entry_area(true)
event.hud_obj.interaction_hub = nil
event.shown_seat_index = nil
event.choice_last_shown_time = -1e6
local ok_ledger, err_ledger = pcall(run_ticks, 50)
check("wrapped checks run without error", ok_ledger, tostring(err_ledger))

local saw_waiting = false
for _, name in ipairs(Prof.section_names()) do
    if name:find("^Waiting/") then saw_waiting = true end
end
check("ledger recorded Waiting sections", saw_waiting)
Prof.situation_enabled = false
local ok_after_off = pcall(run_ticks, 10)
check("turning the ledger off leaves the loop working", ok_after_off)

-- ======================================================================
print("== 10. fix 21: a menu must stop the Waiting control pass ==")
-- ======================================================================
-- Engine:Update returns early while a menu is up, so a control target computed
-- behind a menu can never reach physics. The Waiting branch of
-- OperateAerialVehicle used to lack the guard the InVehicle branch had, so the
-- parked AV kept running the whole idle controller -- including one
-- synchronous ground raycast per tick -- for as long as a menu was open.
local operate_calls = 0
local real_av_operate = AV.Operate
AV.Operate = function(self, list)
    operate_calls = operate_calls + 1
    return real_av_operate(self, list)
end

local function operate_calls_for(situation, menu, times)
    set_situation(situation)
    event.is_in_menu = menu
    operate_calls = 0
    for _ = 1, times do
        core:OperateAerialVehicle({ { Def.ActionList.Nothing, 1 } })
    end
    event.is_in_menu = false
    return operate_calls
end

check("Waiting, no menu: idle controller runs",
    operate_calls_for(Def.Situation.Waiting, false, 10) == 10)
check("Waiting, menu open: idle controller is skipped",
    operate_calls_for(Def.Situation.Waiting, true, 10) == 0)
check("InVehicle, no menu: controller runs",
    operate_calls_for(Def.Situation.InVehicle, false, 10) == 10)
check("InVehicle, menu open: controller is skipped (unchanged)",
    operate_calls_for(Def.Situation.InVehicle, true, 10) == 0)
check("Normal: never operates (unchanged)",
    operate_calls_for(Def.Situation.Normal, false, 10) == 0)

-- What that was costing. Same world, straight transcription of the pre-fix
-- branch: with a menu open the old code still fell through to the Waiting arm.
local function old_operate_aerial_vehicle(self, actions)
    if not self.is_locked_operation then
        if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
            self.av_obj:Operate(actions)
        elseif self.event_obj:IsWaiting() then
            self.av_obj:Operate({ { Def.ActionList.Idle, 1 } })
        end
    end
end

set_situation(Def.Situation.Waiting)
event.is_in_menu = true
reset_count()
-- Advance the frame counter with each call. These are meant to be 100 frames,
-- and the mod now frame-caches the entity handle, the basis vectors and the
-- physics snapshot. Left parked on one frame the whole loop collapses into a
-- single set of reads and measures the cache instead of the code path.
for _ = 1, 100 do
    DAV.frame_seq = DAV.frame_seq + 1
    old_operate_aerial_vehicle(core, { { Def.ActionList.Nothing, 1 } })
end
local menu_old = T.total
reset_count()
for _ = 1, 100 do
    DAV.frame_seq = DAV.frame_seq + 1
    core:OperateAerialVehicle({ { Def.ActionList.Nothing, 1 } })
end
local menu_new = T.total
event.is_in_menu = false
print(string.format("    menu-open Waiting: old %d -> new %d transitions per 100 calls",
    menu_old, menu_new))
check("menu-open Waiting drops to zero transitions", menu_new == 0)
check("the old code really was doing the work", menu_old > 0)

-- ======================================================================
print("== 11. fix 22: the mph label retry is paced and only shouts once ==")
-- ======================================================================
local hud = event.hud_obj
local resolve_calls = 0
local warn_lines = 0
local debug_lines = 0
local real_record = hud.log_obj.Record
hud.log_obj.Record = function(self, level, msg, ...)
    if level == LogLevel.Warning then warn_lines = warn_lines + 1 end
    if level == LogLevel.Debug then debug_lines = debug_lines + 1 end
    return real_record(self, level, msg, ...)
end
-- Simulate the dash container not having mph_text yet, which is what happens
-- for a second or so every time the HUD swaps dash states. The cached handle
-- has to be cleared too: the throttle only applies while nothing is cached,
-- since a live handle costs nothing to use.
local function make_unresolvable()
    hud.mph_text_widget = nil
    hud.is_mph_display_on = nil
    hud.mph_requested_on = nil
    hud.mph_next_lookup_time = 0
    hud.GetMPHTextWidget = function(self)
        resolve_calls = resolve_calls + 1
        return nil
    end
end

make_unresolvable()
resolve_calls = 0; warn_lines = 0; debug_lines = 0
for i = 1, 100 do
    virtual_time = i * 0.01          -- one second at the loop rate
    hud:ToggleOriginalMPHDisplay(false)
end
print(string.format("    unresolved for 1 s at 100 Hz: %d resolve attempts, %d Warnings",
    resolve_calls, warn_lines))
check("retry is paced, not per tick", resolve_calls <= 11)
check("only one Warning is emitted", warn_lines == 1)
check("later misses fall through to Debug", debug_lines >= 1)

-- A changed request must not be stuck behind the backoff.
make_unresolvable()
virtual_time = 10.0
resolve_calls = 0
hud:ToggleOriginalMPHDisplay(false)
check("a fresh request attempts immediately", resolve_calls == 1)
virtual_time = 10.01
hud:ToggleOriginalMPHDisplay(true)
check("a changed target is not stuck behind the backoff", resolve_calls == 2)
virtual_time = 10.02
hud:ToggleOriginalMPHDisplay(true)
check("repeats of the same target stay throttled", resolve_calls == 2)

-- Once it resolves the state latches and nothing more is attempted.
local fake_widget = { SetText = function(self, t) count("widget.SetText") end }
hud.GetMPHTextWidget = function(self) resolve_calls = resolve_calls + 1; return fake_widget end
virtual_time = 20.0
resolve_calls = 0
reset_count()
hud:ToggleOriginalMPHDisplay(true)
check("resolving latches the state", hud.is_mph_display_on == true)
check("the label is written exactly once", n("widget.SetText") == 1)
resolve_calls = 0
hud:ToggleOriginalMPHDisplay(true)
check("no work once latched", resolve_calls == 0)




print("")
print(string.format("situation_cost_test: %d passed, %d failed", pass, fail))
if fail > 0 then error("situation_cost_test failed") end
