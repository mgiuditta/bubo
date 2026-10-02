#include "../OrbShading.h"

// Orbite: the Blob shrinks to a small sphere at the centre while the diagram opens around it.
static float orbite(float3 p, float) {
    return length(p) - 0.12;
}

ORB_FORMA_SDF(orbite, 0.0) // no ripple, or the small sphere would crumple

// --- The Orbite's diagram: thin inclined orbits, moons in their phases, a square around a point
// of light, a dashed line and a field of stars. Light strokes only, on the Notte ink.

static float hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

// Coverage of a line of half width `w` at signed distance `d`, antialiased over one pixel `px`.
static float stroke(float d, float w, float px) { return saturate((w - abs(d)) / px + 0.5); }

// Approximate distance to the ellipse of semi-axes `ab`, good near the curve where strokes are drawn.
static float ellipseDistance(float2 p, float2 ab) {
    float2 k = p / ab;
    float l = length(k);
    return (l - 1.0) * l / max(length(k / ab), 1e-4);
}

// The diagram at full strength, premultiplied; `u.morph` opens it out of the shrinking Blob.
static float4 orbiteDiagram(float2 uv, constant Uniforms &u) {
    const float3 ink = float3(10.0, 11.0, 13.0) / 255.0;     // Palette ink of the Notte direction
    const float3 light = float3(236.0, 238.0, 241.0) / 255.0; // Palette textPrimary
    const float radii[4] = { 0.26, 0.41, 0.56, 0.72 };
    const float phases[5] = { 0.55, 0.0, -0.55, -1.0, 1.0 }; // crescent, half, gibbous, full, new
    float t = u.diagramTime;
    float scale = mix(0.55, 1.0, u.morph);
    float2 p = uv / scale;
    float pixel = 2.0 / u.res.y;
    float px = pixel / scale;
    float ground = 1.0 - smoothstep(0.80, 0.98, length(uv)); // the dark disc; marks live only on it

    // Moons: one on each orbit, and a second one opposite on the outermost.
    float moons = 0.0, gap = 0.0;
    const float moonRadius = 0.042;
    for (int i = 0; i < 5; i++) {
        int ring = min(i, 3);
        float a = radii[ring];
        float tilt = -0.38 + 0.07 * float(ring);
        float speed = 0.22 / (a * sqrt(a));               // inner moons run faster
        float theta = 1.3 * float(i) + (i == 4 ? 3.1416 : 0.0) + t * speed;
        float2 centre = rot(tilt) * float2(a * cos(theta), a * 0.4 * sin(theta));
        float2 l = (p - centre) / moonRadius;
        float dist = length(l);
        float terminator = phases[i] * sqrt(max(0.0, 1.0 - l.y * l.y));
        float lit = saturate((1.0 - dist) * moonRadius / px + 0.5) * saturate((l.x - terminator) * moonRadius / px + 0.5);
        moons = max(moons, max(stroke((dist - 1.0) * moonRadius, 0.5 * px, px), lit * 0.95));
        gap = max(gap, saturate((1.7 - dist) * moonRadius / px + 0.5));
    }

    // Orbits, concentric and inclined, cut around the moons.
    float orbits = 0.0;
    for (int ring = 0; ring < 4; ring++) {
        float a = radii[ring];
        float tilt = -0.38 + 0.07 * float(ring);
        orbits = max(orbits, stroke(ellipseDistance(p * rot(tilt), float2(a, a * 0.4)), 0.45 * px, px));
    }

    // The dashed line crossing the scene, its dashes drifting slowly.
    float2 along = normalize(float2(1.0, 0.32));
    float across = dot(p, float2(-along.y, along.x)) - 0.2;
    float phase = fract(dot(p, along) * 9.0 - t * 0.12);
    float dash = smoothstep(0.0, 0.06, phase) * (1.0 - smoothstep(0.5, 0.56, phase));
    float dashed = stroke(across, 0.5 * px, px) * dash;

    // The square at the centre and its point of light.
    float2 b = abs(p) - 0.075;
    float square = stroke(length(max(b, 0.0)) + min(max(b.x, b.y), 0.0), 0.5 * px, px);
    float r2 = dot(p, p);
    float point = saturate(exp(-r2 / 0.0003) + exp(-r2 / 0.004) * 0.35);

    // Stars: fixed points on the disc, not scaled with the diagram, twinkling while it moves.
    float2 g = uv * 22.0, cell = floor(g);
    float h = hash(cell);
    float stars = 0.0;
    if (h > 0.82) {
        float2 star = cell + 0.5 + (float2(hash(cell + 7.3), hash(cell + 3.1)) - 0.5) * 0.7;
        float twinkle = 0.7 + 0.3 * sin(t * 1.7 + h * 50.0);
        stars = saturate(1.0 - length(g - star) / 22.0 / (1.3 * pixel)) * mix(0.35, 0.9, fract(h * 13.0)) * twinkle;
    }

    float c = max(max(orbits * 0.55, dashed * 0.45) * (1.0 - gap), max(moons, max(square * 0.85, point)));
    c = max(c, stars * (1.0 - gap));
    c *= ground;
    float a = ground * 0.94 * (1.0 - c) + c;
    return float4(ink * ground * 0.94 * (1.0 - c) + light * c, a);
}

// The Orbite: the Blob fades into the centre as the diagram opens around it.
fragment float4 forma_orbite(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float4 out = orbColor<Forma_orbite>(in, u) * (1.0 - u.morph);
    out += orbiteDiagram(orbUV(in, u), u) * u.morph * (1.0 - out.a);
    return out * u.opacity;
}
