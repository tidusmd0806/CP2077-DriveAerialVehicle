--[[
TimeScale -- the single source of truth for "how long is one control tick".

Why this exists
---------------
`DAV.time_resolution` is not a cost knob, it is the sampling period `dt` of the
flight control loop. Every `Cron.Every(DAV.time_resolution, ...)` state machine
(spawn, despawn, takeoff, landing, autopilot) makes its decisions once per tick,
so changing the resolution changes *when* the craft decides to stop, not just how
much CPU the decision costs.

Before this module the conversion from "seconds" to "ticks" was written by hand at
each call site, and inconsistently:

    av.lua:492   timer.tick > (self.down_timeout / DAV.time_resolution)  -- converted
    av.lua:542   timer.tick >= self.up_timeout        -- 350 raw ticks, == 3.5s only
                                                            because the timer is 0.01
    av.lua:824   timer.tick > 350                    -- same
    core.lua:830 timer.tick >= max_count (50000)     -- same

That mix of "seconds", "ticks" and "seconds that happen to look like ticks" is
the structural reason the mod breaks when the resolution moves. Everything now
goes through here.

What must scale, and what must not
--------------------------------
The control law is applied through `Engine:Update`, which pushes a *rate* target
every rendered frame:

    force  = direction_velocity * mass          -- direction_velocity is m/s^2
    torque = (cmd_omega - actual_omega) * gain  -- a rate error

so the tuning constants that feed it are already per-second and must NOT be
scaled by dt:

    acceleration / vertical_acceleration / left_right_acceleration   [m/s^2]
    horizontal_air_resistance_const / vertical_air_resistance_const  [1/s]
        (terminal velocity = a / c = 1.5 / 0.015 = 100 m/s ~= max_speed 220mph,
         which is what pins down the units)
    *_change_amount / *_restore_amount / rotate_roll_change_amount   [rate target]
    CalculateIdleMode damping / height_gain                          [P/D gains]
    FluctuationVelocity step_width_per_second                        [explicitly /s]

Scaling those would make the craft dt_scale times stronger for no reason.

Three things *are* per-tick and must scale:

  1. Tick counts and timeouts -- use TimeScale:Ticks(seconds), never a raw count.
  2. Per-tick accumulators whose result is an absolute value:
         Engine.rpm_count            += rpm_count_step
         AV.thruster_angle         += thruster_angle_step
         Engine.heli_lift_acceleration += ascend/descend_acceleration
     Their rate is `step / resolution`, so `step` must be multiplied by dt_scale.
  3. Reaction distance. A threshold sampled once per tick is only reachable if the
     craft travels less than the threshold per tick. Use TimeScale:Lead() to
     compare against where the craft *will be* next tick instead of where it is.

Modes
-----
`nominal`  (default) scale by the configured resolution. This matches the
           reference the constants were tuned at.

`measured` scale by the real elapsed time between control ticks. This is the
           honest integrator: it stays correct when Cron cannot keep up (Cron
           fires at most once per rendered frame, so a 0.01 request on a 30 fps
           machine is really 0.033). It also changes the feel for anyone running
           at a rate other than the tuning reference, so it is opt-in.
--]]

---@class TimeScale
TimeScale = {}
TimeScale.__index = TimeScale

-- The resolution every constant in this mod was tuned against. Never changed --
-- `dt_scale` is defined relative to it, so moving this would silently rescale
-- the whole flight model. It is not the default; see DEFAULT_HZ below.
TimeScale.BASE_RESOLUTION = 0.01

-- User-adjustable window: 120 Hz at the fast end (0.00833 s, finer than any
-- realistic frame time so it just costs CPU) down to 10 Hz at the coarse end
-- (0.1 s), which is as far as the landing lead compensation can be pushed and
-- still stop a fast descent above the ground clearance.
TimeScale.MIN_HZ = 10
TimeScale.MAX_HZ = 120
TimeScale.MIN_RESOLUTION = 1.0 / TimeScale.MAX_HZ
TimeScale.MAX_RESOLUTION = 1.0 / TimeScale.MIN_HZ

-- Shipped default. 20 Hz is the sweet spot the perf work was aiming at: a 5x
-- cut in control-loop rate against the 0.01 tuning reference, with the lead
-- compensation still holding the takeoff/landing stop points above the ground
-- clearance (verified in tests/timescale_landing_test.lua). Note this is NOT
-- BASE_RESOLUTION -- at the default the flight model runs at dt_scale 5.0.
TimeScale.DEFAULT_HZ = 20
TimeScale.DEFAULT_RESOLUTION = 1.0 / TimeScale.DEFAULT_HZ

-- Ceiling for the measured dt. A 1 s hitch must not integrate a 1 s step.
TimeScale.MAX_MEASURED_DT = 0.10

TimeScale.MODE_NOMINAL = "nominal"
TimeScale.MODE_MEASURED = "measured"

-- Singleton state. There is exactly one control loop, so this module is used as
-- a singleton: call the methods on the class table itself, `TimeScale:Set(...)`.
local resolution = TimeScale.DEFAULT_RESOLUTION
local mode = TimeScale.MODE_NOMINAL
local measured_dt = TimeScale.DEFAULT_RESOLUTION

--- Clamp a requested resolution into the supported range.
--- An unusable value (nil / NaN / non-number) recovers to the shipped default,
--- not to the tuning reference: a broken setting should land on what we ship.
---@param value number|nil
---@return number
function TimeScale:Clamp(value)
    if type(value) ~= "number" or value ~= value then -- NaN / nil / string
        return self.DEFAULT_RESOLUTION
    end
    if value < self.MIN_RESOLUTION then
        return self.MIN_RESOLUTION
    end
    if value > self.MAX_RESOLUTION then
        return self.MAX_RESOLUTION
    end
    return value
end

--- Convert a user-facing Hz value into a clamped resolution.
--- The setting is stored as a period so it stays hand-editable in JSON; the UI
--- works in Hz because that is what people reason about.
---@param hz number|nil
---@return number
function TimeScale:HzToResolution(hz)
    if type(hz) ~= "number" or hz ~= hz or hz <= 0 then
        return self.DEFAULT_RESOLUTION
    end
    if hz > self.MAX_HZ then
        hz = self.MAX_HZ
    elseif hz < self.MIN_HZ then
        hz = self.MIN_HZ
    end
    return self:Clamp(1.0 / hz)
end

--- The current setting expressed in Hz (rounded to whole hertz).
---@return number
function TimeScale:GetHz()
    return math.floor((1.0 / resolution) + 0.5)
end

---@param res number|nil
---@return number
function TimeScale:ResolutionToHz(res)
    if type(res) ~= "number" or res ~= res or res <= 0 then
        return 1.0 / self.BASE_RESOLUTION
    end
    return 1.0 / res
end

--- Publish a new resolution. Cheap enough to call on every settings change.
---@param value number|nil requested resolution
---@param new_mode string|nil MODE_NOMINAL (default) or MODE_MEASURED
---@return number applied resolution
function TimeScale:Set(value, new_mode)
    if new_mode ~= nil then
        mode = (new_mode == self.MODE_MEASURED) and self.MODE_MEASURED or self.MODE_NOMINAL
    end
    resolution = self:Clamp(value)
    measured_dt = resolution
    -- Keep the global in sync; hot paths read this field directly instead of
    -- calling through the module once per tick.
    if DAV ~= nil then
        DAV.time_resolution = resolution
        DAV.dt_scale = self:Scale()
    end
    return resolution
end

--- The dt every timer in the mod is scheduled with.
---@return number
function TimeScale:Get()
    return resolution
end

--- Multiplier for any quantity expressed "per base tick".
---@return number
function TimeScale:Scale()
    if mode == self.MODE_MEASURED then
        return measured_dt / self.BASE_RESOLUTION
    end
    return resolution / self.BASE_RESOLUTION
end

---@return string
function TimeScale:GetMode()
    return mode
end

--- Record the real elapsed time between two control ticks (measured mode only).
---@param dt number
function TimeScale:SetMeasuredDt(dt)
    if type(dt) ~= "number" or dt ~= dt or dt <= 0 then
        return
    end
    if dt > self.MAX_MEASURED_DT then
        dt = self.MAX_MEASURED_DT
    end
    measured_dt = dt
    if DAV ~= nil then
        DAV.dt_scale = self:Scale()
    end
end

--- Convert a duration in seconds into a tick count for a `timer.tick >=` test.
--- Always at least 1 so a zero-length timeout cannot stall a state machine.
---@param seconds number
---@return integer
function TimeScale:Ticks(seconds)
    if type(seconds) ~= "number" or seconds ~= seconds then -- NaN / nil
        return 1
    end
    local ticks = math.ceil(seconds / resolution)
    if ticks < 1 then
        return 1
    end
    return ticks
end

--- Convert a tick count written at the base resolution into seconds.
---@param base_ticks number
---@return number
function TimeScale:BaseTicksToSeconds(base_ticks)
    return (base_ticks or 0) * self.BASE_RESOLUTION
end

--- Scale a per-base-tick increment (rpm step, thruster angle step, ...) so the
--- per-second rate is preserved at the current resolution.
---@param base_amount number value tuned at BASE_RESOLUTION
---@return number
function TimeScale:PerTick(base_amount)
    return (base_amount or 0) * self:Scale()
end

--- How far the craft travels during one control tick -- the distance a threshold
--- check cannot see because it is sampled too late.
---
--- `max_lead` is NOT optional in practice. The speed comes straight out of the
--- physics handle, and a single wild read (right after a spawn or a teleport the
--- vertical velocity can be enormous) would otherwise move the stop point by
--- tens of metres -- which is exactly how "the autopilot declares the landing
--- complete while still far above the ground" happens. Always pass the distance
--- you are protecting so the correction can never exceed it.
---@param closing_speed number speed, in m/s, at which the gap is closing (>= 0)
---@param max_lead number|nil hard ceiling on the returned distance, in metres
---@return number
function TimeScale:Lead(closing_speed, max_lead)
    if type(closing_speed) ~= "number" or closing_speed ~= closing_speed or closing_speed <= 0 then
        return 0
    end
    local lead = closing_speed * self:Scale() * self.BASE_RESOLUTION
    if type(max_lead) == "number" and max_lead == max_lead and lead > max_lead then
        return max_lead
    end
    return lead
end

--- Convert a per-base-tick low-pass blend coefficient into one that keeps the
--- same time constant at the live control period.
---
--- A blend written `x = x + (target - x) * alpha` once per tick is a
--- first-order filter whose discrete pole is `(1 - alpha)` and whose time
--- constant is `-dt / ln(1 - alpha)`. So `alpha` is only meaningful together
--- with `dt`: leaving it fixed while the period grows 5x makes the filter 5x
--- lazier in wall-clock terms.
---
--- That is exactly what happened to the autopilot's heading filter. At 20 Hz the
--- smoothed yaw target trails the raw target by ~0.8 s instead of ~0.16 s, so
--- the craft steers toward a heading it was asked for almost a second ago and
--- keeps overshooting -- the wobble on the approach to a target angle.
---
--- Re-map the pole instead: `alpha_eff = 1 - (1 - alpha) ** (dt / BASE)`.
--- At dt == BASE this returns `alpha` unchanged; at 5x the period it returns a
--- proportionally larger step that lands on the same 0.16 s time constant.
---@param alpha number per-base-tick blend coefficient in 0..1
---@return number
function TimeScale:SmoothAlpha(alpha)
    if type(alpha) ~= "number" or alpha ~= alpha then
        return 0
    end
    if alpha <= 0 then
        return 0
    end
    if alpha >= 1 then
        return 1
    end
    return 1 - (1 - alpha) ^ (resolution / self.BASE_RESOLUTION)
end

--- Human readable summary for logs and the debug overlay.
---@return string
function TimeScale:Describe()
    return string.format(
        "resolution=%.4fs (%.1fHz) mode=%s dt_scale=%.2f",
        resolution, 1.0 / resolution, mode, self:Scale())
end

return TimeScale
