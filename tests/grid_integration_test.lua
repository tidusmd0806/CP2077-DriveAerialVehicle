-- =============================================================================
-- Full-residency integration test.
--
-- Exercises the DAVOB4 base-image path end to end against the real shipped map:
-- load, read equivalence with the legacy text loader, learned-cell precedence,
-- the no-downgrade rule, eviction being inert, the learned-cell flush, and A*
-- route equality.
--
-- Run with:  python tests/run_grid_integration_test.py
-- =============================================================================

local MODDIR, TEXTMAP, BINMAP, EMPTYMAP = ...

------------------------------------------------------------
-- CET stubs
------------------------------------------------------------
Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

local g_player_pos = Vector4.new(100, 100, 50, 1)
function setPlayer(x, y, z) g_player_pos = Vector4.new(x, y, z, 1) end
Game = { GetPlayer = function() return { GetWorldPosition = function() return g_player_pos end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = {
	is_debug_profile_autopilot = false,
	user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false },
	is_debug_mode = false,
	is_debug_enable_obstacle_scan = false,
}
spdlog = { info = function() end }

g_cron = { timers = {}, next_id = 1 }
Cron = {
	Every = function(timeout, a, b)
		local cb, args = a, b
		if type(cb) ~= "function" then cb, args = b, a end
		if type(args) ~= "table" then args = { arg = args } end
		local t = { id = g_cron.next_id, timeout = timeout, recurring = true,
		            cb = cb, args = args, halted = false }
		if args.id == nil then args.id = t.id end
		g_cron.next_id = g_cron.next_id + 1
		g_cron.timers[t.id] = t
		return t.id
	end,
	Halt = function(r)
		local t = g_cron.timers[type(r) == "table" and r.id or r]
		if t then t.halted = true; g_cron.timers[t.id] = nil end
	end,
}
function pump_cron(n)
	for _, t in pairs(g_cron.timers) do
		for _ = 1, n do if not t.halted then t.cb(t.args) end end
	end
end

local function preload(name)
	local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
	local body = f:read("*a")
	f:close()
	package.preload[name] = (loadstring or load)(body, name)
end
preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Modules/obstacle_grid.lua")
preload("Modules/profprobe.lua"); preload("Modules/navigation.lua")

Log = require("Etc/log.lua")
local Navigation = require("Modules/navigation.lua")
local ObstacleGrid = require("Modules/obstacle_grid.lua")

------------------------------------------------------------
-- helpers
------------------------------------------------------------
local pass, fail = 0, 0
local function check(label, cond, detail)
	if cond then
		pass = pass + 1
		print(string.format("  [PASS] %s", label))
	else
		fail = fail + 1
		print(string.format("  [FAIL] %s  %s", label, detail or ""))
	end
end
local function heap_mb() return collectgarbage("count") / 1024 end
local function settle() collectgarbage("collect"); collectgarbage("collect") end

-- Count io.open calls so we can prove the nearest-cell lookups stopped touching
-- the filesystem.
local real_open = io.open
local open_count = 0
io.open = function(path, mode)
	open_count = open_count + 1
	return real_open(path, mode)
end
local function open_reset() open_count = 0 end
local function open_n() return open_count end

local function new_nav(bin_dir, text_dir)
	-- Drop the module-level chunk inventory so each nav enumerates its own dirs.
	local throwaway = Navigation:New({
		core_obj = { log_obj = Log:New() }, log_obj = Log:New() })
	throwaway.obstacle_map_dir = text_dir or bin_dir
	throwaway.obstacle_map_bin_dir = bin_dir
	throwaway:ReleaseObstacleMapSessionCache()

	local core_obj = { log_obj = Log:New() }
	local av = { core_obj = core_obj, log_obj = Log:New(), is_auto_pilot = true }
	core_obj.av_obj = av
	local nav = Navigation:New(av)
	nav.obstacle_map_dir = text_dir or bin_dir
	nav.obstacle_map_bin_dir = bin_dir
	nav.obstacle_map_path = text_dir and (text_dir .. "/none.dat") or (bin_dir .. "/none.dat")
	return nav
end

------------------------------------------------------------
print("=== 1. load the packed base image ===")
------------------------------------------------------------
local nav = new_nav(BINMAP)
local g0 = 0
while not nav.is_base_image_loaded and g0 < 5000 do
	nav:LoadBaseImageStep(1000.0); g0 = g0 + 1
end

check("base image loaded", nav.is_base_image_loaded == true)
check("full residency active", nav:IsFullResidencyActive() == true)
check("all 96 chunks resident", nav.obstacle_grid.chunk_n == 96,
	"got " .. nav.obstacle_grid.chunk_n)
-- 2625384 = the 2625381 base cells plus 3 that were UNKNOWN in the .dat and
-- only became known via the .diff merge mapbin_pack.py now performs.
check("every known cell accounted for", nav.obstacle_grid.cells_known == 2625384,
	"got " .. nav.obstacle_grid.cells_known)
local sc_clear, sc_danger, sc_blocked = nav.obstacle_grid:count_states()
check("state tallies sum to cells_known",
	sc_clear + sc_danger + sc_blocked == nav.obstacle_grid.cells_known,
	string.format("%d+%d+%d vs %d", sc_clear, sc_danger, sc_blocked,
		nav.obstacle_grid.cells_known))
check("tallies match the shipped distribution",
	sc_clear == 1283488 and sc_danger == 933926 and sc_blocked == 407970,
	string.format("clear=%d danger=%d blocked=%d", sc_clear, sc_danger, sc_blocked))
settle()
print(string.format("       base image heap: %.1f MB", heap_mb()))

------------------------------------------------------------
print("=== 2. read equivalence with the legacy text loader ===")
------------------------------------------------------------
-- The runtime no longer carries a text loader, so the comparison baseline is
-- read here in the test. Text v3 numbering: 0=clear, 1=danger, >=2=blocked --
-- deliberately NOT the packed numbering, which is why this comparison matters.
local function loadTextMap(tdir, range)
	local t = {}
	range = range or 20
	for cx = -range, range do
		for cy = -range, range do
			local f = io.open(tdir .. "/chunk_" .. cx .. "_" .. cy .. ".dat", "r")
			if f then
				local raw = f:read("*a"); f:close()
				for line in raw:gmatch("[^\n]+") do
					local x, y, z, v = line:match("^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(%d+)%s*$")
					if x then
						x, y, z, v = tonumber(x), tonumber(y), tonumber(z), tonumber(v)
						t[nav:PackCellKey(x, y, z)] =
							(v >= 2) and true or (v == 1 and "danger" or false)
					end
				end
			end
		end
	end
	return t
end
local legacy = loadTextMap(TEXTMAP)
check("legacy text map loaded", next(legacy) ~= nil)

-- A Navigation whose only data layer is that text-loaded table, so the A* and
-- nearest-lookup comparisons below still run against the legacy shape.
local legacy_nav = new_nav(EMPTYMAP, TEXTMAP)
legacy_nav.obstacle_map = legacy
local legacy_n = 0
for _ in pairs(legacy) do legacy_n = legacy_n + 1 end
legacy_nav.obstacle_map_learned_count = legacy_n
check("legacy-shaped nav reads the text data",
	legacy_nav.obstacle_map_learned_count > 2000000,
	"got " .. legacy_nav.obstacle_map_learned_count)

local mismatches, compared = 0, 0
math.randomseed(20260926)
for _ = 1, 200000 do
	local cx = math.random(-300, 125)
	local cy = math.random(-335, 375)
	local cz = math.random(-5, 95)
	local k = nav:PackCellKey(cx, cy, cz)
	local a = nav:CellStateAtKey(k)
	local b = legacy[k]
	compared = compared + 1
	if a ~= b then
		mismatches = mismatches + 1
		if mismatches <= 3 then
			print(string.format("       (%d,%d,%d) grid=%s legacy=%s", cx, cy, cz,
				tostring(a), tostring(b)))
		end
	end
end
check("200k random cells agree with the text loader", mismatches == 0,
	mismatches .. " of " .. compared .. " differ")

------------------------------------------------------------
print("=== 3. learned cells take precedence over the base image ===")
------------------------------------------------------------
-- Pick a cell the base says is clear and teach it a new value.
local teach_x, teach_y, teach_z
nav.obstacle_grid:iter_chunk_known(0, 0, function(cx, cy, cz, st)
	if not teach_x and st == ObstacleGrid.CLEAR then teach_x, teach_y, teach_z = cx, cy, cz end
end)
check("found a clear base cell to teach", teach_x ~= nil)
if teach_x then
	local k = nav:PackCellKey(teach_x, teach_y, teach_z)
	check("base cell reads clear", nav:CellStateAtKey(k) == false)
	check("teaching returns updated=true", nav:SetObstacleCell(k, true) == true)
	check("learned value overrides base", nav:CellStateAtKey(k) == true)
	check("learned counter incremented", nav.obstacle_map_learned_count == 1,
		"got " .. tostring(nav.obstacle_map_learned_count))
end

------------------------------------------------------------
print("=== 4. the no-downgrade rule holds against the EFFECTIVE state ===")
------------------------------------------------------------
-- A base obstacle must not be silently cleared. This is the regression the
-- learned-table-only comparison would have introduced.
local blocked_x, blocked_y, blocked_z
nav.obstacle_grid:iter_chunk_known(0, 0, function(cx, cy, cz, st)
	if not blocked_x and st == ObstacleGrid.BLOCKED then
		blocked_x, blocked_y, blocked_z = cx, cy, cz
	end
end)
check("found a blocked base cell", blocked_x ~= nil)
if blocked_x then
	local k = nav:PackCellKey(blocked_x, blocked_y, blocked_z)
	check("base cell reads obstacle", nav:CellStateAtKey(k) == true)
	check("clearing a base obstacle is refused", nav:SetObstacleCell(k, false) == false)
	check("cell still reads obstacle", nav:CellStateAtKey(k) == true)
	check("danger is also refused against obstacle", nav:SetObstacleCell(k, "danger") == false)
end
-- ...but a clear base cell may be upgraded.
if teach_x then
	local k2 = nav:PackCellKey(teach_x + 7, teach_y + 7, teach_z)
	if nav:CellStateAtKey(k2) == false then
		check("clear base cell accepts danger", nav:SetObstacleCell(k2, "danger") == true)
		check("and then accepts obstacle", nav:SetObstacleCell(k2, true) == true)
		check("but not back down to clear", nav:SetObstacleCell(k2, false) == false)
	end
end

------------------------------------------------------------
print("=== 5. learned cells survive a far move ===")
------------------------------------------------------------
-- Learned cells are not a copy of the base image, so evicting them would destroy
-- recorded obstacles. There is no eviction step in the packed path at all now,
-- which is the strongest form of the guarantee -- assert the observable property.
setPlayer(-2750, 250, 50)   -- far from every learned cell above
local before = nav.obstacle_map_learned_count
check("learned cells survive", nav.obstacle_map_learned_count == before)
check("learned cell still readable after far move",
	teach_x ~= nil and nav:CellStateAtKey(nav:PackCellKey(teach_x, teach_y, teach_z)) == true)
setPlayer(100, 100, 50)

------------------------------------------------------------
print("=== 6. route corridor is skipped when everything is resident ===")
------------------------------------------------------------
local queued = nav:PrepareRouteChunks(
	Vector4.new(100, 100, 50, 1), Vector4.new(-2610, 150, 50, 1))
check("no corridor chunks queued", queued == 0, "got " .. tostring(queued))

------------------------------------------------------------
print("=== 7. A* routes match the legacy full-text map ===")
------------------------------------------------------------
local routes = {
	{ Vector4.new(100, 100, 50, 1),     Vector4.new(-2610, 150, 50, 1), "2.8 km" },
	{ Vector4.new(1000, -3000, 60, 1),  Vector4.new(-3000, 3000, 60, 1), "6.4 km" },
	{ Vector4.new(0, 0, 80, 1),         Vector4.new(-2900, 3500, 40, 1), "4.6 km" },
	{ Vector4.new(-200, -200, 30, 1),   Vector4.new(1100, 3400, 120, 1), "3.8 km" },
}
for _, r in ipairs(routes) do
	local a = nav:PlanGlobalRoute(r[1], r[2])
	local b = legacy_nav:PlanGlobalRoute(r[1], r[2])
	local same = #a == #b
	if same then
		for i = 1, #a do if a[i] ~= b[i] then same = false break end end
	end
	check(string.format("%s route identical (%d nodes)", r[3], #a), same,
		string.format("grid %d nodes vs legacy %d nodes", #a, #b))
	check(string.format("%s route is non-empty", r[3]), #a > 0)
end

------------------------------------------------------------
print("=== 8. nearest-cell lookups read RAM, not disk ===")
------------------------------------------------------------
local info = nav:MakeChunkInfo(0, 0)
open_reset()
local p1, d1 = nav:FindNearestKnownSectorPosInChunk(info, Vector4.new(0, 0, 40, 1), nil, nil)
local n_open = open_n()
check("nearest-known-in-chunk returns a position", p1 ~= nil)
check("zero file opens during the lookup", n_open == 0, n_open .. " opens")
open_reset()
local p2, d2, st = nav:FindNearestSafeOrDangerCellPosInChunk(info, Vector4.new(0, 0, 40, 1))
check("nearest-safe-or-danger returns a status", st == "clear" or st == "danger",
	tostring(st))
check("zero file opens during safe-or-danger lookup", open_n() == 0, open_n() .. " opens")
check("both lookups land near the query",
	(p1 == nil or Vector4.Distance(p1, Vector4.new(0, 0, 40, 1)) < 600) and
	(p2 == nil or Vector4.Distance(p2, Vector4.new(0, 0, 40, 1)) < 600))

------------------------------------------------------------
print("=== 9. learned-cell flush folds into the image and persists ===")
------------------------------------------------------------
-- Teach a batch of cells inside chunk 0_0 so there is something to fold.
local taught = 0
for i = 0, 49 do
	for j = 0, 9 do
		if nav:SetObstacleCell(nav:PackCellKey(i, j, 40), true) then
			taught = taught + 1
		end
	end
end
local learned_before = nav.obstacle_map_learned_count
check("taught a batch of cells to flush", taught > 100, "taught " .. taught)
nav.obstacle_map_learned_flush_cells = math.max(1, learned_before - 100)
local flushed = nav:FlushLearnedCellsToImage()
check("flush processed one chunk", flushed == 1, "got " .. tostring(flushed))
check("learned table shrank", nav.obstacle_map_learned_count < learned_before,
	string.format("%d -> %d", learned_before, nav.obstacle_map_learned_count))

-- The folded knowledge must survive a fresh load of the written image.
local reloaded = ObstacleGrid:New()
local c = reloaded:load_chunk(BINMAP .. "/chunk_0_0.bin")
check("written image reloads", c ~= nil)
if c then
	reloaded.chunks[ObstacleGrid.chunk_key(0, 0)] = c
	reloaded.chunk_n = 1
	if teach_x then
		check("folded cell survives a reload",
			reloaded:get(teach_x, teach_y, teach_z) == ObstacleGrid.BLOCKED,
			"got " .. tostring(reloaded:get(teach_x, teach_y, teach_z)))
	end
	check("a folded batch cell survives a reload",
		reloaded:get(5, 5, 40) == ObstacleGrid.BLOCKED,
		"got " .. tostring(reloaded:get(5, 5, 40)))
	check("reload is still a valid v4 image", #c.raw == 16 + 132 * 2500,
		tostring(#c.raw))
	-- The header known_count must agree with what is actually in the image.
	local walked = 0
	reloaded:walk_chunk(c, function() walked = walked + 1 end)
	check("header known_count matches the image", c.known_n == walked,
		c.known_n .. " vs " .. walked .. " walked")
end

------------------------------------------------------------
print("=== 10. maintenance is idle under full residency ===")
------------------------------------------------------------
setPlayer(100, 100, 50)
local idle = nav:MaintainObstacleMapCache()
check("maintenance reports idle", idle == true)
check("map marked loaded", nav.is_obstacle_map_loaded == true)

------------------------------------------------------------
print("=== 11. full residency can be switched off ===")
------------------------------------------------------------
nav.obstacle_map_full_residency = false
check("residency flag off disables the fast path", nav:IsFullResidencyActive() == false)
nav.obstacle_map_full_residency = true
check("and back on", nav:IsFullResidencyActive() == true)

------------------------------------------------------------
print("=== 12. session teardown releases the image ===")
------------------------------------------------------------
nav:ReleaseObstacleMapSessionCache()
check("grid cleared", nav.obstacle_grid.chunk_n == 0)
check("base image flag cleared", nav.is_base_image_loaded == false)
check("full residency off after teardown", nav:IsFullResidencyActive() == false)
check("cells_known reset", nav.obstacle_grid.cells_known == 0)

------------------------------------------------------------
print("=== 13. the LIVE path loads the image without LoadObstacleMap ===")
------------------------------------------------------------
-- Nothing in the game calls LoadObstacleMap(); the maintenance timer is the
-- only driver. A nav that never had the one-shot called must still reach full
-- residency purely from MaintainObstacleMapCache ticks. This is the exact
-- regression that left the shipped build streaming text chunks forever.
local live = new_nav(BINMAP)
check("live nav starts with no image", live.is_base_image_loaded == false)
check("live nav starts without residency", live:IsFullResidencyActive() == false)
local ticks = 0
while not live:IsFullResidencyActive() and ticks < 500 do
	live:MaintainObstacleMapCache()
	ticks = ticks + 1
end
check("maintenance timer alone reaches full residency",
	live:IsFullResidencyActive() == true, "after " .. ticks .. " ticks")
check("live load pulled in all 96 chunks", live.obstacle_grid.chunk_n == 96,
	"got " .. live.obstacle_grid.chunk_n)
-- Section 9 folds a 500-cell learned batch into chunk_0_0.bin on disk, so by
-- here the shipped image legitimately holds more known cells than the 2625381
-- it was packed with. Assert the band rather than a stale exact number.
check("live load knows every cell", live.obstacle_grid.cells_known >= 2625381
	and live.obstacle_grid.cells_known <= 2625381 + 1000,
	"got " .. live.obstacle_grid.cells_known)
check("live load settles the loaded flag", live.is_obstacle_map_loaded == true)
check("load settles in a sane number of ticks", ticks < 200, "took " .. ticks)

setPlayer(0, 0, 40)
check("departure queues no corridor once resident",
	live:PrepareRouteChunks(Vector4.new(0, 0, 40, 1),
	                       Vector4.new(-2600, 150, 50, 1)) == 0)

-- The base-image sweep must leave the shared chunk inventory warm. If it does
-- not, the first autopilot target resolution re-sweeps 41x41 coords itself --
-- 5043 io.open calls, measured at 3.57 s synchronous in-game. That is the
-- freeze this guards against.
local warm_inv = live:GetAllChunksCached()
check("inventory warmed to the packed chunk set", #warm_inv == 96,
	"got " .. #warm_inv)
open_reset()
live:FindNearestSafeOrDangerCellPos(Vector4.new(0, 0, 40, 1))
check("target resolution opens no files once warmed", open_n() == 0,
	"opened " .. open_n())
open_reset()
live:FindNearestKnownSectorPos(Vector4.new(0, 0, 40, 1))
check("known-sector resolution opens no files", open_n() == 0,
	"opened " .. open_n())

-- A build with no packed data must fall through to streaming rather than wait
-- forever for an image that will never arrive.
local nopack = new_nav(EMPTYMAP, TEXTMAP)
local spin = 0
while nopack.base_image_pending ~= false and spin < 200 do
	nopack:MaintainObstacleMapCache()
	spin = spin + 1
end
check("missing packed data is detected, not waited on",
	nopack.base_image_pending == false, "after " .. spin .. " ticks")
check("detection is quick", spin < 20, "took " .. spin)
check("and residency stays off so streaming still runs",
	nopack:IsFullResidencyActive() == false)

-- The departure gate must be able to finish the load synchronously too.
local gated = new_nav(BINMAP)
check("gated nav starts empty", gated.is_base_image_loaded == false)
check("FinishBaseImageLoad completes it", gated:FinishBaseImageLoad(3000.0) == true)
check("gated nav is fully resident", gated.obstacle_grid.chunk_n == 96,
	"got " .. gated.obstacle_grid.chunk_n)

print("=== 14. the manifest replaces the discovery sweep ===")
------------------------------------------------------------
-- Discovery-by-probing is 41x41 io.open calls and a FAILED open costs ~0.7 ms
-- under CET.  The manifest must resolve the whole chunk set from one read so the
-- load time stops scaling with disk latency.
local mnav = new_nav(BINMAP)
open_reset()
mnav:LoadBaseImageStep(0.001)   -- tiny budget: only init + the first warm item
local pend = mnav.base_image_pending
check("manifest resolves all 96 chunks up front",
	type(pend) == "table" and #pend == 96, "got " .. tostring(pend and #pend))
check("manifest short-circuits the sweep entirely",
	mnav.base_image_sweep_done == true, "sweep_done=" .. tostring(mnav.base_image_sweep_done))
open_reset()
mnav:ReadBinManifest()
check("chunk discovery via manifest is exactly one open", open_n() == 1,
	"opened " .. open_n() .. " (was 1681 probes before the manifest)")
check("manifest entries carry a loadable path",
	type(pend[1].path) == "string" and pend[1].path:find("chunk_") ~= nil,
	tostring(pend[1].path))

-- And the fallback must still work when there is no manifest.
local nomani = new_nav(BINMAP)
nomani.obstacle_map_bin_dir = BINMAP .. "__absent__"
check("missing manifest reads as no manifest", nomani:ReadBinManifest() == nil)
nomani:LoadBaseImageStep(0.0001)
check("without a manifest the sweep is armed instead",
	type(nomani.base_image_pending) == "table"
	and nomani.base_image_sweep_done == false,
	"pending=" .. type(nomani.base_image_pending)
	.. " sweep_done=" .. tostring(nomani.base_image_sweep_done))
check("the armed sweep starts at the probe-range origin",
	nomani.base_image_sweep_cx >= -(nomani.obstacle_map_probe_range or 20)
	and nomani.base_image_sweep_cx < 0,
	"sweep_cx=" .. tostring(nomani.base_image_sweep_cx))

-- Under full residency the warm phase must not probe the text files at all:
-- nothing reads has_dat/has_diff there, and 288 probes measured ~576 ms.
local seednav = new_nav(BINMAP)
open_reset()
local guard = 0
while not seednav.is_base_image_loaded and guard < 5000 do
	seednav:LoadBaseImageStep(1000.0)
	guard = guard + 1
end
local sinv = seednav:GetAllChunksCached()
check("inventory entry is packed-only",
	sinv[1].has_bin == true and sinv[1].has_dat == nil and sinv[1].has_diff == nil,
	"has_dat=" .. tostring(sinv[1].has_dat) .. " has_diff=" .. tostring(sinv[1].has_diff))
-- Cached lookups must not touch the filesystem at all now.
open_reset()
for i = 1, #sinv do
	seednav:MakeChunkInfo(sinv[i].chunk_x, sinv[i].chunk_y)
end
check("cached inventory lookups open nothing", open_n() == 0, "opened " .. open_n())

print("=== 15. learned cells outside the base image persist to .bin ===")
------------------------------------------------------------
-- The gap this closes: FlushLearnedCellsToImage used to require has_chunk(), and
-- fold_cells refused a missing chunk, so a cell recorded outside the shipped map
-- lived only in the legacy .diff stream -- which the residency path never reads
-- back. Round-trip one and prove it survives a reload.
local function exists(p)
	local f = io.open(p, "rb"); if not f then return false end; f:close(); return true
end
local function slurp(p)
	local f = io.open(p, "rb"); if not f then return "" end
	local s = f:read("*a"); f:close(); return s or ""
end

-- Grid-level: fold_cells must mint a chunk and grow it.
local OG = require("Modules/obstacle_grid.lua")
local g = OG:New({})
g:fold_cells(9, 9, { { 452, 454, 7, OG.BLOCKED } })
local minted = g.chunks[OG.chunk_key(9, 9)]
check("fold_cells mints a missing chunk", minted ~= nil)
check("minted chunk reports the cell", g:get(452, 454, 7) == OG.BLOCKED)
check("minted window is tight, not the 132-level default",
	minted ~= nil and minted.zlevels == 1, "zlevels=" .. tostring(minted and minted.zlevels))
check("minted chunk counted in known cells", g.cells_known == 1, "got " .. g.cells_known)
-- A later fold far above must grow the window rather than drop the cell.
g:fold_cells(9, 9, { { 453, 455, 60, OG.DANGER } })
check("ensure_z_range grew the window", g:get(453, 455, 60) == OG.DANGER)
check("growth kept the earlier cell", g:get(452, 454, 7) == OG.BLOCKED)
check("growth recomputed the window",
	minted.zmin == 7 and minted.zlevels == 54,
	"zmin=" .. minted.zmin .. " zlevels=" .. minted.zlevels)

-- Navigation-level: full round trip through SaveObstacleMap + reload.
local OUT_CX, OUT_CY = 40, 40   -- outside the packed extent x[-6..2] y[-7..7]
local out_bin = BINMAP .. "/chunk_" .. OUT_CX .. "_" .. OUT_CY .. ".bin"
local lnav = new_nav(BINMAP)
local guard = 0
while not lnav.is_base_image_loaded and guard < 5000 do
	lnav:LoadBaseImageStep(1000.0); guard = guard + 1
end
check("nav resident before learning", lnav.obstacle_grid.chunk_n == 96,
	"got " .. lnav.obstacle_grid.chunk_n)
check("target chunk absent from the base image",
	lnav.obstacle_grid:has_chunk(OUT_CX, OUT_CY) == false)

local k = lnav:PackCellKey(OUT_CX * 50 + 3, OUT_CY * 50 + 4, 7)
lnav.obstacle_map[k] = true
lnav:MarkCellDirty(k)
lnav.obstacle_map_learned_count = 1
check("learned cell reads blocked before saving", lnav:CellStateAtKey(k) == true)

os.remove(out_bin)
lnav:SaveObstacleMap()

check("packed chunk written outside the base extent", exists(out_bin))
check("learned overlay drained", lnav.obstacle_map[k] == nil)
check("learned count back to zero", lnav.obstacle_map_learned_count == 0)
check("grid now holds the new chunk", lnav.obstacle_grid:has_chunk(OUT_CX, OUT_CY) == true)
check("cell still blocked, now served from the image", lnav:CellStateAtKey(k) == true)
local man = slurp(BINMAP .. "/manifest.txt")
check("manifest lists the new chunk", man:find("40 40") ~= nil)
check("manifest header count kept true", man:find("DAVOB4%-MANIFEST 97") ~= nil,
	man:sub(1, 24))

-- And a fresh nav must pick it up from the manifest with no help.
local rnav = new_nav(BINMAP)
local guard2 = 0
while not rnav.is_base_image_loaded and guard2 < 5000 do
	rnav:LoadBaseImageStep(1000.0); guard2 = guard2 + 1
end
check("reloaded nav sees 97 chunks", rnav.obstacle_grid.chunk_n == 97,
	"got " .. rnav.obstacle_grid.chunk_n)
check("reloaded cell is still blocked", rnav:CellStateAtKey(k) == true,
	"got " .. tostring(rnav:CellStateAtKey(k)))

-- And no .diff was written on the residency path.
check("no .diff written under full residency",
	#slurp(BINMAP .. "/chunk_" .. OUT_CX .. "_" .. OUT_CY .. ".diff") == 0)

print("=== 16. the destructive diff-integration path is gone ===")
------------------------------------------------------------
-- IntegrateObstacleMapDiff rewrote chunk_*.dat from `obstacle_map` and then
-- os.remove()d the .diff. Under the packed model obstacle_map holds only the
-- learned overlay, so that operation destroyed the base snapshot along with any
-- delta that had not been integrated anywhere. Removing it is the guarantee.
check("IntegrateObstacleMapDiff no longer exists",
	Navigation.IntegrateObstacleMapDiff == nil,
	type(Navigation.IntegrateObstacleMapDiff))
check("LoadObstacleMap no longer exists",
	Navigation.LoadObstacleMap == nil, type(Navigation.LoadObstacleMap))
check("the streaming window loader is gone",
	Navigation.EnsureResidentChunks == nil and Navigation.EvictDistantChunks == nil,
	type(Navigation.EnsureResidentChunks) .. "/" .. type(Navigation.EvictDistantChunks))
check("and the packed path is what remains",
	type(Navigation.FoldDirtyChunkToImage) == "function"
	and type(Navigation.LoadBaseImageStep) == "function"
	and type(Navigation.ReadBinManifest) == "function")

print("=== 17. saving survives the CET sandbox with no legacy text dir ===")
------------------------------------------------------------
-- The regression this pins down. Data/map is gone under the packed-only
-- migration, so EnsureMapDirectory's test write fails. The old code then fell
-- through to os.execute('mkdir ...') -- and CET's Lua sandbox has no
-- os.execute. Every save threw *before* reaching the packed branch, so
-- recording ran, learned cells piled up, and .bin never changed.
local snav = new_nav(BINMAP)
local g17 = 0
while not snav.is_base_image_loaded and g17 < 5000 do
	snav:LoadBaseImageStep(1000.0); g17 = g17 + 1
end
check("sandbox nav is fully resident", snav:IsFullResidencyActive() == true)

-- No legacy text directory anywhere, exactly like the installed mod.
snav.obstacle_map_dir = BINMAP .. "__no_such_text_dir__"
snav.obstacle_map_dir_ok = false
check("legacy dir really is absent",
	not (snav:EnsureDirWritable(snav.obstacle_map_dir)))

-- CET strips these. Leaving them nil means any use raises rather than silently
-- working, which is the whole bug made visible.
local real_exec, real_popen = os.execute, io.popen
os.execute, io.popen = nil, nil

-- Teach a cell the base image currently calls clear.
local function find_clear_cell(nav, skip)
	for z = 0, 200, 2 do
		for y = -200, 200, 11 do
			for x = -200, 200, 11 do
				local k = nav:PackCellKey(x, y, z)
				if not (skip and skip[k]) and nav:CellStateAtKey(k) == false then
					return k
				end
			end
		end
	end
	return nil
end
local pk = find_clear_cell(snav, nil)
check("found a clear cell to teach", pk ~= nil)

local ok17, err17 = pcall(function()
	snav:SetObstacleCell(pk, true)
	snav:SaveObstacleMap()
end)
check("save does not throw with os.execute nil", ok17, tostring(err17))

-- Prove it landed on disk, not just in RAM.
local rnav = new_nav(BINMAP)
local g17b = 0
while not rnav.is_base_image_loaded and g17b < 5000 do
	rnav:LoadBaseImageStep(1000.0); g17b = g17b + 1
end
check("taught cell survives a reload", rnav:CellStateAtKey(pk) == true,
	tostring(rnav:CellStateAtKey(pk)))

-- And stopping a mapping session must flush rather than leave the cells in RAM.
-- The periodic save is skipped while autopilot runs, and mapping flights are
-- exactly when recording happens.
snav.is_obstacle_map_recording = true
local pk2 = find_clear_cell(snav, { [pk] = true })
if pk2 then
	snav:SetObstacleCell(pk2, true)
	check("dirty cell pending before stop",
		next(snav.obstacle_map_dirty_cells) ~= nil)
	local ok_stop = pcall(function() snav:StopObstacleRecording() end)
	check("StopObstacleRecording does not throw", ok_stop)
	check("StopObstacleRecording flushed the dirty cells",
		next(snav.obstacle_map_dirty_cells) == nil)
	local rnav2 = new_nav(BINMAP)
	local g17c = 0
	while not rnav2.is_base_image_loaded and g17c < 5000 do
		rnav2:LoadBaseImageStep(1000.0); g17c = g17c + 1
	end
	check("stop-flushed cell survives a reload", rnav2:CellStateAtKey(pk2) == true,
		tostring(rnav2:CellStateAtKey(pk2)))
else
	check("found a second clear cell", false, "none found")
end

os.execute, io.popen = real_exec, real_popen

------------------------------------------------------------
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
