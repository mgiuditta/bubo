#include "../OrbShading.h"

// Chat · idee regalo: a wrapped present with ribbon and lid, topped by a bow whose loops flutter.
static float regalo(float3 p, float t) {
    p.y += 0.08;
    float box = sdRoundBox(p - float3(0, -0.2, 0), float3(0.5, 0.35, 0.4), 0.04);
    float lid = sdRoundBox(p - float3(0, 0.25, 0), float3(0.57, 0.1, 0.46), 0.04);
    float ribbonV = sdRoundBox(p - float3(0, -0.05, 0), float3(0.09, 0.52, 0.47), 0.02);
    float ribbonH = sdRoundBox(p - float3(0, -0.2, 0), float3(0.54, 0.09, 0.44), 0.02);
    float d = min(min(box, lid), min(ribbonV, ribbonH));
    float flutter = 0.12 * sin(t * 2.4);
    float3 l = p - float3(-0.22, 0.5, 0);
    l.xy = l.xy * rot(0.5 + flutter);
    float3 r = p - float3(0.22, 0.5, 0);
    r.xy = r.xy * rot(-0.5 - flutter);
    float loops = min(sdTorusXY(l, 0.17, 0.05), sdTorusXY(r, 0.17, 0.05));
    float knot = length(p - float3(0, 0.38, 0)) - 0.1;
    return min(d, min(loops, knot));
}

ORB_FORMA(regalo)
