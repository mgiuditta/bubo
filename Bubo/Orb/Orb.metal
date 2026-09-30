// The Orb: SDF raymarch ported 1:1 from the WebGL shader in reference/bubo.html.
// One pipeline per Forma: the FORMA function constant picks the Forma's SDF, and every
// pipeline includes the Blob, so a Morph blends the two. FORMA 0 is the Blob alone.
#include <metal_stdlib>
using namespace metal;

constant int FORMA [[function_constant(0)]];

struct Uniforms {
    float2 res;
    float t, amp, freq, speed, swirl, spike, glow, audio;
    float frame;      // >1 shrinks the Orb in its view, leaving room for the halo
    float morph;      // 0 = Blob, 1 = the pipeline's Forma; already eased
    float grain, bands, gloss; // Tinta character, 0…1; spikes are in `spike`
    float3 a, b;      // Tinta: base and highlight
};

struct VOut { float4 pos [[position]]; };

vertex VOut orbVertex(uint vid [[vertex_id]]) {
    float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    return { float4(p[vid], 0, 1) };
}

static float3 m289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 m289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 perm(float4 x) { return m289(((x * 34.0) + 1.0) * x); }
static float4 tis(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

static float sn(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);
    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);
    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;
    i = m289(i);
    float4 p = perm(perm(perm(i.z + float4(0.0, i1.z, i2.z, 1.0)) + i.y + float4(0.0, i1.y, i2.y, 1.0)) + i.x + float4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    float3 ns = n_ * D.wyz - D.xzx;
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);
    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 p0 = float3(a0.xy, h.x), p1 = float3(a0.zw, h.y), p2 = float3(a1.xy, h.z), p3 = float3(a1.zw, h.w);
    float4 nr = tis(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= nr.x; p1 *= nr.y; p2 *= nr.z; p3 *= nr.w;
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

static float2x2 rot(float a) { float c = cos(a), s = sin(a); return float2x2(float2(c, -s), float2(s, c)); }

static float sdSegment(float3 p, float3 a, float3 b, float r) { float3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) - r; }

// --- Forme: one SDF per Forma, named as `forma` in catalogo.json. ---
// Each must be nearly exact outside the solid (gradient close to 1): the halo reads the
// ray's closest distance, and an underestimate shows up as streaks.

// Ricerca: a magnifying glass. Ring and handle are exact; the glass is a thin disc.
static float lente(float3 p) {
    const float scale = 1.2;                           // uniform scale keeps the SDF exact
    p /= scale;
    float3 c = float3(-0.14, 0.16, 0);
    float3 q = p - c;
    float ring = length(float2(length(q.xy) - 0.40, q.z)) - 0.08;
    float glass = max(length(q.xy) - 0.36, abs(q.z) - 0.015);
    float handle = sdSegment(p, c + float3(0.34, -0.34, 0), float3(0.62, -0.64, 0), 0.10);
    return min(min(ring, glass), handle) * scale;
}

// The pipeline's Forma, gently swaying so it reads as 3D.
static float forma(float3 p, float t) {
    float3 q = p;
    q.xz = q.xz * rot(sin(t * 0.5) * 0.45);
    switch (FORMA) {
        case 1: return lente(q);
        default: return length(p) - 0.92;
    }
}

// map() of the reference: the Blob blended toward the Forma by u.morph.
static float map(float3 p, constant Uniforms &u) {
    float blob = 1.0 - u.morph;                        // swirl and turn belong to the Blob
    float3 q = p;
    q.xz = q.xz * rot((u.swirl * 0.7 * sin(u.t * 0.6 + p.y * 2.2) + u.t * 0.12) * blob);
    float na = mix(1.0, 0.28, u.morph);                // a Forma keeps a little of the Stato's ripple
    float n = sn(q * u.freq + float3(0, 0, u.t * u.speed));
    float n2 = sn(q * u.freq * 2.2 - float3(u.t * u.speed * 0.6));
    float sp = u.spike > 0 ? pow(max(0.0, sn(q * 4.5 + u.t * 0.5)), 3.0) * u.spike : 0.0;
    float a = (u.amp + u.audio * 0.22) * na;
    float d = length(q) - 0.92;
    if (FORMA != 0) d = mix(d, forma(q, u.t), u.morph);
    // Grain is not damped on a Forma: it keeps a Tinta recognizable where spikes fade.
    float gr = u.grain > 0 ? sn(q * 11.0 + float3(0, u.t * 0.15, 0)) * u.grain * 0.022 : 0.0;
    return d - (n * 0.7 + n2 * 0.3) * a - sp * 0.4 * na - gr;
}

fragment float4 orbFragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 fc = float2(in.pos.x, u.res.y - in.pos.y); // gl_FragCoord has y up
    float2 uv = (fc * 2.0 - u.res) / u.res.y;
    float3 ro = float3(0, 0, 3), rd = normalize(float3(uv * 0.72 * u.frame, -1.6));
    float t = 0.0, md = 9.0;
    bool hit = false;
    bool march = true;
    // Bounding sphere of radius 1.5 (Blob 0.92 + noise + audio + spike, with margin).
    float bq = dot(ro, rd), c = dot(ro, ro) - 1.5 * 1.5, disc = bq * bq - c;
    if (disc < 0.0) {
        md = sqrt(max(dot(ro, ro) - bq * bq, 0.0)) - 0.92; // ray–centre distance, for the halo
        march = false;
    } else {
        t = max(-bq - sqrt(disc), 0.0);
    }
    if (march) {
        for (int i = 0; i < 90; i++) {
            float d = map(ro + rd * t, u);
            md = min(md, d);
            if (d < 0.002) { hit = true; break; }
            t += d * 0.6;
            if (t > 6.0) break;
        }
    }
    float3 col = 0.0;
    float al = 0.0;
    if (hit) {
        float3 p = ro + rd * t;
        float2 e = float2(0.002, 0);
        float3 n = normalize(float3(map(p + e.xyy, u) - map(p - e.xyy, u),
                                    map(p + e.yxy, u) - map(p - e.yxy, u),
                                    map(p + e.yyx, u) - map(p - e.yyx, u)));
        float3 L = normalize(float3(-0.5, 0.7, 0.6));
        float dif = clamp(dot(n, L), 0.0, 1.0);
        float fr = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 2.6);
        float band = sn(p * (2.6 + u.bands * 3.0) + float3(0, u.t * 0.4, 0)) * 0.5 + 0.5;
        col = mix(u.a * 0.18, u.a * 0.95, dif * 0.8 + 0.1);
        col += u.b * pow(band, 3.0) * (0.15 + u.bands * 0.7);
        col += u.b * fr * 1.35;
        col += float3(1.0, 0.93, 0.88) * pow(clamp(dot(reflect(-L, n), -rd), 0.0, 1.0), mix(10.0, 90.0, u.gloss)) * (0.3 + u.gloss * 0.7);
        al = 1.0;
    }
    float g = exp(-max(md, 0.0) * 5.5) * u.glow * 0.55;
    if (!hit) { col = u.a * g + u.b * g * g * 0.4; al = clamp(g, 0.0, 1.0); }
    col = col / (1.0 + col * 0.35);
    return float4(col, al);
}
