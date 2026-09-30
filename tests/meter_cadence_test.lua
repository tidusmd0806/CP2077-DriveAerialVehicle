-- =============================================================================
-- Meter / cadence regression test
--
-- Covers the three heaviest items in Event:CheckAllEvents:
--
--   A. Event:CheckPerspective  -- the FPP meter lock used to flip every tick,
--      firing ForceShowMeter() at half the loop rate for a meter that was
--      already forced.
--   B. Event:CheckHeight       -- the ground probe ends in a synchronous
--      physics query and used to run at the full loop rate even when the craft
--      was parked and the answer could not change.
--   C. HUD meter writes        -- speed / RPM / HP were written to their widgets
--      every tick regardless of whether the displayed digits changed.
--
-- The invariant under test is the same one the situation-cost test uses:
--   "same visible state at every step, far fewer calls to get there".
-- A latch that suppresses a write the player would have seen is a bug, not an
-- optimisation, so every section asserts the visible value as well as the count.
--
-- Run:  python tests/run_meter_cadence_test.py
-- =============================================================================

local MODDIR = ...

-- ------------------------------------------------------------- counters -----
local CALLS = {}
local function count(key)
    CALLS[key] = (CALLS[key] or 0) + 1
end
local function reset_calls() CALLS = {} end
local function n(key) return CALLS[key] or 0 end

-- --------------------------------------------------------- controllable clock
-- Every throttle in the mod keys off os.clock(). A frozen/stepped clock is what
-- makes the cadence assertions exact instead of timing-dependent.
local CLOCK = { t = 1000.0 }
os.clock = function() return CLOCK.t end
-- 1/64 s is exact in binary, so 64 steps == 1.0000000000000000 s.
local DT = 1 / 64
local function advance(steps) CLOCK.t = CLOCK.t + DT * steps end

-- ----------------------------------------------------------- stub types -----
Vector4 = {}
Vector4.__index = Vector4
function Vector4.new(x, y, z, w)
    return setmetatable({ x = x, y = y, z = z, w = w or 1 }, Vector4)
end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.IsZero(v) return v.x == 0 and v.y == 0 and v.z == 0 end
function Vector4.Distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end
Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }
CName = { new = function(s) return { value = s, hash = tostring(s) } end }
ResRef = { FromName = function(s) return { name = s } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
spdlog = { info = function() end }
inkTextRef = { SetText = function(w, v) count("SetText"); w.text = v end }

-- ------------------------------------------------------- stub game API ------
local world = {
    player_x = 0, player_y = 0, player_z = 0,
    av_x = 0, av_y = 0, av_z = 0,
    unit = "UI-Settings-UnitMetric",
}

local player_stub = {
    GetWorldPosition = function(self)
        count("player.GetWorldPosition")
        return Vector4.new(world.player_x, world.player_y, world.player_z, 1)
    end,
}
Game = {
    GetPlayer = function() count("Game.GetPlayer"); return player_stub end,
}

-- ------------------------------------------------------- fake sub-modules ---
local fake_module_mt = {
    __index = function(self, key)
        return function(...) count("fake." .. tostring(key)) end
    end,
}
local function fake_module()
    return { New = function(cls) return setmetatable({}, fake_module_mt) end }
end

package.preload["External/GameUI.lua"] = function()
    return { Observe = function(name, cb) return { name = name, cb = cb } end }
end
package.preload["External/GameHUD.lua"] = function()
    return { Initialize = function() count("GameHUD.Initialize") end }
end
package.preload["External/GameSettings.lua"] = function()
    return { Get = function(k) count("GameSettings.Get"); return world.unit end }
end
package.preload["Modules/sound.lua"] = fake_module
package.preload["Modules/ui.lua"] = fake_module
package.preload["Modules/profprobe.lua"] = fake_module
-- AV and Engine are never instantiated here: every Event under test is handed a
-- hand-built stub as its av_obj, so the real classes only need to exist.
package.preload["Modules/av.lua"] = fake_module
package.preload["Modules/engine.lua"] = fake_module

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
preload("Modules/hud.lua")
preload("Modules/event.lua")

Log = require("Etc/log.lua")
Def = require("Etc/def.lua")
local HUD = require("Modules/hud.lua")
local Event = require("Modules/event.lua")

DAV = {
    frame_seq = 0,
    time_resolution = 0.01,
    is_ready = true,                       -- skip observer/override registration
    is_valid_vehicle_durability_display = false,
    user_setting_table = { is_enable_landing_vfx = true },
}

-- ------------------------------------------------------------- asserts ------
local pass, fail = 0, 0
local function ok(cond, label, detail)
    if cond then
        pass = pass + 1
        print("  PASS  " .. label)
    else
        fail = fail + 1
        print("  FAIL  " .. label .. (detail and ("   [" .. tostring(detail) .. "]") or ""))
    end
end
local function eq_int(got, want, label)
    ok(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function in_range(got, lo, hi, label)
    ok(got >= lo and got <= hi, label, tostring(got) .. " not in [" .. lo .. "," .. hi .. "]")
end

-- =============================================================================
-- A. CheckPerspective -- the meter lock must stay latched while FPP lasts
-- =============================================================================
print("== A. CheckPerspective latch ==")

local function make_event()
    local ev = Event:New()
    -- HUD replaced by a call recorder: the perspective path only ever asks the
    -- HUD for ForceShowMeter.
    local hud = setmetatable({}, {
        __index = function(t, k)
            return function(...) count("hud." .. tostring(k)) end
        end,
    })
    ev.hud_obj = hud
    return ev
end

local function make_av_stub(camera_mode)
    return {
        camera_obj = {
            current_camera_mode = camera_mode,
            GetCurrentCameraDistanceLevel = function(self)
                count("camera.GetCurrentCameraDistanceLevel")
                return self.current_camera_mode
            end,
        },
    }
end

reset_calls()
local evA = make_event()
evA.av_obj = make_av_stub(Def.CameraDistanceLevel.Fpp)
evA.is_locked_showing_meter = false
for _ = 1, 64 do evA:CheckPerspective() end
eq_int(n("hud.ForceShowMeter"), 1, "FPP held for 64 ticks -> ForceShowMeter fires once")
eq_int(evA.is_locked_showing_meter and 1 or 0, 1, "lock stays set while in FPP")

evA.av_obj.camera_obj.current_camera_mode = Def.CameraDistanceLevel.TppClose
evA:CheckPerspective()
eq_int(evA.is_locked_showing_meter and 1 or 0, 0, "leaving FPP releases the lock")
eq_int(n("hud.ForceShowMeter"), 1, "leaving FPP fires no extra ForceShowMeter")

evA.av_obj.camera_obj.current_camera_mode = Def.CameraDistanceLevel.Fpp
evA:CheckPerspective()
eq_int(n("hud.ForceShowMeter"), 2, "re-entering FPP forces once again")
for _ = 1, 64 do evA:CheckPerspective() end
eq_int(n("hud.ForceShowMeter"), 2, "second FPP hold adds no further calls")

-- The pre-fix shape, transcribed, to show what the latch is buying.
do
    reset_calls()
    local locked = false
    local function is_fpp() return true end
    local function old_check()
        if is_fpp() and not locked then
            count("hud.ForceShowMeter")
            locked = true
        else
            locked = false
        end
    end
    for _ = 1, 64 do old_check() end
    ok(n("hud.ForceShowMeter") > 1,
        "pre-fix shape really did thrash (sanity check on the bug)",
        n("hud.ForceShowMeter") .. " calls / 64 ticks")
end

-- =============================================================================
-- B. CheckHeight -- cadence of the synchronous ground probe
-- =============================================================================
print("== B. CheckHeight cadence ==")

-- height: what the ground probe reports. vz: vertical velocity.
-- distance: |player - AV| along x.
local function probe_setup(height, vz, distance)
    local av = {
        minimum_distance_to_ground = 1.2,
        projection_offset = { x = 0, y = 0, z = 0 },
        entity_id = { hash = 1 },
        GetPosition = function(self)
            count("av.GetPosition")
            return Vector4.new(world.av_x, world.av_y, world.av_z, 1)
        end,
        SetLandingVFXPosition = function(self, p) count("av.SetLandingVFXPosition") end,
        ProjectLandingWarning = function(self, on)
            count("av.ProjectLandingWarning")
            world.last_warning = on
        end,
        engine_obj = {
            GetVelocity = function(self)
                count("engine.GetVelocity")
                return Vector3.new(0, 0, vz)
            end,
        },
        navigation_obj = {
            GetHeight = function(self)
                count("ground_probe")
                return height
            end,
        },
    }
    world.player_x = distance
    world.av_x = 0
    local ev = make_event()
    ev:Init(av)
    return ev
end

-- 64 ticks == 1.0 s at DT = 1/64.
local function run_ticks(ev, ticks)
    for _ = 1, ticks do
        ev:CheckHeight()
        advance(1)
    end
end

-- B1. Nobody close enough to see the projection.
reset_calls()
run_ticks(probe_setup(1.2, 0.0, 100.0), 64)
in_range(n("ground_probe"), 2, 3, "far (100 m) -> ~2 probes/s")

-- B2. Parked next to the AV, craft not moving vertically.
reset_calls()
run_ticks(probe_setup(1.2, 0.0, 5.0), 64)
in_range(n("ground_probe"), 4, 6, "near + still -> ~4 probes/s")

-- B3. High up and descending: slow, but able to catch the threshold.
reset_calls()
run_ticks(probe_setup(50.0, -5.0, 5.0), 64)
in_range(n("ground_probe"), 9, 12, "near + moving + 50 m -> ~10 probes/s")

-- B4. Low and moving: unchanged, every tick.
reset_calls()
run_ticks(probe_setup(2.0, -5.0, 5.0), 64)
eq_int(n("ground_probe"), 64, "near + moving + low -> every tick (unchanged)")

-- B5. The first probe after Init is never delayed.
reset_calls()
local evB5 = probe_setup(2.0, 0.0, 5.0)
evB5:CheckHeight()
eq_int(n("ground_probe"), 1, "first probe after Init runs immediately")
eq_int(evB5.last_height or -1, 2, "last_height recorded for the next prediction")

-- B6. Visible state still transitions, at every threshold crossing.
reset_calls()
local evB6 = probe_setup(50.0, -5.0, 5.0)
world.last_warning = nil
evB6:CheckHeight()
eq_int(world.last_warning and 1 or 0, 0, "high -> warning off")
evB6.last_height = 50.0
evB6.next_height_check_time = 0
advance(1)
-- Now drop the reported height below the 4 + 1.2 = 5.2 m threshold.
evB6.av_obj.navigation_obj.GetHeight = function(self)
    count("ground_probe"); return 3.0
end
evB6:CheckHeight()
eq_int(world.last_warning and 1 or 0, 1, "crossing below threshold -> warning on")
evB6.next_height_check_time = 0
evB6.av_obj.navigation_obj.GetHeight = function(self)
    count("ground_probe"); return 50.0
end
evB6:CheckHeight()
eq_int(world.last_warning and 1 or 0, 0, "crossing back above threshold -> warning off")

-- B7. A missing player must not be read as "far away".
reset_calls()
local saved_player = Game.GetPlayer
Game.GetPlayer = function() count("Game.GetPlayer"); return nil end
local evB7 = probe_setup(2.0, -5.0, 5.0)
run_ticks(evB7, 64)
eq_int(n("ground_probe"), 64, "unknown player distance is not treated as far")
Game.GetPlayer = saved_player

-- B8. The VFX slot is only written when the measured height moved.
reset_calls()
local evB8 = probe_setup(1.2, 0.0, 5.0)
run_ticks(evB8, 64)
ok(n("av.SetLandingVFXPosition") <= 1,
    "parked AV writes the VFX offset at most once",
    n("av.SetLandingVFXPosition") .. " writes / 64 ticks")

-- =============================================================================
-- C. HUD meter writes -- edge triggered on the displayed value
-- =============================================================================
print("== C. HUD meter edge triggering ==")

local function make_hud()
    local hud = HUD:New()
    hud.hud_car_controller = {
        SpeedValue = { text = nil },
        EvaluateRPMMeterWidget = function(self, v)
            count("EvaluateRPMMeterWidget")
            world.last_rpm_written = v
        end,
    }
    hud.ink_hp_text = {
        SetText = function(w, t)
            count("ink_hp_text.SetText")
            w.text = t
        end,
    }
    hud.is_manually_setting_speed = true
    hud.is_manually_setting_rpm = true
    return hud
end

-- C1. Speed: unchanged displayed digits -> one write, then silence.
reset_calls()
local hud = make_hud()
hud:SetSpeedMeterValue(10.0)
hud:SetSpeedMeterValue(10.0)
hud:SetSpeedMeterValue(10.0005)   -- still 36 km/h after flooring
eq_int(n("SetText"), 1, "speed 10.0 / 10.0 / 10.0005 -> one widget write")
eq_int(hud.hud_car_controller.SpeedValue.text, 36, "the value written is the floored km/h")

-- C2. 100 identical calls -> still one write.
reset_calls()
hud = make_hud()
for _ = 1, 100 do hud:SetSpeedMeterValue(12.5) end
eq_int(n("SetText"), 1, "100 identical speed calls -> one write")
eq_int(n("GameSettings.Get"), 1, "unit lookup cached across all 100 calls")

-- C3. A real change still gets through.
reset_calls()
hud:SetSpeedMeterValue(13.5)      -- was 12.5 -> 45, now 48
eq_int(n("SetText"), 1, "a changed speed writes again")
eq_int(hud.hud_car_controller.SpeedValue.text, 48, "the new value reaches the widget")

-- C4. The unit cache refreshes, so a unit change is picked up.
reset_calls()
advance(128)                      -- 2.0 s, past speed_unit_refresh_interval
world.unit = "UI-Settings-UnitImperial"
hud:SetSpeedMeterValue(13.5)
eq_int(n("GameSettings.Get"), 1, "unit re-read once after the refresh interval")
eq_int(hud.hud_car_controller.SpeedValue.text, 30, "imperial factor applied (13.5 m/s -> 30 mph)")
world.unit = "UI-Settings-UnitMetric"

-- C5. Handing the meter back to the game clears the latch.
reset_calls()
hud = make_hud()
hud:SetSpeedMeterValue(20.0)
eq_int(n("SetText"), 1, "first manual write")
hud:EnableManualMeter(false, true)
hud:EnableManualMeter(true, true)
hud:SetSpeedMeterValue(20.0)
eq_int(n("SetText"), 2, "manual -> game -> manual re-arms the speed latch")

-- C6. Same for RPM.
reset_calls()
hud = make_hud()
hud:SetRPMMeterValue(7)
hud:SetRPMMeterValue(7)
eq_int(n("EvaluateRPMMeterWidget"), 1, "same RPM twice -> one write")
hud:SetRPMMeterValue(8)
eq_int(n("EvaluateRPMMeterWidget"), 2, "changed RPM writes")
eq_int(world.last_rpm_written, 8, "second write carries the new RPM")
hud:EnableManualMeter(true, false)
hud:EnableManualMeter(true, true)
hud:SetRPMMeterValue(8)
eq_int(n("EvaluateRPMMeterWidget"), 3, "game -> manual re-arms the RPM latch")

-- C7. HP.
reset_calls()
hud = make_hud()
hud.vehicle_hp = 100
hud:SetHPDisplay()
hud:SetHPDisplay()
hud:SetHPDisplay()
eq_int(n("ink_hp_text.SetText"), 1, "intact hull -> HP written once")
eq_int(hud.ink_hp_text.text, "100", "HP text is the unpadded 100")
hud.vehicle_hp = 87.4
hud:SetHPDisplay()
eq_int(n("ink_hp_text.SetText"), 2, "damage writes again")
eq_int(hud.ink_hp_text.text, " 87", "two-digit HP keeps its single-space pad")
hud.vehicle_hp = 9.2
hud:SetHPDisplay()
eq_int(hud.ink_hp_text.text, "  9", "single-digit HP keeps its two-space pad")

-- C8. ResetMeterCaches forces a re-write of everything.
reset_calls()
hud:ResetMeterCaches()
hud:SetSpeedMeterValue(13.5)
hud:SetRPMMeterValue(8)
hud:SetHPDisplay()
eq_int(n("SetText") + n("EvaluateRPMMeterWidget") + n("ink_hp_text.SetText"), 3,
    "after ResetMeterCaches every meter writes once more")

-- C9. Disabled meters never write.
reset_calls()
hud = make_hud()
hud.is_manually_setting_speed = false
hud.is_manually_setting_rpm = false
hud:SetSpeedMeterValue(99.0)
hud:SetRPMMeterValue(9)
eq_int(n("SetText") + n("EvaluateRPMMeterWidget"), 0,
    "meter handed to the game -> no writes at all")

-- C10. A dead widget handle must not latch, so it self-heals.
reset_calls()
hud = make_hud()
hud.ink_hp_text = nil
hud.vehicle_hp = 42
hud:SetHPDisplay()
eq_int(hud.last_hp_display_value, nil, "no latch when the widget is missing")
hud.ink_hp_text = { SetText = function(w, t) count("ink_hp_text.SetText"); w.text = t end }
hud:SetHPDisplay()
eq_int(n("ink_hp_text.SetText"), 1, "it writes as soon as the widget shows up")
eq_int(hud.ink_hp_text.text, " 42", "and with the right text")

-- =============================================================================
print(string.format("\n%d passed, %d failed", pass, fail))
return fail == 0
