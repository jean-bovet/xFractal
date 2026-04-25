#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertexShader(uint vid [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * 0.5 + 0.5;
    return out;
}

// ---- Double-float (DD) arithmetic ------------------------------------------
// Each value is an unevaluated sum (hi + lo) where |lo| <= 0.5 ulp(hi).
// References: Dekker 1971; Hida/Li/Bailey 2001 ("Library for Double-Double
// and Quad-Double Arithmetic"); Inigo Quilez "Deep zoom" notes.

struct dd { float hi; float lo; };

inline dd dd_from_float(float a) { return dd{a, 0.0}; }

// Quick-Two-Sum: requires |a| >= |b|.
inline dd qtwoSum(float a, float b) {
    float s = a + b;
    float e = b - (s - a);
    return dd{s, e};
}

// Two-Sum: no ordering requirement (Knuth).
inline dd twoSum(float a, float b) {
    float s = a + b;
    float bb = s - a;
    float e = (a - (s - bb)) + (b - bb);
    return dd{s, e};
}

// Two-Prod via FMA: a*b = p + e exactly.
inline dd twoProd(float a, float b) {
    float p = a * b;
    float e = fma(a, b, -p);
    return dd{p, e};
}

inline dd dd_add(dd a, dd b) {
    dd s = twoSum(a.hi, b.hi);
    dd t = twoSum(a.lo, b.lo);
    s.lo += t.hi;
    s = qtwoSum(s.hi, s.lo);
    s.lo += t.lo;
    return qtwoSum(s.hi, s.lo);
}

inline dd dd_neg(dd a) { return dd{-a.hi, -a.lo}; }
inline dd dd_sub(dd a, dd b) { return dd_add(a, dd_neg(b)); }

inline dd dd_mul(dd a, dd b) {
    dd p = twoProd(a.hi, b.hi);
    p.lo += a.hi * b.lo + a.lo * b.hi;
    return qtwoSum(p.hi, p.lo);
}

// ---- Uniforms --------------------------------------------------------------

struct Uniforms {
    float2 centerHi;     // (cx_hi, cy_hi)
    float2 centerLo;     // (cx_lo, cy_lo)
    float  scaleHi;
    float  scaleLo;
    float  aspect;
    uint   maxIterations;
};

// ---- Fragment --------------------------------------------------------------

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]]) {
    float2 p = in.uv * 2.0 - 1.0;
    p.x *= u.aspect;

    dd scale = dd{u.scaleHi, u.scaleLo};

    dd cx = dd_add(dd{u.centerHi.x, u.centerLo.x},
                   dd_mul(dd_from_float(p.x), scale));
    dd cy = dd_add(dd{u.centerHi.y, u.centerLo.y},
                   dd_mul(dd_from_float(p.y), scale));

    dd zx = dd_from_float(0.0);
    dd zy = dd_from_float(0.0);

    uint iter = 0;
    bool escaped = false;
    float zMag2 = 0.0;

    for (uint i = 0; i < u.maxIterations; i++) {
        dd zx2 = dd_mul(zx, zx);
        dd zy2 = dd_mul(zy, zy);
        dd zxzy = dd_mul(zx, zy);

        // zx' = zx^2 - zy^2 + cx
        dd zxNew = dd_add(dd_sub(zx2, zy2), cx);
        // zy' = 2*zx*zy + cy
        dd zyNew = dd_add(dd_add(zxzy, zxzy), cy);

        zx = zxNew;
        zy = zyNew;

        // Escape test only needs the high parts — z stays bounded ~[0,2].
        zMag2 = zx.hi * zx.hi + zy.hi * zy.hi;
        if (zMag2 > 4.0) {
            iter = i;
            escaped = true;
            break;
        }
    }

    if (!escaped) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float smoothIter = float(iter) + 1.0 - log2(log2(zMag2) * 0.5);
    float t = smoothIter / float(u.maxIterations);

    float3 color = 0.5 + 0.5 * cos(6.2831 * (t + float3(0.0, 0.33, 0.67)));
    return float4(color, 1.0);
}
