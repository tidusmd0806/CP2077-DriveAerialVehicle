# DriveAerialVehicle.dll — Native Interface Specification

RED4ext plugin that implements the flight physics core of the *Drive an Aerial Vehicle* (DAV)
MOD. It registers one native REDscript class, **`FlyAVSystem`**, whose methods are called from
CET Lua (and, in principle, any REDscript caller). The DLL also pushes events **out** to Lua
through the game's own event dispatch (see [Event bridge](#event-bridge-dll--lua)).

- DLL: `red4ext/plugins/DriveAerialVehicle/DriveAerialVehicle.dll`
- Registered RTTI class: `FlyAVSystem` (native, parent `IScriptable`)
- Callers obtain the singleton via Codeware: `GetSingleton("FlyAVSystem")`
- Game state: `Running` game state `OnUpdate` drives the DLL frame clock (60 Hz)

### Singleton model (important)

The DLL holds **one** flight state: one bound vehicle, one flight-control buffer set, one
threshold monitor, one sound config, one thruster config. Every native ignores the instance it
was called on (`aContext`), so `FlyAVSystem.new()` a hundred times still shares the same state.
**One consumer at a time.** The DAV MOD is the intended owner; other MODs that want the DLL
should ask DAV to stand down first via [`DAV:Disable()`](#davdisable-davenable-interop) (or not
be installed alongside it). Deploy the DLL exactly once — a second copy fails class registration.

---

## 1. Conventions

| Topic | Rule |
|---|---|
| Return value | `Float` returns: `1` = success, `0` = ignored (no vehicle bound / invalid state). Getters return neutral values (`0`, zero vector, `false`, `-1`) when unresolved. |
| Types across the boundary | Simple types only: `Float`, `Int32`, `Uint32`, `Uint64`, `Bool`, `String`, `Vector3`, `Vector4`. **ref types (`IScriptable`, handles, `ScriptRef`) cannot cross the CET boundary at all** — never add one. |
| Vehicle binding | All vehicle-bound functions act on the vehicle bound by [`SetVehicle`](#setvehicle). If nothing is bound they are no-ops. |
| Threading (in) | Natives are called on the **game thread** (CET Lua). They write lock-free atomics / double-buffered slots consumed by the physics thread. |
| Threading (hook) | The DLL hooks three game physics functions that run on the **physics thread**; flight control is applied there. Never call game script APIs from them. |
| Vehicle handle lifetime | The DLL holds a `Handle<vehicle::BaseObject>`. Lua must release it with `SetVehicle(0)` on despawn and on CET shutdown. All reads of the vehicle body are SEH-guarded (`VehicleBodyAlive()`). |
| Raycast safety | Synchronous ground raycasts are issued **only while physics is actively stepping** (`g_phys_alive`). Querying a physics scene during world teardown deadlocks the game. |
| Numbers from Lua | `entity:GetEntityID().hash` is a cdata uint64 — wrap with `tonumber()` before passing. |

---

## 2. API reference

### 2.1 Vehicle binding & global switches

#### `SetVehicle`
```
SetVehicle(entity_id_hash: Uint32) -> Float
```
| Param | Type | Description |
|---|---|---|
| `entity_id_hash` | Uint32 (DLL reads 64-bit) | `entity:GetEntityID().hash` of the AV. Pass `0` to release the binding. |

Binds the vehicle all other functions act on. On a changed hash the stale handle is dropped and
lazily re-resolved (also adopted from the physics hook when `FindEntityByID` cannot see the entity
yet). Re-binding resets thruster component caches.

#### `EnableOriginalPhysics`
```
EnableOriginalPhysics(is_enable: Bool) -> Float
```
`false` = the DLL owns the vehicle's physics: the hooks suppress the game's resistance/force
application for the bound vehicle and gravity follows `EnableGravity`. `true` = game defaults.

---

### 2.2 Physics read/write (bound vehicle)

All read the live `PhysicsData` through the SEH liveness gate; safe to call any time.

| Function | Signature | Notes |
|---|---|---|
| `GetMass` | `() -> Float` | `total_mass`; falls back to the last value published by the physics hook when unresolved. |
| `HasGravity` | `() -> Bool` | Gravity flag (`physicsData.unk1B0`). |
| `EnableGravity` | `(is_enable: Bool) -> Float` | Desired gravity state; remembered unconditionally and re-applied by the physics hook every tick (a one-shot write while unresolved is silently dropped by the game). |
| `GetVelocity` | `() -> Vector3` | Zero when unresolved. |
| `GetAngularVelocity` | `() -> Vector3` | Zero when unresolved. |
| `GetPhysicsState` | `() -> Float` | `-1` = unresolved; `0` = physics enabled; non-zero (e.g. `16`) = game disabled the body (landed/parked). |
| `UnsetPhysicsState` | `() -> Float` | Calls `ForceEnablePhysics()` once on the bound vehicle. |
| `IsOnGround` | `() -> Bool` | Game contact flag. |
| `GetNativeTickCount` | `() -> Float` | Number of physics-hook ticks seen for the bound vehicle. Liveness probe: if it stops advancing, the physics step for this vehicle stopped (parked / disabled / world teardown). |
| `GetNativeRPM` | `() -> Float` | RPM integrator maintained by the native flight model (mode 3). |

---

### 2.3 Basic Control (legacy)

Raw physics primitives kept for API compatibility; **the DAV MOD itself does not call these**
(the flight model in `SetFlightControl` supersedes them). Other consumers may use them for
simple vehicle pushes. All act on the bound vehicle and return `0` when nothing is bound.

| Function | Signature | Description |
|---|---|---|
| `AddVelocity` | `(velocity: Vector3, angularVelocity: Vector3) -> Float` | Adds to linear/angular velocity. |
| `AddForce` | `(force: Vector3, torque: Vector3) -> Float` | Accumulates force/torque for the next physics step. |
| `ChangeVelocity` | `(velocity: Vector3, angularVelocity: Vector3, switchIndex: Float) -> Float` | `switchIndex`: `1` = velocity only, `2` = angular only, anything else = both. |
| `ChangeForce` | `(force: Vector3, torque: Vector3, switchIndex: Float) -> Float` | Same selector as `ChangeVelocity`. |
| `GetForce` | `() -> Vector3` | Accumulated force; zero when unresolved. |
| `GetTorque` | `() -> Vector3` | Accumulated torque; zero when unresolved. |

---

### 2.4 Flight control

#### `SetFlightControl`
```
SetFlightControl(mode: Float, velocity: Vector3, angularVelocity: Vector3, torqueGain: Float) -> Float
```
| Param | Description |
|---|---|
| `mode` | `0` off (native applies nothing) · `1` force/torque steering (`force = target_accel·mass`, `torque = (target_angvel − angvel)·torqueGain`) · `2` velocity hold (sets velocity/angularVelocity to the targets) · `3` full native flight model (consumes held commands from `SetNativeCommand` + all pushed params) · `4` idle hover (unboarded hover, consumes `SetIdleHoverParams`) |
| `velocity` | Target linear velocity / force target (mode-dependent). |
| `angularVelocity` | Target angular velocity (CET Euler convention). |
| `torqueGain` | Proportional gain for angular error (mode 1). |

Called from Lua every control tick. Doubles as the lazy re-resolution point for the vehicle
handle. **Auto re-assert:** with a driver aboard, no autopilot, no heli flag and any held command
non-zero, the physics hook promotes mode `2`/`4` to `3` automatically (airplane rescue; skipped
when flight flag bit2 is set because heli drives manual flight through mode 2).

#### `SetNativeCommand`
```
SetNativeCommand(action_id: Int32, value: Float) -> Float
```
Event-driven input edge into the DLL's held-command state (64 slots).
`action_id = 0` clears **all** held commands (dismount / menu / abort reset). Any other id stores
`value` into slot `id + 1`; `value = 0` releases that single command. The flight model (mode 3)
reads the held state every physics tick.

#### `SetFlightFlags`
```
SetFlightFlags(flags: Int32) -> Float
```
| Bit | Meaning | Effect |
|---|---|---|
| 0 | player aboard | enables auto mode re-assert; gates sound edge events |
| 1 | autopilot engaged | suppresses re-assert and sound edges |
| 2 | helicopter flight mode | suppresses the airplane-only mode 2→3 re-assert |

#### `SetFlightParams` / `SetFlightParams2` / `SetFlightParams3`
```
SetFlightParams(a: Vector4, b: Vector4, c: Vector4) -> Float
SetFlightParams2(a: Vector4, b: Vector4, c: Vector4) -> Float
SetFlightParams3(a: Vector4) -> Float
```
Flight-model tunables, packed into `Vector4`s. The field order is defined jointly with the Lua
side (`Engine:PushNativeParams`) and must be changed in lockstep. Each call **preserves** the
fields owned by the other two calls (copy-on-write into a double-buffered slot). Current packing
(Lua source of truth):

| Call | X | Y | Z | W |
|---|---|---|---|---|
| `SetFlightParams.a` | max_speed | horizontal air resistance | vertical air resistance | acceleration |
| `SetFlightParams.b` | vertical acceleration | left/right acceleration | roll change amount | roll restore amount |
| `SetFlightParams.c` | pitch change amount | pitch restore amount | yaw change amount | rotate roll change amount |
| `SetFlightParams2.a` | h_roll change | h_roll restore | h_pitch change | h_pitch restore |
| `SetFlightParams2.b` | h_yaw change | h_acceleration | h_lift idle acceleration | h_ascend acceleration |
| `SetFlightParams2.c` | h_descend acceleration | rpm step | rpm restore step | rpm count scale |
| `SetFlightParams3.a` | max_roll | max_pitch | force restore angle | restore boundary deg |

#### `SetIdleHoverParams`
```
SetIdleHoverParams(a: Vector4, b: Vector4, c: Vector4, d: Vector4) -> Float
```
Idle hover (mode 4) reference + gains. Packing (see `Engine:PushIdleHoverParams`):

| Vector4 | X | Y | Z | W |
|---|---|---|---|---|
| a | ground_z | min distance to ground | damping (0.2) | height gain (0.5) |
| b | pitch band | roll band | restore boundary deg | dt scale |
| c | max_roll | max_pitch | force restore angle | horizontal air resistance |
| d | vertical air resistance | idle gravity (0/1) | 12 | 1 |

`ground_z` is the only value the physics hook cannot see itself; Lua re-pushes it a couple of
times per second.

#### `SetFlightModel`
```
SetFlightModel(v1..v10: Vector4) -> Float
```
One-shot flight-model state push (boarding / model switch). Documented packing:

| Vector4 | Contents |
|---|---|
| v1 | `flight_mode` (0 plane / 1 heli), `has_gravity`, `dt_scale`, `ncmd` (held-command count, 0–6) |
| v2 | `reset` (non-zero clears native integrators: RPM, heli lift), action ids 1–3 |
| v3 | action ids 4–6, value 1 |
| v4 | values 2–5 |
| v5 | value 6, -, -, - |
| v6 | attitude (roll, pitch, yaw, CET Euler); W = 1 when valid |
| v7 | entity world quaternion (i, j, k, r); W = 1 when valid |
| v8 | entity forward (x, y, z); W = 1 when the axis triplet is valid |
| v9 | entity right (x, y, z), … |
| v10 | entity up (x, y, z), … |

---

### 2.5 Ground measurement (DLL-side raycast)

The DLL runs the game's own `gameISpatialQueriesSystem.SyncRaycastByQueryFilter` (resolved via
`IGameInstance::GetSystem`, parameters identified by RTTI — nothing hardcoded).

#### `SetGroundQuery`
```
SetGroundQuery(offset: Float, distance: Float, mask1: Uint64, mask2: Uint64) -> Float
```
| Param | Description |
|---|---|
| `offset` | Ray start height above the vehicle's world Z. |
| `distance` | Downward query length. |
| `mask1`, `mask2` | Collision filter group masks (user settings; RTTI cannot supply them). |

The query shape is parsed once per world; if pushed before the system exists the arguments are
remembered and replayed after resolution.

#### `SetGroundReference`
```
SetGroundReference(z: Float) -> Float
```
Seeds the ground Z reference (marks it valid) before first ground contact teaches it.

#### `GetGroundInfo`
```
() -> Vector4
```
Returns `(ground_z, vehicle_world_z, on_ground /*0|1*/, valid /*0|1*/)` — one call replaces a
CET-side raycast for every height decision.

---

### 2.6 Threshold monitor (DLL game-thread)

The DLL watches three monitors on the frame clock and announces crossings as events
([Event bridge](#event-bridge-dll--lua)). Hysteresis: height ±0.5 m, distance ±2 m, entry ±0.5 m.

#### `SetThresholds`
```
SetThresholds(height_thr: Float, dist_thr: Float, entry_radius: Float,
              keepalive: Float, mask: Int32, entry_off: Vector4) -> Float
```
| Param | Description |
|---|---|
| `height_thr` | Landing-warning height threshold (m). Fires `dav_evt_height_low` below / `dav_evt_height_high` above. |
| `dist_thr` | Player↔vehicle distance threshold (m) for engine audio (`dav_evt_dist_near` / `dav_evt_dist_far`). |
| `entry_radius` | Entry-area radius (m) around `entry_off` (`dav_evt_entry_in` / `dav_evt_entry_out`). |
| `keepalive` | While the player stays inside the entry area, `dav_evt_entry_in` re-fires every N seconds. |
| `mask` | bit0 = height monitor, bit1 = distance monitor, bit2 = entry-area monitor. `0` disarms everything and resets edge state. |
| `entry_off` | Entry-area center in **vehicle-local** coordinates (rotated by the entity quaternion). |

The mask is stored last: it arms the monitor and everything it reads is already in place.

#### `SetLandingVFX`
```
SetLandingVFX(enabled: Float, offset: Vector4) -> Float
```
Enables (`enabled ≠ 0`) the `dav_evt_height_tick` stream while the vehicle is inside the warning
zone. The tick carries the measured height in `timeToLive` (deadband 1 cm, max interval 0.25 s);
Lua re-projects the VFX from it. `offset` is reserved (currently unused).

#### `SetWorldGone`
```
SetWorldGone(gone: Float) -> Float
```
`1` = treat the world as detached: the frame clock returns immediately from every update and
touches nothing. `0` = re-arm. Manual kill switch; the automatic teardown protection is the
physics-liveness raycast gate (§1 Conventions).

---

### 2.7 Sound layers

#### `SetSoundParams`
```
SetSoundParams(graceSeconds: Float, accelIds: String, thrusterIds: String) -> Float
```
| Param | Description |
|---|---|
| `graceSeconds` | Grace period before a `*_stop` edge fires (default 0.3 when ≤ 0). |
| `accelIds` | Comma-separated action ids of the acceleration sound layers (`Def.AccelerationActionList`). |
| `thrusterIds` | Comma-separated action ids of the thruster layers (`Def.ThrusterActionList`). |

The DLL polls the action states on the frame clock (gated by flight flags) and queues
`dav_av_accel_start/stop`, `dav_heli_accel_start/stop`, `dav_heli_thruster_start/stop` events on
the puppet. Lua plays/stops the layers from the event.

---

### 2.8 Thruster swing

#### `SetThrusterSetup`
```
SetThrusterSetup(enabled: Float, step: Float, restore: Float, maxAngle: Float,
                 axis: Int32, engineNames: String, fxNames: String) -> Float
```
| Param | Description |
|---|---|
| `enabled` | `0` releases the setup (despawn / helicopter); non-zero arms it. |
| `step` | Swing rate, deg/s. |
| `restore` | Restore-to-center rate, deg/s. |
| `maxAngle` | Maximum swing angle, deg. |
| `axis` | Swing axis code: `0`=X+ `1`=X- `2`=Y+ `3`=Y- `4`=Z+ `5`=Z- |
| `engineNames` | `;`-separated component names to swing (resolved by the DLL via a memory walk of the entity's component storage — `FindComponentByName` crashes from the DLL). |
| `fxNames` | `;`-separated component names for the FX slots. |

Re-pushing the setup drops the previous vehicle's component handles.

#### `SetThrusterCommand`
```
SetThrusterCommand(forward: Float, backward: Float) -> Float
```
Current input levels (0…1). The DLL integrates the swing on the frame clock and writes component
local orientations directly.

---

## `DAV:Disable()` / `DAV:Enable()` (interop)

Because the DLL is a singleton, the DAV MOD exposes a runtime hand-over switch so another MOD
can take the DLL (and the sky) for itself. Every CET mod runs in its own Lua VM, so the API is
published on CET's shared mod table (`GetMod`):

```lua
-- from any other mod's Lua:
local dav = GetMod("DriveAerialVehicle")
if dav ~= nil and dav.Disable ~= nil then
    local ok = dav.Disable()   -- false = refused (player is riding the AV)
    -- ... use the FlyAVSystem DLL exclusively ...
    dav.Enable()               -- give control back; summoning works again
end
```

| Entry | Behavior |
|---|---|
| `dav.Disable()` (= `DAV:Disable()`) | Refused (`false`) while the player is riding the AV. Otherwise: despawns the AV immediately, releases the DLL vehicle handle, thruster setup, threshold monitor and landing VFX, and blocks every summon path (`AV:Spawn` returns `false`). Idempotent. |
| `dav.Enable()` (= `DAV:Enable()`) | Clears the disabled flag; summoning and normal DAV behavior are restored. Idempotent. |
| `dav.is_disabled()` | Current flag (also `DAV.is_disabled` inside DAV itself). |

State is runtime-only: it is **not** persisted across sessions, and it does not unload the DLL —
the DLL keeps running its frame clock (idle, with nothing bound).

---

## Event bridge (DLL → Lua)

There is no direct DLL→Lua call. The DLL builds `gameActionEvent` instances via RTTI
(`CreateInstance`, fields set through `CProperty::SetValue`), queues them on the player puppet
with `entEntity::QueueEvent`, and the game dispatches them to a REDscript callback which CET
observes:

```
DLL QueueEvent(gameActionEvent{eventAction=dav_evt_*, timeToLive=payload})
  → REDscript @addMethod(PlayerPuppet) cb OnDAVMonitorEvent(event)   # registers the CNames
    → CET Observe("PlayerPuppet", "OnDAVMonitorEvent", fn)
      → Lua Event:OnDavThresholdEvent(name, ttl)
```

| Event name | `timeToLive` payload | Fired when |
|---|---|---|
| `dav_evt_height_low` / `dav_evt_height_high` | measured height (m) | crossing `height_thr` (±0.5 m hysteresis) |
| `dav_evt_height_tick` | measured height (m) | every frame inside the warning zone (1 cm deadband, ≥ 0.25 s) |
| `dav_evt_dist_near` / `dav_evt_dist_far` | 1.5 | player crossing `dist_thr` |
| `dav_evt_entry_in` / `dav_evt_entry_out` | 1.5 | player crossing the entry area (+ keepalive re-fire) |
| `dav_av_accel_start/stop`, `dav_heli_accel_start/stop`, `dav_heli_thruster_start/stop` | 1.5 | sound layer edge transitions |

Rules:
- CNames only exist if REDscript references them (`n"dav_evt_*"` in the cb body). `CName.new()`
  from Lua does **not** register names.
- `timeToLive` is a free float channel: unknown actions ignore it, so height rides there.
- After shutdown starts (`g_shutting_down`) the DLL refuses to queue events — events fed into a
  teardown are dispatched later by game code whose puppet is gone.

---

## Threading & shutdown rules (hard requirements)

1. **Never** call `FindComponentByName` (or any script API) from the DLL — resolve components by
   the guarded memory walk instead.
2. All vehicle-body reads go through the SEH liveness gate (`VehicleBodyAlive()`); a dangling
   handle is non-null and readable-looking after teardown.
3. Synchronous physics queries (raycasts) only while `g_phys_alive` (hook ticked within ~0.25 s).
   The exit flow always pauses physics seconds before detaching the world, which stops the
   raycasts long before the scene dies. Querying a dying physics scene = process-wide deadlock.
4. `DavGameState_OnUpdate` **must return `false`** (returning `true` marks the state finished and
   kills the frame clock).
5. On `OnExit` the DLL drops the vehicle handle, entity hash and monitor mask
   (`g_shutting_down`). Lua's `onShutdown` also calls `SetVehicle(0)` (CET-reload insurance).
6. Physics-thread code (the three hooks) touches only atomics / double-buffered slots — never the
   script VM.

---

## Diagnostics

Log: `red4ext/logs/driveaerialvehicle-YYYY-MM-DD-HH-MM-SS.log`. Useful markers:
`game state OnUpdate live`, `SetWorldGone(…)`, `game state OnExit (shutdown guard armed)`,
`hook stalled` (physics stopped), `snd edge`, `hook apply heartbeat`.
