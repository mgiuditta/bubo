#include "../OrbShading.h"

// Chat: a triangular prism with a ray that comes in on the left and fans out in three on the right.
static float prisma(float3 p, float) {
    float tri = sdQuad2(p.xy, float2(-0.65, -0.5), float2(0.25, -0.5), float2(-0.2, 0.35), float2(-0.425, -0.075));
    float glass = extrude(tri, p.z, 0.22) - 0.03;
    float3 out0 = float3(0.025, -0.075, 0);
    float rays = min(sdSegment(p, float3(-0.98, 0.05, 0), float3(-0.425, -0.075, 0), 0.05),
                     min(sdSegment(p, out0, float3(0.90, 0.35, 0), 0.05),
                         min(sdSegment(p, out0, float3(0.98, -0.08, 0), 0.05),
                             sdSegment(p, out0, float3(0.90, -0.52, 0), 0.05))));
    return min(glass, rays);
}

ORB_FORMA(prisma)
