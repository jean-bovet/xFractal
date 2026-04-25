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

struct dd { float hi; float lo; };

inline dd dd_from_float(float a) { return dd{a, 0.0}; }

inline dd qtwoSum(float a, float b) {
    float s = a + b;
    float e = b - (s - a);
    return dd{s, e};
}

inline dd twoSum(float a, float b) {
    float s = a + b;
    float bb = s - a;
    float e = (a - (s - bb)) + (b - bb);
    return dd{s, e};
}

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
    float2 centerHi;
    float2 centerLo;
    float  scaleHi;
    float  scaleLo;
    float  aspect;
    uint   maxIterations;
    uint   usePerturbation;
    uint   refOrbitLength;
    // World-space offset from screen center to the reference pixel C0
    // (refOffset = center - C0). Lets us pick a reference that isn't the
    // geometric center, which prevents reference-escape capping iteration
    // count when the center lands on a fast-escaping region.
    float2 refOffset;
};

// ---- Coloring helper -------------------------------------------------------

inline float4 colorize(uint iter, float zMag2, uint maxIterations) {
    float smoothIter = float(iter) + 1.0 - log2(log2(zMag2) * 0.5);
    float t = smoothIter / float(maxIterations);
    float3 color = 0.5 + 0.5 * cos(6.2831 * (t + float3(0.0, 0.33, 0.67)));
    return float4(color, 1.0);
}

// ---- Fragment --------------------------------------------------------------

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]],
                               constant float2 *refOrbit [[buffer(1)]]) {
    float2 p = in.uv * 2.0 - 1.0;
    p.x *= u.aspect;

    // ---- Perturbation path (Pauldelbrot 2013) ----
    // c = C0 + dc, z = Z + dz with reference (C0, Z_n) precomputed on CPU.
    // Recurrence: dz_{n+1} = 2*Z_n*dz_n + dz_n^2 + dc.
    // dz, dc stay in float because their magnitudes are tiny (~scale).
    if (u.usePerturbation != 0u) {
        // Reference orbit must have at least 2 entries to step at all.
        if (u.refOrbitLength < 2u) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        // dc = (c - C0) = p * scale + (center - C0).
        // Both terms have magnitude ~scale; float captures them.
        float2 dc = p * u.scaleHi + u.refOffset;
        float2 dz = float2(0.0);

        uint cap = min(u.maxIterations, u.refOrbitLength - 1u);
        uint iter = 0u;
        bool escaped = false;
        float zMag2 = 0.0;

        for (uint i = 0u; i < cap; i++) {
            float2 Z = refOrbit[i];

            // 2*Z*dz (complex)
            float2 twoZdz = float2(
                2.0 * (Z.x * dz.x - Z.y * dz.y),
                2.0 * (Z.x * dz.y + Z.y * dz.x)
            );
            // dz^2 (complex)
            float2 dz2 = float2(
                dz.x * dz.x - dz.y * dz.y,
                2.0 * dz.x * dz.y
            );
            dz = twoZdz + dz2 + dc;

            // z_{i+1} = Z_{i+1} + dz_{i+1} (escape test)
            float2 Z1 = refOrbit[i + 1u];
            float2 z = Z1 + dz;
            zMag2 = z.x * z.x + z.y * z.y;
            if (zMag2 > 4.0) {
                iter = i + 1u;
                escaped = true;
                break;
            }
        }

        if (!escaped) return float4(0.0, 0.0, 0.0, 1.0);
        return colorize(iter, zMag2, u.maxIterations);
    }

    // ---- DD path (default) ----
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

        dd zxNew = dd_add(dd_sub(zx2, zy2), cx);
        dd zyNew = dd_add(dd_add(zxzy, zxzy), cy);

        zx = zxNew;
        zy = zyNew;

        zMag2 = zx.hi * zx.hi + zy.hi * zy.hi;
        if (zMag2 > 4.0) {
            iter = i;
            escaped = true;
            break;
        }
    }

    if (!escaped) return float4(0.0, 0.0, 0.0, 1.0);
    return colorize(iter, zMag2, u.maxIterations);
}
