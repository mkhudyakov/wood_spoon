extends RefCounted
## Turns the carved voxel solid into a triangle mesh (surface nets on a 1 mm grid)
## and writes it as a binary STL, in millimetres: the spoon you can hold or print.

static func write_stl(wood, path: String) -> bool:
	var gx := 232
	var gy := 66
	var gz := 36
	# solidity sampled at every millimetre (0.5 = the surface)
	var f := PackedFloat32Array()
	f.resize(gx * gy * gz)
	for k in gz:
		for j in gy:
			for i in gx:
				f[(k * gy + j) * gx + i] = wood.dens_i(i * 2 + wood.MG - 1, j * 2 + wood.MG - 1, k * 2 + wood.MG - 1) / 255.0 - 0.5
	# one vertex in every cell the surface passes through
	var vid := PackedInt32Array()
	vid.resize(gx * gy * gz)
	vid.fill(-1)
	var verts := PackedVector3Array()
	for k in gz - 1:
		for j in gy - 1:
			for i in gx - 1:
				var base := (k * gy + j) * gx + i
				var sum := Vector3.ZERO
				var cnt := 0
				for e in 12:
					var ax := e >> 2
					var o := e & 3
					var a := Vector3i(i, j, k)
					if ax == 0:
						a += Vector3i(0, o & 1, o >> 1)
					elif ax == 1:
						a += Vector3i(o & 1, 0, o >> 1)
					else:
						a += Vector3i(o & 1, o >> 1, 0)
					var b := a
					b[ax] += 1
					var fa := f[(a.z * gy + a.y) * gx + a.x]
					var fb := f[(b.z * gy + b.y) * gx + b.x]
					if (fa > 0.0) != (fb > 0.0):
						var t := fa / (fa - fb)
						sum += Vector3(a) + (Vector3(b) - Vector3(a)) * t
						cnt += 1
				if cnt > 0:
					vid[base] = verts.size()
					verts.append(sum / cnt)
	# a quad wherever the surface crosses a grid edge
	var tris := PackedInt32Array()
	for k in range(1, gz - 1):
		for j in range(1, gy - 1):
			for i in range(1, gx - 1):
				var f0 := f[(k * gy + j) * gx + i]
				for ax in 3:
					var n := Vector3i(i, j, k)
					n[ax] += 1
					var f1 := f[(n.z * gy + n.y) * gx + n.x]
					if (f0 > 0.0) == (f1 > 0.0):
						continue
					var u := (ax + 1) % 3
					var v := (ax + 2) % 3
					var c0 := Vector3i(i, j, k)
					var c1 := c0
					c1[u] -= 1
					var c2 := c1
					c2[v] -= 1
					var c3 := c0
					c3[v] -= 1
					var q0 := vid[(c0.z * gy + c0.y) * gx + c0.x]
					var q1 := vid[(c1.z * gy + c1.y) * gx + c1.x]
					var q2 := vid[(c2.z * gy + c2.y) * gx + c2.x]
					var q3 := vid[(c3.z * gy + c3.y) * gx + c3.x]
					if q0 < 0 or q1 < 0 or q2 < 0 or q3 < 0:
						continue
					if f0 > 0.0:
						tris.append_array(PackedInt32Array([q0, q1, q2, q0, q2, q3]))
					else:
						tris.append_array(PackedInt32Array([q0, q2, q1, q0, q3, q2]))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var header := PackedByteArray()
	header.resize(80)
	file.store_buffer(header)
	@warning_ignore("integer_division")
	var nt := tris.size() / 3
	file.store_32(nt)
	for t in nt:
		var a := verts[tris[t * 3]]
		var b := verts[tris[t * 3 + 1]]
		var c := verts[tris[t * 3 + 2]]
		var nn := (b - a).cross(c - a).normalized()
		for vv in [nn, a, b, c]:
			file.store_float(vv.x)
			file.store_float(vv.y)
			file.store_float(vv.z)
		file.store_16(0)
	file.close()
	return nt > 0
