--!strict
--!native
-- Collide2D: narrow-phase contact generation for the planar solver.
--
-- Body shapes are "rounded segments": a capsule is a segment with a radius and a
-- circle is a capsule whose two ends coincide. World shapes are convex polygons
-- (the cross-sections of blocks, wedges and floors cut by the motion plane).
--
-- All results go into a small scratch buffer (no allocation per call):
--   Collide2D.count             number of points written
--   Collide2D.px[i], py[i]      contact point on the body shape's surface (world)
--   Collide2D.nx, ny            contact normal, pointing from the body shape into the world shape
--   Collide2D.sep[i]            separation along the normal (negative = overlapping)
--   Collide2D.id[i]             feature id, stable while the same features touch (warm starting)

export type Polygon = {
	count: number,
	-- local vertices (counter-clockwise) and outward edge normals
	lx: { number },
	ly: { number },
	lnx: { number },
	lny: { number },
	-- world-space cache (filled by Collide2D.updatePolygon)
	x: { number },
	y: { number },
	nx: { number },
	ny: { number },
	cx: number,
	cy: number,
	minX: number,
	minY: number,
	maxX: number,
	maxY: number,
}

local Collide2D = {}

local px = table.create(2, 0)
local py = table.create(2, 0)
local sepBuf = table.create(2, 0)
local idBuf = table.create(2, 0)
Collide2D.px = px
Collide2D.py = py
Collide2D.sep = sepBuf
Collide2D.id = idBuf
Collide2D.count = 0
Collide2D.nx = 0
Collide2D.ny = 0

local INF = math.huge
local sqrt = math.sqrt
local min = math.min
local max = math.max
local abs = math.abs

-- Builds a convex polygon from counter-clockwise local vertices {x1, y1, x2, y2, ...}.
function Collide2D.newPolygon(flat: { number }): Polygon
	local n = #flat // 2
	assert(n >= 3, "polygon needs at least 3 vertices")
	local lx, ly, lnx, lny = table.create(n, 0), table.create(n, 0), table.create(n, 0), table.create(n, 0)
	for i = 1, n do
		lx[i] = flat[2 * i - 1]
		ly[i] = flat[2 * i]
	end
	local area = 0
	for i = 1, n do
		local j = i % n + 1
		local ex, ey = lx[j] - lx[i], ly[j] - ly[i]
		local len = sqrt(ex * ex + ey * ey)
		assert(len > 1e-9, "degenerate polygon edge")
		lnx[i] = ey / len
		lny[i] = -ex / len
		area += lx[i] * ly[j] - lx[j] * ly[i]
	end
	assert(area > 0, "polygon vertices must be counter-clockwise")
	local poly: Polygon = {
		count = n,
		lx = lx,
		ly = ly,
		lnx = lnx,
		lny = lny,
		x = table.clone(lx),
		y = table.clone(ly),
		nx = table.clone(lnx),
		ny = table.clone(lny),
		cx = 0,
		cy = 0,
		minX = 0,
		minY = 0,
		maxX = 0,
		maxY = 0,
	}
	Collide2D.updatePolygon(poly, 0, 0, 1, 0)
	return poly
end

-- Axis-aligned box centred at (cx, cy) in local coordinates, optionally rotated.
function Collide2D.newBox(hw: number, hh: number, cx: number?, cy: number?, angle: number?): Polygon
	local ox, oy = cx or 0, cy or 0
	local c, s = math.cos(angle or 0), math.sin(angle or 0)
	local corners = { -hw, -hh, hw, -hh, hw, hh, -hw, hh }
	local flat = table.create(8, 0)
	for i = 1, 4 do
		local x, y = corners[2 * i - 1], corners[2 * i]
		flat[2 * i - 1] = ox + c * x - s * y
		flat[2 * i] = oy + s * x + c * y
	end
	return Collide2D.newPolygon(flat)
end

-- Recomputes world vertices/normals/AABB for a polygon attached to a body at (bx, by) with rotation (c, s).
function Collide2D.updatePolygon(p: Polygon, bx: number, by: number, c: number, s: number)
	local minX, minY, maxX, maxY = INF, INF, -INF, -INF
	local sx, sy = 0, 0
	for i = 1, p.count do
		local lx, ly = p.lx[i], p.ly[i]
		local x = bx + c * lx - s * ly
		local y = by + s * lx + c * ly
		p.x[i] = x
		p.y[i] = y
		local nx, ny = p.lnx[i], p.lny[i]
		p.nx[i] = c * nx - s * ny
		p.ny[i] = s * nx + c * ny
		sx += x
		sy += y
		if x < minX then
			minX = x
		end
		if x > maxX then
			maxX = x
		end
		if y < minY then
			minY = y
		end
		if y > maxY then
			maxY = y
		end
	end
	p.cx = sx / p.count
	p.cy = sy / p.count
	p.minX, p.minY, p.maxX, p.maxY = minX, minY, maxX, maxY
end

-- Closest points between segments P1Q1 and P2Q2 (Ericson, "Real-Time Collision Detection" 5.1.9).
-- Returns (c1x, c1y, c2x, c2y, dist²).
local function closestSegSeg(
	p1x: number,
	p1y: number,
	q1x: number,
	q1y: number,
	p2x: number,
	p2y: number,
	q2x: number,
	q2y: number
): (number, number, number, number, number)
	local d1x, d1y = q1x - p1x, q1y - p1y
	local d2x, d2y = q2x - p2x, q2y - p2y
	local rx, ry = p1x - p2x, p1y - p2y
	local a = d1x * d1x + d1y * d1y
	local e = d2x * d2x + d2y * d2y
	local f = d2x * rx + d2y * ry
	local s, t
	local EPS = 1e-12
	if a <= EPS and e <= EPS then
		s, t = 0, 0
	elseif a <= EPS then
		s = 0
		t = math.clamp(f / e, 0, 1)
	else
		local c = d1x * rx + d1y * ry
		if e <= EPS then
			t = 0
			s = math.clamp(-c / a, 0, 1)
		else
			local b = d1x * d2x + d1y * d2y
			local denom = a * e - b * b
			if denom ~= 0 then
				s = math.clamp((b * f - c * e) / denom, 0, 1)
			else
				s = 0
			end
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = math.clamp(-c / a, 0, 1)
			elseif t > 1 then
				t = 1
				s = math.clamp((b - c) / a, 0, 1)
			end
		end
	end
	local c1x, c1y = p1x + d1x * s, p1y + d1y * s
	local c2x, c2y = p2x + d2x * t, p2y + d2y * t
	local dx, dy = c2x - c1x, c2y - c1y
	return c1x, c1y, c2x, c2y, dx * dx + dy * dy
end
Collide2D.closestSegSeg = closestSegSeg

-- Clips the rounded segment AB against polygon edge `e` (used for face contacts).
-- Writes up to two points. Returns the number written.
local function clipToFace(
	ax: number,
	ay: number,
	bx: number,
	by: number,
	r: number,
	poly: Polygon,
	e: number,
	spec: number
): number
	local n = poly.count
	local j = e % n + 1
	local v1x, v1y = poly.x[e], poly.y[e]
	local v2x, v2y = poly.x[j], poly.y[j]
	local enx, eny = poly.nx[e], poly.ny[e]
	local tx, ty = v2x - v1x, v2y - v1y
	local L = sqrt(tx * tx + ty * ty)
	tx /= L
	ty /= L
	local tA = (ax - v1x) * tx + (ay - v1y) * ty
	local tB = (bx - v1x) * tx + (by - v1y) * ty
	local lo, hi
	if abs(tB - tA) > 1e-9 then
		local l0 = (0 - tA) / (tB - tA)
		local l1 = (L - tA) / (tB - tA)
		lo = max(0, min(l0, l1))
		hi = min(1, max(l0, l1))
		if lo > hi then
			return 0
		end
	else
		if tA < 0 or tA > L then
			return 0
		end
		lo, hi = 0, 1
	end
	local dx, dy = bx - ax, by - ay
	local count = 0
	Collide2D.nx = -enx
	Collide2D.ny = -eny
	for k = 1, 2 do
		local lam = if k == 1 then lo else hi
		if k == 2 and (hi - lo) * sqrt(dx * dx + dy * dy) < 1e-6 then
			break -- both clip points coincide (circle or perpendicular segment)
		end
		local qx, qy = ax + dx * lam, ay + dy * lam
		local sep = enx * (qx - v1x) + eny * (qy - v1y) - r
		if sep <= spec then
			count += 1
			px[count] = qx - enx * r
			py[count] = qy - eny * r
			sepBuf[count] = sep
			idBuf[count] = e * 4 + k
		end
	end
	return count
end

-- Rounded segment (capsule; a circle when A == B) against a convex polygon (world cache must be current).
-- Returns the number of contact points written to the scratch buffer.
function Collide2D.capsulePolygon(
	ax: number,
	ay: number,
	bx: number,
	by: number,
	r: number,
	poly: Polygon,
	spec: number
): number
	Collide2D.count = 0
	local n = poly.count
	local limit = r + spec

	-- 1. Separating axis over the polygon's edge normals.
	local bestSep, bestEdge = -INF, 1
	for i = 1, n do
		local nx, ny = poly.nx[i], poly.ny[i]
		local vx, vy = poly.x[i], poly.y[i]
		local sA = nx * (ax - vx) + ny * (ay - vy)
		local sB = nx * (bx - vx) + ny * (by - vy)
		local s = if sA < sB then sA else sB
		if s > bestSep then
			bestSep = s
			bestEdge = i
		end
	end
	if bestSep > limit then
		return 0
	end

	-- 2. Separating axis along the segment's own normal.
	local dx, dy = bx - ax, by - ay
	local len2 = dx * dx + dy * dy
	local segSep = -INF
	if len2 > 1e-12 then
		local len = sqrt(len2)
		local ux, uy = -dy / len, dx / len
		if ux * (poly.cx - ax) + uy * (poly.cy - ay) < 0 then
			ux, uy = -ux, -uy
		end
		local minProj = INF
		for i = 1, n do
			local p = ux * (poly.x[i] - ax) + uy * (poly.y[i] - ay)
			if p < minProj then
				minProj = p
			end
		end
		segSep = minProj
		if segSep > limit then
			return 0
		end
	end

	if bestSep > 0 or segSep > 0 then
		-- 3a. Core segment is outside the polygon: exact closest points.
		local bestD2, sx, sy, qx, qy, closeEdge = INF, 0, 0, 0, 0, 1
		for i = 1, n do
			local j = i % n + 1
			local c1x, c1y, c2x, c2y, d2 =
				closestSegSeg(ax, ay, bx, by, poly.x[i], poly.y[i], poly.x[j], poly.y[j])
			if d2 < bestD2 then
				bestD2, sx, sy, qx, qy, closeEdge = d2, c1x, c1y, c2x, c2y, i
			end
		end
		local d = sqrt(bestD2)
		if d > limit then
			return 0
		end
		local nx, ny
		if d > 1e-9 then
			nx, ny = (qx - sx) / d, (qy - sy) / d
		else
			nx, ny = -poly.nx[bestEdge], -poly.ny[bestEdge]
		end
		-- Face region: the closest feature is an edge interior -> clip for a (possibly) two-point manifold.
		local faceEdge, faceDot = 0, -INF
		for i = 1, n do
			local dot = -(poly.nx[i] * nx + poly.ny[i] * ny)
			if dot > faceDot then
				faceDot = dot
				faceEdge = i
			end
		end
		if faceDot > 0.9995 then
			local c = clipToFace(ax, ay, bx, by, r, poly, faceEdge, spec)
			if c > 0 then
				Collide2D.count = c
				return c
			end
		end
		-- Vertex region (or clip fallback): single point along the closest direction.
		Collide2D.nx, Collide2D.ny = nx, ny
		px[1] = sx + nx * r
		py[1] = sy + ny * r
		sepBuf[1] = d - r
		idBuf[1] = closeEdge * 4 + 3
		Collide2D.count = 1
		return 1
	end

	-- 3b. Core segment penetrates the polygon: use the least-penetrating face.
	local c = clipToFace(ax, ay, bx, by, r, poly, bestEdge, spec)
	if c == 0 then
		-- Segment extends beyond the face on both sides of its span (rare): deepest endpoint.
		local enx, eny = poly.nx[bestEdge], poly.ny[bestEdge]
		local vx, vy = poly.x[bestEdge], poly.y[bestEdge]
		local sA = enx * (ax - vx) + eny * (ay - vy)
		local sB = enx * (bx - vx) + eny * (by - vy)
		local qx, qy, s = ax, ay, sA
		if sB < sA then
			qx, qy, s = bx, by, sB
		end
		Collide2D.nx, Collide2D.ny = -enx, -eny
		px[1] = qx - enx * r
		py[1] = qy - eny * r
		sepBuf[1] = s - r
		idBuf[1] = bestEdge * 4 + 3
		c = 1
	end
	Collide2D.count = c
	return c
end

return Collide2D
