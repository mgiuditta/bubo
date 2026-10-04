#include "../OrbShading.h"

// One tile standing on its bottom edge, its right foot as the pivot, leaning `a` radians toward +x.
static float dominoTile(float3 p, float cx, float a) {
    float2 pivot = float2(cx + 0.11, -0.45);
    float2 q = (p.xy - pivot) * rot(a) - float2(-0.11, 0.45); // centred on the tile
    float3 l = float3(q, p.z);
    float tile = sdRoundBox(l, float3(0.11, 0.45, 0.2), 0.04);
    float bar = sdSegment(l, float3(-0.07, 0, 0.2), float3(0.07, 0, 0.2), 0.035); // the line across its face
    return min(tile, bar);
}

// Agente · automazioni: three domino tiles in a row, the last one already leaning; the first two fall in turn.
static float domino(float3 p, float t) {
    float u = fract(t / 5.0);
    float reset = 1.0 - smoothstep(0.9, 1.0, u);
    float a0 = 0.35 * smoothstep(0.2, 0.35, u) * reset;
    float a1 = 0.35 * smoothstep(0.4, 0.55, u) * reset;
    return min(dominoTile(p, -0.6, a0), min(dominoTile(p, -0.05, a1), dominoTile(p, 0.5, 0.35)));
}

ORB_FORMA(domino)
