-- Ground-probe (height) cache test (docs/PERF_ANALYSIS_init441.md fix (2)).
--
-- Navigation:GetHeight() drives a synchronous world raycast. Before the fix it
-- ran once per caller and resolved the vehicle position twice per call. These
-- checks put counters on SyncRaycastByQueryFilter and GetWorldPosition and
-- prove the probe now happens at most once per rendered frame.

local MODDIR = ...

-- ---------------------------------------------------------------- stubs ----
Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Vector3To4(v) return Vector4.new(v.x, v.y, v.z, 0) end
Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }
EulerAngles = { new = function(p, y, r) return { pitch = p, yaw = y, roll = r } end }
Quaternion = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }
CName = { new = function(s) return { value = s } end }
QueryFilter = {
    new = function() return { mask2 = 0 } end,
    AddGroup = function() return { mask2 = 1 } end,
}
DynamicEntitySpec = { new = function() return {} end }
SaveLocksManager = { RequestSaveLockAdd = function() end, RequestSaveLockRemove = function() end }
GameObjectEffectHelper = { StartEffectEvent = function() end, StopEffectEvent = function() end }
json = { decode = function() return {} end, encode = function() return "{}" end }
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end, After = function() end }

DAV = {
    frame_seq = 0,
    model_index = 1,
    model_type_index = 1,
    is_debug_mode = false,
    is_debug_enable_obstacle_scan = false,
    is_debug_profile_autopilot = false,
    user_setting_table = {
        is_enable_landing_vfx = false,
        is_enable_obstacle_recording = false,
        garage_info_list = {},
        astar_calculation_precision = 100,
    },
}

-- Counters under test.
local find_calls = 0     -- Game.FindEntityByID
local pos_calls = 0      -- entity:GetWorldPosition
local ray_calls = 0      -- SyncRaycastByQueryFilter
local last_ray_start = nil
local last_ray_target = nil

local live_pos = Vector4.new(10, 20, 50, 1)
local ground_z = 40
local ray_hits = true
local deleted = {}

local function make_entity()
    return {
        IsPlayerMounted = function() return false end,
        IsDestroyed = function() return false end,
        IsEngineTurnedOn = function() return true end,
        GetWorldPosition = function()
            pos_calls = pos_calls + 1
            return Vector4.new(live_pos.x, live_pos.y, live_pos.z, 1)
        end,
        GetWorldForward = function() return Vector4.new(1, 0, 0, 0) end,
        GetWorldRight = function() return Vector4.new(0, 1, 0, 0) end,
        GetWorldUp = function() return Vector4.new(0, 0, 1, 0) end,
        GetWorldOrientation = function()
            return { ToEulerAngles = function() return EulerAngles.new(0, 0, 0) end }
        end,
    }
end

local live_entity = make_entity()

Game = {
    FindEntityByID = function(id)
        find_calls = find_calls + 1
        return live_entity
    end,
    GetPlayer = function()
        return { GetWorldPosition = function() return Vector4.new(0, 0, 0, 1) end,
                 PSIsInDriverCombat = function() return false end }
    end,
    GetTimeSystem = function() return { GetGameTimeStamp = function() return 0 end } end,
    GetDynamicEntitySystem = function()
        return {
            CreateEntity = function(_, spec) return { hash = 99 } end,
            DeleteEntity = function(_, id) deleted[#deleted + 1] = id end,
        }
    end,
    GetSpatialQueriesSystem = function()
        return {
            -- Called with method syntax, so self is the first argument.
            SyncRaycastByQueryFilter = function(_, from, to, filter, a, b)
                ray_calls = ray_calls + 1
                last_ray_start = from
                last_ray_target = to
                if ray_hits then
                    return true, { position = Vector4.new(from.x, from.y, ground_z, 1) }
                end
                return false, nil
            end
        }
    end,
    GetVehicleSystem = function() return { GetPlayerUnlockedVehicles = function() return {} end } end,
    IsSavingLocked = function() return false, nil end,
}

local function preload(name)
    local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
    local b = f:read("*a"); f:close()
    package.preload[name] = (loadstring or load)(b, name)
end

preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Etc/timescale.lua")
TimeScale = require("Etc/timescale.lua")
preload("Etc/def.lua")
preload("Modules/profprobe.lua")
preload("Modules/obstacle_grid.lua")
preload("Modules/camera.lua")
preload("Modules/engine.lua")
preload("Modules/navigation.lua")
preload("Modules/av.lua")

Log = require("Etc/log.lua")
local AV = require("Modules/av.lua")
local Navigation = require("Modules/navigation.lua")

-- ------------------------------------------------------------- harness -----
local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1; print("  [PASS] " .. name)
    else fail = fail + 1; print("  [FAIL] " .. name .. (detail and ("  " .. detail) or "")) end
end

local function new_pair()
    local av = setmetatable({
        log_obj = Log:New(),
        -- Navigation:New reads session fields off core_obj (all `or`-defaulted).
        core_obj = {},
        entity_id = { hash = 7 },
        _entity = nil,
        _entity_frame = -1,
        search_ground_offset = 2,
        search_ground_distance = 100,
        collision_filters = { "Static" },
        collision_query_filter = nil,
        minimum_distance_to_ground = 1.2,
    }, AV)
    av.navigation_obj = Navigation:New(av)
    return av
end

local function reset(frame)
    find_calls, pos_calls, ray_calls = 0, 0, 0
    DAV.frame_seq = frame
end

print("== 1. one ground probe per frame ==")
local av = new_pair()
live_pos = Vector4.new(10, 20, 50, 1)
ground_z = 40
ray_hits = true
reset(100)
local h = av.navigation_obj:GetHeight()
check("height computed", h == 10, "got " .. tostring(h))
check("exactly one raycast", ray_calls == 1, "got " .. ray_calls)
for _ = 1, 10 do av.navigation_obj:GetHeight() end
check("11 calls, still one raycast", ray_calls == 1, "got " .. ray_calls)

print("== 2. new frame re-probes ==")
DAV.frame_seq = 101
av.navigation_obj:GetHeight()
check("second frame probes again", ray_calls == 2, "got " .. ray_calls)
DAV.frame_seq = 102
av.navigation_obj:GetHeight(); av.navigation_obj:GetHeight()
check("third frame probes once", ray_calls == 3, "got " .. ray_calls)

print("== 3. cached value tracks the world, not the cache ==")
DAV.frame_seq = 110
ground_z = 45
check("fresh frame sees new ground", av.navigation_obj:GetHeight() == 5,
      "got " .. tostring(av.navigation_obj:GetHeight()))
ground_z = 20
check("same frame keeps the cached value", av.navigation_obj:GetHeight() == 5,
      "got " .. tostring(av.navigation_obj:GetHeight()))
DAV.frame_seq = 111
check("next frame sees the new ground", av.navigation_obj:GetHeight() == 30,
      "got " .. tostring(av.navigation_obj:GetHeight()))
ground_z = 40

print("== 4. position resolved once per probe (was twice) ==")
reset(200)
av.navigation_obj:GetHeight()
check("one GetWorldPosition per GetHeight", pos_calls == 1, "got " .. pos_calls)
check("one FindEntityByID per GetHeight", find_calls == 1, "got " .. find_calls)

print("== 5. raycast geometry is unchanged ==")
reset(210)
av.navigation_obj:GetHeight()
-- start = pos.z + search_ground_offset, target = start - search_ground_distance
check("ray starts at pos.z + offset", last_ray_start.z == 52, "got " .. tostring(last_ray_start.z))
check("ray ends at start - distance", last_ray_target.z == -48, "got " .. tostring(last_ray_target.z))
check("ray keeps x/y", last_ray_start.x == 10 and last_ray_start.y == 20)

print("== 6. GetGroundPosition does not mutate the caller's vector ==")
local probe = Vector4.new(1, 2, 300, 1)
local before_z = probe.z
av:GetGroundPosition(probe)
check("caller's z untouched", probe.z == before_z,
      "got " .. tostring(probe.z) .. " expected " .. tostring(before_z))
check("caller's x untouched", probe.x == 1)
check("caller's y untouched", probe.y == 2)

print("== 7. GetGroundPosition defaults to the vehicle position ==")
reset(220)
local g = av:GetGroundPosition()
check("returns the ground z", g == ground_z, "got " .. tostring(g))
check("resolved the position itself", pos_calls == 1, "got " .. pos_calls)

print("== 8. raycast miss falls back as before ==")
reset(230)
ray_hits = false
av.navigation_obj:InvalidateHeightCache()
-- start_z = 50 + 2 = 52 ; fallback = start_z - distance - 1 = 52 - 100 - 1 = -49
local g2 = av:GetGroundPosition()
check("fallback = start_z - distance - 1", g2 == -49, "got " .. tostring(g2))
local h2 = av.navigation_obj:GetHeight()
check("height with no ground hit", h2 == 50 - (-49), "got " .. tostring(h2))
ray_hits = true

print("== 9. InvalidateHeightCache forces a re-probe ==")
reset(240)
av.navigation_obj:GetHeight()
check("first probe", ray_calls == 1, "got " .. ray_calls)
av.navigation_obj:GetHeight()
check("still cached", ray_calls == 1, "got " .. ray_calls)
av.navigation_obj:InvalidateHeightCache()
av.navigation_obj:GetHeight()
check("invalidate forces a probe", ray_calls == 2, "got " .. ray_calls)
av.navigation_obj:GetHeight()
check("then caches again", ray_calls == 2, "got " .. ray_calls)

print("== 10. Despawn / Spawn drop the height cache ==")
local av2 = new_pair()
reset(250)
av2.navigation_obj:GetHeight()
check("cached before despawn", av2.navigation_obj._height ~= nil)
av2:Despawn()
check("height cache cleared by Despawn",
      av2.navigation_obj._height == nil and av2.navigation_obj._height_frame == nil)

local av3 = new_pair()
av3.navigation_obj._height = 999
av3.navigation_obj._height_frame = DAV.frame_seq
av3.entity_id = nil
av3:Spawn(Vector4.new(0, 0, 80, 1), EulerAngles.new(0, 0, 0))
check("height cache cleared by Spawn",
      av3.navigation_obj._height == nil and av3.navigation_obj._height_frame == nil)
reset(260)
live_pos = Vector4.new(0, 0, 80, 1)
check("post-spawn height is fresh", av3.navigation_obj:GetHeight() == 40,
      "got " .. tostring(av3.navigation_obj:GetHeight()))

print("== 11. no frame_seq bypasses the cache (never serves stale) ==")
local av4 = new_pair()
DAV.frame_seq = nil
find_calls, pos_calls, ray_calls = 0, 0, 0
av4.navigation_obj:GetHeight()
av4.navigation_obj:GetHeight()
av4.navigation_obj:GetHeight()
check("every call probes when frame_seq is absent", ray_calls == 3, "got " .. ray_calls)
DAV.frame_seq = 300

print("== 12. two callers in one frame share one probe ==")
-- In the real 100Hz tick GetHeight is reached from Event:CheckHeight and from
-- Engine:CalculateIdleMode. Both in one frame must cost a single raycast.
local av5 = new_pair()
live_pos = Vector4.new(10, 20, 50, 1)
ground_z = 40
reset(400)
local h_a = av5.navigation_obj:GetHeight()   -- Event:CheckHeight
local h_b = av5.navigation_obj:GetHeight()   -- Engine:CalculateIdleMode
check("two callers, one raycast", ray_calls == 1, "got " .. ray_calls)
check("both see the same height", h_a == h_b and h_a == 10,
      "got " .. tostring(h_a) .. " / " .. tostring(h_b))

print("")
print(string.format("height_cache_test: %d passed, %d failed", pass, fail))
if fail > 0 then error("height_cache_test failed") end
