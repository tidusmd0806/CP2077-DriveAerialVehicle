-- =============================================================================
-- TEMPORARY instrumentation for the residual autopilot freeze.
--
-- Everything is gated on Prof.enabled. To remove the probe entirely:
--   1. delete this file
--   2. delete the `require("Modules/profprobe.lua")` line in navigation.lua
--   3. grep for `PROBE(` in navigation.lua and drop those call sites
--
-- Runtime controls (CET console / config):
--   DAV.debug_profile_autopilot = false   -- stop measuring
--   DAV.debug_profile_warn_ms   = 8.0     -- per-call log threshold
--
-- Output:
--   * one line per call that crosses the threshold, with the autopilot context
--     captured at that moment (context strings are built lazily, so a quiet
--     run costs nothing beyond two clock reads)
--   * an aggregate table every Prof.summary_every seconds, worst section first
--
-- os.clock() is process CPU time on Windows. That is the right signal here: the
-- hitch is our own CPU burn on the game thread, not a wait we could overlap.
-- =============================================================================

local Prof = {}

Prof.enabled       = true
Prof.warn_ms       = 8.0
Prof.summary_every = 15.0

local sections = {}
local order    = {}
local last_summary = 0
local logger   = nil
local level    = "INFO"
local ctx_fn   = nil

--- Attach the mod logger. `record` is called as record(level, message).
function Prof.attach(record_fn, log_level)
	logger = record_fn
	if log_level ~= nil then level = log_level end
end

--- Register a global context provider: function returning a short one-line string
--- describing the current autopilot state. Only invoked when a call is slow.
function Prof.context(fn)
	ctx_fn = fn
end

local function clock_ms()
	return os.clock() * 1000.0
end

local function emit(msg)
	if logger == nil then return end
	pcall(logger, level, msg)
end

local function safe_ctx()
	if ctx_fn == nil then return "" end
	local ok, s = pcall(ctx_fn)
	if ok and type(s) == "string" then return " | " .. s end
	return ""
end

--- Aggregate summary of every section measured so far.
function Prof.dump(title)
	if #order == 0 then
		emit("[probe] no sections measured")
		return
	end
	-- worst by total CPU first: that is what actually steals frame time
	local names = {}
	for i, n in ipairs(order) do names[i] = n end
	table.sort(names, function(a, b) return sections[a].total > sections[b].total end)

	emit(string.format("===== PROBE SUMMARY %s =====", title or ""))
	emit(string.format("  %-26s %7s %9s %9s %8s %8s",
		"section", "calls", "total_ms", "avg_ms", "max_ms", ">=8ms"))
	for _, n in ipairs(names) do
		local s = sections[n]
		emit(string.format("  %-26s %7d %9.1f %9.3f %8.2f %8d",
			n, s.n, s.total, s.total / s.n, s.max, s.over))
	end
	emit("  ============================================")
end

function Prof.reset()
	sections = {}
	order = {}
	last_summary = 0
end

--- Render call arguments compactly for the warn line. Only called on slow calls,
--- so the cost of building the string is fine.
function Prof.fmt_args(...)
	local n = select("#", ...)
	if n == 0 then return "" end
	local parts = {}
	for i = 1, math.min(n, 4) do
		local v = select(i, ...)
		local t = type(v)
		if t == "number" then
			parts[#parts + 1] = string.format("%.1f", v)
		elseif t == "string" then
			parts[#parts + 1] = v
		elseif t == "table" then
			if v.x ~= nil and v.y ~= nil then
				parts[#parts + 1] = string.format("(%.0f,%.0f,%.0f)", v.x, v.y, v.z or 0)
			else
				parts[#parts + 1] = "tbl#" .. tostring(#v)
			end
		else
			parts[#parts + 1] = tostring(v)
		end
	end
	return " args=" .. table.concat(parts, " ")
end

--- Start a timed section. Returns the token to pass to Prof.finish.
function Prof.begin(name)
	if not Prof.enabled then return nil end
	return clock_ms()
end

--- Close a timed section.
---@param name string
---@param t0 number token from Prof.begin
---@param ctxfun optional function appended to the warn line
---@param ... forwarded to ctxfun, and only when the call is actually slow, so a
---          fast call allocates nothing. Lets callers pass `Prof.fmt_args, ...`
---          straight through instead of building a closure per call.
function Prof.finish(name, t0, ctxfun, ...)
	if not Prof.enabled or t0 == nil then return end
	local now = clock_ms()
	local ms = now - t0

	local s = sections[name]
	if s == nil then
		s = { name = name, n = 0, total = 0, max = 0, over = 0, max_ctx = nil }
		sections[name] = s
		order[#order + 1] = name
	end
	s.n = s.n + 1
	s.total = s.total + ms
	if ms >= Prof.warn_ms then s.over = s.over + 1 end

	if ms > s.max then
		s.max = ms
		local extra = ""
		if ctxfun ~= nil then
			local ok, s2 = pcall(ctxfun, ...)
			if ok and type(s2) == "string" then extra = " | " .. s2 end
		end
		s.max_ctx = extra
		-- Report anything that can visibly hitch the frame.
		if ms >= Prof.warn_ms then
			emit(string.format("[probe] %-24s %7.2f ms%s%s",
				name, ms, extra, safe_ctx()))
		end
	end

	-- Periodic aggregate, driven by whichever section happens to be running.
	if Prof.summary_every > 0 and (now - last_summary) >= Prof.summary_every * 1000.0 then
		last_summary = now
		Prof.dump("periodic")
	end
end

--- Time a function call in one line.
function Prof.call(name, fn, ctxfun)
	if not Prof.enabled then return fn() end
	local t0 = clock_ms()
	local a, b, c, d = fn()
	Prof.finish(name, t0, ctxfun)
	return a, b, c, d
end

--- Wrap a list of table methods so every call is timed, without editing bodies.
---
--- Doing this in one place keeps the probe a single grep away from removal and,
--- more importantly, means the instrumentation cannot perturb the logic being
--- investigated. The `calls` column of the summary is what matters for anything
--- individually cheap but called thousands of times per tick.
---@param tbl table the class table (methods looked up on it directly)
---@param targets table list of { method_name, probe_name }
---@return table names actually wrapped
function Prof.wrap_methods(tbl, targets)
	local wrapped = {}
	for _, t in ipairs(targets) do
		local mname, pname = t[1], t[2]
		local orig = tbl[mname]
		if type(orig) == "function" then
			tbl[mname] = function(self, ...)
				if not Prof.enabled then return orig(self, ...) end
				local t0 = clock_ms()
				local a, b, c, d, e = orig(self, ...)
				Prof.finish(pname, t0, Prof.fmt_args, ...)
				return a, b, c, d, e
			end
			wrapped[#wrapped + 1] = mname
		end
	end
	return wrapped
end

return Prof
