shader_type canvas_item;
render_mode blend_mix, unshaded;

// ============================================================================
//  ЭВОЛЮЦИЯ — биолюминесцентный океан.
//  Полноэкранный фон: fbm-взвесь, аврора (верх), каустика (низ), боке-планктон,
//  виньетка и мягкое свечение вокруг существа (u_focus). Значения намеренно
//  выходят за 1.0 — вместе с hdr_2d=true и WorldEnvironment.glow это даёт блум.
//  Материал создаётся один раз; меняются только юниформы.
// ============================================================================

uniform vec2 u_size = vec2(1280.0, 720.0);
uniform float u_time_scale : hint_range(0.0, 4.0) = 1.0;
uniform float u_time_offset = 0.0;

// Палитра текущей эры (значения приходят из EvolutionDB через Backdrop).
uniform vec4 u_col_a : source_color = vec4(0.45, 0.94, 0.85, 1.0);
uniform vec4 u_col_b : source_color = vec4(0.35, 0.79, 1.0, 1.0);
uniform vec4 u_col_glow : source_color = vec4(0.72, 0.62, 1.0, 1.0);
uniform vec4 u_col_deep : source_color = vec4(0.02, 0.04, 0.09, 1.0);
uniform vec4 u_col_mid : source_color = vec4(0.04, 0.10, 0.17, 1.0);

// Палитра предыдущей эры — для кросс-фейда по u_stage_blend.
uniform vec4 u_col_a_prev : source_color = vec4(0.45, 0.94, 0.85, 1.0);
uniform vec4 u_col_b_prev : source_color = vec4(0.35, 0.79, 1.0, 1.0);
uniform vec4 u_col_glow_prev : source_color = vec4(0.72, 0.62, 1.0, 1.0);

uniform float u_stage_blend : hint_range(0.0, 1.0) = 1.0;
uniform float u_pulse : hint_range(0.0, 2.0) = 0.0;
uniform vec2 u_focus = vec2(0.42, 0.55);
uniform float u_focus_strength : hint_range(0.0, 2.0) = 0.85;
uniform float u_energy : hint_range(0.0, 1.0) = 0.2;
uniform float u_bokeh_amount : hint_range(0.0, 1.0) = 0.8;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = sin(dot(p, vec2(41.0, 289.0)));
	return fract(vec2(262144.0, 32768.0) * n);
}

// Гладкий value-noise.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 4 октавы fbm с поворотом между октавами — «живой» шум без решётки.
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = rot * p * 2.03 + vec2(11.3, 7.7);
		amp *= 0.5;
	}
	return v;
}

// Аврора: вертикальные полотнища, искривлённые fbm-варпом.
float aurora_layer(vec2 p, float t, float seed) {
	vec2 q = p;
	q.x += sin(q.y * 1.6 + t * 0.05 + seed) * 0.30;
	float warp = fbm(vec2(q.x * 1.25 + seed * 5.0, q.y * 0.55 - t * 0.018));
	float ribbon = sin(q.x * 2.9 + warp * 6.0 + t * 0.04 + seed);
	ribbon = clamp(ribbon * 0.5 + 0.5, 0.0, 1.0);
	ribbon = pow(ribbon, 4.0);
	float veil = smoothstep(0.25, 0.95, warp);
	return ribbon * veil;
}

// Каустика: три слоя «паутинных» бликов, медленно ползущих по дну.
float caustic_layer(vec2 p, float t) {
	float acc = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 q = p * (1.35 + fi * 0.85);
		q += vec2(
			sin(q.y * 1.3 + t * (0.06 + fi * 0.03) + fi * 2.0),
			cos(q.x * 1.1 - t * (0.05 + fi * 0.02) + fi * 1.7)
		) * 0.45;
		float w = abs(sin(q.x * 1.9 + sin(q.y * 2.2 + t * 0.09) * 1.6));
		acc += pow(1.0 - w, 9.0) * (0.60 - fi * 0.14);
	}
	return acc;
}

// Боке: редкие мягкие кружки-планктон, медленно всплывающие.
float bokeh_layer(vec2 p, float t) {
	float acc = 0.0;
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		vec2 g = p * (2.1 + fi * 1.9)
			+ vec2(t * (0.010 + fi * 0.008), -t * (0.016 + fi * 0.006));
		vec2 cell = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = hash21(cell + fi * 13.37);
		vec2 off = (hash22(cell + fi * 3.7) - 0.5) * 0.55;
		float r = 0.06 + h * 0.13;
		float d = length(f - off);
		float disc = 1.0 - smoothstep(r * 0.35, r, d);
		float tw = 0.55 + 0.45 * sin(t * (0.25 + h * 0.45) + h * 6.2831);
		acc += disc * tw * step(0.72, h) * (1.0 - fi * 0.40);
	}
	return acc;
}

void fragment() {
	vec2 res = max(u_size, vec2(1.0));
	float aspect = res.x / res.y;
	// координаты с сохранением пропорций: y в [-1, 1], x — по аспекту.
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0) * 2.0;
	float t = (TIME + u_time_offset) * u_time_scale;

	vec3 col_a = mix(u_col_a_prev.rgb, u_col_a.rgb, u_stage_blend);
	vec3 col_b = mix(u_col_b_prev.rgb, u_col_b.rgb, u_stage_blend);
	vec3 col_glow = mix(u_col_glow_prev.rgb, u_col_glow.rgb, u_stage_blend);

	float energy = clamp(u_energy, 0.0, 1.0);
	float pulse_boost = 1.0 + u_pulse * 0.45;

	// --- ГЛУБИНА: 70-80% кадра — тёмная вода. Цвет эры сюда не льётся. ---
	vec3 base = mix(u_col_mid.rgb, u_col_deep.rgb, smoothstep(-0.25, 0.90, p.y));
	vec3 col = base * 0.62;

	// Взвесь: едва заметная дымка, только чтобы тёмное не было плоским.
	float haze = fbm(p * 0.85 + vec2(t * 0.012, -t * 0.020));
	col += col_a * haze * (0.008 + energy * 0.022);

	// Свечение толщи воды у горизонта — очень широкое и очень слабое.
	float horizon = exp(-pow((p.y + 0.12) * 2.35, 2.0));
	col += mix(col_a, col_glow, 0.55) * horizon * (0.012 + energy * 0.035);

	// --- АКЦЕНТЫ: узкие полосы, локальные пятна, HDR в пиках ---

	// Аврора — редкие полотнища сверху.
	float top_mask = (1.0 - smoothstep(-0.85, 0.55, p.y)) * 0.85;
	float au = aurora_layer(p + vec2(0.0, 0.55), t, 0.0);
	au += aurora_layer(p * 1.18 + vec2(1.7, 0.40), t * 0.85, 4.3) * 0.70;
	col += mix(col_a, col_b, 0.40) * au * top_mask
		* (0.05 + energy * 0.13) * pulse_boost * 2.0;

	// Каустика — тонкие светящиеся нити по дну (пики уходят в HDR).
	float bot_mask = smoothstep(-0.75, 0.95, p.y);
	float ca = caustic_layer(p + vec2(0.0, -0.15), t);
	ca = ca * ca * 1.15;
	col += mix(col_b, col_glow, 0.55) * ca * (0.06 + energy * 0.22)
		* (0.22 + bot_mask) * pulse_boost * 1.10;

	// Боке — редкий планктон, точечные HDR-искры для блума.
	float bo = bokeh_layer(p, t);
	col += mix(col_glow, col_a, 0.45) * bo * (0.04 + energy * 0.14)
		* pulse_boost * u_bokeh_amount * 1.30;

	// Фокус вокруг существа: плотное ядро + мягкое кольцо, без широкой заливки.
	vec2 fpos = (u_focus - 0.5) * vec2(aspect, 1.0) * 2.0;
	float fd = length(p - fpos);
	float halo = exp(-fd * fd * 26.0);
	float ring = exp(-pow((fd - 0.55) * 7.0, 2.0)) * 0.12;
	float focus_amt = (halo + ring) * clamp(u_focus_strength, 0.0, 2.0);
	col += col_glow * focus_amt * (0.05 + energy * 0.09) * (1.0 + u_pulse * 1.10);
	col += col_a * halo * (0.03 + 0.03 * energy) * (1.0 + u_pulse);

	// Пульс: короткий «вдох» света по всему кадру.
	col *= 1.0 + u_pulse * 0.16;

	// Виньетка: края заметно темнее, взгляд в центр.
	float vig = 1.0 - smoothstep(0.40, 1.55, length(p * vec2(0.85, 0.98)));
	col *= mix(0.22, 1.0, vig);

	// Мягкая дизеризация против бандинга на тёмных градиентах.
	float dither = (hash21(FRAGCOORD.xy + fract(t) * 37.0) - 0.5) / 255.0;
	col += dither;

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
