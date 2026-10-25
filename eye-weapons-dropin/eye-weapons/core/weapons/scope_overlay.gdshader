shader_type canvas_item;
// Circular scope overlay: dark outside the lens, thin ring, crosshair.
// Put on a full-rect ColorRect inside a CanvasLayer in your HUD,
// toggle `visible` from the Chimera's scope_changed signal.

uniform vec4 scope_color : source_color = vec4(0.015, 0.02, 0.03, 1.0);
uniform float radius = 0.34;
uniform float edge_softness = 0.02;
uniform vec4 ring_color : source_color = vec4(0.85, 0.9, 0.95, 0.85);
uniform vec4 reticle_color : source_color = vec4(0.1, 0.12, 0.14, 0.9);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= 1.7777778; // ~16:9; pass screen aspect as a uniform if you support other ratios
	float d = length(uv);

	// dark outside the lens
	float outside = smoothstep(radius, radius + edge_softness, d);
	vec4 col = vec4(scope_color.rgb, outside * scope_color.a);

	// thin ring at the lens edge
	float ring = 1.0 - smoothstep(0.0, 0.006, abs(d - radius));
	col = mix(col, ring_color, ring * ring_color.a * (1.0 - outside));

	// crosshair inside the lens
	if (d < radius) {
		float hx = (1.0 - smoothstep(0.0, 0.0035, abs(uv.y))) * (1.0 - smoothstep(0.10, 0.13, abs(uv.x)));
		float hy = (1.0 - smoothstep(0.0, 0.0035, abs(uv.x))) * (1.0 - smoothstep(0.10, 0.13, abs(uv.y)));
		float dot_m = 1.0 - smoothstep(0.0, 0.006, d);
		float ch = max(max(hx, hy), dot_m);
		col = mix(col, reticle_color, ch * reticle_color.a);
	}
	COLOR = col;
}
