#include "../OrbShading.h"

// Mail: a megaphone, the bell to the right, with its rear block and a pistol grip.
static float megafono(float3 p, float) {
    float horn = sdCappedCone(float3(p.y, p.x - 0.05, p.z), 0.45, 0.15, 0.50);
    float rim = sdCylinder(float3(p.y, p.x - 0.50, p.z), 0.53, 0.04);
    float rear = sdCylinder(float3(p.y, p.x + 0.55, p.z), 0.20, 0.15);
    float grip = sdSegment(p, float3(-0.15, -0.15, 0), float3(-0.28, -0.62, 0), 0.07);
    return min(min(horn, rim), min(rear, grip));
}

ORB_FORMA(megafono)
