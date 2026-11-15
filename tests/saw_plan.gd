extends SceneTree
## Saws the half log the way the task describes and reports what is left for the knife.
const Wood = preload("res://scripts/wood.gd")
const CM3 := 0.000125

func _initialize() -> void:
	var w = Wood.new()
	w.new_billet()
	print("billet: waste %.0f cm3" % (w.waste * CM3))
	var t0 := Time.get_ticks_msec()
	var X := Vector3(1, 0, 0)
	var Y := Vector3(0, 1, 0)
	var Z := Vector3(0, 0, 1)
	# end of the handle
	w.saw_cut(Vector3(224, 32, 32), Y, -Z, 40.0)
	print("  end cut %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	print("  fell %.1f cm3 in %d ms" % [w.drop_offcuts() * 0.001, Time.get_ticks_msec() - t0])
	# stop cuts at the neck from both sides, down to 11 mm from the axis
	w.saw_cut(Vector3(82, 0, 32), Z, Y, 21.0)
	w.saw_cut(Vector3(82, 64, 32), Z, -Y, 21.0)
	print("  no piece falls from a stop cut: %.1f" % w.drop_offcuts())
	# rip cuts from the end along the handle, 11 mm either side of the axis
	t0 = Time.get_ticks_msec()
	w.saw_cut(Vector3(223.3, 21, 28), Z, -X, 141.5)
	print("  rip %d ms" % (Time.get_ticks_msec() - t0))
	print("  cheek fell: %.1f cm3" % (w.drop_offcuts() * 0.001))
	w.saw_cut(Vector3(223.3, 43, 28), Z, -X, 141.5)
	print("  cheek fell: %.1f cm3" % (w.drop_offcuts() * 0.001))
	# under the handle: stop cut from below, then a rip from the end at z = 21
	w.saw_cut(Vector3(82, 32, 0), Y, Z, 21.0)
	w.saw_cut(Vector3(223.3, 32, 21), Y, -X, 141.5)
	print("  underside fell: %.1f cm3" % (w.drop_offcuts() * 0.001))
	print("after the plain cuts: waste %.1f cm3, lost %.2f" % [w.waste * CM3, w.over * CM3])
	# the two corners at the tip of the bowl, on the skew (seen from above)
	for sy in [-1.0, 1.0]:
		var nrm := Vector3(-0.62 / 38.0, sy * 0.80 / 24.0, 0).normalized()      # outward normal of the outline
		var pt := Vector3(40, 32, 32) + Vector3(-38.0 * 0.62, sy * 24.0 * 0.80, 0) + nrm * 2.5
		var al := Vector3(-nrm.y, nrm.x, 0)
		w.saw_cut(pt, al, -Z, 40.0)
		print("  corner fell: %.1f cm3" % (w.drop_offcuts() * 0.001))
	print("after the corners: waste %.1f cm3, lost %.2f cm3" % [w.waste * CM3, w.over * CM3])
	quit()
