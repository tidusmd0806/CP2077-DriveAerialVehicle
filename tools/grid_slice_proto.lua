-- =============================================================================
-- Slice-COW variant: the chunk image is an ARRAY OF Z-SLICE STRINGS (2500 bytes
-- each) instead of one big immutable string.
--
-- Why: with one immutable image, every learned cell must sit in an overlay table
-- until the chunk is saved. A heavy learning session turned that overlay into
-- ~1.7M integer-keyed entries = 65 MB of live GC objects, which put the p99.9
-- tick back at 6.2 ms - the overlay re-creates exactly the problem the byte grid
-- removed, just later.
--
-- With per-z-slice copy-on-write:
--   * reads cost one extra table index (measured: negligible)
--   * a write rebuilds ONE 2500-byte slice, and only after that slice has
--     accumulated COMPACT_MIN pending deltas, so the cost is amortised
--   * live objects stay ~96 chunks x 132 slices = ~12.7k immutable strings and
--     total bytes never grow beyond the image itself
-- =============================================================================

local SLICE_BYTES = 2500          -- 50 x 50
local CHUNK_CELLS = 50
local HDR, BODY_BASE = 16, 17
local byte, char, concat = string.byte, string.char, table.concat
local tunpack = unpack

local Slice = {}
Slice.__index = Slice
Slice.UNKNOWN, Slice.CLEAR, Slice.DANGER, Slice.BLOCKED = 0, 1, 2, 3

--- Writes a slice absorbs before it is folded into a fresh image string.
--- Small = cheap memory, more rebuilds. Large = fewer rebuilds, fatter delta
--- tables. Measured at 64 and 512 in tools/grid_slice_bench.lua.
Slice.COMPACT_MIN = 64

function Slice:New(opts)
	local self = setmetatable({}, Slice)
	opts = opts or {}
	self.cell_size = opts.cell_size or 10.0
	self.def_zmin, self.def_zlev = opts.zmin or -4, opts.zlevels or 132
	self.chunks = {}
	self.chunk_n = 0
	self.dirty = {}
	self._buf = {}                 -- reusable 2500-slot scratch for rebuilds
	self.rebuilds = 0
	return self
end

function Slice:load_chunk(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local raw = f:read("*a")
	f:close()
	if not raw or #raw < HDR + SLICE_BYTES then return nil end
	if raw:sub(1, 6) ~= "DAVOB4" then return nil end
	local zlevels = raw:byte(7)
	local zmin = raw:byte(8) - 128

	-- Split the one-shot read into per-z-slice strings. Still zero per-cell Lua
	-- work: zlevels :sub() calls over a buffer we already have.
	local slices = {}
	for z = 0, zlevels - 1 do
		local a = BODY_BASE + z * SLICE_BYTES
		slices[z + 1] = raw:sub(a, a + SLICE_BYTES - 1)
	end
	return {
		slices  = slices,
		zmin    = zmin,
		zlevels = zlevels,
		bx = 0, by = 0,
		pend    = nil,   -- [global slice-relative index] = value
		pend_z  = nil,   -- [lz] = pending count in that slice
		pend_n  = 0,
	}
end

function Slice:load_all(list)
	local n = 0
	for _, e in ipairs(list) do
		local c = self:load_chunk(e.path)
		if c then
			c.bx, c.by = e.cx * CHUNK_CELLS, e.cy * CHUNK_CELLS
			self.chunks[((e.cx + 512) * 1024) + (e.cy + 512)] = c
			self.chunk_n = self.chunk_n + 1
			n = n + 1
		end
	end
	return n
end

function Slice:ensure_chunk(ccx, ccy, zmin, zlevels)
	local k = ((ccx + 512) * 1024) + (ccy + 512)
	local c = self.chunks[k]
	if c then return c end
	local blank = string.rep("\0", SLICE_BYTES)
	local slices = {}
	for z = 1, zlevels do slices[z] = blank end
	c = { slices = slices, zmin = zmin, zlevels = zlevels,
	      bx = ccx * CHUNK_CELLS, by = ccy * CHUNK_CELLS,
	      pend = nil, pend_z = nil, pend_n = 0 }
	self.chunks[k] = c
	self.chunk_n = self.chunk_n + 1
	return c
end

--- Hot read: chunk -> z slice -> byte.
function Slice:get(cx, cy, cz)
	local c = self.chunks[((math.floor(cx / CHUNK_CELLS)) + 512) * 1024 + ((math.floor(cy / CHUNK_CELLS)) + 512)]
	if c == nil then return 0 end
	local lz = cz - c.zmin
	if lz < 0 or lz >= c.zlevels then return 0 end
	local off = (cy - c.by) * CHUNK_CELLS + (cx - c.bx)
	local p = c.pend
	if p ~= nil then
		local v = p[lz * SLICE_BYTES + off]
		if v ~= nil then return v end
	end
	return byte(c.slices[lz + 1], off + 1)
end

--- Fold one z slice's pending deltas into a fresh image string.
function Slice:compact_slice(c, lz)
	local p = c.pend
	if p == nil then return end
	local base = lz * SLICE_BYTES
	local s = c.slices[lz + 1]
	local buf = self._buf
	local touched = false
	for i = 1, SLICE_BYTES do
		local v = p[base + i]
		if v ~= nil then
			buf[i] = v
			touched = true
		else
			buf[i] = byte(s, i)
		end
	end
	if not touched then return end
	c.slices[lz + 1] = char(tunpack(buf, 1, SLICE_BYTES))
	for i = 1, SLICE_BYTES do
		if p[base + i] ~= nil then
			p[base + i] = nil
			c.pend_n = c.pend_n - 1
		end
	end
	if c.pend_z then c.pend_z[lz] = nil end
	self.rebuilds = self.rebuilds + 1
end

--- Write one learned cell.
---@return boolean changed
function Slice:set(cx, cy, cz, v)
	local ccx, ccy = math.floor(cx / CHUNK_CELLS), math.floor(cy / CHUNK_CELLS)
	local k = ((ccx + 512) * 1024) + (ccy + 512)
	local c = self.chunks[k]
	if c == nil then
		c = self:ensure_chunk(ccx, ccy, self.def_zmin, self.def_zlev)
	end
	local lz = cz - c.zmin
	if lz < 0 or lz >= c.zlevels then return false end
	local off = (cy - c.by) * CHUNK_CELLS + (cx - c.bx)
	local sidx = lz * SLICE_BYTES + off

	local p = c.pend
	local cur
	if p ~= nil then cur = p[sidx] end
	if cur == nil then cur = byte(c.slices[lz + 1], off + 1) end
	if cur == v then return false end          -- already correct, nothing to learn

	if p == nil then p = {}; c.pend = p end
	if c.pend_z == nil then c.pend_z = {} end
	p[sidx] = v
	c.pend_n = c.pend_n + 1
	self.dirty[k] = true

	local n = (c.pend_z[lz] or 0) + 1
	if n >= self.COMPACT_MIN then
		self:compact_slice(c, lz)
	else
		c.pend_z[lz] = n
	end
	return true
end

--- Reassemble the whole chunk image (for saving).
function Slice:materialize(c)
	if c.pend and c.pend_n > 0 then
		for lz = 0, c.zlevels - 1 do self:compact_slice(c, lz) end
	end
	return table.concat(c.slices, "", 1, c.zlevels)
end

function Slice:pending_cells()
	local n = 0
	for _, c in pairs(self.chunks) do n = n + (c.pend_n or 0) end
	return n
end

return Slice
