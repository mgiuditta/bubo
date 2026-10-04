#include "../OrbShading.h"

// The tower's radius at height y.
static float faroRadius(float y) { return 0.38 - 0.13 * (y + 0.7); }

// Viaggi: a lighthouse, a tapering striped tower with a gallery, a lantern and a roof; two beams of light turn around it.
static float faro(float3 p, float t) {
    float tower = sdCappedCone(p - float3(0, -0.2, 0), 0.5, 0.38, 0.25);
    float bands = min(sdCylinder(p - float3(0, -0.5, 0), faroRadius(-0.5) + 0.03, 0.07), sdCylinder(p - float3(0, -0.1, 0), faroRadius(-0.1) + 0.03, 0.07));
    float base = sdCylinder(p - float3(0, -0.74, 0), 0.5, 0.06);
    float gallery = sdCylinder(p - float3(0, 0.33, 0), 0.34, 0.03);
    float lantern = sdCylinder(p - float3(0, 0.5, 0), 0.17, 0.14);
    float roof = sdCappedCone(p - float3(0, 0.73, 0), 0.09, 0.24, 0.02);
    float tip = length(p - float3(0, 0.86, 0)) - 0.04;
    float d = min(min(tower, bands), min(base, min(gallery, min(lantern, min(roof, tip)))));
    float a = t * 1.2;
    float3 dir = float3(cos(a), 0, sin(a));
    float3 lamp = float3(0, 0.5, 0);
    d = min(d, min(sdRoundCone(p, lamp, lamp + dir * 0.85, 0.04, 0.14), sdRoundCone(p, lamp, lamp - dir * 0.85, 0.04, 0.14)));
    return d;
}

ORB_FORMA(faro)
