// The Orb's shading, shared by the fragment function of every Forma: SDF raymarch ported 1:1 from
// the WebGL shader in reference/bubo.html. Each Forma lives in its own file in Forme/, includes this
// header and ends with ORB_FORMA(name), which makes its pipeline's fragment function `forma_<name>`:
// the Blob blended toward that Forma by u.morph. The Blob alone is `forma_blob`, in Orb.metal.
#pragma once
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 res;
    float t, amp, freq, speed, swirl, spike, glow, audio;
    float frame;      // >1 shrinks the Orb in its view, leaving room for the halo
    float morph;      // 0 = Blob, 1 = the pipeline's Forma; already eased
    float grain, bands, gloss; // Tinta character, 0…1; spikes are in `spike`
    float opacity;    // the whole Orb's, halo included; below 1 only in the Reduce Motion fade
    float diagramTime; // the Orbite diagram's clock, seconds; still at 0 with Reduce Motion
    float3 a, b;      // Tinta: base and highlight
};

struct VOut { float4 pos [[position]]; };

static inline float3 m289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static inline float4 m289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static inline float4 perm(float4 x) { return m289(((x * 34.0) + 1.0) * x); }
static inline float4 tis(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

static inline float sn(float3 v) {
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

static inline float2x2 rot(float a) { float c = cos(a), s = sin(a); return float2x2(float2(c, -s), float2(s, c)); }

static inline float sdSegment(float3 p, float3 a, float3 b, float r) { float3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) - r; }

// --- Exact primitives (Inigo Quilez's, iquilezles.org/articles/distfunctions). A union (min) of exact
// distances is exact outside; intersections and smooth blends are not, so the Forme avoid them. ---

static inline float dot2(float2 v) { return dot(v, v); }
static inline float dot2(float3 v) { return dot(v, v); }

// A box of half-size b with edges rounded by r (r ≤ b), centred on the origin.
static inline float sdRoundBox(float3 p, float3 b, float r) {
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// A cylinder of radius r along y, from -h to h.
static inline float sdCylinder(float3 p, float r, float h) {
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// A truncated cone along y: radius r1 at -h, r2 at h.
static inline float sdCappedCone(float3 p, float h, float r1, float r2) {
    float2 q = float2(length(p.xz), p.y);
    float2 k1 = float2(r2, h), k2 = float2(r2 - r1, 2.0 * h);
    float2 ca = float2(q.x - min(q.x, q.y < 0.0 ? r1 : r2), abs(q.y) - h);
    float2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot2(k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(ca), dot2(cb)));
}

// A cone with spherical ends: radius r1 around a, r2 around b; needs |r1 - r2| < |b - a|.
static inline float sdRoundCone(float3 p, float3 a, float3 b, float r1, float r2) {
    float3 ba = b - a;
    float l2 = dot(ba, ba), rr = r1 - r2, a2 = l2 - rr * rr, il2 = 1.0 / l2;
    float3 pa = p - a;
    float y = dot(pa, ba), z = y - l2;
    float x2 = dot2(pa * l2 - ba * y), y2 = y * y * l2, z2 = z * z * l2;
    float k = sign(rr) * rr * rr * x2;
    if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
    if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
    return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}

// A torus in the xy plane: ring radius R, tube radius r.
static inline float sdTorusXY(float3 p, float R, float r) { return length(float2(length(p.xy) - R, p.z)) - r; }

// Unsigned distance to the 2D segment ab.
static inline float udSegment2(float2 p, float2 a, float2 b) { float2 pa = p - a, ba = b - a; return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)); }

// Unsigned distance to the quarter circle of radius R around c that lies in the quadrant (sx, sy), signs ±1.
static inline float udQuarterArc(float2 p, float2 c, float R, float2 quadrant) {
    float2 q = (p - c) * quadrant;
    if (q.x >= 0.0 && q.y >= 0.0) return abs(length(q) - R);
    return min(length(q - float2(R, 0)), length(q - float2(0, R)));
}

// The 2D quadrilateral v0 v1 v2 v3, exact inside and out.
static inline float sdQuad2(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float2 v[4] = { v0, v1, v2, v3 };
    float d = dot2(p - v[0]), s = 1.0;
    for (int i = 0, j = 3; i < 4; j = i, i++) {
        float2 e = v[j] - v[i], w = p - v[i];
        d = min(d, dot2(w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0)));
        bool3 c = bool3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
        if (all(c) || all(!c)) s = -s;
    }
    return s * sqrt(d);
}

// A 2D box of half-size b with corners rounded by r.
static inline float sdRoundBox2(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// The 2D heart: tip at the origin, lobes up to y ≈ 1.1, half-width ≈ 0.6.
static inline float sdHeart2(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) return sqrt(dot2(p - float2(0.25, 0.75))) - sqrt(2.0) / 4.0;
    return sqrt(min(dot2(p - float2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// The 2D five-pointed star of outer radius r; rf sets how deep the points are cut.
static inline float sdStar5(float2 p, float r, float rf) {
    const float2 k1 = float2(0.809016994375, -0.587785252292), k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0, 1);
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// A 2D distance d2 pulled along z into a slab of half-depth h: exact outside wherever d2 is exact outside.
static inline float extrude(float d2, float z, float h) {
    float2 w = float2(d2, abs(z) - h);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

// A smooth 0…1…0 pulse of half-width w centred at c.
static inline float pulse(float x, float c, float w) { float k = clamp(1.0 - abs(x - c) / w, 0.0, 1.0); return k * k * (3.0 - 2.0 * k); }

// --- How every Forma is drawn. A Forma's SDF must be nearly exact outside the solid (gradient close
// to 1): the halo reads the ray's closest distance, and an underestimate shows up as streaks. Every
// Forma is a union of exact pieces, moved only by rotations, translations and uniform scales, which
// keep it exact. Its own motion runs on the shader clock, which Reduce Motion slows down. Each fits
// in a radius of about 1.1 and faces the camera (+z); y is up.

// Forma F, gently swaying so it reads as 3D.
template <typename F>
static inline float formaDistance(float3 p, float t) {
    float3 q = p;
    q.xz = q.xz * rot(sin(t * 0.5) * 0.45);
    return F::distance(q, t);
}

// map() of the reference: the Blob blended toward Forma F by u.morph.
template <typename F>
static inline float map(float3 p, constant Uniforms &u) {
    float blob = 1.0 - u.morph;                        // swirl and turn belong to the Blob
    float3 q = p;
    q.xz = q.xz * rot((u.swirl * 0.7 * sin(u.t * 0.6 + p.y * 2.2) + u.t * 0.12) * blob);
    // A Forma keeps a little of the Stato's ripple (F::ripple()).
    float na = mix(1.0, F::ripple(), u.morph);
    float n = sn(q * u.freq + float3(0, 0, u.t * u.speed));
    float n2 = sn(q * u.freq * 2.2 - float3(u.t * u.speed * 0.6));
    float sp = u.spike > 0 ? pow(max(0.0, sn(q * 4.5 + u.t * 0.5)), 3.0) * u.spike : 0.0;
    float a = (u.amp + u.audio * 0.22) * na;
    float d = length(q) - 0.92;
    if (!F::isBlob()) d = mix(d, formaDistance<F>(q, u.t), u.morph);
    d -= (n * 0.7 + n2 * 0.3) * a + sp * 0.4 * na;
    // Grain is not damped on a Forma: it keeps a Tinta recognizable where spikes fade.
    // Only near the surface: far steps skip a fourth noise, and grain (≤ 0.022) is below the band.
    if (u.grain > 0 && d < 0.06) d -= sn(q * 11.0 + float3(0, u.t * 0.15, 0)) * u.grain * 0.022;
    return d;
}

// The fragment's position in the Orb's view: y up, the shorter side from -1 to 1.
static inline float2 orbUV(VOut in, constant Uniforms &u) {
    float2 fc = float2(in.pos.x, u.res.y - in.pos.y); // gl_FragCoord has y up
    return (fc * 2.0 - u.res) / u.res.y;
}

// The Orb as Forma F, premultiplied and before u.opacity.
template <typename F>
static inline float4 orbColor(VOut in, constant Uniforms &u) {
    float2 uv = orbUV(in, u);
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
            float d = map<F>(ro + rd * t, u);
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
        float3 n = normalize(float3(map<F>(p + e.xyy, u) - map<F>(p - e.xyy, u),
                                    map<F>(p + e.yxy, u) - map<F>(p - e.yxy, u),
                                    map<F>(p + e.yyx, u) - map<F>(p - e.yyx, u)));
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
    // The halo fades to zero before the view's shorter side: at the edge it is still ~3% and
    // the cut shows the view's square.
    float g = exp(-max(md, 0.0) * 5.5) * u.glow * 0.55 * (1.0 - smoothstep(0.7, 1.0, length(uv)));
    if (!hit) { col = u.a * g + u.b * g * g * 0.4; al = clamp(g, 0.0, 1.0); }
    col = col / (1.0 + col * 0.35);
    return float4(col, al); // premultiplied
}

// The distance of Forma `name`, for the GPU probe of the tests only (FormaTests).
#ifdef FORMA_PROBE
#define ORB_FORMA_PROBE(name) \
    kernel void probe_##name(device const float4 *points [[buffer(0)]], device float *distances [[buffer(1)]], \
                             uint i [[thread_position_in_grid]]) { \
        distances[i] = formaDistance<Forma_##name>(points[i].xyz, points[i].w); \
    }
#else
#define ORB_FORMA_PROBE(name)
#endif

// Forma `name` drawn by the SDF `static float name(float3 p, float t)`, keeping `ripple` of the
// Stato's ripple; for a Forma that writes its own fragment function, like the Orbite.
#define ORB_FORMA_SDF(name, rippleKept) \
    struct Forma_##name { \
        static float distance(float3 p, float t) { return name(p, t); } \
        static float ripple() { return rippleKept; } \
        static bool isBlob() { return false; } \
    }; \
    ORB_FORMA_PROBE(name)

// Forma `name`: its SDF `static float name(float3 p, float t)` and its fragment function `forma_<name>`.
#define ORB_FORMA(name) \
    ORB_FORMA_SDF(name, 0.28) \
    fragment float4 forma_##name(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) { \
        return orbColor<Forma_##name>(in, u) * u.opacity; \
    }
