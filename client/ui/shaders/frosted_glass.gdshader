// 磨砂玻璃：把屏幕内容模糊、染色、压暗，再裁成圆角 + 描边。
// 用法：一个铺满窗口的 ColorRect，material = 本 shader，uniforms 由 UIPanel 每帧同步。
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float corner_radius = 10.0;
uniform float border_width = 1.0;
uniform vec4 border_color : source_color = vec4(0.42, 0.56, 0.72, 0.55);
uniform vec4 border_highlight : source_color = vec4(0.75, 0.9, 1.0, 0.32);
uniform vec4 tint : source_color = vec4(0.028, 0.06, 0.11, 1.0);
uniform float tint_alpha = 0.75;
uniform float blur = 6.0;
uniform float noise_amount = 0.03;
uniform float brightness = 0.92;
uniform float saturation = 0.82;
uniform float vignette = 0.3;
uniform float shine = 0.10;
uniform float inner_glow = 0.06;

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 blur_screen(vec2 uv) {
	vec2 px = max(blur, 0.001) / vec2(textureSize(screen_tex, 0));
	// 中心 + 两圈八向采样。权重和为 1。
	vec3 c = texture(screen_tex, uv).rgb * 0.16;
	c += texture(screen_tex, uv + vec2(px.x, 0.0)).rgb * 0.085;
	c += texture(screen_tex, uv + vec2(-px.x, 0.0)).rgb * 0.085;
	c += texture(screen_tex, uv + vec2(0.0, px.y)).rgb * 0.085;
	c += texture(screen_tex, uv + vec2(0.0, -px.y)).rgb * 0.085;

	vec2 d1 = vec2(px.x, px.y) * 0.707;
	c += texture(screen_tex, uv + d1).rgb * 0.06;
	c += texture(screen_tex, uv - d1).rgb * 0.06;
	c += texture(screen_tex, uv + vec2(d1.x, -d1.y)).rgb * 0.06;
	c += texture(screen_tex, uv + vec2(-d1.x, d1.y)).rgb * 0.06;

	vec2 d2 = px * 2.1;
	c += texture(screen_tex, uv + vec2(d2.x, 0.0)).rgb * 0.04;
	c += texture(screen_tex, uv + vec2(-d2.x, 0.0)).rgb * 0.04;
	c += texture(screen_tex, uv + vec2(0.0, d2.y)).rgb * 0.04;
	c += texture(screen_tex, uv + vec2(0.0, -d2.y)).rgb * 0.04;
	c += texture(screen_tex, uv + vec2(d2.x, d2.y) * 0.707).rgb * 0.035;
	c += texture(screen_tex, uv - vec2(d2.x, d2.y) * 0.707).rgb * 0.035;
	c += texture(screen_tex, uv + vec2(d2.x, -d2.y) * 0.707).rgb * 0.035;
	c += texture(screen_tex, uv + vec2(-d2.x, d2.y) * 0.707).rgb * 0.035;
	return c;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 p = (UV - 0.5) * rect_size;
	float d = rounded_box(p, half_size - vec2(0.5), max(corner_radius, 0.0));

	// 圆角外的像素直接透明；1.2px 过渡做抗锯齿。
	float inside = 1.0 - smoothstep(-1.2, 0.6, d);
	if (inside <= 0.001) {
		discard;
	}

	vec3 base = blur_screen(SCREEN_UV);

	// 亮度 / 饱和
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	base = mix(vec3(luma), base, saturation) * brightness;

	// 染色
	base = mix(base, tint.rgb, clamp(tint_alpha, 0.0, 0.96));

	// 左上角的一层很薄的斜向高光
	vec2 q = UV - vec2(0.5);
	float band = exp(-pow((q.x * 0.7 + q.y) * 3.4, 2.0));
	base += vec3(0.5, 0.7, 1.0) * band * shine * (1.0 - UV.y * 0.8);

	// 暗角
	float vig = smoothstep(0.28, 0.95, length(q * vec2(1.45, 1.0)));
	base *= 1.0 - vignette * vig;

	// 内缘一圈微光，让玻璃有厚度
	float rim = smoothstep(-border_width - 2.0, -border_width, d) *
			(1.0 - smoothstep(-border_width, -border_width + 1.5, d));
	base += border_highlight.rgb * rim * inner_glow * 2.0;

	// 颗粒
	float n = hash(floor(FRAGCOORD.xy * 0.75));
	base += (n - 0.5) * noise_amount;

	// 描边：贴着 SDF 边缘，宽度 1~2px
	float edge_band = smoothstep(-border_width - 1.2, -border_width - 0.1, d) *
			(1.0 - smoothstep(-border_width * 0.5, 0.3, d));
	base = mix(base, border_color.rgb, edge_band * border_color.a);

	// 顶部一道更亮的高光线
	float top_hi = (1.0 - smoothstep(0.0, 2.2, p.y + half_size.y)) *
			smoothstep(0.0, 0.25, 1.0 - abs(UV.x - 0.5) * 1.3);
	base += border_highlight.rgb * top_hi * 0.16;

	COLOR = vec4(base, inside);
}
