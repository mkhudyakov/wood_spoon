extends RefCounted
## The piece of wood being carved: half a split log, 230 mm long, as a voxel solid.
## Grain runs along X. The flat split face is on top (z = 32), the bark below.
##
## Each voxel (0.5 mm) stores three bytes: how solid it is, the tool mark of the
## cut that exposed it, and how much oil has soaked in. Every cut is written as an
## exact surface (fractional solidity), so facets come out flat and crisp.

const RES := 0.5
const MG := 2
const LEN := 230.0
const WID := 64.0
const HGT := 34.0
const TOP := 32.0          # height of the split face
const RAD := 32.0          # log radius
const CY := 32.0           # centre line of the billet (and of the spoon)
const END0 := 2.0          # sawn ends of the billet
const END1 := 228.0

# tool marks (stored x 40 in the green channel)
const F_BARK := 0
const F_SPLIT := 1
const F_SAW := 2
const F_AXE := 3
const F_KNIFE := 4
const F_TORN := 5
const F_SAND := 6

var nx := 0
var ny := 0
var nz := 0
var cols := 9
var rows := 8
var aw := 0
var ah := 0
var rowstride := 0
var vox := PackedByteArray()
var cbase := PackedInt32Array()

# the spoon we are aiming for, sampled at 1 mm: 0 waste, 1 spoon, 2 hollow of the bowl
var mask := PackedByteArray()
var mx := 230
var my := 64
var mz := 34

# running totals, in voxels (1 voxel = 0.125 mm^3)
var waste := 0          # wood outside the spoon that is still there
var cavity := 0         # wood still filling the bowl
var over := 0           # spoon wood that has been cut away
var solid := 0
var dirty := true
var broken := false

# solid voxels per 4 mm cell: lets the renderer skip empty space
var cx := 0
var cy := 0
var cz := 0
var ccount := PackedInt32Array()


func _init() -> void:
	nx = int(LEN / RES) + MG * 2
	ny = int(WID / RES) + MG * 2
	nz = int(HGT / RES) + MG * 2
	rows = int(ceil(float(nz) / cols))
	aw = cols * nx
	ah = rows * ny
	rowstride = aw * 3
	cx = (nx + 7) >> 3
	cy = (ny + 7) >> 3
	cz = (nz + 7) >> 3
	cbase.resize(nz)
	for c in nz:
		@warning_ignore("integer_division")
		cbase[c] = (c / cols) * ny * rowstride + (c % cols) * nx * 3


# ---------------------------------------------------------------- the target spoon

static func _sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 0 = waste wood, 1 = the spoon, 2 = the hollow of the bowl. Mirrors the shader.
static func target(x: float, y: float, z: float) -> int:
	if z > TOP:
		return 0
	var dy := y - CY
	var dz := TOP - z
	var ex := (x - 40.0) / 34.5
	var ey := dy / 20.5
	var ez := dz / 12.5
	if ex * ex + ey * ey + ez * ez < 1.0:
		return 2
	ex = (x - 40.0) / 38.0
	ey = dy / 24.0
	ez = dz / 16.0
	if ex * ex + ey * ey + ez * ez < 1.0:
		return 1
	if x >= 62.0 and x <= 222.0:
		var wy := 6.0 + 5.0 * exp(-pow((x - 62.0) / 12.0, 2.0)) + 3.5 * _sstep(110.0, 215.0, x)
		var th := 4.5 + 3.0 * exp(-pow((x - 62.0) / 10.0, 2.0))
		var zc := TOP - th
		var e := 0.0
		if x > 212.0:
			e = pow((x - 212.0) / 10.0, 2.6)
		if pow(absf(dy) / wy, 2.6) + pow(absf(z - zc) / th, 2.6) + e < 1.0:
			return 1
	return 0


func _build_mask() -> Array:
	mask.resize(mx * my * mz)
	var nb := 0
	var ncv := 0
	for k in mz:
		for j in my:
			var base := (k * my + j) * mx
			for i in mx:
				var t := target(i + 0.5, j + 0.5, k + 0.5)
				mask[base + i] = t
				if t == 1:
					nb += 1
				elif t == 2:
					ncv += 1
	return [nb, ncv]


## A fresh billet: half a log, split face up, bark underneath.
func new_billet() -> void:
	var counts: Array = [0, 0]
	if mask.is_empty():
		counts = _build_mask()
	else:
		for v in mask:
			if v == 1:
				counts[0] += 1
			elif v == 2:
				counts[1] += 1
	vox.resize(aw * ah * 3)
	vox.fill(0)
	ccount.resize(cx * cy * cz)
	ccount.fill(0)
	solid = 0
	for c in nz:
		var z := (c - MG + 0.5) * RES
		for b in ny:
			var y := (b - MG + 0.5) * RES
			var r := sqrt((y - CY) * (y - CY) + (z - TOP) * (z - TOP))
			var s_round := r - RAD
			var s_top := z - TOP
			var sd := maxf(s_round, s_top)
			var fin := F_BARK if s_round > s_top else F_SPLIT
			var i := cbase[c] + b * rowstride
			for a in nx:
				var x := (a - MG + 0.5) * RES
				var sx := maxf(END0 - x, x - END1)
				var d := sd
				var f := fin
				if sx > d:
					d = sx
					f = F_SAW
				var dn := int(clampf(0.5 - d / RES, 0.0, 1.0) * 255.0)
				vox[i] = dn
				vox[i + 1] = f * 40
				if dn >= 128:
					solid += 1
					ccount[((c >> 3) * cy + (b >> 3)) * cx + (a >> 3)] += 1
				i += 3
	cavity = int(counts[1]) * 8
	waste = solid - (int(counts[0]) + int(counts[1])) * 8
	over = 0
	broken = false
	dirty = true


func snapshot() -> Dictionary:
	return {"vox": vox.duplicate(), "ccount": ccount.duplicate(), "waste": waste, "cavity": cavity, "over": over, "solid": solid}


func restore(s: Dictionary) -> void:
	vox = (s.vox as PackedByteArray).duplicate()
	ccount = (s.ccount as PackedInt32Array).duplicate()
	waste = s.waste
	cavity = s.cavity
	over = s.over
	solid = s.solid
	broken = false
	dirty = true


## One byte per 4 mm cell: 255 where there is wood in the cell or right next to it.
func coarse_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(cx * cz * cy)
	out.fill(0)
	for k in cz:
		for j in cy:
			for i in cx:
				if ccount[(k * cy + j) * cx + i] <= 0:
					continue
				for dk in range(maxi(k - 1, 0), mini(k + 2, cz)):
					for dj in range(maxi(j - 1, 0), mini(j + 2, cy)):
						for di in range(maxi(i - 1, 0), mini(i + 2, cx)):
							out[dj * (cx * cz) + dk * cx + di] = 255
	return out


# ---------------------------------------------------------------- queries

func _mask_at(a: int, b: int, c: int) -> int:
	var i := (a - MG) >> 1
	var j := (b - MG) >> 1
	var k := (c - MG) >> 1
	if i < 0 or j < 0 or k < 0 or i >= mx or j >= my or k >= mz:
		return 0
	return mask[(k * my + j) * mx + i]


func _gone(a: int, b: int, c: int) -> void:
	solid -= 1
	ccount[((c >> 3) * cy + (b >> 3)) * cx + (a >> 3)] -= 1
	var m := _mask_at(a, b, c)
	if m == 0:
		waste -= 1
	elif m == 1:
		over += 1
	else:
		cavity -= 1


func dens_i(a: int, b: int, c: int) -> int:
	if a < 0 or b < 0 or c < 0 or a >= nx or b >= ny or c >= nz:
		return 0
	return vox[cbase[c] + b * rowstride + a * 3]


## Solidity (0..1) at a point, trilinear.
func dens(p: Vector3) -> float:
	var gx := p.x / RES + MG - 0.5
	var gy := p.y / RES + MG - 0.5
	var gz := p.z / RES + MG - 0.5
	var a := int(floor(gx))
	var b := int(floor(gy))
	var c := int(floor(gz))
	var fx := gx - a
	var fy := gy - b
	var fz := gz - c
	var d000 := dens_i(a, b, c)
	var d100 := dens_i(a + 1, b, c)
	var d010 := dens_i(a, b + 1, c)
	var d110 := dens_i(a + 1, b + 1, c)
	var d001 := dens_i(a, b, c + 1)
	var d101 := dens_i(a + 1, b, c + 1)
	var d011 := dens_i(a, b + 1, c + 1)
	var d111 := dens_i(a + 1, b + 1, c + 1)
	var x00 := lerpf(d000, d100, fx)
	var x10 := lerpf(d010, d110, fx)
	var x01 := lerpf(d001, d101, fx)
	var x11 := lerpf(d011, d111, fx)
	return lerpf(lerpf(x00, x10, fy), lerpf(x01, x11, fy), fz) / 255.0


## Outward surface normal near p.
func normal_at(p: Vector3) -> Vector3:
	var e := 0.8
	var n := Vector3(
		dens(p - Vector3(e, 0, 0)) - dens(p + Vector3(e, 0, 0)),
		dens(p - Vector3(0, e, 0)) - dens(p + Vector3(0, e, 0)),
		dens(p - Vector3(0, 0, e)) - dens(p + Vector3(0, 0, e)))
	if n.length() < 1e-5:
		return Vector3.UP
	return n.normalized()


func attr_at(p: Vector3) -> Vector2i:
	var a := clampi(int(floor(p.x / RES)) + MG, 0, nx - 1)
	var b := clampi(int(floor(p.y / RES)) + MG, 0, ny - 1)
	var c := clampi(int(floor(p.z / RES)) + MG, 0, nz - 1)
	var i := cbase[c] + b * rowstride + a * 3
	@warning_ignore("integer_division")
	return Vector2i(vox[i + 1] / 40, vox[i + 2])


## First surface point along a ray (piece coordinates). {} when the ray misses.
func raycast(ro: Vector3, rd: Vector3) -> Dictionary:
	var inv := Vector3(1.0 / rd.x if absf(rd.x) > 1e-9 else 1e9, 1.0 / rd.y if absf(rd.y) > 1e-9 else 1e9, 1.0 / rd.z if absf(rd.z) > 1e-9 else 1e9)
	var lo := Vector3(-1, -1, -1)
	var hi := Vector3(LEN + 1, WID + 1, HGT + 1)
	var ta := (lo - ro) * inv
	var tb := (hi - ro) * inv
	var t0 := maxf(maxf(minf(ta.x, tb.x), minf(ta.y, tb.y)), maxf(minf(ta.z, tb.z), 0.0))
	var t1 := minf(minf(maxf(ta.x, tb.x), maxf(ta.y, tb.y)), maxf(ta.z, tb.z))
	if t1 <= t0:
		return {}
	var t := t0
	var stp := 0.4
	while t < t1:
		if dens(ro + rd * t) > 0.5:
			var a := t - stp
			var b := t
			for i in 6:
				var m := (a + b) * 0.5
				if dens(ro + rd * m) > 0.5:
					b = m
				else:
					a = m
			var p := ro + rd * b
			return {"p": p, "n": normal_at(p), "t": b}
		t += stp
	return {}


## Thickness of wood under a surface point (how far until daylight on the other side).
func thickness(p: Vector3, n: Vector3) -> float:
	var t := 0.4
	while t < 60.0:
		if dens(p - n * t) < 0.5:
			return t
		t += 0.25
	return 60.0


## Smallest cross-section (mm^2) between two X positions: tells when the spoon is about to snap.
func min_section(x0: float, x1: float) -> float:
	var a0 := clampi(int(x0 / RES) + MG, 0, nx - 1)
	var a1 := clampi(int(x1 / RES) + MG, 0, nx - 1)
	var best := 1e9
	var a := a0
	while a <= a1:
		var n := 0
		for c in nz:
			var i := cbase[c] + a * 3
			for b in ny:
				if vox[i] >= 128:
					n += 1
				i += rowstride
		best = minf(best, n * RES * RES)
		a += 2
	return best


# ---------------------------------------------------------------- cutting

## Saw: a 1.4 mm kerf in any plane. The blade enters at surface point p, lies along `along`
## (it is long: it spans the piece) and goes `depth` mm into the wood in direction `into`.
## `prev` is the depth already sawn in this cut (only the new part is worked).
func saw_cut(p: Vector3, along: Vector3, into: Vector3, depth: float, prev := 0.0) -> float:
	var d := into.normalized()
	var m := along.cross(d)
	if m.length() < 0.2:
		return 0.0
	m = m.normalized()
	var hw := 0.7
	var g_lo := prev - 1.0 if prev > 0.0 else -1000.0
	var g_hi := depth + RES * 0.5
	var removed := 0
	for c in nz:
		var dz := (c - MG + 0.5) * RES - p.z
		for b in ny:
			var dy := (b - MG + 0.5) * RES - p.y
			var fm := dy * m.y + dz * m.z        # distance from the kerf plane, at x = p.x
			var gd := dy * d.y + dz * d.z        # depth under the entry point, at x = p.x
			# the stretch of this row that lies inside the kerf and in the newly sawn depth
			var x0 := -1000.0
			var x1 := 1000.0
			if absf(m.x) > 0.001:
				var u0 := (-hw - RES - fm) / m.x
				var u1 := (hw + RES - fm) / m.x
				x0 = maxf(x0, minf(u0, u1))
				x1 = minf(x1, maxf(u0, u1))
			elif absf(fm) > hw + RES:
				continue
			if absf(d.x) > 0.001:
				var v0 := (g_lo - gd) / d.x
				var v1 := (g_hi - gd) / d.x
				x0 = maxf(x0, minf(v0, v1))
				x1 = minf(x1, maxf(v0, v1))
			elif gd < g_lo or gd > g_hi:
				continue
			if x0 > x1:
				continue
			var a0 := clampi(int((p.x + x0) / RES) + MG - 1, 0, nx - 1)
			var a1 := clampi(int((p.x + x1) / RES) + MG + 1, 0, nx - 1)
			var base := cbase[c] + b * rowstride
			for a in range(a0, a1 + 1):
				var dx := (a - MG + 0.5) * RES - p.x
				var inside := minf(hw - absf(fm + dx * m.x), depth - (gd + dx * d.x))
				if inside < -RES * 0.5:
					continue
				var nd := int(clampf(0.5 - inside / RES, 0.0, 1.0) * 255.0)
				var i := base + a * 3
				var od := vox[i]
				vox[i + 1] = F_SAW * 40
				if nd < od:
					vox[i] = nd
					if od >= 128 and nd < 128:
						_gone(a, b, c)
						removed += 1
	dirty = true
	return removed * RES * RES * RES


## After sawing: every piece no longer joined to the main one falls away. The piece that
## holds the most of the spoon stays on the bench. Returns the volume that fell, mm^3.
func drop_offcuts() -> float:
	var n := mx * my * mz
	var lab := PackedByteArray()
	lab.resize(n)
	var stack := PackedInt32Array()
	stack.resize(n)
	var spoon_in: Array = [0]
	var size_in: Array = [0]
	var comps := 0
	var sxy := mx * my
	for start in n:
		if lab[start] != 0:
			continue
		var k0 := start / sxy
		var j0 := (start - k0 * sxy) / mx
		var i0 := start - k0 * sxy - j0 * mx
		if vox[cbase[k0 * 2 + MG] + (j0 * 2 + MG) * rowstride + (i0 * 2 + MG) * 3] < 128:
			continue
		if comps >= 250:
			break
		comps += 1
		var sp := 0
		var cnt := 0
		var top := 0
		stack[0] = start
		top = 1
		lab[start] = comps
		while top > 0:
			top -= 1
			var q := stack[top]
			cnt += 1
			if mask[q] == 1:
				sp += 1
			var k := q / sxy
			var j := (q - k * sxy) / mx
			var i := q - k * sxy - j * mx
			for e in 6:
				var qi := i
				var qj := j
				var qk := k
				if e == 0:
					qi -= 1
				elif e == 1:
					qi += 1
				elif e == 2:
					qj -= 1
				elif e == 3:
					qj += 1
				elif e == 4:
					qk -= 1
				else:
					qk += 1
				if qi < 0 or qj < 0 or qk < 0 or qi >= mx or qj >= my or qk >= mz:
					continue
				var nq := (qk * my + qj) * mx + qi
				if lab[nq] != 0:
					continue
				if vox[cbase[qk * 2 + MG] + (qj * 2 + MG) * rowstride + (qi * 2 + MG) * 3] < 128:
					continue
				lab[nq] = comps
				stack[top] = nq
				top += 1
		spoon_in.append(sp)
		size_in.append(cnt)
	if comps < 2:
		return 0.0
	var keep := 1
	for cI in range(2, comps + 1):
		if int(spoon_in[cI]) > int(spoon_in[keep]) or (int(spoon_in[cI]) == int(spoon_in[keep]) and int(size_in[cI]) > int(size_in[keep])):
			keep = cI
	var before := solid
	var near := {}        # empty-looking cells next to a fallen one: they may hold slivers
	for q in n:
		var l := lab[q]
		if l == 0 or l == keep:
			continue
		var k := q / sxy
		var j := (q - k * sxy) / mx
		var i := q - k * sxy - j * mx
		for dc in 2:
			for db in 2:
				for da in 2:
					var a := i * 2 + MG + da
					var b := j * 2 + MG + db
					var c := k * 2 + MG + dc
					var vi := cbase[c] + b * rowstride + a * 3
					if vox[vi] >= 128:
						_gone(a, b, c)
					vox[vi] = 0
		for e in 6:
			var qi := i + (1 if e == 1 else (-1 if e == 0 else 0))
			var qj := j + (1 if e == 3 else (-1 if e == 2 else 0))
			var qk := k + (1 if e == 5 else (-1 if e == 4 else 0))
			if qi < 0 or qj < 0 or qk < 0 or qi >= mx or qj >= my or qk >= mz:
				continue
			var nq := (qk * my + qj) * mx + qi
			if lab[nq] == 0:
				near[nq] = true
	# slivers left beside the kerf on the side that fell
	for q in near:
		var k: int = q / sxy
		var j: int = (q - k * sxy) / mx
		var i: int = q - k * sxy - j * mx
		for pass_i in 2:
			for dc in 2:
				for db in 2:
					for da in 2:
						var a := i * 2 + MG + da
						var b := j * 2 + MG + db
						var c := k * 2 + MG + dc
						var vi := cbase[c] + b * rowstride + a * 3
						if vox[vi] == 0:
							continue
						# the neighbour outside this cell, along each axis
						var oa := a + (1 if da == 1 else -1)
						var ob := b + (1 if db == 1 else -1)
						var oc := c + (1 if dc == 1 else -1)
						var gone := false
						for e in 3:
							var ni := i + ((1 if da == 1 else -1) if e == 0 else 0)
							var nj := j + ((1 if db == 1 else -1) if e == 1 else 0)
							var nk := k + ((1 if dc == 1 else -1) if e == 2 else 0)
							if ni < 0 or nj < 0 or nk < 0 or ni >= mx or nj >= my or nk >= mz:
								continue
							var nl := lab[(nk * my + nj) * mx + ni]
							if nl != 0 and nl != keep:
								gone = true
						if not gone and pass_i == 1:
							# joined only to a voxel of this cell that has just gone
							var inner := 0
							inner += vox[cbase[c] + b * rowstride + (a + (-1 if da == 1 else 1)) * 3]
							inner += vox[cbase[c] + (b + (-1 if db == 1 else 1)) * rowstride + a * 3]
							inner += vox[cbase[c + (-1 if dc == 1 else 1)] + b * rowstride + a * 3]
							var outer := 0
							outer += vox[cbase[c] + b * rowstride + oa * 3]
							outer += vox[cbase[c] + ob * rowstride + a * 3]
							outer += vox[cbase[oc] + b * rowstride + a * 3]
							gone = inner == 0 and outer == 0
						if gone:
							if vox[vi] >= 128:
								_gone(a, b, c)
							vox[vi] = 0
	dirty = true
	return (before - solid) * RES * RES * RES


static func _hash(a: int, b: int, c: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	return float(h & 1023) / 1023.0


## Knife (hook_r = 0) or hook knife (hook_r = radius of its curve): one slicing stroke
## from surface point A to surface point B. Everything above the chord goes, plus a
## shaving up to `bite` mm thick in the middle of the stroke. Where the stroke climbs
## against the grain the fibres tear instead of cutting.
## tear_k: 1 = sharp knife in kind wood; larger = duller or harder.
const PROF_N := 24


## The blade rides on the wood: feel the surface under the stroke A-B, then take a shaving off it.
## Returns the height of the cut above the straight line A-B at PROF_N+1 stations,
## k (how far the wood bulges above that line, mm; negative in a hollow) and the highest point.
func _profile(pa: Vector3, cd: Vector3, ln: float, nc: Vector3, bite: float, hook_r: float) -> Dictionary:
	var surf := PackedFloat32Array()
	surf.resize(PROF_N + 1)
	var hit := PackedByteArray()
	hit.resize(PROF_N + 1)
	var num := 0.0
	var den := 0.0
	var top := 0.0
	for i in PROF_N + 1:
		var sn := float(i) / PROF_N
		var hh: Dictionary = raycast(pa + cd * (ln * sn) + nc * 16.0, -nc)
		if not hh.is_empty() and float(hh.t) < 24.0:
			var hv := 16.0 - float(hh.t)
			surf[i] = hv
			hit[i] = 1
			var g := 4.0 * sn * (1.0 - sn)
			num += hv * g
			den += g * g
			top = maxf(top, hv)
	var k := 0.0
	if den > 0.5:
		k = clampf(num / den, -12.0 if hook_r > 0.0 else -3.0, 12.0)
	var cutp := PackedFloat32Array()
	cutp.resize(PROF_N + 1)
	for i in PROF_N + 1:
		var sn := float(i) / PROF_N
		var g := 4.0 * sn * (1.0 - sn)
		var cv := (k - bite) * g
		if hit[i] == 1:
			cv = maxf(cv, surf[i] - bite * g - 0.25)     # a blade takes only so much in one pass
		cutp[i] = cv
	return {"cut": cutp, "k": k, "top": top}


## How badly each part of the stroke runs against the grain (0 clean .. 1 torn).
## The fibres run along X: the cut tears wherever the blade climbs along them.
func _tear(cd: Vector3, nc: Vector3, ln: float, k: float, bite: float, tear_k: float) -> PackedFloat32Array:
	var tear := PackedFloat32Array()
	tear.resize(PROF_N)
	for i in PROF_N:
		var sn := (i + 0.5) / PROF_N
		var slope := (k - bite) * 4.0 * (1.0 - 2.0 * sn) / ln
		var ns := (nc - cd * slope).normalized()
		var u := -cd.x * ns.x
		tear[i] = clampf((u - 0.055 / tear_k) * 9.0 * tear_k, 0.0, 1.0)
	return tear


## Before the cut: what share of a stroke A-B would tear (0 = clean all the way).
func grain(pa: Vector3, pb: Vector3, n: Vector3, bite: float, hook_r: float, tear_k: float) -> float:
	var chord := pb - pa
	var ln := chord.length()
	if ln < 1.0:
		return 0.0
	var cd := chord / ln
	var bl := n.cross(cd)
	if bl.length() < 0.05:
		return 0.0
	var nc := cd.cross(bl.normalized()).normalized()
	if nc.dot(n) < 0.0:
		nc = -nc
	var pr := _profile(pa, cd, ln, nc, bite, hook_r)
	var tear := _tear(cd, nc, ln, float(pr.k), bite, tear_k)
	var bad := 0
	for i in PROF_N:
		if tear[i] > 0.25:
			bad += 1
	return float(bad) / PROF_N


## Returns {vol (mm^3), torn (0..1 share of the stroke that tore), uphill (worst slope against the grain)}.
func knife_cut(pa: Vector3, pb: Vector3, n: Vector3, bite: float, width: float, hook_r: float, tear_k: float) -> Dictionary:
	var chord := pb - pa
	var ln := chord.length()
	if ln < 1.0:
		return {"vol": 0.0, "torn": 0.0, "uphill": 0.0}
	var cd := chord / ln
	var bl := n.cross(cd)
	if bl.length() < 0.05:
		return {"vol": 0.0, "torn": 0.0, "uphill": 0.0}
	bl = bl.normalized()
	var nc := cd.cross(bl).normalized()
	if nc.dot(n) < 0.0:
		nc = -nc
	var hw := width * 0.5
	var pr := _profile(pa, cd, ln, nc, bite, hook_r)
	var cutp: PackedFloat32Array = pr.cut
	var k: float = pr.k
	var hmax: float = bite + 8.0 + float(pr.top)
	var ST := PROF_N
	var nbins := PROF_N
	var tear := _tear(cd, nc, ln, k, bite, tear_k)
	var worst := 0.0
	for i in nbins:
		worst = maxf(worst, tear[i])
	# bounding box of the stroke
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for sx in [0.0, ln]:
		for sw in [-hw, hw]:
			for sh in [minf(k, 0.0) - bite - 1.5, hmax]:
				var q: Vector3 = pa + cd * sx + bl * sw + nc * sh
				lo = lo.min(q)
				hi = hi.max(q)
	var a0 := clampi(int(lo.x / RES) + MG, 0, nx - 1)
	var a1 := clampi(int(hi.x / RES) + MG + 1, 0, nx - 1)
	var b0 := clampi(int(lo.y / RES) + MG, 0, ny - 1)
	var b1 := clampi(int(hi.y / RES) + MG + 1, 0, ny - 1)
	var c0 := clampi(int(lo.z / RES) + MG, 0, nz - 1)
	var c1 := clampi(int(hi.z / RES) + MG + 1, 0, nz - 1)
	var removed := 0
	var torn_n := 0
	var cut_n := 0
	var r2 := hook_r * hook_r
	for c in range(c0, c1 + 1):
		var qz := (c - MG + 0.5) * RES - pa.z
		for b in range(b0, b1 + 1):
			var qy := (b - MG + 0.5) * RES - pa.y
			var sy := qy * cd.y + qz * cd.z
			var wy := qy * bl.y + qz * bl.z
			var hy := qy * nc.y + qz * nc.z
			var base := cbase[c] + b * rowstride
			for a in range(a0, a1 + 1):
				var qx := (a - MG + 0.5) * RES - pa.x
				var s := sy + qx * cd.x
				if s < 0.0 or s > ln:
					continue
				var w := wy + qx * bl.x
				if w > hw or w < -hw:
					continue
				var sn := s / ln
				var fi := sn * ST
				var i0 := mini(int(fi), ST - 1)
				var h := hy + qx * nc.x - lerpf(cutp[i0], cutp[i0 + 1], fi - i0)
				if hook_r > 0.0:
					h -= hook_r - sqrt(maxf(r2 - w * w, 0.0))
				if h < -RES or h > hmax:
					continue
				var i := base + a * 3
				var od := vox[i]
				var tr := tear[mini(int(sn * nbins), nbins - 1)]
				var fin := F_KNIFE
				if tr > 0.0 and od > 0:
					h += tr * _hash(a, b, c) * 1.1
					if tr > 0.25:
						fin = F_TORN
				var nd := int(clampf(0.5 - h / RES, 0.0, 1.0) * 255.0)
				if nd < od:
					vox[i] = nd
					vox[i + 1] = fin * 40
					cut_n += 1
					if fin == F_TORN:
						torn_n += 1
					if od >= 128 and nd < 128:
						_gone(a, b, c)
						removed += 1
				elif od < 128 and h < 1.5 and h > -RES:
					vox[i + 1] = fin * 40
	dirty = true
	return {"vol": removed * RES * RES * RES, "torn": float(torn_n) / maxf(cut_n, 1.0), "uphill": worst}


## Is a stroke from A to B (surface normal n) with or against the grain? > 0.055 tears.
static func uphill(pa: Vector3, pb: Vector3, n: Vector3) -> float:
	var chord := pb - pa
	var ln := chord.length()
	if ln < 0.5:
		return 0.0
	var cd := chord / ln
	var bl := n.cross(cd)
	if bl.length() < 0.05:
		return 0.0
	var nc := cd.cross(bl.normalized()).normalized()
	if nc.dot(n) < 0.0:
		nc = -nc
	return -cd.x * nc.x


## Sandpaper: rubs the surface down a little and levels the facets around p.
func sand(p: Vector3, radius: float) -> void:
	var a0 := clampi(int((p.x - radius) / RES) + MG, 1, nx - 2)
	var a1 := clampi(int((p.x + radius) / RES) + MG, 1, nx - 2)
	var b0 := clampi(int((p.y - radius) / RES) + MG, 1, ny - 2)
	var b1 := clampi(int((p.y + radius) / RES) + MG, 1, ny - 2)
	var c0 := clampi(int((p.z - radius) / RES) + MG, 1, nz - 2)
	var c1 := clampi(int((p.z + radius) / RES) + MG, 1, nz - 2)
	var r2 := radius * radius
	var upd_i := PackedInt32Array()
	var upd_v := PackedByteArray()
	for c in range(c0, c1 + 1):
		var dz := (c - MG + 0.5) * RES - p.z
		for b in range(b0, b1 + 1):
			var dy := (b - MG + 0.5) * RES - p.y
			var base := cbase[c] + b * rowstride
			for a in range(a0, a1 + 1):
				var dx := (a - MG + 0.5) * RES - p.x
				if dx * dx + dy * dy + dz * dz > r2:
					continue
				var i := base + a * 3
				var od := vox[i]
				var avg := (vox[i - 3] + vox[i + 3] + vox[i - rowstride] + vox[i + rowstride] + vox[cbase[c - 1] + b * rowstride + a * 3] + vox[cbase[c + 1] + b * rowstride + a * 3]) / 6.0
				if avg <= 0.5 or avg >= 254.5:
					continue       # deep inside the wood or far out in the air
				var nd := int(clampf(lerpf(od, avg, 0.5) - 5.0, 0.0, 255.0))
				upd_i.append(i)
				upd_v.append(mini(nd, od))
				if od >= 128 and nd < 128:
					_gone(a, b, c)
	for k in upd_i.size():
		var i := upd_i[k]
		vox[i] = upd_v[k]
		vox[i + 1] = F_SAND * 40
	dirty = true


## Oil: soaks into everything within reach of the rag.
func oil(p: Vector3, radius: float) -> void:
	var a0 := clampi(int((p.x - radius) / RES) + MG, 0, nx - 1)
	var a1 := clampi(int((p.x + radius) / RES) + MG, 0, nx - 1)
	var b0 := clampi(int((p.y - radius) / RES) + MG, 0, ny - 1)
	var b1 := clampi(int((p.y + radius) / RES) + MG, 0, ny - 1)
	var c0 := clampi(int((p.z - radius) / RES) + MG, 0, nz - 1)
	var c1 := clampi(int((p.z + radius) / RES) + MG, 0, nz - 1)
	var r2 := radius * radius
	for c in range(c0, c1 + 1):
		var dz := (c - MG + 0.5) * RES - p.z
		for b in range(b0, b1 + 1):
			var dy := (b - MG + 0.5) * RES - p.y
			var base := cbase[c] + b * rowstride
			for a in range(a0, a1 + 1):
				var dx := (a - MG + 0.5) * RES - p.x
				var d2 := dx * dx + dy * dy + dz * dz
				if d2 > r2:
					continue
				var i := base + a * 3 + 2
				var v := int(255.0 * (1.0 - 0.5 * d2 / r2))
				if v > vox[i]:
					vox[i] = v
	dirty = true


# ---------------------------------------------------------------- measuring the result

## Points spread over the whole surface: [{p, n, fin, oil}].
func surface_points(count: int) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var c := Vector3(LEN * 0.5, CY, 22.0)
	var tries := 0
	while out.size() < count and tries < count * 6:
		tries += 1
		var d := Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var o := Vector3(rng.randf_range(4.0, LEN - 4.0), CY, 22.0) - d * 90.0
		var h := raycast(o, d)
		if h.is_empty():
			continue
		var p: Vector3 = h.p
		var n: Vector3 = h.n
		var at := attr_at(p + n * 0.4)
		out.append({"p": p, "n": n, "fin": at.x, "oil": at.y})
	return out


## Everything worth knowing about the piece, in real units.
func stats(density_g_cm3: float) -> Dictionary:
	var pts := surface_points(500)
	var torn := 0
	var knife := 0
	var sanded := 0
	var rough := 0
	var oiled := 0
	for s in pts:
		var f: int = s.fin
		if f == F_TORN:
			torn += 1
		elif f == F_KNIFE:
			knife += 1
		elif f == F_SAND:
			sanded += 1
		else:
			rough += 1
		if int(s.oil) > 60:
			oiled += 1
	var n := maxf(pts.size(), 1.0)
	# thinnest place of the bowl, felt from inside along the centre line and across
	var wall := 99.0
	for q in [Vector2(40, 32), Vector2(25, 32), Vector2(55, 32), Vector2(40, 22), Vector2(40, 42), Vector2(14, 32), Vector2(66, 32)]:
		var h := raycast(Vector3(q.x, q.y, 60.0), Vector3(0, 0, -1))
		if h.is_empty():
			wall = 0.0
			continue
		var hp: Vector3 = h.p
		var t := 0.4
		while t < 40.0 and dens(hp + Vector3(0, 0, -t)) > 0.5:
			t += 0.2
		wall = minf(wall, t)
	# left / right symmetry at 1 mm
	var diff := 0
	var tot := 0
	for k in range(0, mz):
		for j in range(0, 32):
			for i in range(0, mx, 2):
				var l := dens_i(i * 2 + MG, j * 2 + MG, k * 2 + MG) >= 128
				var r := dens_i(i * 2 + MG, (63 - j) * 2 + MG, k * 2 + MG) >= 128
				if l or r:
					tot += 1
					if l != r:
						diff += 1
	var v := RES * RES * RES / 1000.0       # cm^3 per voxel
	return {
		"waste": waste * v, "cavity": cavity * v, "over": over * v,
		"weight": solid * v * density_g_cm3,
		"torn": torn / n, "knife": knife / n, "sanded": sanded / n, "rough": rough / n, "oiled": oiled / n,
		"wall": wall, "symmetry": 1.0 - float(diff) / maxf(tot, 1.0),
		"neck": min_section(86.0, 200.0),
	}
