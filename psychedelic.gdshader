// Psychedelic 8-bit backdrop: a swirling plasma cut into chunky pixels,
// squeezed into a few colour bands and dithered like an old console.
// Written for the Compatibility renderer (float maths only).
shader_type canvas_item;

uniform vec2 screen_size = vec2(720.0, 1280.0);
uniform float pixel_size = 16.0;
uniform float bands = 6.0;
// 0..1, kicked up by the game on every hit and fading back down.
uniform float pulse = 0.0;
// Rotates the whole palette; the game nudges it on each point.
uniform float hue_shift = 0.0;
uniform float brightness = 0.42;
// Animation clock from the game, so it can speed up without jumping.
uniform float clock = 0.0;
// 0..1: how wild the visuals get. Driven by the player's combo.
uniform float trip = 0.0;

vec3 palette(float t) {
	// Cosine rainbow: hot pink, orange, lime, cyan, violet.
	return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

float bayer2(vec2 cell) {
	// 2x2 ordered dither, the classic checkered 8-bit look.
	float x = mod(cell.x, 2.0);
	float y = mod(cell.y, 2.0);
	return (x * 2.0 + y * 3.0 - 4.0 * x * y) / 4.0;
}

void fragment() {
	vec2 cell = floor(UV * screen_size / pixel_size);
	vec2 p = cell * pixel_size / screen_size.x;  // square pixels, 0..1 across
	float t = clock * (0.35 + pulse * 0.6);

	vec2 c = vec2(0.5 + 0.35 * sin(t * 0.7), 0.9 + 0.6 * cos(t * 0.5));
	float v = sin(p.x * 9.0 + t);
	v += sin((p.y * 7.0 - t * 1.3));
	v += sin((p.x + p.y) * 6.0 + t * 0.8);
	v += sin(length(p - c) * 14.0 - t * 2.0);
	v = v * 0.125 + 0.5;  // roughly 0..1

	float b = bands + floor(trip * 6.0);
	float band = floor(v * b + bayer2(cell)) / b;
	vec3 col = palette(band + hue_shift + clock * (0.05 + trip * 0.15));
	col *= brightness + trip * 0.1 + pulse * 0.35;

	COLOR = vec4(col, 1.0);
}
