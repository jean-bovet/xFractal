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
    float2 refOffset;
    uint   fractalType;        // 0 mandelbrot, 1 julia, 2 newton, 3 multibrot
    uint   palette;            // 0 hot, 1 cold, 2 gray, 3 chromatic
    uint   smooth;
    uint   multibrotExponent;
    uint   newtonFlavor;
    float2 juliaC;
};

// ---- Coloring --------------------------------------------------------------

inline float3 hsv2rgb(float h, float s, float v) {
    h = fmod(h, 360.0);
    if (h < 0.0) h += 360.0;
    float c = v * s;
    float hp = h / 60.0;
    float x = c * (1.0 - fabs(fmod(hp, 2.0) - 1.0));
    float3 rgb;
    if      (hp < 1.0) rgb = float3(c, x, 0.0);
    else if (hp < 2.0) rgb = float3(x, c, 0.0);
    else if (hp < 3.0) rgb = float3(0.0, c, x);
    else if (hp < 4.0) rgb = float3(0.0, x, c);
    else if (hp < 5.0) rgb = float3(x, 0.0, c);
    else               rgb = float3(c, 0.0, x);
    return rgb + (v - c);
}

// `count` is a (possibly fractional) escape count, or -1.0 for points considered
// to be inside the set (no escape). Mirrors the original Obj-C palettes.
inline float4 paletteColor(uint kind, float count) {
    if (count < 0.0) return float4(0.0, 0.0, 0.0, 1.0);
    if (kind == 0u) {
        float ci = log(count * 0.1 + 1.0);
        ci = fmod(ci, 2.0);
        if (ci > 1.0) ci = 2.0 - ci;
        return float4(1.0, ci, 0.0, 1.0);
    } else if (kind == 1u) {
        float ci = log(count * 0.1 + 1.0);
        if (ci < 1.0) {
            return float4(0.0, 0.0, ci, 1.0);
        } else {
            ci = fmod(ci, 2.0);
            if (ci > 1.0) ci = 2.0 - ci;
            return float4(0.0, 0.7 * (1.0 - ci), 1.0, 1.0);
        }
    } else if (kind == 2u) {
        float ci = log(count * 0.05 + 1.0);
        if (ci > 1.0) {
            ci = fmod(ci, 2.0);
            if (ci > 1.0) ci = 2.0 - ci;
            const float contrast = 0.3;
            ci = (1.0 - contrast) * ci + contrast;
        }
        return float4(ci, ci, ci, 1.0);
    } else {
        float ci = log(count * 0.03 + 1.0) + 0.125;
        ci = fmod(ci, 2.0);
        if (ci > 1.0) ci = 2.0 - ci;
        return float4(hsv2rgb(240.0 * ci, 1.0, 1.0), 1.0);
    }
}

inline float smoothCount(uint iter, float zMag2, uint useSmooth) {
    if (useSmooth == 0u) return float(iter);
    // Standard smooth-iteration formula: nu = iter + 1 - log2(log2(|z|))
    return float(iter) + 1.0 - log2(0.5 * log2(max(zMag2, 1.000001)));
}

// ---- Float complex helpers -------------------------------------------------

inline float2 cmul(float2 a, float2 b) {
    return float2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

inline float2 cdiv(float2 a, float2 b) {
    float d = b.x*b.x + b.y*b.y;
    return float2((a.x*b.x + a.y*b.y) / d, (a.y*b.x - a.x*b.y) / d);
}

inline float2 cpow_int(float2 z, uint n) {
    if (n == 0u) return float2(1.0, 0.0);
    float2 r = z;
    for (uint i = 1u; i < n; i++) {
        r = cmul(r, z);
    }
    return r;
}

// ---- Iteration kernels -----------------------------------------------------
// Each kernel returns a "color count" (smooth iteration value) or -1 for inside.

inline float iterateMandelbrotDD(constant Uniforms &u, float2 p) {
    dd scale = dd{u.scaleHi, u.scaleLo};
    dd cx = dd_add(dd{u.centerHi.x, u.centerLo.x},
                   dd_mul(dd_from_float(p.x), scale));
    dd cy = dd_add(dd{u.centerHi.y, u.centerLo.y},
                   dd_mul(dd_from_float(p.y), scale));

    dd zx = dd_from_float(0.0);
    dd zy = dd_from_float(0.0);

    uint iter = 0u;
    float zMag2 = 0.0;
    bool escaped = false;
    for (uint i = 0u; i < u.maxIterations; i++) {
        dd zx2 = dd_mul(zx, zx);
        dd zy2 = dd_mul(zy, zy);
        dd zxzy = dd_mul(zx, zy);

        zx = dd_add(dd_sub(zx2, zy2), cx);
        zy = dd_add(dd_add(zxzy, zxzy), cy);

        zMag2 = zx.hi * zx.hi + zy.hi * zy.hi;
        if (zMag2 > 4.0) { iter = i; escaped = true; break; }
    }
    if (!escaped) return -1.0;
    return smoothCount(iter, zMag2, u.smooth);
}

inline float iterateMandelbrotPerturbation(constant Uniforms &u, float2 p,
                                           constant float2 *refOrbit) {
    if (u.refOrbitLength < 2u) return -1.0;
    float2 dc = p * u.scaleHi + u.refOffset;
    float2 dz = float2(0.0);

    uint cap = min(u.maxIterations, u.refOrbitLength - 1u);
    uint iter = 0u;
    float zMag2 = 0.0;
    bool escaped = false;

    for (uint i = 0u; i < cap; i++) {
        float2 Z = refOrbit[i];
        float2 twoZdz = float2(
            2.0 * (Z.x * dz.x - Z.y * dz.y),
            2.0 * (Z.x * dz.y + Z.y * dz.x)
        );
        float2 dz2 = float2(
            dz.x * dz.x - dz.y * dz.y,
            2.0 * dz.x * dz.y
        );
        dz = twoZdz + dz2 + dc;

        float2 Z1 = refOrbit[i + 1u];
        float2 z = Z1 + dz;
        zMag2 = z.x * z.x + z.y * z.y;
        if (zMag2 > 4.0) { iter = i + 1u; escaped = true; break; }
    }
    if (!escaped) return -1.0;
    return smoothCount(iter, zMag2, u.smooth);
}

inline float iterateJuliaDD(constant Uniforms &u, float2 p) {
    // Initial z = pixel coordinate (in world space); c is fixed.
    dd scale = dd{u.scaleHi, u.scaleLo};
    dd zx = dd_add(dd{u.centerHi.x, u.centerLo.x},
                   dd_mul(dd_from_float(p.x), scale));
    dd zy = dd_add(dd{u.centerHi.y, u.centerLo.y},
                   dd_mul(dd_from_float(p.y), scale));

    dd cx = dd_from_float(u.juliaC.x);
    dd cy = dd_from_float(u.juliaC.y);

    uint iter = 0u;
    float zMag2 = 0.0;
    bool escaped = false;
    for (uint i = 0u; i < u.maxIterations; i++) {
        dd zx2 = dd_mul(zx, zx);
        dd zy2 = dd_mul(zy, zy);
        dd zxzy = dd_mul(zx, zy);

        zx = dd_add(dd_sub(zx2, zy2), cx);
        zy = dd_add(dd_add(zxzy, zxzy), cy);

        zMag2 = zx.hi * zx.hi + zy.hi * zy.hi;
        if (zMag2 > 4.0) { iter = i; escaped = true; break; }
    }
    if (!escaped) return -1.0;
    return smoothCount(iter, zMag2, u.smooth);
}

inline float iterateMultibrot(constant Uniforms &u, float2 p) {
    // Single-precision z^n + c. Multibrot doesn't need DD at typical zooms.
    float2 c = float2(u.centerHi.x + p.x * u.scaleHi,
                      u.centerHi.y + p.y * u.scaleHi);
    float2 z = float2(0.0);
    uint n = max(u.multibrotExponent, 2u);

    uint iter = 0u;
    float zMag2 = 0.0;
    bool escaped = false;
    for (uint i = 0u; i < u.maxIterations; i++) {
        z = cpow_int(z, n) + c;
        zMag2 = z.x * z.x + z.y * z.y;
        if (zMag2 > 4.0) { iter = i; escaped = true; break; }
    }
    if (!escaped) return -1.0;
    return smoothCount(iter, zMag2, u.smooth);
}

inline float iterateNewton(constant Uniforms &u, float2 p) {
    // Pixel coordinate is the starting z; fractal explores the basins of
    // attraction of Newton's method on a fixed polynomial.
    float2 z = float2(u.centerHi.x + p.x * u.scaleHi,
                      u.centerHi.y + p.y * u.scaleHi);
    float2 prev = z;
    uint iter = 0u;
    bool converged = false;

    for (uint i = 0u; i < u.maxIterations; i++) {
        float2 t;        // p(z)
        float2 dp;       // p'(z)

        if (u.newtonFlavor == 0u) {
            // p(z) = z^3 - 1; p'(z) = 3 z^2
            float2 z2 = cmul(z, z);
            float2 z3 = cmul(z2, z);
            t  = float2(z3.x - 1.0, z3.y);
            dp = float2(3.0 * z2.x, 3.0 * z2.y);
        } else if (u.newtonFlavor == 1u) {
            // p(z) = z^3 - 2z + 2; p'(z) = 3 z^2 - 2
            float2 z2 = cmul(z, z);
            float2 z3 = cmul(z2, z);
            t  = float2(z3.x - 2.0 * z.x + 2.0, z3.y - 2.0 * z.y);
            dp = float2(3.0 * z2.x - 2.0, 3.0 * z2.y);
        } else {
            // p(z) = z^8 + 15 z^4 - 16; p'(z) = 8 z^7 + 60 z^3
            float2 z2 = cmul(z, z);
            float2 z3 = cmul(z2, z);
            float2 z4 = cmul(z2, z2);
            float2 z7 = cmul(z3, z4);
            float2 z8 = cmul(z4, z4);
            t  = float2(z8.x + 15.0 * z4.x - 16.0, z8.y + 15.0 * z4.y);
            dp = float2(8.0 * z7.x + 60.0 * z3.x, 8.0 * z7.y + 60.0 * z3.y);
        }

        if (t.x * t.x + t.y * t.y < 0.04) {
            iter = i;
            converged = true;
            break;
        }

        z = z - cdiv(t, dp);

        if (z.x == prev.x && z.y == prev.y) return -1.0;
        prev = z;
    }
    if (!converged) return -1.0;
    return float(iter);
}

// ---- Fragment --------------------------------------------------------------

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]],
                               constant float2 *refOrbit [[buffer(1)]]) {
    float2 p = in.uv * 2.0 - 1.0;
    p.x *= u.aspect;

    float count;
    if (u.fractalType == 0u) {
        count = (u.usePerturbation != 0u)
            ? iterateMandelbrotPerturbation(u, p, refOrbit)
            : iterateMandelbrotDD(u, p);
    } else if (u.fractalType == 1u) {
        count = iterateJuliaDD(u, p);
    } else if (u.fractalType == 2u) {
        count = iterateNewton(u, p);
    } else {
        count = iterateMultibrot(u, p);
    }
    return paletteColor(u.palette, count);
}
