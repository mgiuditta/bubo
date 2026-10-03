#include "../OrbShading.h"

// Mail: a desk tray seen from above, with two sheets lying in it.
static float vassoio(float3 p, float) {
    float3 q = p;
    q.yz = p.yz * rot(-0.5);                           // tipped toward the camera
    q.y += 0.05;
    float floor_ = sdRoundBox(q, float3(0.76, 0.05, 0.52), 0.02);
    float sides = sdRoundBox(float3(abs(q.x), q.y, q.z) - float3(0.72, 0.13, 0), float3(0.05, 0.14, 0.52), 0.02);
    float back = sdRoundBox(q - float3(0, 0.13, -0.48), float3(0.76, 0.14, 0.05), 0.02);
    float front = sdRoundBox(q - float3(0, 0.07, 0.48), float3(0.76, 0.08, 0.05), 0.02);
    float3 s1 = q - float3(-0.04, 0.10, 0.02);
    s1.xz = s1.xz * rot(-0.10);
    float3 s2 = q - float3(0.06, 0.17, -0.03);
    s2.xz = s2.xz * rot(0.08);
    float sheet1 = sdRoundBox(s1, float3(0.50, 0.035, 0.36), 0.01);
    float sheet2 = sdRoundBox(s2, float3(0.46, 0.035, 0.34), 0.01);
    return min(min(min(floor_, sides), min(back, front)), min(sheet1, sheet2));
}

ORB_FORMA(vassoio)
