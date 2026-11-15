extends RefCounted
## Draws the wood by ray marching its voxel solid inside a box, with a procedural
## grain (growth rings around the pith, fibres along the length), tool marks,
## oil, the pencil layout on the split face and an optional "what is still waste" hint.

const Wood = preload("res://scripts/wood.gd")

const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D atlas : filter_linear, repeat_disable;
uniform sampler2D attr : filter_nearest, repeat_disable;
uniform sampler2D coarse : filter_nearest, repeat_disable;
uniform vec3 dims = vec3(8.0);
uniform vec3 cdims = vec3(1.0);
uniform float cols = 9.0;
uniform vec2 asize = vec2(8.0);
uniform float res = 0.5;
uniform float mg = 2.0;
uniform vec3 center = vec3(0.0);
uniform vec3 bmin = vec3(0.0);
uniform vec3 bmax = vec3(1.0);
uniform vec3 col_early : source_color = vec3(0.93, 0.83, 0.66);
uniform vec3 col_late : source_color = vec3(0.80, 0.64, 0.42);
uniform vec3 col_bark : source_color = vec3(0.23, 0.17, 0.12);
uniform float ring_w = 2.4;
uniform float lines = 1.0;
uniform float hint = 0.0;
varying vec3 mpos;
varying vec3 mcam;

void vertex() {
	mpos = VERTEX + center;
	mcam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz + center;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float dens(vec3 p) {
	vec3 g = clamp(p / res + mg, vec3(0.5), dims - 0.5);
	float c = g.z - 0.5;
	float c0 = floor(c);
	float f = c - c0;
	float c1 = min(c0 + 1.0, dims.z - 1.0);
	vec2 t0 = vec2(mod(c0, cols), floor(c0 / cols));
	vec2 t1 = vec2(mod(c1, cols), floor(c1 / cols));
	float a = textureLod(atlas, (t0 * dims.xy + g.xy) / asize, 0.0).r;
	float b = textureLod(atlas, (t1 * dims.xy + g.xy) / asize, 0.0).r;
	return mix(a, b, f);
}

// tool mark (x) and oil (y) of the nearest voxel
vec2 marks(vec3 p) {
	vec3 g = clamp(floor(p / res + mg), vec3(0.0), dims - 1.0);
	vec2 t = vec2(mod(g.z, cols), floor(g.z / cols));
	vec3 v = textureLod(attr, (t * dims.xy + g.xy + 0.5) / asize, 0.0).rgb;
	return vec2(v.g * 255.0 / 40.0, v.b);
}

float occupied(vec3 p) {
	vec3 c = floor((p / res + mg) / 8.0);
	if (any(lessThan(c, vec3(0.0))) || any(greaterThanEqual(c, cdims))) return 0.0;
	return textureLod(coarse, (vec2(c.x + c.z * cdims.x, c.y) + 0.5) / vec2(cdims.x * cdims.z, cdims.y), 0.0).r;
}

float sstep(float a, float b, float x) {
	float t = clamp((x - a) / (b - a), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// 0 = waste, 1 = spoon, 2 = hollow of the bowl (same function as in the game code)
float target(vec3 p) {
	if (p.z > 32.0) return 0.0;
	float dy = p.y - 32.0;
	float dz = 32.0 - p.z;
	vec3 e = vec3((p.x - 40.0) / 34.5, dy / 20.5, dz / 12.5);
	if (dot(e, e) < 1.0) return 2.0;
	e = vec3((p.x - 40.0) / 38.0, dy / 24.0, dz / 16.0);
	if (dot(e, e) < 1.0) return 1.0;
	if (p.x >= 62.0 && p.x <= 222.0) {
		float wy = 6.0 + 5.0 * exp(-pow((p.x - 62.0) / 12.0, 2.0)) + 3.5 * sstep(110.0, 215.0, p.x);
		float th = 4.5 + 3.0 * exp(-pow((p.x - 62.0) / 10.0, 2.0));
		float zc = 32.0 - th;
		float ee = p.x > 212.0 ? pow((p.x - 212.0) / 10.0, 2.6) : 0.0;
		if (pow(abs(dy) / wy, 2.6) + pow(abs(p.z - zc) / th, 2.6) + ee < 1.0) return 1.0;
	}
	return 0.0;
}

// pencil layout on the split face: outline of the spoon, the bowl, the centre line
float pencil(vec3 p) {
	float dy = p.y - 32.0;
	float g = sqrt(pow((p.x - 40.0) / 38.0, 2.0) + pow(dy / 24.0, 2.0));
	float k = 9.0;
	float wy = 1.0;
	if (p.x >= 62.0 && p.x <= 222.5) {
		wy = 6.0 + 5.0 * exp(-pow((p.x - 62.0) / 12.0, 2.0)) + 3.5 * sstep(110.0, 215.0, p.x);
		k = abs(dy) / wy;
		if (p.x > 212.0) k = pow(pow(k, 2.6) + pow((p.x - 212.0) / 10.0, 2.6), 1.0 / 2.6);
	}
	// the outline is the edge of "bowl or handle"
	float lb = k < 1.0 ? 9.0 : abs(g - 1.0) * 24.0;
	float lh = g < 1.0 ? 9.0 : abs(k - 1.0) * wy;
	float l = min(lb, lh);
	float c = sqrt(pow((p.x - 40.0) / 34.5, 2.0) + pow(dy / 20.5, 2.0));
	l = min(l, abs(c - 1.0) * 20.0);
	l = min(l, abs(dy) + (p.x < 4.0 || p.x > 226.0 ? 9.0 : 0.0));
	// saw marks: the neck and the end of the handle
	l = min(l, abs(p.x - 82.0) + (k > 1.1 ? 0.0 : 9.0));
	l = min(l, abs(p.x - 223.5));
	return 1.0 - smoothstep(0.25, 0.55, l);
}

void fragment() {
	vec3 ro = mcam;
	vec3 rd = normalize(mpos - mcam);
	vec3 inv = 1.0 / rd;
	vec3 ta = (bmin - ro) * inv;
	vec3 tb = (bmax - ro) * inv;
	vec3 tmn = min(ta, tb);
	vec3 tmx = max(ta, tb);
	float t0 = max(max(tmn.x, tmn.y), max(tmn.z, 0.0));
	float t1 = min(tmx.x, min(tmx.y, tmx.z));
	if (t1 <= t0) discard;
	float stp = res * 1.1;
	float t = t0 + 0.02;
	bool hit = false;
	for (int i = 0; i < 520; i++) {
		if (t > t1) break;
		vec3 q = ro + rd * t;
		if (occupied(q) < 0.5) { t += 3.9; continue; }
		if (dens(q) > 0.5) { hit = true; break; }
		t += stp;
	}
	if (!hit) discard;
	float a = t - stp;
	float b = t;
	for (int i = 0; i < 6; i++) {
		float m = 0.5 * (a + b);
		if (dens(ro + rd * m) > 0.5) b = m; else a = m;
	}
	t = b;
	vec3 p = ro + rd * t;
	float e = res * 0.9;
	vec3 n = -vec3(
		dens(p + vec3(e, 0.0, 0.0)) - dens(p - vec3(e, 0.0, 0.0)),
		dens(p + vec3(0.0, e, 0.0)) - dens(p - vec3(0.0, e, 0.0)),
		dens(p + vec3(0.0, 0.0, e)) - dens(p - vec3(0.0, 0.0, e)));
	float nl = length(n);
	n = nl > 1e-5 ? n / nl : -rd;
	vec2 mk = marks(p + n * res * 0.8);
	float fin = floor(mk.x + 0.5);
	float oil = mk.y;

	// the wood itself: rings around the pith, fibres along the length
	vec2 q2 = vec2(p.y - 32.0 - 1.6 * sin(p.x * 0.021), p.z - 37.0 - 1.1 * sin(p.x * 0.013 + 1.0));
	float r = length(q2) + 0.9 * vnoise(vec3(p.x * 0.03, p.y * 0.3, p.z * 0.3));
	float ring = 0.5 + 0.5 * sin(r * 6.2831 / ring_w);
	ring = smoothstep(0.25, 0.95, ring);
	float fibre = vnoise(vec3(p.x * 0.11, p.y * 5.0, p.z * 5.0));
	float fleck = vnoise(vec3(p.x * 0.9, p.y * 14.0, p.z * 14.0));
	vec3 col = mix(col_early, col_late, ring * 0.6) * (0.9 + 0.16 * fibre) * (0.97 + 0.06 * fleck);
	float rough = 0.6;
	float bump = 0.0;
	if (fin < 0.5) {            // bark
		float bk = vnoise(vec3(p.x * 0.25, p.y * 0.8, p.z * 0.8));
		col = col_bark * (0.6 + 0.8 * bk) + vec3(0.05, 0.05, 0.04) * step(0.72, vnoise(p * 1.7));
		rough = 0.95;
		bump = 0.55;
	} else if (fin < 1.5) {     // riven face
		col *= 0.97;
		rough = 0.85;
		bump = 0.22;
	} else if (fin < 2.5) {     // sawn
		col *= 0.93 + 0.07 * sin((p.y + p.z) * 11.0);
		rough = 0.85;
	} else if (fin < 3.5) {     // axe
		rough = 0.62;
		bump = 0.05;
	} else if (fin < 4.5) {     // knife: a clean, slightly shiny facet
		rough = 0.36;
	} else if (fin < 5.5) {     // torn grain
		col = col * 1.08 + 0.05;
		rough = 0.95;
		bump = 0.6;
	} else {                    // sanded
		col = mix(col, vec3(dot(col, vec3(0.333))), 0.12) * 1.03;
		rough = 0.8;
	}
	if (bump > 0.0) {
		vec3 k = p * vec3(0.9, 4.0, 4.0);
		n = normalize(n + bump * (vec3(vnoise(k), vnoise(k + 7.3), vnoise(k + 13.1)) - 0.5));
	}
	// oil soaks in: deeper colour, the figure comes up, a soft sheen
	col = mix(col, pow(col, vec3(2.0)) * vec3(1.06, 0.93, 0.78), oil);
	rough = mix(rough, rough * 0.55, oil);

	if (lines > 0.5 && fin > 0.5 && fin < 1.5 && abs(p.z - 32.0) < 0.5) {
		col = mix(col, vec3(0.16, 0.17, 0.2), 0.8 * pencil(p));
	}
	if (hint > 0.5) {
		float tg = target(p - n * 0.6);
		vec3 hc = tg < 0.5 ? vec3(0.95, 0.25, 0.2) : (tg < 1.5 ? vec3(0.25, 0.8, 0.35) : vec3(0.25, 0.45, 0.95));
		col = mix(col, hc, 0.42);
	}

	vec4 vp = VIEW_MATRIX * MODEL_MATRIX * vec4(p - center, 1.0);
	vec4 cp = PROJECTION_MATRIX * vp;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH = (cp.z / cp.w) * 0.5 + 0.5;
#else
	DEPTH = cp.z / cp.w;
#endif
	LIGHT_VERTEX = vp.xyz;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
}
"""

static var _shader: Shader = null


static func make(wood) -> MeshInstance3D:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var size := Vector3(Wood.LEN, Wood.WID, Wood.HGT)
	bm.size = size + Vector3.ONE * 1.6
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	sm.set_shader_parameter("dims", Vector3(wood.nx, wood.ny, wood.nz))
	sm.set_shader_parameter("cdims", Vector3(wood.cx, wood.cy, wood.cz))
	sm.set_shader_parameter("cols", float(wood.cols))
	sm.set_shader_parameter("asize", Vector2(wood.aw, wood.ah))
	sm.set_shader_parameter("res", Wood.RES)
	sm.set_shader_parameter("mg", float(Wood.MG))
	sm.set_shader_parameter("center", size * 0.5)
	sm.set_shader_parameter("bmin", -Vector3.ONE * 0.8)
	sm.set_shader_parameter("bmax", size + Vector3.ONE * 0.8)
	mi.material_override = sm
	# the mesh is centred on the block; piece coordinates start at its corner
	mi.position = Vector3.ZERO
	sync(mi, wood)
	return mi


static func sync(mi: MeshInstance3D, wood) -> void:
	var sm: ShaderMaterial = mi.material_override
	var img := Image.create_from_data(wood.aw, wood.ah, false, Image.FORMAT_RGB8, wood.vox)
	var tex = mi.get_meta("tex") if mi.has_meta("tex") else null
	if tex == null:
		tex = ImageTexture.create_from_image(img)
		mi.set_meta("tex", tex)
		sm.set_shader_parameter("atlas", tex)
		sm.set_shader_parameter("attr", tex)
	else:
		(tex as ImageTexture).update(img)
	var cimg := Image.create_from_data(wood.cx * wood.cz, wood.cy, false, Image.FORMAT_L8, wood.coarse_bytes())
	var ctex = mi.get_meta("ctex") if mi.has_meta("ctex") else null
	if ctex == null:
		ctex = ImageTexture.create_from_image(cimg)
		mi.set_meta("ctex", ctex)
		sm.set_shader_parameter("coarse", ctex)
	else:
		(ctex as ImageTexture).update(cimg)
	wood.dirty = false


static func set_species(mi: MeshInstance3D, sp: Dictionary) -> void:
	var sm: ShaderMaterial = mi.material_override
	sm.set_shader_parameter("col_early", sp.early)
	sm.set_shader_parameter("col_late", sp.late)
	sm.set_shader_parameter("col_bark", sp.bark)
	sm.set_shader_parameter("ring_w", sp.ring)


static func set_flags(mi: MeshInstance3D, lines: bool, hint: bool) -> void:
	var sm: ShaderMaterial = mi.material_override
	sm.set_shader_parameter("lines", 1.0 if lines else 0.0)
	sm.set_shader_parameter("hint", 1.0 if hint else 0.0)
