-- =============================================================================
-- Grid: flat byte-per-cell obstacle store (DAVOB4 / v4).
--
-- Replaces the "one Lua table entry per cell" representation. The whole point is
-- to make the resident obstacle map invisible to the garbage collector:
--
--   old: 2.6M cells -> 2.6M keys + 2.6M values + 2 index tables  ~ 300 MB
--        ~8M live GC objects -> incremental GC never finishes quietly,
--        p99.9 tick 52 ms, 4.5% of ticks over 8 ms.
--
--   new: 96 chunks -> 96 immutable Lua strings, 1 byte per cell  ~ 30 MB
--        96 live GC objects, and strings are never *traced* internally.
--
-- Reads are `raw:byte(i)` - O(1), no allocation, no hashing, no string concat.
-- Writes go to a small integer-keyed overlay per chunk and are merged back into
-- the binary image on save, so learning stays cheap and the base image stays
-- immutable.
-- =============================================================================

local Grid = {}
Grid.__index = Grid

local MAGIC       = "DAVOB4"
local HDR         = 16          -- header size, body starts at 0-based offset 16
local CHUNK_CELLS = 50         -- chunk footprint in cells (500 m at 10 m cells)
local SLICE       = CHUNK_CELLS * CHUNK_CELLS   -- 2500 cells per z slice
-- Lua is 1-based: 0-based body offset `i` is `raw:byte(HDR + i + 1)`.
local BODY_BASE   = HDR + 1
-- Bound the method lookup: `byte(s, i)` is a plain C call, `s:byte(i)` walks the
-- string metatable's __index first.
local byte        = string.byte
local char        = string.char
local tunpack     = unpack

-- Four states, matching what the old table representation could express
-- (nil / false / "danger" / true).
Grid.UNKNOWN = 0
Grid.CLEAR   = 1
Grid.DANGER  = 2
Grid.BLOCKED = 3

--- Chunk key as a plain integer. No string concat, no string interning.
--- Supports chunk coords in [-512, 511] == +/- 256 km at 500 m chunks.
local function ck(cx, cy)
	return (cx + 512) * 1024 + (cy + 512)
end
Grid.chunk_key = ck

--- Cell coords -> chunk coords. floor() so negative cells land in the right chunk
--- (floor(-85/50) == -2, not -1).
local function cell_to_chunk(c)
	return math.floor(c / CHUNK_CELLS)
end
Grid.cell_to_chunk = cell_to_chunk

function Grid:New(opts)
	local self = setmetatable({}, Grid)
	opts = opts or {}
	self.cell_size  = opts.cell_size or 10.0
	-- Default z window for chunks that have no base file yet (learning into virgin
	-- territory). -4 .. 127 cells == -40 m .. 1270 m, which brackets anything in
	-- Night City and matches what mapbin_pack.py writes, so base and overlay always
	-- share one index space and nothing ever needs remapping.
	self.def_zmin   = opts.zmin or -4
	self.def_zlev   = opts.zlevels or 132
	self.chunks     = {}          -- [int chunk key] = chunk record
	self.chunk_n    = 0
	self.dirty      = {}          -- [int chunk key] = true
	self.cells_known = 0          -- count of non-UNKNOWN cells held
	-- Reusable scratch buffer for rebuilding a z slice on write.
	self._slice_buf = nil
	return self
end

--- Load one chunk file into RAM. One read("*a"), zero per-cell Lua work.
---@param path string
---@return table|nil chunk
function Grid:load_chunk(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local raw = f:read("*a")
	f:close()
	if not raw or #raw < HDR + SLICE then return nil end
	if raw:sub(1, 6) ~= MAGIC then return nil end

	local zlevels = raw:byte(7)
	local zmin    = raw:byte(8) - 128
	local cm      = raw:byte(9) + raw:byte(10) * 256
	if cm > 0 then self.cell_size = cm / 100.0 end

	return {
		raw      = raw,
		zmin     = zmin,
		zlevels  = zlevels,
		bx       = 0,      -- filled by load_all from the file name
		by       = 0,
		ov       = nil,    -- learned cells: [linear index] = value
		ov_n     = 0,
	}
end

--- Create an empty (all-UNKNOWN) chunk so the hot path never sees a nil image.
---@param cx integer chunk x
---@param cy integer chunk y
---@param zmin integer
---@param zlevels integer
---@return table chunk
function Grid:ensure_chunk(cx, cy, zmin, zlevels)
	local k = ck(cx, cy)
	local c = self.chunks[k]
	if c then return c end
	c = {
		raw     = string.rep("\0", HDR + SLICE * zlevels),
		zmin    = zmin,
		zlevels = zlevels,
		bx      = cx * CHUNK_CELLS,
		by      = cy * CHUNK_CELLS,
		ov      = nil,
		ov_n    = 0,
	}
	self.chunks[k] = c
	self.chunk_n = self.chunk_n + 1
	return c
end

--- Load every chunk in a list of {cx, cy, path} records.
---@param list table
---@return number chunks_loaded
function Grid:load_all(list)
	local n = 0
	for _, e in ipairs(list) do
		local c = self:load_chunk(e.path)
		if c then
			c.bx = e.cx * CHUNK_CELLS
			c.by = e.cy * CHUNK_CELLS
			self.chunks[ck(e.cx, e.cy)] = c
			self.chunk_n = self.chunk_n + 1
			n = n + 1
		end
	end
	return n
end

--- Read the state of one cell. Hot path.
--- Optimised for the A* inner loop:
---   * `//` is a VM-level integer floor division (math.floor is a C call)
---   * `byte()` is a bound C function, not a string method lookup
---   * every chunk always owns a real `raw` image, so there is no nil test here
---   * no chunk cache: measured slower than re-indexing (a store to self costs more
---     than the table hit it saves)
---@return number one of Grid.UNKNOWN / CLEAR / DANGER / BLOCKED
function Grid:get(cx, cy, cz)
	local c = self.chunks[((math.floor(cx / CHUNK_CELLS)) + 512) * 1024 + ((math.floor(cy / CHUNK_CELLS)) + 512)]
	if c == nil then return Grid.UNKNOWN end

	local lz = cz - c.zmin
	if lz < 0 or lz >= c.zlevels then return Grid.UNKNOWN end
	local idx = lz * SLICE + (cy - c.by) * CHUNK_CELLS + (cx - c.bx)

	local ov = c.ov
	if ov ~= nil then
		local v = ov[idx]
		if v ~= nil then return v end
	end
	return byte(c.raw, BODY_BASE + idx)
end

--- Write the state of one cell (learning path).
--- A chunk that has no base file is created on demand with the default z window,
--- so learning is not limited to areas the shipped map already covers.
---@param cz number cell z
---@param v number Grid.CLEAR / DANGER / BLOCKED
---@return boolean changed
function Grid:set(cx, cy, cz, v)
	local ccx, ccy = math.floor(cx / CHUNK_CELLS), math.floor(cy / CHUNK_CELLS)
	local key = ck(ccx, ccy)
	local c = self.chunks[key]
	if c == nil then
		c = self:ensure_chunk(ccx, ccy, self.def_zmin, self.def_zlev)
	end

	local lz = cz - c.zmin
	if lz < 0 or lz >= c.zlevels then return false end   -- outside the z window
	local idx = lz * SLICE + (cy - c.by) * CHUNK_CELLS + (cx - c.bx)

	local ov = c.ov
	if ov == nil then
		ov = {}
		c.ov = ov
	end
	local old = ov[idx]
	if old ~= nil then
		if old == v then return false end
		ov[idx] = v
		return true
	end
	local base = byte(c.raw, BODY_BASE + idx)
	if base == v then
		-- Matches the on-disk image; nothing to remember.
		return false
	end
	ov[idx] = v
	c.ov_n = c.ov_n + 1
	self.cells_known = self.cells_known + 1
	self.dirty[key] = true
	return true
end

--- Merge the learned overlay into the base image and return the new binary blob.
---@param c table chunk record
---@return string binary v4 image
function Grid:materialize(c)
	if c.ov == nil or c.ov_n == 0 then return c.raw end
	local raw, zlevels = c.raw, c.zlevels
	local buf = self._buf or {}
	self._buf = buf
	local slices = {}
	for z = 0, zlevels - 1 do
		local base = z * SLICE
		for i = 1, SLICE do
			local j = base + i - 1
			buf[i] = c.ov[j] or byte(raw, BODY_BASE + j)
		end
		slices[z + 1] = char(tunpack(buf, 1, SLICE))
	end
	local cm = math.floor(self.cell_size * 100 + 0.5)
	return MAGIC .. char(zlevels, c.zmin + 128, cm % 256, math.floor(cm / 256))
	     .. string.rep("\0", 6) .. table.concat(slices, "", 1, zlevels)
end

function Grid:dirty_count()
	local n = 0
	for _ in pairs(self.dirty) do n = n + 1 end
	return n
end

--- Rough live-heap figure in MB.
function Grid:heap_mb()
	return collectgarbage("count") / 1024
end

return Grid
