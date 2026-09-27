-- =============================================================================
-- ObstacleGrid: the shipped obstacle map as a flat byte-per-cell image.
--
-- WHY THIS EXISTS
-- The resident cost of the old representation was never the bytes, it was the
-- number of live garbage-collected objects. 2.6M cells spread across
-- `obstacle_map` + `obstacle_map_chunk_index` is roughly 8 million live objects,
-- and Lua 5.4's incremental GC has to trace all of them on every cycle. Measured
-- on the shipped map: 127 MB live, p99.9 tick 8.4 ms, max 17.5 ms, 0.21% of
-- ticks over 8 ms. That is the idle micro-stutter, and no amount of spreading the
-- load across frames fixes it, because the cost is *being alive*, not loading.
--
-- One immutable Lua string per chunk holding one byte per cell changes that
-- completely: the whole map becomes ~96 strings, ~200 live objects in total, and
-- strings are never traced internally. Measured: 30 MB live, 0.00% of ticks over
-- 8 ms across every GC configuration tried.
--
-- It also makes loading trivial. A chunk file *is* the image, so a load is one
-- read("*a") with no per-cell Lua work: 264 ms for the entire map versus 3.8 s
-- of parsing.
--
-- And it makes full residency cheap enough that the resident-window / eviction /
-- corridor-streaming machinery is no longer needed. Unknown cells were treated as
-- blocked by A*, and a radius-2 window only covers 24% of the map (5.7% from a
-- corner chunk), which is why long or awkward routes came back partial. With the
-- whole map resident the known-cell ratio is 100% and that failure mode is gone.
--
-- FILE FORMAT (DAVOB4), little endian
--   off  size  field
--   0     6    magic  "DAVOB4"
--   6     1    z_levels          (1..255)
--   7     1    zmin_bias         (uint8, z_min + 128)
--   8     2    cell_size_cm      (uint16 LE, 1000 == 10.0 m)
--   10    4    known_count       (uint32 LE, cells that are not UNKNOWN)
--   14    2    reserved
--   16    ...  body: z_levels * 50 * 50 bytes
--
--   body index = (z - z_min) * 2500 + (cy - chunk_cy*50) * 50 + (cx - chunk_cx*50)
--
--   cell byte: 0 = unknown, 1 = clear, 2 = danger, 3 = blocked
--
-- tools/mapbin_pack.py converts the legacy text chunks into this format.
-- =============================================================================

local ObstacleGrid = {}
ObstacleGrid.__index = ObstacleGrid

local MAGIC       = "DAVOB4"
local HDR         = 16
local CHUNK_CELLS = 50
local SLICE       = CHUNK_CELLS * CHUNK_CELLS   -- 2500 cells per z slice
-- Lua strings are 1-based: 0-based body offset `i` is `byte(raw, HDR + i + 1)`.
local BODY_BASE   = HDR + 1

-- Prebuilt single-character strings, so slice rebuilds can use table.concat
-- instead of a 2500-argument string.char(table.unpack(...)) call.
local CHAR = {}
for i = 0, 255 do CHAR[i] = string.char(i) end

local byte = string.byte

-- Cell states. Deliberately ordered so higher == more obstructive.
ObstacleGrid.UNKNOWN = 0
ObstacleGrid.CLEAR   = 1
ObstacleGrid.DANGER  = 2
ObstacleGrid.BLOCKED = 3

-- Packed cell-key layout, shared with Navigation:PackCellKey so the grid can be
-- indexed straight from a key without the caller unpacking it first.
ObstacleGrid.KEY_SZ_SHIFT = 1024      -- 2^10
ObstacleGrid.KEY_SY_SHIFT = 262144    -- 2^18
ObstacleGrid.KEY_XY_BIAS  = 131072   -- 2^17
ObstacleGrid.KEY_Z_BIAS   = 256

ObstacleGrid.CHUNK_CELLS = CHUNK_CELLS
ObstacleGrid.SLICE       = SLICE

--- Chunk key as a plain integer, from chunk coordinates.
--- Chunk coords in [-512, 511] == +/- 256 km at 500 m chunks.
function ObstacleGrid.chunk_key(ccx, ccy)
	return (ccx + 512) * 1024 + (ccy + 512)
end

---@class ObstacleGrid
---@param opts table|nil { zmin = int, zlevels = int }
function ObstacleGrid:New(opts)
	local self = setmetatable({}, ObstacleGrid)
	opts = opts or {}
	-- Default z window. -4..127 cells == -40 m..1270 m brackets everything in
	-- the shipped map (measured z range -3..88) with room to spare, and matches
	-- what mapbin_pack.py writes, so base images and learned cells always share
	-- one index space and nothing ever needs remapping.
	self.def_zmin   = opts.zmin or -4
	self.def_zlev   = opts.zlevels or 132
	self.cell_size  = opts.cell_size or 10.0
	self.chunks     = {}        -- [int chunk key] = chunk record
	self.chunk_n    = 0
	self.cells_known = 0        -- cells with a state other than UNKNOWN
	self.state_counts = nil     -- lazily filled by count_states()
	self._buf       = {}       -- reusable slice-rebuild scratch
	return self
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

--- Load one v4 chunk file. One read("*a"), zero per-cell Lua work.
---@param path string
---@return table|nil chunk
function ObstacleGrid:load_chunk(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local raw = f:read("*a")
	f:close()
	if not raw or #raw < HDR + SLICE then return nil end
	if raw:sub(1, 6) ~= MAGIC then return nil end

	local zlevels = byte(raw, 7)
	local zmin    = byte(raw, 8) - 128
	local cm      = byte(raw, 9) + byte(raw, 10) * 256
	if cm > 0 then self.cell_size = cm / 100.0 end
	local known   = byte(raw, 11) + byte(raw, 12) * 256
	              + byte(raw, 13) * 65536 + byte(raw, 14) * 16777216

	return {
		raw      = raw,
		zmin     = zmin,
		zlevels  = zlevels,
		bx       = 0,     -- chunk origin in cells, set by load_all
		by       = 0,
		known_n  = known,
	}
end

--- Load every chunk in a { cx, cy, path } list.
---@param list table
---@return number chunks_loaded
function ObstacleGrid:load_all(list)
	local n = 0
	for _, e in ipairs(list) do
		local c = self:load_chunk(e.path)
		if c then
			c.bx = e.cx * CHUNK_CELLS
			c.by = e.cy * CHUNK_CELLS
			self.chunks[ObstacleGrid.chunk_key(e.cx, e.cy)] = c
			self.chunk_n = self.chunk_n + 1
			self.cells_known = self.cells_known + (c.known_n or 0)
			n = n + 1
		end
	end
	return n
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- Cell state from cell coordinates. Hot path.
--- NOTE: CET embeds LuaJIT, which is Lua 5.1 semantics. The 5.4 integer-division
--- operator `//` is a *syntax error* there, so floor division is spelled
--- math.floor() throughout. `byte()` is a bound C function rather than a string
--- method lookup.
---@param cx integer
---@param cy integer
---@param cz integer
---@return number ObstacleGrid.UNKNOWN|CLEAR|DANGER|BLOCKED
function ObstacleGrid:get(cx, cy, cz)
	local c = self.chunks[(math.floor(cx / CHUNK_CELLS) + 512) * 1024
	                     + (math.floor(cy / CHUNK_CELLS) + 512)]
	if c == nil then return ObstacleGrid.UNKNOWN end
	local lz = cz - c.zmin
	if lz < 0 or lz >= c.zlevels then return ObstacleGrid.UNKNOWN end
	return byte(c.raw, BODY_BASE + lz * SLICE + (cy - c.by) * CHUNK_CELLS + (cx - c.bx))
end

--- Cell state straight from a packed cell key, unpacking inline.
--- Saves the caller a round trip through ParseSectorKey.
---@param key number packed cell key
---@return number ObstacleGrid.UNKNOWN|CLEAR|DANGER|BLOCKED
function ObstacleGrid:get_packed(key)
	if type(key) ~= "number" then return ObstacleGrid.UNKNOWN end
	local sz = (key % ObstacleGrid.KEY_SZ_SHIFT) - ObstacleGrid.KEY_Z_BIAS
	local rem = math.floor(key / ObstacleGrid.KEY_SZ_SHIFT)
	local sy = (rem % ObstacleGrid.KEY_SY_SHIFT) - ObstacleGrid.KEY_XY_BIAS
	local sx = math.floor(rem / ObstacleGrid.KEY_SY_SHIFT) - ObstacleGrid.KEY_XY_BIAS

	local c = self.chunks[(math.floor(sx / CHUNK_CELLS) + 512) * 1024
	                     + (math.floor(sy / CHUNK_CELLS) + 512)]
	if c == nil then return ObstacleGrid.UNKNOWN end
	local lz = sz - c.zmin
	if lz < 0 or lz >= c.zlevels then return ObstacleGrid.UNKNOWN end
	return byte(c.raw, BODY_BASE + lz * SLICE + (sy - c.by) * CHUNK_CELLS + (sx - c.bx))
end

function ObstacleGrid:has_chunk(ccx, ccy)
	return self.chunks[ObstacleGrid.chunk_key(ccx, ccy)] ~= nil
end

--- Clamp a cell-z range to what the v4 header can express: zmin is an unsigned
--- byte biased by 128, zlevels is an unsigned byte.
---@return number zlo, number zhi
local function clamp_z(zlo, zhi)
	if zlo < -128 then zlo = -128 end
	if zhi > 127 then zhi = 127 end
	if zhi < zlo then zhi = zlo end
	if zhi - zlo + 1 > 255 then zhi = zlo + 254 end
	return zlo, zhi
end

--- Mint an empty (all-UNKNOWN) chunk covering cell z range [zlo, zhi].
--- Learned cells recorded outside the shipped base image need somewhere to live,
--- and this is what lets them persist in the packed format instead of being
--- stranded in the legacy .diff stream. The window is sized to the caller's
--- cells rather than the full default so a sparse chunk costs kilobytes, not the
--- 330 KB a full 132-level window would.
---@param ccx integer
---@param ccy integer
---@param zlo integer lowest cell z the chunk must hold
---@param zhi integer highest cell z the chunk must hold
---@return table chunk
function ObstacleGrid:new_chunk(ccx, ccy, zlo, zhi)
	local key = ObstacleGrid.chunk_key(ccx, ccy)
	local c = self.chunks[key]
	if c then return c end
	zlo, zhi = clamp_z(zlo, zhi)
	local levels = zhi - zlo + 1
	local cm = math.floor(self.cell_size * 100 + 0.5)
	c = {
		raw = MAGIC .. string.char(levels, zlo + 128, cm % 256, math.floor(cm / 256))
		     .. string.char(0, 0, 0, 0) .. string.rep("\0", 2)
		     .. string.rep("\0", levels * SLICE),
		zmin    = zlo,
		zlevels = levels,
		bx      = ccx * CHUNK_CELLS,
		by      = ccy * CHUNK_CELLS,
		known_n = 0,
	}
	self.chunks[key] = c
	self.chunk_n = self.chunk_n + 1
	self.state_counts = nil
	return c
end

--- Grow a chunk's z window to cover [zlo, zhi], zero-filling new slices.
--- Folding can reach altitudes the chunk was not created with; cells outside the
--- window read as UNKNOWN, so growing is required to not silently drop them.
---@param c table chunk record
---@param zlo integer
---@param zhi integer
---@return table c
function ObstacleGrid:ensure_z_range(c, zlo, zhi)
	local cur_lo, cur_hi = c.zmin, c.zmin + c.zlevels - 1
	if zlo >= cur_lo and zhi <= cur_hi then return c end
	zlo, zhi = clamp_z(math.min(zlo, cur_lo), math.max(zhi, cur_hi))
	local front = (cur_lo - zlo) * SLICE
	local back  = (zhi - cur_hi) * SLICE
	local body  = c.raw:sub(BODY_BASE)
	if front > 0 then body = string.rep("\0", front) .. body end
	if back > 0 then body = body .. string.rep("\0", back) end
	c.raw = c.raw:sub(1, BODY_BASE - 1) .. body
	c.zmin = zlo
	c.zlevels = zhi - zlo + 1
	c.index = nil
	return c
end

-- ---------------------------------------------------------------------------
-- Iterating known cells
--
-- Several lookups want "every non-unknown cell in this chunk". The old code kept
-- a parallel table of 2.6M keys for that, which is precisely the GC cost this
-- module exists to remove, and a cached Lua array of indices would cost 42 MB on
-- its own. So nothing is stored: the image is walked with "[^%z]", which skips
-- whole runs of unknown cells inside one C-level scan. These paths are only
-- reached by nearest-cell resolution, not by A*, so the scan is the right call.
-- ---------------------------------------------------------------------------

--- Walk the known cells of one chunk.
---@param c table chunk record
---@param fn fun(cx:number, cy:number, cz:number, state:number)
function ObstacleGrid:walk_chunk(c, fn)
	local last = HDR + c.zlevels * SLICE
	local bx, by, zmin, raw = c.bx, c.by, c.zmin, c.raw
	-- Start at BODY_BASE, not 1: the header is non-zero and would otherwise be
	-- decoded as cells - its 0x03 length byte reads as BLOCKED at a negative index.
	local pos = BODY_BASE
	while true do
		local s = raw:find("[^%z]", pos)
		if not s or s > last then break end
		local j = s - BODY_BASE
		local lz = math.floor(j / SLICE)
		local rem = j - lz * SLICE
		local ly = math.floor(rem / CHUNK_CELLS)
		local lx = rem - ly * CHUNK_CELLS
		fn(bx + lx, by + ly, zmin + lz, byte(raw, s))
		pos = s + 1
	end
end

--- Iterate known cells of one chunk.
---@param ccx integer chunk x
---@param ccy integer chunk y
---@param fn fun(cx:number, cy:number, cz:number, state:number)
---@return boolean true if the chunk exists
function ObstacleGrid:iter_chunk_known(ccx, ccy, fn)
	local c = self.chunks[ObstacleGrid.chunk_key(ccx, ccy)]
	if c == nil then return false end
	self:walk_chunk(c, fn)
	return true
end

--- Iterate known cells of every chunk.
---@param fn fun(cx:number, cy:number, cz:number, state:number)
function ObstacleGrid:iter_all_known(fn)
	for _, c in pairs(self.chunks) do
		self:walk_chunk(c, fn)
	end
end

--- Per-state tallies for the debug overlay. Scans the images, so the result is
--- cached and invalidated by anything that writes.
---@return number clear, number danger, number blocked
function ObstacleGrid:count_states()
	if self.state_counts then
		return self.state_counts[1], self.state_counts[2], self.state_counts[3]
	end
	local clear, danger, blocked = 0, 0, 0
	for _, c in pairs(self.chunks) do
		local last = HDR + c.zlevels * SLICE
		local raw = c.raw
		local pos = BODY_BASE
		while true do
			local s = raw:find("[^%z]", pos)
			if not s or s > last then break end
			local v = byte(raw, s)
			if v == ObstacleGrid.CLEAR then clear = clear + 1
			elseif v == ObstacleGrid.DANGER then danger = danger + 1
			else blocked = blocked + 1 end
			pos = s + 1
		end
	end
	self.state_counts = { clear, danger, blocked }
	return clear, danger, blocked
end

-- ---------------------------------------------------------------------------
-- Folding learned cells into the image
--
-- When the learned-cell table grows too large we bake it into the base image and
-- drop it from the table. Only the z slices that were actually touched get
-- rebuilt, so a flush is proportional to what changed, not to the map size.
-- ---------------------------------------------------------------------------

--- Bake one cell into a chunk image.
--- Caller is responsible for grouping by chunk and calling finish_slice() once
--- per touched slice; this simple form rebuilds per call and is meant for
--- batched flushes, not the live write path.
---@param ccx integer
---@param ccy integer
---@param cells table list of { cx, cy, cz, state }
---@return boolean folded
function ObstacleGrid:fold_cells(ccx, ccy, cells)
	if cells == nil or #cells == 0 then return false end

	-- z extent of what we are about to fold, needed both to size a new chunk and
	-- to grow an existing one.
	local zlo, zhi
	for _, e in ipairs(cells) do
		local cz = e[3]
		if cz ~= nil then
			if zlo == nil or cz < zlo then zlo = cz end
			if zhi == nil or cz > zhi then zhi = cz end
		end
	end
	if zlo == nil then return false end

	local c = self.chunks[ObstacleGrid.chunk_key(ccx, ccy)]
	if c == nil then
		c = self:new_chunk(ccx, ccy, zlo, zhi)
	else
		self:ensure_z_range(c, zlo, zhi)
	end

	-- Group pending values by z slice so each slice is rebuilt at most once.
	local by_slice = {}
	for _, e in ipairs(cells) do
		local cx, cy, cz, st = e[1], e[2], e[3], e[4]
		local lz = cz - c.zmin
		if lz >= 0 and lz < c.zlevels then
			local off = (cy - c.by) * CHUNK_CELLS + (cx - c.bx)
			if off >= 0 and off < SLICE then
				local t = by_slice[lz]
				if not t then t = {}; by_slice[lz] = t end
				t[off] = st
			end
		end
	end

	local buf = self._buf
	local added = 0
	for lz, pend in pairs(by_slice) do
		local base = lz * SLICE
		local s = c.raw:sub(BODY_BASE + base, BODY_BASE + base + SLICE - 1)
		for i = 1, SLICE do
			local old = byte(s, i)
			local v = pend[i - 1]
			buf[i] = CHAR[v or old]
			-- Count newly-known cells only; overwriting a known cell is neutral.
			if v ~= nil and old == 0 and v ~= 0 then added = added + 1 end
		end
		-- table.concat over a prebuilt char table rather than
		-- string.char(table.unpack(buf, ...)): `table.unpack` does not exist in
		-- Lua 5.1 / LuaJIT, and passing 2500 arguments in one call is fragile
		-- there regardless.
		local new_slice = table.concat(buf, "", 1, SLICE)
		c.raw = c.raw:sub(1, BODY_BASE + base - 1) .. new_slice ..
		        c.raw:sub(BODY_BASE + base + SLICE)
	end

	if c.index ~= nil then c.index = nil end
	c.known_n = (c.known_n or 0) + added
	self.cells_known = self.cells_known + added
	-- The image changed, so the cached tallies are stale.
	self.state_counts = nil
	return true
end

--- Reassemble a chunk image for saving.
---@param c table chunk record
---@return string binary v4 image
function ObstacleGrid:materialize(c)
	local cm = math.floor(self.cell_size * 100 + 0.5)
	local known = math.min(c.known_n or 0, 0xFFFFFFFF)
	return MAGIC .. string.char(c.zlevels, c.zmin + 128, cm % 256, math.floor(cm / 256))
	     .. string.char(known % 256, math.floor(known / 256) % 256,
	                   math.floor(known / 65536) % 256, math.floor(known / 16777216) % 256)
	     .. string.rep("\0", 2) .. c.raw:sub(BODY_BASE)
end

--- Write a chunk image back to disk as v4.
---@param ccx integer
---@param ccy integer
---@param path string
---@return boolean
function ObstacleGrid:save_chunk(ccx, ccy, path)
	local c = self.chunks[ObstacleGrid.chunk_key(ccx, ccy)]
	if c == nil then return false end
	local f = io.open(path, "wb")
	if not f then return false end
	local ok, err = pcall(f.write, f, self:materialize(c))
	f:close()
	return ok and true or false
end

--- Drop every image and index. Used on session teardown.
function ObstacleGrid:clear()
	self.chunks = {}
	self.chunk_n = 0
	self.cells_known = 0
	self.state_counts = nil
end

function ObstacleGrid:heap_mb()
	return collectgarbage("count") / 1024
end

return ObstacleGrid
