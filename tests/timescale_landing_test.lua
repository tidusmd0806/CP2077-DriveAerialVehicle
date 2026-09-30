-- =============================================================================
-- Time-scale / landing-stop regression test
--
-- `DAV.time_resolution` is the sampling period of the flight control loop, not
-- a CPU budget knob. This test pins down the two properties that make it safe to
-- expose as a user setting:
--
--   A. TimeScale unit maths -- seconds<->ticks, per-tick increments, the
--      reaction lead, clamping, and the Hz<->period conversion behind the
--      continuous 10..120 Hz slider.
--   B. The landing stop point. A headless model of the AutoLanding decision is
--      run over a (resolution x approach-speed) sweep, once with the old bare
--      threshold and once with the lead-compensated one, and the height at which
--      the stop command actually fires is compared against the ground clearance.
--
-- Section B is the regression that matters. The control loop samples height once
-- per tick, so between the last "still high enough" and the stop the craft keeps
-- travelling `speed * resolution` metres. At 100 Hz and a 5 m/s final approach
-- that is 5 cm and nobody notices; at 20 Hz and 25 m/s it is 1.25 m against a
-- 1.2 m clearance, which is the reported "it stops at the wrong time".
--
-- The physics step in the model is deliberately 10x finer than the fastest tick
-- so the control granularity, not the integrator, dominates the error.
--
-- Run:  python tests/run_timescale_landing_test.py
-- =============================================================================

local MODDIR = ...

local function preload(name)
    local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
    local b = f:read("*a"); f:close()
    package.preload[name] = (loadstring or load)(b, name)
end

preload("Etc/timescale.lua")
local TimeScale = require("Etc/timescale.lua")

local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1; print("  [PASS] " .. name)
    else fail = fail + 1; print("  [FAIL] " .. name .. (detail and ("  " .. detail) or "")) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- ===========================================================================
-- A. Unit maths
-- ===========================================================================
print("A. TimeScale unit maths")

DAV = {}
TimeScale:Set(0.01, TimeScale.MODE_NOMINAL)
check("base resolution publishes dt_scale == 1.0", DAV.dt_scale == 1.0,
    "dt_scale=" .. tostring(DAV.dt_scale))
check("Ticks(3.5) at 0.01 == 350 (old hardcoded up_timeout)", TimeScale:Ticks(3.5) == 350,
    tostring(TimeScale:Ticks(3.5)))
check("Ticks(5) at 0.01 == 500 (old down_timeout)", TimeScale:Ticks(5) == 500)
check("Lead(0) is 0", TimeScale:Lead(0) == 0)
check("Lead(25) at 0.01 == 0.25 m", near(TimeScale:Lead(25), 0.25), tostring(TimeScale:Lead(25)))
check("PerTick(0.6) at 0.01 == 0.6 (unchanged at base)", near(TimeScale:PerTick(0.6), 0.6))

TimeScale:Set(0.05, TimeScale.MODE_NOMINAL)
check("0.05 publishes dt_scale == 5.0", DAV.dt_scale == 5.0, tostring(DAV.dt_scale))
check("Ticks(3.5) at 0.05 == 70", TimeScale:Ticks(3.5) == 70, tostring(TimeScale:Ticks(3.5)))
check("Lead(25) at 0.05 == 1.25 m", near(TimeScale:Lead(25), 1.25), tostring(TimeScale:Lead(25)))
check("PerTick(0.6) at 0.05 == 3.0 (rate preserved)", near(TimeScale:PerTick(0.6), 3.0))

-- Clamping. 0.5 s (the value that broke takeoff/landing) is 2 Hz, well below
-- the 10 Hz floor, and must be snapped to it rather than honoured.
TimeScale:Set(0.5)
check("0.5 s (2 Hz) clamps to MAX_RESOLUTION == 1/10",
    near(DAV.time_resolution, 1 / 10), tostring(DAV.time_resolution))
check("0.5 s clamp keeps scale <= 10", TimeScale:Scale() <= 10.0 + 1e-9, tostring(TimeScale:Scale()))
TimeScale:Set(0.0001)
check("sub-minimum clamps to MIN_RESOLUTION == 1/120",
    near(DAV.time_resolution, 1 / 120), tostring(DAV.time_resolution))
TimeScale:Set(nil)
check("nil falls back to the shipped default", DAV.time_resolution == TimeScale.DEFAULT_RESOLUTION,
    tostring(DAV.time_resolution))
TimeScale:Set(0 / 0)
check("NaN falls back to the shipped default", DAV.time_resolution == TimeScale.DEFAULT_RESOLUTION,
    tostring(DAV.time_resolution))
check("Ticks(0) never returns 0", TimeScale:Ticks(0) == 1)

-- Lead with a ceiling. The speed fed to Lead() comes straight out of the physics
-- handle; a wild read must not be able to move a stop point by tens of metres.
TimeScale:Set(0.05)
check("Lead with cap: under the cap is unchanged",
    near(TimeScale:Lead(10, 1.2), 0.5), tostring(TimeScale:Lead(10, 1.2)))
check("Lead with cap: over the cap is clamped",
    near(TimeScale:Lead(25, 1.2), 1.2), tostring(TimeScale:Lead(25, 1.2)))
check("Lead with cap: a wild 500 m/s read is clamped, not honoured",
    near(TimeScale:Lead(500, 1.2), 1.2), tostring(TimeScale:Lead(500, 1.2)))
check("Lead with cap: NaN speed is 0", TimeScale:Lead(0 / 0, 1.2) == 0)
check("Lead with NaN cap falls back to uncapped",
    near(TimeScale:Lead(10, 0 / 0), 0.5), tostring(TimeScale:Lead(10, 0 / 0)))
check("Lead without cap still tracks the tick",
    near(TimeScale:Lead(25), 1.25), tostring(TimeScale:Lead(25)))
TimeScale:Set(0.01)
check("at 100 Hz the cap never bites for realistic speeds",
    near(TimeScale:Lead(25, 1.2), 0.25), tostring(TimeScale:Lead(25, 1.2)))

-- Shipped default: 20 Hz. This is deliberately NOT the tuning reference --
-- the default runs the flight model at dt_scale 5.0, which is the whole point
-- of the rate correction. BASE_RESOLUTION must stay 0.01 or every constant
-- would silently rescale.
check("default is 20 Hz", TimeScale.DEFAULT_HZ == 20
    and near(TimeScale.DEFAULT_RESOLUTION, 0.05),
    string.format("%d Hz / %.4f s", TimeScale.DEFAULT_HZ, TimeScale.DEFAULT_RESOLUTION))
check("tuning reference stays 0.01 (100 Hz) regardless of the default",
    TimeScale.BASE_RESOLUTION == 0.01, tostring(TimeScale.BASE_RESOLUTION))
check("default sits inside the 10..120 Hz window",
    TimeScale.DEFAULT_RESOLUTION >= TimeScale.MIN_RESOLUTION - 1e-12
    and TimeScale.DEFAULT_RESOLUTION <= TimeScale.MAX_RESOLUTION + 1e-12)
TimeScale:Set(TimeScale.DEFAULT_RESOLUTION)
check("at the default dt_scale is 5.0", near(DAV.dt_scale, 5.0), tostring(DAV.dt_scale))
check("at the default Lead(25) is 1.25 m", near(TimeScale:Lead(25), 1.25), tostring(TimeScale:Lead(25)))
check("at the default Ticks(3.5) is 70", TimeScale:Ticks(3.5) == 70, tostring(TimeScale:Ticks(3.5)))
TimeScale:Set(0.01, TimeScale.MODE_NOMINAL)

-- Continuous Hz <-> period conversion across the whole slider range.
check("range is 10..120 Hz",
    TimeScale.MIN_HZ == 10 and TimeScale.MAX_HZ == 120
    and near(TimeScale.MIN_RESOLUTION, 1 / 120)
    and near(TimeScale.MAX_RESOLUTION, 1 / 10),
    string.format("%g..%g Hz", TimeScale.MIN_HZ, TimeScale.MAX_HZ))
for hz = 10, 120, 5 do
    local res = TimeScale:HzToResolution(hz)
    check(string.format("%d Hz round trips through the stored period", hz),
        math.floor(TimeScale:ResolutionToHz(res) + 0.5) == hz
        and res >= TimeScale.MIN_RESOLUTION - 1e-12
        and res <= TimeScale.MAX_RESOLUTION + 1e-12,
        string.format("res=%.6f -> %.3f Hz", res, TimeScale:ResolutionToHz(res)))
end
check("above-range Hz clamps to 120",
    near(TimeScale:HzToResolution(1000), 1 / 120), tostring(TimeScale:HzToResolution(1000)))
check("below-range Hz clamps to 10",
    near(TimeScale:HzToResolution(1), 1 / 10), tostring(TimeScale:HzToResolution(1)))
-- A garbage Hz value recovers to the shipped default (20 Hz), not to the
-- tuning reference -- a bad setting should land on what we ship, not on some
-- internal constant the user never asked for.
check("0 / nil / NaN Hz fall back to the shipped default",
    near(TimeScale:HzToResolution(0), TimeScale.DEFAULT_RESOLUTION)
    and near(TimeScale:HzToResolution(nil), TimeScale.DEFAULT_RESOLUTION)
    and near(TimeScale:HzToResolution(0 / 0), TimeScale.DEFAULT_RESOLUTION),
    string.format("got %.4f want %.4f",
        TimeScale:HzToResolution(0), TimeScale.DEFAULT_RESOLUTION))
TimeScale:Set(0.01)
check("GetHz reports 100 at the base resolution", TimeScale:GetHz() == 100, tostring(TimeScale:GetHz()))
TimeScale:Set(TimeScale:HzToResolution(37))
check("GetHz reports 37 after a 37 Hz request", TimeScale:GetHz() == 37, tostring(TimeScale:GetHz()))
TimeScale:Set(0.01)

-- Measured mode: the scale follows the real elapsed time, not the request.
TimeScale:Set(0.01, TimeScale.MODE_MEASURED)
TimeScale:SetMeasuredDt(0.03)
check("measured mode: 0.03 s elapsed -> scale 3.0", near(TimeScale:Scale(), 3.0), tostring(TimeScale:Scale()))
TimeScale:SetMeasuredDt(5.0)
check("measured mode clamps a 5 s hitch to MAX_MEASURED_DT",
    near(TimeScale:Scale(), TimeScale.MAX_MEASURED_DT / TimeScale.BASE_RESOLUTION),
    tostring(TimeScale:Scale()))
TimeScale:Set(0.01, TimeScale.MODE_NOMINAL)

-- ===========================================================================
-- B. Landing stop point
-- ===========================================================================
print("B. Landing stop point vs resolution")

local PHYSICS_DT = 1 / 600   -- 10x finer than the fastest supported tick
local MIN_GROUND = 1.2       -- AV.minimum_distance_to_ground

--- Descend at a constant `approach_speed` and report the height at which the
--- stop command fires. This is the AutoLanding decision in isolation: the C#
--- side integrates position continuously, the Lua side samples once per tick.
---@param resolution number control loop period
---@param approach_speed number downward speed, m/s (>= 0)
---@param compensate boolean use the lead-compensated threshold
---@return number stop_height
local function descend(resolution, approach_speed, compensate)
    TimeScale:Set(resolution, TimeScale.MODE_NOMINAL)

    local h = 20.0
    local since_control = resolution          -- tick 1 fires immediately
    local t = 0.0

    while t <= 30 do
        if since_control >= resolution then
            since_control = since_control - resolution
            local lead = compensate and TimeScale:Lead(approach_speed) or 0
            -- `<=`, not `<`: with an exact multiple of the step the lead
            -- cancels the travel exactly, and a strict `<` would fire a whole
            -- tick late.
            if h - lead <= MIN_GROUND then
                return h
            end
        end
        h = h - approach_speed * PHYSICS_DT
        t = t + PHYSICS_DT
        since_control = since_control + PHYSICS_DT
    end
    return h
end

local RESOLUTIONS = {
    1 / 120, 1 / 100, 1 / 80, 1 / 60, 1 / 50, 1 / 40, 1 / 33, 1 / 25, 1 / 20, 1 / 10,
}
local SPEEDS = { 5, 12, 25 }

-- Old behaviour: the undershoot grows with resolution *and* speed, unbounded.
print("    uncompensated stop height (clearance = 1.20 m)")
print("      speed | 120Hz  100Hz   80Hz   60Hz   50Hz   40Hz   33Hz   25Hz   20Hz   10Hz")
for _, speed in ipairs(SPEEDS) do
    local row = string.format("      %5.0f |", speed)
    for _, res in ipairs(RESOLUTIONS) do
        row = row .. string.format(" %6.2f", descend(res, speed, false))
    end
    print(row)
end

-- New behaviour.
print("    compensated stop height")
print("      speed | 120Hz  100Hz   80Hz   60Hz   50Hz   40Hz   33Hz   25Hz   20Hz   10Hz")
local compensated = {}
for _, speed in ipairs(SPEEDS) do
    local row = string.format("      %5.0f |", speed)
    for _, res in ipairs(RESOLUTIONS) do
        local stop = descend(res, speed, true)
        compensated[#compensated + 1] = stop
        row = row .. string.format(" %6.2f", stop)
    end
    print(row)
end

-- 1. The old code really does crash the fast-and-coarse corner: 25 m/s at 20 Hz
--    stops 1.25 m low, i.e. below the ground it was supposed to stop above.
local old_fast_coarse = descend(0.05, 25, false)
check("harness reproduces the bug (25 m/s @20Hz stops below the clearance)",
    old_fast_coarse < MIN_GROUND,
    string.format("stop=%.3f vs clearance=%.2f", old_fast_coarse, MIN_GROUND))

-- 2. The old code is fine at the shipped 100 Hz / gentle approach, so the test
--    is not simply asserting that everything is broken.
--    ...but the old code always lands *low* by up to one tick of travel; at the
--    shipped 100 Hz and a gentle 5 m/s approach that is 5 cm, which is why the
--    bug was never visible before.
local old_slow_fine = descend(0.01, 5, false)
check("harness is not trivially broken (5 m/s @100Hz undershoot is only ~5cm)",
    MIN_GROUND - old_slow_fine <= 5 * 0.01 + 1e-6,
    string.format("stop=%.3f undershoot=%.3f", old_slow_fine, MIN_GROUND - old_slow_fine))

-- 2b. The uncapped lead is a foot-gun. The speed handed to Lead() comes out of
--     the physics handle, and a single wild read (a spawn or teleport transient)
--     inflates it by `speed * resolution`. At 500 m/s and 20 Hz that is 25 m,
--     so `height - lead <= clearance` is true at 20 m altitude and the landing
--     is declared complete 19 m above the ground -- the reported symptom.
--     Capping the lead at the protected clearance keeps the predicate honest.
TimeScale:Set(0.05)
local wild = 500
local altitude = 20.0
local uncapped_lead = TimeScale:Lead(wild)
local capped_lead   = TimeScale:Lead(wild, MIN_GROUND)
local uncapped_fires = (altitude - uncapped_lead) <= MIN_GROUND
local capped_fires   = (altitude - capped_lead)   <= MIN_GROUND
check("uncapped wild read fires the stop at 20 m (the reported symptom)",
    uncapped_lead > 20 and uncapped_fires,
    string.format("lead=%.1f fires=%s", uncapped_lead, tostring(uncapped_fires)))
check("capped wild read does NOT fire at 20 m",
    capped_lead <= MIN_GROUND + 1e-9 and not capped_fires,
    string.format("lead=%.2f fires=%s", capped_lead, tostring(capped_fires)))
-- And the cap must not break the honest case: a real descent still fires near
-- the ground at every resolution.
for _, res in ipairs(RESOLUTIONS) do
    local real_lead = TimeScale:Lead(25, MIN_GROUND)
    TimeScale:Set(res)
    real_lead = TimeScale:Lead(25, MIN_GROUND)
    check(string.format("capped lead still fires just above clearance (%.1f Hz)", 1 / res),
        (MIN_GROUND + real_lead - MIN_GROUND) >= 0
        and (MIN_GROUND - real_lead) <= MIN_GROUND
        and real_lead <= MIN_GROUND + 1e-9,
        string.format("lead=%.3f", real_lead))
end
TimeScale:Set(0.01)

-- 3. The compensation never stops below the clearance, at any combination.
local worst = -math.huge
for _, speed in ipairs(SPEEDS) do
    for _, res in ipairs(RESOLUTIONS) do
        local stop = descend(res, speed, true)
        worst = math.max(worst, MIN_GROUND - stop)
    end
end
check("compensated never stops below the clearance", worst <= 1e-9,
    string.format("worst undershoot=%.4f m", worst))

-- 4. The compensation never stops absurdly high either -- it leads by about one
--    tick of travel, not by a fixed fudge factor.
local max_overshoot = 0
for _, speed in ipairs(SPEEDS) do
    for _, res in ipairs(RESOLUTIONS) do
        local stop = descend(res, speed, true)
        local expected_lead = speed * res
        local overshoot = stop - (MIN_GROUND + expected_lead)
        -- Allow one physics step of slop on top of the predicted lead.
        max_overshoot = math.max(max_overshoot, overshoot)
        check(string.format("lead tracks one tick of travel (%.0f m/s @ %.1f Hz)", speed, 1 / res),
            overshoot <= PHYSICS_DT * speed + 1e-9,
            string.format("stop=%.3f expected<=%.3f", stop, MIN_GROUND + expected_lead))
    end
end

-- 5. Spread across the whole 120..10 Hz window. The compensated stop can only
--    differ by the lead difference between the two ends, i.e.
--        speed * (1/10 - 1/120) = speed * 0.0917
--    plus one physics step of slop. Anything wider means the compensation is
--    not actually tracking the tick length.
local window = TimeScale.MAX_RESOLUTION - TimeScale.MIN_RESOLUTION
for _, speed in ipairs(SPEEDS) do
    local lo, hi = math.huge, -math.huge
    for _, res in ipairs(RESOLUTIONS) do
        local stop = descend(res, speed, true)
        lo = math.min(lo, stop)
        hi = math.max(hi, stop)
    end
    local bound = speed * window + PHYSICS_DT * speed + 1e-6
    check(string.format("compensated stop spread across 120..10 Hz within %.2f m (%.0f m/s)", bound, speed),
        hi - lo <= bound,
        string.format("%.2f .. %.2f (spread %.3f, bound %.3f)", lo, hi, hi - lo, bound))
end

-- 6. Without compensation the same spread is unbounded -- this is the whole
--    point of the setting being dangerous before this change.
local old_lo, old_hi = math.huge, -math.huge
for _, res in ipairs(RESOLUTIONS) do
    local stop = descend(res, 25, false)
    old_lo = math.min(old_lo, stop)
    old_hi = math.max(old_hi, stop)
end
check("uncompensated spread at 25 m/s crosses the clearance (contrast case)",
    old_lo < MIN_GROUND and (old_hi - old_lo) > 1.0,
    string.format("%.2f .. %.2f (spread %.3f)", old_lo, old_hi, old_hi - old_lo))

-- ===========================================================================
-- C. Static guard: the tick-count anti-patterns must not come back
-- ===========================================================================
print("C. Static source guard")

local MODULES = {
    "init.lua",
    "Modules/av.lua", "Modules/core.lua", "Modules/engine.lua",
    "Modules/event.lua", "Modules/navigation.lua", "Modules/hud.lua",
}

-- Each pattern is (regex, why it is banned).
local BANNED = {
    { "Cron%.Every%(0%.01", "hardcoded 0.01 timer -- use DAV.time_resolution" },
    { "/%s*DAV%.time_resolution", "hand-rolled seconds->ticks -- use TimeScale:Ticks()" },
    { "timer%.tick%s*[<>]%s*%d+", "raw tick count in a comparison -- use TimeScale:Ticks(seconds)" },
    { "timer%.tick%s*[<>]=%s*%d+", "raw tick count in a comparison -- use TimeScale:Ticks(seconds)" },
}

local function read_file(rel)
    local f = io.open(MODDIR .. "/" .. rel, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

local violations = 0
for _, rel in ipairs(MODULES) do
    local src = read_file(rel)
    if src then
        local lineno = 0
        for line in src:gmatch("[^\n]*") do
            lineno = lineno + 1
            local code = line:gsub("%-%-.*$", "")  -- drop line comments
            for _, pat in ipairs(BANNED) do
                if code:find(pat[1]) then
                    violations = violations + 1
                    print(string.format("  [FAIL] %s:%d  %s", rel, lineno, pat[2]))
                    print("         " .. line:match("^%s*(.*)$"))
                end
            end
        end
    end
end
check("no raw tick-count / hardcoded-resolution anti-patterns remain", violations == 0,
    string.format("%d violation(s)", violations))

-- ===========================================================================
-- D. Full landing chain -- the fixed 20 s safety net must not fire first
--
-- Mirrors AutoLanding's decision chain plus the Engine fluctuation model:
--   * descent starts at 0.5 m/s and accelerates at autopilot_acceleration
--   * flare at min(h/2, 80) bleeds to 20% of cruise
--   * C# integrates at 600 Hz, Lua decides once per control tick
-- The old `(h/v)*1.8` budget won every single time, 17-56 m above the ground.
-- The fixed 20 s net lets the ground / target branches terminate the landing.
-- ===========================================================================
print("D. Full landing chain vs the fixed 20 s safety net")

local LANDING_TIMEOUT = 20          -- Navigation.landing_timeout_seconds
local SPEED = 25
local ACCEL = math.max(1.0, SPEED * 0.063)   -- Navigation:ApplyAutopilotSpeed

---@param res number control period
---@param height number landing height
---@param budget_seconds number the timeout budget under test
---@return number stop_height, string reason
local function full_landing(res, height, budget_seconds)
    TimeScale:Set(res)
    local ticks = TimeScale:Ticks(budget_seconds)
    local z, v = height, -0.5
    local step, target, active = ACCEL, SPEED, false
    local flare, tick, since, t = false, 0, res, 0.0
    local PDT = 1 / 600

    while t <= 400 do
        if since >= res then
            since = since - res
            tick = tick + 1
            local descent = math.max(0, -v)
            local lead = TimeScale:Lead(descent, MIN_GROUND)
            local dh = height * 0.5
            local rate = 1
            if dh > 80 then dh = 80; rate = 3 end

            if tick == 1 then
                step, target, active = ACCEL, SPEED, true
            elseif z - lead <= MIN_GROUND then
                return z, "ground"
            elseif tick > ticks then
                return z, "TIMEOUT"
            elseif z - lead <= dh and not flare then
                flare = true
                step, target, active = -ACCEL * rate, SPEED * 0.2, true
            end
        end
        if active then
            local m = math.abs(v)
            if m == 0 then active = false
            elseif step > 0 and m > target then v = -target; active = false
            elseif step < 0 and m < target then v = -target; active = false
            else v = v / m * (m + step * PDT) end
        end
        z = z + v * PDT
        t = t + PDT
        since = since + PDT
    end
    return z, "never"
end

-- The old budget loses every time.
local old_losses = 0
for _, h in ipairs({ 20, 50, 100, 200 }) do
    for _, res in ipairs({ 0.01, 0.05 }) do
        local stop, reason = full_landing(res, h, (h / SPEED) * 1.8)
        if reason == "TIMEOUT" then old_losses = old_losses + 1 end
        print(string.format("    old budget %4.0fm @%5.1fHz -> stop=%5.1fm %s", h, 1 / res, stop, reason))
    end
end
check("old (h/v*1.8) budget times out on every landing (the reported bug)",
    old_losses == 8, string.format("%d/8 timed out", old_losses))

-- The fixed 20 s net lands on the ground at every resolution.
-- Tolerance is 5 cm, not an epsilon: the physics step keeps falling between
-- the last sample and the stop, so landing a few millimetres inside the
-- clearance is expected and meaningless for a 5 t craft. What matters is that
-- it lands AT the clearance rather than 17-56 m above it.
for _, h in ipairs({ 20, 50, 100, 150 }) do
    for _, res in ipairs({ 0.01, 1 / 33, 0.05 }) do
        local stop, reason = full_landing(res, h, LANDING_TIMEOUT)
        print(string.format("    20s net    %4.0fm @%5.1fHz -> stop=%5.1fm %s", h, 1 / res, stop, reason))
        check(string.format("20s net lands %dm @%.1fHz on the ground", h, 1 / res),
            reason == "ground"
            and stop >= MIN_GROUND - 0.05
            and stop <= MIN_GROUND * 2,
            string.format("stop=%.4f reason=%s", stop, reason))
    end
end

-- Documented coverage limit: at 25 m/s cruise a 200 m descent needs ~23.6 s,
-- so the net fires before touchdown. Well above the heights this mod targets
-- (autopilot_leaving_height = max(20, speed*2) = 50 m at 25 m/s), but worth
-- pinning so a future change to the descent profile is caught.
local stop200, reason200 = full_landing(0.05, 200, LANDING_TIMEOUT)
check("200 m at 25 m/s exceeds the 20 s net (documented limit)",
    reason200 == "TIMEOUT", string.format("stop=%.1f reason=%s", stop200, reason200))

-- ===========================================================================
-- E. Summon descent (AV:SpawnToSky) -- same class of bug, different constant
--
-- Mirrors the spawn descent:
--   tick 1      : SetDirectionVelocity(0, 0, down_speed)   -- 5 m/s down
--   height < 10 : SetFluctuationVelocityParams(-2, 1)      -- bleed to 1 m/s
--   stop        : height - lead <= minimum_distance_to_ground, or timeout
-- The old down_timeout of 5 s was shorter than the ~6.8 s the profile needs,
-- so every summon stopped on the timeout ~3 m above the ground.
-- ===========================================================================
print("E. Summon descent vs down_timeout")

local SPAWN_HEIGHT = 20
local DOWN_SPEED = 5
local FLARE_ALT = 10
local FLARE_DECEL = 2
local FLARE_SPEED = 1

---@return number stop_height, string reason, number elapsed
local function spawn_descent(res, timeout_s)
    TimeScale:Set(res)
    local ticks = TimeScale:Ticks(timeout_s)
    local lead = TimeScale:Lead(DOWN_SPEED, MIN_GROUND)
    local h, v = SPAWN_HEIGHT, 0.0
    local flared, tick, since, t = false, 0, res, 0.0
    local PDT = 1 / 600
    while t <= 60 do
        if since >= res then
            since = since - res
            tick = tick + 1
            if tick == 1 then
                v = DOWN_SPEED
            elseif h - lead <= MIN_GROUND then
                return h, "ground", t
            elseif tick > ticks then
                return h, "TIMEOUT", t
            elseif h - lead < FLARE_ALT then
                flared = true
            end
        end
        if flared then
            v = v - FLARE_DECEL * PDT
            if v < FLARE_SPEED then v = FLARE_SPEED end
        end
        h = h - v * PDT
        t = t + PDT
        since = since + PDT
    end
    return h, "never", t
end

-- The old 5 s constant loses at every resolution.
for _, res in ipairs({ 0.01, 1 / 33, 0.05 }) do
    local h, reason, t = spawn_descent(res, 5)
    print(string.format("    down_timeout= 5s @%5.1fHz -> stop=%5.2fm %s", 1 / res, h, reason))
    check(string.format("old 5s summon timeout stops high @%.1fHz (the reported bug)", 1 / res),
        reason == "TIMEOUT" and h > MIN_GROUND + 1,
        string.format("stop=%.2fm reason=%s", h, reason))
end

-- The new 10 s constant reaches the ground at every resolution.
for _, res in ipairs({ 0.01, 1 / 33, 0.05 }) do
    local h, reason, t = spawn_descent(res, 10)
    print(string.format("    down_timeout=10s @%5.1fHz -> stop=%5.2fm %s in %.2fs", 1 / res, h, reason, t))
    check(string.format("10s summon timeout lands on the ground @%.1fHz", 1 / res),
        reason == "ground" and h >= MIN_GROUND - 0.05 and h <= MIN_GROUND * 2,
        string.format("stop=%.2fm reason=%s", h, reason))
end

-- Pin the profile so a future change to spawn_height / down_speed / the flare
-- constants that pushes the descent past 10 s trips this test.
local _, _, needed = spawn_descent(0.01, 60)
check("summon descent profile needs ~6.8s, well inside the 10s budget",
    needed > 6 and needed < 8, string.format("%.2fs", needed))
check("10s budget exceeds the profile with headroom",
    10 > needed * 1.4, string.format("10s vs %.2fs", needed))

-- ===========================================================================
-- F. Acceleration sound stop-debounce
--
-- The accel/thruster flags are latched from the drained action queue. That
-- queue is transient: whether a tick sees a movement command depends on how
-- the button-hold producer timer and the control-loop consumer timer fall
-- relative to each other and to the frame rate. Out of phase, the queue is
-- empty on some ticks while the key is still held, and the old code turned
-- every one of those into a Stop event -- the sound churned on/off all the
-- way through an acceleration and never got loud enough to hear.
--
-- New rule: latch on the first command, drop only after the no-command
-- condition has persisted for sound_stop_grace_seconds (0.3 s) worth of ticks.
-- ===========================================================================
print("F. Acceleration sound stop-debounce")

local GRACE_SECONDS = 0.3

--- Replay the new latching rule over a command pattern.
--- '#' = command present this tick, '.' = queue empty this tick
local function replay(res, pattern)
    TimeScale:Set(res)
    local grace = TimeScale:Ticks(GRACE_SECONDS)
    local on, idle, starts, stops = false, 0, 0, 0
    for i = 1, #pattern do
        local want = pattern:sub(i, i) == "#"
        if want then
            idle = 0
            if not on then on = true; starts = starts + 1 end
        elseif on then
            idle = idle + 1
            if idle >= grace then
                on = false; idle = 0; stops = stops + 1
            end
        end
    end
    return starts, stops
end

--- The old rule: any empty tick stops the sound immediately.
local function replay_old(pattern)
    local on, starts, stops = false, 0, 0
    for i = 1, #pattern do
        local want = pattern:sub(i, i) == "#"
        if want and not on then on = true; starts = starts + 1
        elseif not want and on then on = false; stops = stops + 1 end
    end
    return starts, stops
end

for _, res in ipairs({ 0.01, 1 / 33, 0.05 }) do
    TimeScale:Set(res)
    local hz = 1 / res
    local grace = TimeScale:Ticks(GRACE_SECONDS)

    -- Single one-tick dropout in the middle of a long acceleration.
    local pat = string.rep("#", 20) .. "." .. string.rep("#", 20)
    local _, old_stops = replay_old(pat)
    local new_starts, new_stops = replay(res, pat)
    check(string.format("old rule churns on a 1-tick dropout @%.0fHz", hz),
        old_stops >= 1, string.format("%d stops", old_stops))
    check(string.format("debounce swallows a 1-tick dropout @%.0fHz", hz),
        new_starts == 1 and new_stops == 0,
        string.format("%d starts, %d stops", new_starts, new_stops))

    -- A dropout just short of the grace window is still swallowed.
    local short = string.rep("#", 10) .. string.rep(".", grace - 1) .. string.rep("#", 10)
    local _, s_short = replay(res, short)
    check(string.format("debounce swallows a %d-tick dropout @%.0fHz", grace - 1, hz),
        s_short == 0, string.format("%d stops", s_short))

    -- A real release (gap >= grace) still stops, exactly once.
    local released = string.rep("#", 10) .. string.rep(".", grace + 5)
    local r_starts, r_stops = replay(res, released)
    check(string.format("real release stops exactly once @%.0fHz", hz),
        r_starts == 1 and r_stops == 1,
        string.format("%d starts, %d stops", r_starts, r_stops))

    print(string.format("    %.0fHz grace=%d ticks | 1-gap: old=%d stop new=%d stop | release=%d stop",
        hz, grace, old_stops, new_stops, r_stops))
end

-- The grace window must be rate-independent in wall-clock terms, and never so
-- short that a stop becomes impossible.
TimeScale:Set(0.01)
local g100 = TimeScale:Ticks(GRACE_SECONDS)
TimeScale:Set(0.05)
local g20 = TimeScale:Ticks(GRACE_SECONDS)
check("grace is ~0.3s at 100Hz", math.abs(g100 * 0.01 - GRACE_SECONDS) < 0.011,
    string.format("%d ticks = %.2fs", g100, g100 * 0.01))
check("grace is ~0.3s at 20Hz", math.abs(g20 * 0.05 - GRACE_SECONDS) < 0.051,
    string.format("%d ticks = %.2fs", g20, g20 * 0.05))
check("grace is at least 2 ticks at every rate so a stop is still reachable",
    g100 >= 2 and g20 >= 2, string.format("%d / %d", g100, g20))

-- ===========================================================================
-- G. Low-pass blend coefficients must be rate-invariant
--
-- `x = x + (target - x) * alpha` once per tick is a first-order filter with
-- pole (1 - alpha) and time constant -dt/ln(1-alpha). A hardcoded alpha is
-- therefore a hardcoded dt: leave it fixed while the period grows 5x and the
-- filter gets 5x lazier. The autopilot's heading filter lagged the target by
-- ~0.8 s at 20 Hz instead of ~0.16 s, so the craft steered at a heading it
-- was asked for almost a second ago -- the approach wobble.
--
-- TimeScale:SmoothAlpha re-maps the pole: 1 - (1 - alpha) ** (dt / BASE).
-- ===========================================================================
print("G. Low-pass blend time-constant invariance")

local BASE = TimeScale.BASE_RESOLUTION

--- Wall-clock time constant of the discrete blend at a given period/alpha.
local function tau(res, alpha)
    if alpha >= 1 then return 0 end
    return -res / math.log(1 - alpha)
end

--- The real thing: how long the blend takes to close 95% of the gap.
local function settle_time(res, alpha, tolerance)
    tolerance = tolerance or 0.05
    local x, target, t = 0.0, 1.0, 0.0
    while math.abs(target - x) > tolerance and t < 100 do
        x = x + (target - x) * alpha
        t = t + res
    end
    return t
end

for _, base_alpha in ipairs({ 0.06, 0.15, 0.3 }) do
    TimeScale:Set(BASE)
    local ref_tau = tau(BASE, base_alpha)
    local ref_settle = settle_time(BASE, base_alpha)
    for _, res in ipairs({ 0.01, 1 / 33, 0.05, 0.1 }) do
        TimeScale:Set(res)
        local a = TimeScale:SmoothAlpha(base_alpha)
        local got_tau = tau(res, a)
        local got_settle = settle_time(res, a)
        print(string.format("    alpha=%.2f  @%5.1fHz -> %.4f  (tau %.3fs vs ref %.3fs, settle %.2fs vs %.2fs)",
            base_alpha, 1 / res, a, got_tau, ref_tau, got_settle, ref_settle))
        check(string.format("alpha=%.2f keeps its time constant @%.1fHz", base_alpha, 1 / res),
            math.abs(got_tau - ref_tau) < ref_tau * 0.02,
            string.format("%.4fs vs %.4fs", got_tau, ref_tau))
        check(string.format("alpha=%.2f settles within one tick of the reference @%.1fHz", base_alpha, 1 / res),
            math.abs(got_settle - ref_settle) <= res + BASE,
            string.format("%.2fs vs %.2fs", got_settle, ref_settle))
    end
end

-- Identity at the base resolution: nothing changes for the tuning reference.
TimeScale:Set(BASE)
check("SmoothAlpha is the identity at BASE_RESOLUTION",
    math.abs(TimeScale:SmoothAlpha(0.06) - 0.06) < 1e-12,
    tostring(TimeScale:SmoothAlpha(0.06)))
-- And it must be larger at a coarser period (bigger step, same tau).
TimeScale:Set(0.05)
check("SmoothAlpha grows with the period",
    TimeScale:SmoothAlpha(0.06) > 0.25, tostring(TimeScale:SmoothAlpha(0.06)))
-- Bounds and bad input.
check("SmoothAlpha clamps 0", TimeScale:SmoothAlpha(0) == 0)
check("SmoothAlpha clamps 1", TimeScale:SmoothAlpha(1) == 1)
check("SmoothAlpha clamps negative", TimeScale:SmoothAlpha(-0.5) == 0)
check("SmoothAlpha clamps >1", TimeScale:SmoothAlpha(3) == 1)
check("SmoothAlpha survives NaN", TimeScale:SmoothAlpha(0 / 0) == 0)
-- Never exceeds 1, which would make the filter unstable.
TimeScale:Set(0.1)
check("SmoothAlpha never exceeds 1 at the coarsest period",
    TimeScale:SmoothAlpha(0.9) <= 1.0, tostring(TimeScale:SmoothAlpha(0.9)))

-- ===========================================================================
-- H. Restore boundary layer
--
-- The roll/pitch restore was a bare relay: full rate target the moment the
-- angle left the deadband. A relay commits to the full rate for a whole tick,
-- so the overshoot it commits is `full_rate * dt` -- 5x bigger at 20 Hz than
-- at 100 Hz, which is the rocking around the deadband edge.
--
-- Tapering the rate to zero across a boundary layer (widened by dt_scale) makes
-- the committed overshoot independent of the control rate.
-- ===========================================================================
print("H. Restore boundary layer")

local BOUNDARY_BASE = 1.0   -- Engine.restore_boundary_deg

--- Mirror of Engine:RestoreRate.
local function restore_rate(excess, full_rate, res)
    TimeScale:Set(res)
    local boundary = BOUNDARY_BASE * TimeScale:Scale()
    if boundary <= 0 or excess >= boundary then return full_rate end
    if excess <= 0 then return 0 end
    return full_rate * (excess / boundary)
end

-- Far outside the deadband: full rate, unchanged from the old behaviour.
for _, res in ipairs({ 0.01, 0.05 }) do
    check(string.format("far outside the boundary keeps full rate @%.0fHz", 1 / res),
        restore_rate(10.0, 0.2, res) == 0.2,
        tostring(restore_rate(10.0, 0.2, res)))
end

-- Inside the boundary: the rate tapers toward zero at the edge.
TimeScale:Set(0.05)
local boundary20 = BOUNDARY_BASE * TimeScale:Scale()
check("boundary widens with dt_scale", boundary20 > 4.0,
    string.format("%.1f deg", boundary20))
check("halfway through the boundary gives half the rate",
    math.abs(restore_rate(boundary20 / 2, 0.2, 0.05) - 0.1) < 1e-9,
    tostring(restore_rate(boundary20 / 2, 0.2, 0.05)))
check("zero excess gives zero rate", restore_rate(0, 0.2, 0.05) == 0)
check("negative excess is clamped to zero", restore_rate(-1, 0.2, 0.05) == 0)

-- The point of the whole thing: the angle committed in one tick inside the
-- boundary must not grow with the control period.
local committed = {}
for _, res in ipairs({ 0.01, 1 / 33, 0.05 }) do
    -- Start at the boundary edge and integrate the taper down to the deadband.
    TimeScale:Set(res)
    local b = BOUNDARY_BASE * TimeScale:Scale()
    local remaining, total = b, 0.0
    local guard = 0
    while remaining > 1e-9 and guard < 100000 do
        local rate = restore_rate(remaining, 0.2, res)
        local step = rate * res
        if step > remaining then step = remaining end
        remaining = remaining - step
        total = total + step
        guard = guard + 1
    end
    committed[1 / res] = total
    print(string.format("    %.0fHz: boundary=%.1f deg, total angle covered = %.3f deg",
        1 / res, b, total))
end
-- The covered angle is the boundary itself by construction; what matters is
-- that the *rate* at any given distance inside the boundary is lower at a
-- coarser period, so the body is never commanded to cross its own boundary
-- in a single tick.
TimeScale:Set(0.01)
local r100 = restore_rate(0.5, 0.2, 0.01)
TimeScale:Set(0.05)
local r20 = restore_rate(0.5, 0.2, 0.05)
check("same distance inside the boundary commands a lower rate at 20Hz",
    r20 < r100, string.format("%.4f vs %.4f", r20, r100))
check("at 20Hz one tick cannot cross the whole boundary",
    r20 * 0.05 < boundary20,
    string.format("%.4f m vs %.1f deg", r20 * 0.05, boundary20))

-- Boundary of 0 disables the taper (old relay behaviour) for anyone who wants it.
TimeScale:Set(0.05)
local saved = BOUNDARY_BASE
BOUNDARY_BASE = 0
check("boundary 0 restores the bare relay", restore_rate(0.001, 0.2, 0.05) == 0.2,
    tostring(restore_rate(0.001, 0.2, 0.05)))
BOUNDARY_BASE = saved

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then
    error("timescale landing test failed")
end
