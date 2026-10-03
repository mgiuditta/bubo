#include "../OrbShading.h"

// Ricerca: a globe on a tilted arc stand, turning on its axis; its equator, a meridian and a few lands show the turn.
static float globo(float3 p, float t) {
    const float tilt = 0.40, R = 0.50, arc = 0.64;
    const float3 c = float3(0, 0.12, 0);
    float3 q = p - c;
    q.xy = q.xy * rot(tilt);                           // the axis is q.y
    float stand = abs(length(q.xy) - arc);             // the arc on the -x side, between the two pivots
    if (q.x > 0.0) stand = min(length(q.xy - float2(0, arc)), length(q.xy + float2(0, arc)));
    float d = length(float2(stand, q.z)) - 0.04;
    float3 g = q;
    g.xz = g.xz * rot(t * 0.6);                        // the spin
    d = min(d, length(g) - R);
    d = min(d, length(float2(length(g.xz) - R, g.y)) - 0.03);  // equator
    d = min(d, sdTorusXY(g, R, 0.03));                          // meridian
    d = min(d, length(g - float3(0.30, 0.25, 0.25)) - 0.14);    // lands
    d = min(d, length(g - float3(-0.32, -0.12, 0.28)) - 0.15);
    d = min(d, length(g - float3(0.05, -0.30, -0.36)) - 0.13);
    float3 pivot = c - arc * float3(sin(tilt), cos(tilt), 0);
    float3 foot = float3(0, -0.76, 0);
    d = min(d, sdSegment(p, pivot, foot, 0.05));
    return min(d, sdCylinder(p - float3(0, -0.80, 0), 0.30, 0.02) - 0.03);
}

ORB_FORMA(globo)
