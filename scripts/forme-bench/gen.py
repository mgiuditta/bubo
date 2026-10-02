#!/usr/bin/env python3
"""Fake Forme for the measurements of ADR 0010: N unique SDFs, each a union of 5-15 exact primitives
(the same ones the real Forme use), laid out three ways:
  perfile/  one .metal per Forma with ORB_FORMA(name)          -> option C (and archive A')
  fc.metal  one fragment, `switch (FORMA)` function constant   -> options A (archive) and B (runtime)
  uber.metal one fragment, runtime `switch` on an index uniform -> option D
Usage: gen.py <out dir> <N> <seed>
"""
import os, random, sys

out, n, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rng = random.Random(seed)
ORB = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../Bubo/Orb')
HEADER = os.path.normpath(os.path.join(ORB, 'OrbShading.h'))

def f(x): return f'{x:.3f}'
def v3(a=0.6): return f'float3({f(rng.uniform(-a, a))}, {f(rng.uniform(-a, a))}, {f(rng.uniform(-0.2, 0.2))})'
def v2(a=0.6): return f'float2({f(rng.uniform(-a, a))}, {f(rng.uniform(-a, a))})'

def piece(i):
    k = rng.randrange(11)
    if k == 0: return f'length(p - {v3()}) - {f(rng.uniform(0.08, 0.4))}'
    if k == 1: return f'sdRoundBox(p - {v3()}, float3({f(rng.uniform(.1,.5))}, {f(rng.uniform(.1,.5))}, {f(rng.uniform(.05,.3))}), 0.04)'
    if k == 2: return f'sdCylinder(p - {v3()}, {f(rng.uniform(.05,.3))}, {f(rng.uniform(.05,.4))})'
    if k == 3: return f'sdCappedCone(p - {v3()}, {f(rng.uniform(.1,.3))}, {f(rng.uniform(.05,.3))}, {f(rng.uniform(.02,.2))})'
    if k == 4: return f'sdRoundCone(p, {v3()}, {v3()}, {f(rng.uniform(.03,.08))}, {f(rng.uniform(.03,.08))})'
    if k == 5: return f'sdTorusXY(p - {v3()}, {f(rng.uniform(.2,.5))}, {f(rng.uniform(.03,.1))})'
    if k == 6: return f'sdSegment(p, {v3()}, {v3()}, {f(rng.uniform(.03,.12))})'
    if k == 7: return f'extrude(sdQuad2(p.xy, {v2()}, {v2()}, {v2()}, {v2()}), p.z, 0.02) - 0.02'
    if k == 8: return f'extrude(sdRoundBox2(p.xy - {v2()}, float2({f(rng.uniform(.1,.5))}, {f(rng.uniform(.1,.5))}), 0.1), p.z, 0.05) - 0.03'
    if k == 9: return f'extrude(sdStar5(p.xy - {v2()}, {f(rng.uniform(.2,.4))}, 0.45), p.z - 0.05, 0.03) - 0.01'
    return f'extrude(sdHeart2((p.xy - {v2()}) * 2.0) * 0.5, p.z, 0.05)'

def sdf(name):
    lines = [f'static float {name}(float3 p, float t) {{']
    if rng.random() < 0.6:
        lines.append(f'    p.xy = p.xy * rot({f(rng.uniform(.05,.2))} * sin(t * {f(rng.uniform(.5,2))}));')
    count = rng.randint(5, 15)
    lines.append(f'    float d = {piece(0)};')
    for i in range(1, count):
        lines.append(f'    d = min(d, {piece(i)});')
    lines.append('    return d;')
    lines.append('}')
    return '\n'.join(lines)

names = [f'fake{seed}_{i}' for i in range(n)]
bodies = [sdf(name) for name in names]

os.makedirs(f'{out}/perfile', exist_ok=True)
for name, body in zip(names, bodies):
    with open(f'{out}/perfile/{name}.metal', 'w') as fh:
        fh.write(f'#include "{HEADER}"\n\n{body}\n\nORB_FORMA({name})\n')
with open(f'{out}/perfile/orb.metal', 'w') as fh:
    fh.write(open(os.path.join(ORB, 'Orb.metal')).read()
             .replace('#include "OrbShading.h"', f'#include "{HEADER}"'))

cases = '\n'.join(f'        case {i + 1}: return {name}(p, t);' for i, name in enumerate(names))
with open(f'{out}/fc.metal', 'w') as fh:
    fh.write(f'''#include "{HEADER}"
constant int FORMA [[function_constant(0)]];
vertex VOut orbVertex(uint vid [[vertex_id]]) {{
    float2 p[3] = {{ float2(-1, -1), float2(3, -1), float2(-1, 3) }};
    return {{ float4(p[vid], 0, 1) }};
}}
{chr(10).join(bodies)}
struct Forma_any {{
    static float distance(float3 p, float t) {{
        switch (FORMA) {{
{cases}
        default: return length(p) - 0.92;
        }}
    }}
    static float ripple() {{ return 0.28; }}
    static bool isBlob() {{ return FORMA == 0; }}
}};
fragment float4 orbFragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {{
    return orbColor<Forma_any>(in, u) * u.opacity;
}}
''')

# Uber: the index comes from the uniforms at run time (diagramTime carries it), so the header's
# template gets the index through a copy where distance() takes it.
header = open(HEADER).read()
header = header.replace('return F::distance(q, t);', 'return F::distance(q, t, index);') \
    .replace('formaDistance(float3 p, float t) {', 'formaDistance(float3 p, float t, int index) {') \
    .replace('formaDistance<F>(q, u.t)', 'formaDistance<F>(q, u.t, int(u.diagramTime))')
with open(f'{out}/uber_header.h', 'w') as fh:
    fh.write(header)
with open(f'{out}/uber.metal', 'w') as fh:
    fh.write(f'''#include "uber_header.h"
vertex VOut orbVertex(uint vid [[vertex_id]]) {{
    float2 p[3] = {{ float2(-1, -1), float2(3, -1), float2(-1, 3) }};
    return {{ float4(p[vid], 0, 1) }};
}}
{chr(10).join(bodies)}
struct Forma_any {{
    static float distance(float3 p, float t, int index) {{
        switch (index) {{
{cases}
        default: return length(p) - 0.92;
        }}
    }}
    static float ripple() {{ return 0.28; }}
    static bool isBlob() {{ return false; }}
}};
fragment float4 orbFragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {{
    return orbColor<Forma_any>(in, u) * u.opacity;
}}
''')
print(len(names))
