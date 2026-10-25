shader_type canvas_item;

// Post-lens clarity pass.
//
// Contrast Adaptive Sharpening (AMD FidelityFX CAS, 3x3 cross). It sharpens
// where there is local contrast and leaves flat areas alone, so it recovers
// detail lost to FSR2 temporal upscaling and the wide-anchor lens without the
// ringing halos a plain unsharp mask produces. Cost: 5 texture taps.
//
// Runs on a full-screen ColorRect drawn below the HUD, so UI stays crisp.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform bool enabled = true;
uniform float sharpen_amount : hint_range(0.0, 1.0) = 0.45;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 center = texture(screen_tex, SCREEN_UV).rgb;
	vec3 color = center;

	if (enabled) {
		vec2 px = SCREEN_PIXEL_SIZE;
		vec3 north = texture(screen_tex, SCREEN_UV + vec2(0.0, -px.y)).rgb;
		vec3 west  = texture(screen_tex, SCREEN_UV + vec2(-px.x, 0.0)).rgb;
		vec3 east  = texture(screen_tex, SCREEN_UV + vec2( px.x, 0.0)).rgb;
		vec3 south = texture(screen_tex, SCREEN_UV + vec2(0.0,  px.y)).rgb;

		// Neighbour min/max with the centre counted twice (CAS).
		vec3 mn = min(min(north, west), min(east, south));
		mn = min(mn, center);
		vec3 mx = max(max(north, west), max(east, south));
		mx = max(mx, center);

		// Contrast-adaptive amplitude: tiny in flat regions, large on edges.
		vec3 amp = clamp(min(mn, vec3(1.0) - mx) / max(mx, vec3(1e-4)), vec3(0.0), vec3(1.0));
		amp = sqrt(amp);

		vec3 weights = amp * (-1.0 / 8.0);
		vec3 sharpened = ((north + west + east + south) * weights + center) / (1.0 + 4.0 * weights);

		color = mix(center, sharpened, sharpen_amount);
	}

	if (grain_amount > 0.0) {
		float noise = hash12(FRAGCOORD.xy + TIME * 60.0) - 0.5;
		color += noise * grain_amount * 0.05;
	}

	COLOR = vec4(color, 1.0);
}
