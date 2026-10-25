shader_type canvas_item;
render_mode unshaded;

// Scope overlay: opaque black outside a circular lens, fine green reticle inside.
// `intensity` is driven by the player's scope blend so the whole effect fades in
// and out with the FOV transition.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float radius : hint_range(0.05, 0.9) = 0.42;
uniform float aspect_ratio : hint_range(0.1, 4.0) = 1.777;
uniform float line_width : hint_range(0.0, 0.02) = 0.0012;
uniform vec4 reticle_color : source_color = vec4(0.82, 1.0, 0.86, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= aspect_ratio;
	float distance_from_center = length(uv);

	float outside = smoothstep(radius, radius + 0.0025, distance_from_center);
	float inside = 1.0 - smoothstep(radius - 0.001, radius, distance_from_center);

	float horizontal = 1.0 - smoothstep(0.0, line_width * 1.6, abs(uv.y));
	float vertical = 1.0 - smoothstep(0.0, line_width * 1.6, abs(uv.x));
	float center_gap = smoothstep(0.012, 0.022, distance_from_center);
	float reticle = max(horizontal, vertical) * inside * center_gap;
	float center_dot = 1.0 - smoothstep(0.0, line_width * 2.4, distance_from_center);

	float mask = max(outside, max(reticle, center_dot));
	vec3 color = mix(vec3(0.0), reticle_color.rgb, max(reticle, center_dot));
	COLOR = vec4(color, mask * intensity);
}
