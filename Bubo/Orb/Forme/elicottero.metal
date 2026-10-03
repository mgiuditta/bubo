#include "../OrbShading.h"

// Viaggi · voli panoramici: a helicopter in profile, with skids and a tail boom; the main and tail rotors turn.
static float elicottero(float3 p, float t) {
    p.x -= 0.1;
    p.y -= 0.05;
    float cabin = sdSegment(p, float3(-0.05, -0.05, 0), float3(0.3, -0.05, 0), 0.34);
    float boom = sdRoundCone(p, float3(-0.2, 0.04, 0), float3(-0.9, 0.12, 0), 0.14, 0.05);
    float fin = sdSegment(p, float3(-0.88, 0.12, 0), float3(-0.96, 0.4, 0), 0.05);
    float mast = sdSegment(p, float3(0.1, 0.25, 0), float3(0.1, 0.5, 0), 0.06);
    float3 r = p - float3(0.1, 0.52, 0);
    r.xz = r.xz * rot(t * 9.0);
    float blades = min(sdSegment(r, float3(-0.95, 0, 0), float3(0.95, 0, 0), 0.045), sdSegment(r, float3(0, 0, -0.95), float3(0, 0, 0.95), 0.045));
    float3 tr = p - float3(-0.9, 0.22, 0.08);
    tr.yz = tr.yz * rot(t * 12.0);
    float tail = sdSegment(tr, float3(0, -0.2, 0), float3(0, 0.2, 0), 0.03);
    float skids = min(sdSegment(p, float3(-0.35, -0.6, 0.2), float3(0.7, -0.6, 0.2), 0.04), sdSegment(p, float3(-0.35, -0.6, -0.2), float3(0.7, -0.6, -0.2), 0.04));
    float struts = min(sdSegment(p, float3(-0.1, -0.3, 0.12), float3(-0.1, -0.6, 0.2), 0.035), sdSegment(p, float3(0.45, -0.3, 0.12), float3(0.45, -0.6, 0.2), 0.035));
    return min(min(min(cabin, boom), min(fin, mast)), min(min(blades, tail), min(skids, struts)));
}

ORB_FORMA(elicottero)
