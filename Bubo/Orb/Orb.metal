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
    float opacity;    // the whole Orb's, halo included; below 1 only in the Reduce Motion fade
    float diagramTime; // the Orbite diagram's clock, seconds; still at 0 with Reduce Motion
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

// --- Exact primitives (Inigo Quilez's, iquilezles.org/articles/distfunctions). A union (min) of exact
// distances is exact outside; intersections and smooth blends are not, so the Forme avoid them. ---

static float dot2(float2 v) { return dot(v, v); }
static float dot2(float3 v) { return dot(v, v); }

// A box of half-size b with edges rounded by r (r ≤ b), centred on the origin.
static float sdRoundBox(float3 p, float3 b, float r) {
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// A cylinder of radius r along y, from -h to h.
static float sdCylinder(float3 p, float r, float h) {
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// A truncated cone along y: radius r1 at -h, r2 at h.
static float sdCappedCone(float3 p, float h, float r1, float r2) {
    float2 q = float2(length(p.xz), p.y);
    float2 k1 = float2(r2, h), k2 = float2(r2 - r1, 2.0 * h);
    float2 ca = float2(q.x - min(q.x, q.y < 0.0 ? r1 : r2), abs(q.y) - h);
    float2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot2(k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(ca), dot2(cb)));
}

// A cone with spherical ends: radius r1 around a, r2 around b; needs |r1 - r2| < |b - a|.
static float sdRoundCone(float3 p, float3 a, float3 b, float r1, float r2) {
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
static float sdTorusXY(float3 p, float R, float r) { return length(float2(length(p.xy) - R, p.z)) - r; }

// Unsigned distance to the 2D segment ab.
static float udSegment2(float2 p, float2 a, float2 b) { float2 pa = p - a, ba = b - a; return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)); }

// Unsigned distance to the quarter circle of radius R around c that lies in the quadrant (sx, sy), signs ±1.
static float udQuarterArc(float2 p, float2 c, float R, float2 quadrant) {
    float2 q = (p - c) * quadrant;
    if (q.x >= 0.0 && q.y >= 0.0) return abs(length(q) - R);
    return min(length(q - float2(R, 0)), length(q - float2(0, R)));
}

// The 2D quadrilateral v0 v1 v2 v3, exact inside and out.
static float sdQuad2(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
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
static float sdRoundBox2(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// The 2D heart: tip at the origin, lobes up to y ≈ 1.1, half-width ≈ 0.6.
static float sdHeart2(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) return sqrt(dot2(p - float2(0.25, 0.75))) - sqrt(2.0) / 4.0;
    return sqrt(min(dot2(p - float2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// The 2D five-pointed star of outer radius r; rf sets how deep the points are cut.
static float sdStar5(float2 p, float r, float rf) {
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
static float extrude(float d2, float z, float h) {
    float2 w = float2(d2, abs(z) - h);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

// A smooth 0…1…0 pulse of half-width w centred at c.
static float pulse(float x, float c, float w) { float k = clamp(1.0 - abs(x - c) / w, 0.0, 1.0); return k * k * (3.0 - 2.0 * k); }

// --- Forme: one SDF per Forma, named as `forma` in catalogo.json. ---
// Each must be nearly exact outside the solid (gradient close to 1): the halo reads the
// ray's closest distance, and an underestimate shows up as streaks. Every Forma is a union of
// exact pieces, moved only by rotations, translations and uniform scales, which keep it exact.
// Their own motion runs on the shader clock, which Reduce Motion slows down.
// Each fits in a radius of about 1.1 and faces the camera (+z); y is up.

// Ricerca: a magnifying glass: ring, glass (a thin disc) and handle.
static float lente(float3 p) {
    const float scale = 1.2;                           // uniform scale keeps the SDF exact
    p /= scale;
    float3 c = float3(-0.14, 0.16, 0);
    float3 q = p - c;
    float ring = length(float2(length(q.xy) - 0.40, q.z)) - 0.08;
    float glass = extrude(length(q.xy) - 0.36, q.z, 0.015);
    float handle = sdSegment(p, c + float3(0.34, -0.34, 0), float3(0.62, -0.64, 0), 0.10);
    return min(min(ring, glass), handle) * scale;
}

// Orbite: the Blob shrinks to a small sphere at the centre while the diagram opens around it.
static float orbite(float3 p) {
    return length(p) - 0.12;
}

// Meteo: a cloud. Three puffs on a flat-bottomed base; the puffs bob slowly, out of step.
static float nuvola(float3 p, float t) {
    p.y += 0.09;
    float base = sdRoundBox(p - float3(0, -0.24, 0), float3(0.62, 0.24, 0.27), 0.24);
    float left = length(p - float3(-0.40, 0.04 + 0.02 * sin(t * 0.9), 0)) - 0.36;
    float top = length(p - float3(0.06, 0.22 + 0.025 * sin(t * 0.9 + 2.1), 0)) - 0.48;
    float right = length(p - float3(0.50, 0.0 + 0.02 * sin(t * 0.9 + 4.2), 0)) - 0.32;
    return min(min(base, left), min(top, right));
}

// Salute: a plump heart, beating lub-dub about fifty times a minute.
static float cuore(float3 p, float t) {
    float phase = fract(t / 1.2 + 0.5);                // t = 0 is between beats
    float s = 1.0 + 0.07 * pulse(phase, 0.1, 0.09) + 0.045 * pulse(phase, 0.3, 0.09);
    p /= s;
    const float size = 1.32, round = 0.15;
    float2 q = (p.xy + float2(0, 0.74)) / size;
    float heart = sdHeart2(q) * size;                  // exact inside too, so it can be shrunk
    return (extrude(heart + round, p.z, 0.05) - round) * s;
}

// Mail: a closed envelope, its flap drawn as a raised V on the front.
static float busta(float3 p) {
    float body = sdRoundBox(p, float3(0.84, 0.56, 0.08), 0.05);
    float3 q = float3(abs(p.x), p.y, p.z);
    float flap = sdSegment(q, float3(0.74, 0.46, 0.10), float3(0.0, -0.06, 0.10), 0.05);
    return min(body, flap);
}

// Tempo: an hourglass frame with its sand. The sand runs from the top cone into a growing pile,
// then the frame turns over and starts again.
static float clessidra(float3 p, float t) {
    const float period = 8.0, flow = 0.85;             // fraction of the period spent flowing
    float phase = fract(t / period + 0.42);            // t = 0 is halfway through
    float f = min(phase / flow, 1.0);                  // how much sand has fallen
    p.xy = p.xy * rot(M_PI_F * smoothstep(flow, 1.0, phase));
    float3 q = float3(abs(p.x), abs(p.y), p.z);
    float plate = sdCylinder(q - float3(0, 0.80, 0), 0.50, 0.035) - 0.025;
    float post = sdSegment(q, float3(0.44, 0, 0), float3(0.44, 0.78, 0), 0.04);
    const float neck = 0.05, rim = 0.66, wide = 0.40, narrow = 0.03;
    float level = neck + (rim - neck) * (1.0 - f);     // top of the sand above the neck
    float topH = max((level - neck) * 0.5, 0.004);
    float upper = sdCappedCone(p - float3(0, neck + topH, 0), topH,
                               narrow, narrow + (wide - narrow) * (1.0 - f));
    float pileH = max((rim - neck) * f * 0.5, 0.004);
    float lower = sdCappedCone(p - float3(0, -rim + pileH, 0), pileH, narrow + (wide - narrow) * f, narrow);
    float d = min(min(plate, post), min(upper, lower));
    if (f < 0.98) d = min(d, sdSegment(p, float3(0, neck, 0), float3(0, -rim + 2.0 * pileH, 0), 0.016));
    return d;
}

// Codice: a pair of curly brackets, one bent tube folded into four.
static float parentesi(float3 p) {
    float2 q = float2(-abs(p.x), abs(p.y));            // the upper half of the left bracket
    const float x = -0.40, top = 0.80, a = 0.22;
    float hook = udQuarterArc(q, float2(x + a, top - a), a, float2(-1, 1));
    float stem = udSegment2(q, float2(x, top - a), float2(x, a));
    float cusp = udQuarterArc(q, float2(x - a, a), a, float2(1, -1));
    return length(float2(min(hook, min(stem, cusp)), p.z)) - 0.085;
}

// Musica: two beamed eighth notes, hopping to a slow beat.
static float nota(float3 p, float t) {
    p.y -= 0.03 * abs(sin(t * 2.6));
    const float2 tilt = float2(0.906, 0.423) * 0.09;   // the heads lean 25°
    float3 h1 = float3(-0.38, -0.52, 0), h2 = float3(0.34, -0.40, 0);
    float3 d = float3(tilt, 0);
    float heads = min(sdSegment(p, h1 - d, h1 + d, 0.17), sdSegment(p, h2 - d, h2 + d, 0.17));
    float stems = min(sdSegment(p, float3(-0.22, -0.48, 0), float3(-0.22, 0.56, 0), 0.045),
                      sdSegment(p, float3(0.50, -0.36, 0), float3(0.50, 0.68, 0), 0.045));
    float beam = sdSegment(p, float3(-0.22, 0.56, 0), float3(0.50, 0.68, 0), 0.075);
    return min(heads, min(stems, beam));
}

// Creativo: a round paintbrush, tip down to the left, making a slow stroke.
static float pennello(float3 p, float t) {
    const float2 pivot = float2(0.45, 0.45);
    p.xy = (p.xy - pivot) * rot(0.12 * sin(t * 1.4)) + pivot;
    const float3 u = float3(0.7071, 0.7071, 0), tip = float3(-0.72, -0.72, 0);
    float belly = sdRoundCone(p, tip + u * 0.04, tip + u * 0.40, 0.025, 0.21);
    float shoulder = sdRoundCone(p, tip + u * 0.40, tip + u * 0.62, 0.21, 0.15);
    float ferrule = sdSegment(p, tip + u * 0.66, tip + u * 0.94, 0.155);
    float handle = sdRoundCone(p, tip + u * 0.98, tip + u * 1.92, 0.12, 0.065);
    return min(min(belly, shoulder), min(ferrule, handle));
}

// Finanza: a coin with a raised rim and a star, turned three quarters; now and then it spins once.
static float moneta(float3 p, float t) {
    float turn = 0.5 + 2.0 * M_PI_F * smoothstep(0.75, 1.0, fract(t / 6.0));
    p.xz = p.xz * rot(turn);
    float disc = extrude(length(p.xy) - 0.69, p.z, 0.05) - 0.03;
    float3 q = float3(p.xy, abs(p.z));                 // both faces alike
    float rim = sdTorusXY(q - float3(0, 0, 0.085), 0.66, 0.045);
    float star = extrude(sdStar5(p.xy, 0.36, 0.45), q.z - 0.09, 0.025) - 0.01;
    return min(disc, min(rim, star));
}

// Viaggi: an airliner seen from above, heading up to the right, rolling gently.
static float aereo(float3 p, float t) {
    p.xy = p.xy * rot(-M_PI_F * 0.25);                 // nose along +y
    p.y -= 0.04 * sin(t * 0.8);
    p.xz = p.xz * rot(0.18 * sin(t * 0.7));
    float3 q = float3(abs(p.x), p.y, p.z);
    float body = sdSegment(p, float3(0, -0.70, 0), float3(0, 0.68, 0), 0.11);
    float wing = extrude(sdQuad2(q.xy, float2(0.08, 0.22), float2(0.86, -0.14), float2(0.86, -0.27), float2(0.08, -0.12)),
                         q.z, 0.01) - 0.02;
    float tail = extrude(sdQuad2(q.xy, float2(0.06, -0.48), float2(0.34, -0.68), float2(0.34, -0.77), float2(0.06, -0.66)),
                         q.z, 0.01) - 0.015;
    float fin = extrude(sdQuad2(p.yz, float2(-0.46, 0.0), float2(-0.72, 0.30), float2(-0.79, 0.30), float2(-0.73, 0.0)),
                        p.x, 0.01) - 0.015;
    float engine = sdSegment(q, float3(0.36, 0.12, -0.07), float3(0.36, -0.10, -0.07), 0.06);
    return min(min(body, wing), min(min(tail, fin), engine));
}

// Chat: a speech bubble with its tail down to the left; three dots on the front rise in turn, like typing.
static float fumetto(float3 p, float t) {
    float bubble2 = min(sdRoundBox2(p.xy - float2(0, 0.12), float2(0.76, 0.48), 0.26),
                        sdQuad2(p.xy, float2(-0.50, -0.20), float2(-0.14, -0.20), float2(-0.56, -0.70), float2(-0.63, -0.69)));
    float d = extrude(bubble2, p.z, 0.05) - 0.08;
    for (int i = 0; i < 3; i++) {
        float lift = max(sin(t * 4.0 - float(i) * 0.9), 0.0);
        d = min(d, length(p - float3(-0.32 + 0.32 * float(i), 0.12, 0.10 + 0.03 * lift)) - 0.085);
    }
    return d;
}

// Agente: a generic robot head with ears and an antenna; it blinks every few seconds.
static float robot(float3 p, float t) {
    p.y += 0.14;
    float head = sdRoundBox(p - float3(0, -0.05, 0), float3(0.56, 0.46, 0.32), 0.16);
    float3 q = float3(abs(p.x), p.y, p.z);
    float ear = sdCylinder((q - float3(0.60, -0.04, 0)).yxz, 0.12, 0.08) - 0.01;
    float close = pulse(fract(t / 4.0), 0.9, 0.03);     // 1 with the eyes shut
    float L = 0.11 * close, r = mix(0.13, 0.03, close);
    float2 e = q.xy - float2(0.24, 0.04);
    float eye = extrude(length(e - float2(clamp(e.x, -L, L), 0)) - r, p.z - 0.32, 0.05) - 0.015;
    float mouth = sdSegment(p, float3(-0.18, -0.25, 0.32), float3(0.18, -0.25, 0.32), 0.035);
    float3 a = p - float3(0, 0.41, 0);                 // the antenna sways around its base
    a.xy = a.xy * rot(0.12 * sin(t * 1.7));
    float antenna = min(sdSegment(a, float3(0), float3(0, 0.30, 0), 0.03), length(a - float3(0, 0.36, 0)) - 0.08);
    return min(min(head, ear), min(min(eye, mouth), antenna));
}

// The pipeline's Forma, gently swaying so it reads as 3D.
static float forma(float3 p, float t) {
    float3 q = p;
    q.xz = q.xz * rot(sin(t * 0.5) * 0.45);
    switch (FORMA) {
        case 1: return lente(q);
        case 2: return nuvola(q, t);
        case 3: return cuore(q, t);
        case 4: return busta(q);
        case 5: return clessidra(q, t);
        case 6: return parentesi(q);
        case 7: return nota(q, t);
        case 8: return pennello(q, t);
        case 9: return moneta(q, t);
        case 10: return aereo(q, t);
        case 11: return fumetto(q, t);
        case 12: return robot(q, t);
        case 13: return orbite(q);
        default: return length(p) - 0.92;
    }
}

// map() of the reference: the Blob blended toward the Forma by u.morph.
static float map(float3 p, constant Uniforms &u) {
    float blob = 1.0 - u.morph;                        // swirl and turn belong to the Blob
    float3 q = p;
    q.xz = q.xz * rot((u.swirl * 0.7 * sin(u.t * 0.6 + p.y * 2.2) + u.t * 0.12) * blob);
    // A Forma keeps a little of the Stato's ripple; the Orbite none, or its small sphere would crumple.
    float na = mix(1.0, FORMA == 13 ? 0.0 : 0.28, u.morph);
    float n = sn(q * u.freq + float3(0, 0, u.t * u.speed));
    float n2 = sn(q * u.freq * 2.2 - float3(u.t * u.speed * 0.6));
    float sp = u.spike > 0 ? pow(max(0.0, sn(q * 4.5 + u.t * 0.5)), 3.0) * u.spike : 0.0;
    float a = (u.amp + u.audio * 0.22) * na;
    float d = length(q) - 0.92;
    if (FORMA != 0) d = mix(d, forma(q, u.t), u.morph);
    d -= (n * 0.7 + n2 * 0.3) * a + sp * 0.4 * na;
    // Grain is not damped on a Forma: it keeps a Tinta recognizable where spikes fade.
    // Only near the surface: far steps skip a fourth noise, and grain (≤ 0.022) is below the band.
    if (u.grain > 0 && d < 0.06) d -= sn(q * 11.0 + float3(0, u.t * 0.15, 0)) * u.grain * 0.022;
    return d;
}

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
    float4 out = float4(col, al); // premultiplied
    if (FORMA == 13) {
        // The Orbite: the Blob fades into the centre as the diagram opens around it.
        out *= 1.0 - u.morph;
        out += orbiteDiagram(uv, u) * u.morph * (1.0 - out.a);
    }
    return out * u.opacity;
}
