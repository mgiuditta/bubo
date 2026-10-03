#include "../OrbShading.h"

// Creativo: a treasure chest with a barrel lid and a lock; the lid opens a little at the front and shuts again.
static float forziere(float3 p, float t) {
    float body = sdRoundBox(p - float3(0, -0.45, 0), float3(0.55, 0.3, 0.4), 0.03);
    float lock = sdRoundBox(p - float3(0, -0.2, 0.4), float3(0.1, 0.12, 0.05), 0.02);
    float a = 0.18 * (0.5 - 0.5 * cos(t * 1.2));
    float3 q = p - float3(0, -0.15, -0.4);                // the lid turns about its back hinge
    q.yz = q.yz * rot(a);
    q.z -= 0.4;
    float lid = sdCylinder(q.xzy, 0.55, 0.4);
    float rim = sdRoundBox(q, float3(0.58, 0.04, 0.43), 0.02);
    return min(min(body, lock), min(lid, rim));
}

ORB_FORMA(forziere)
