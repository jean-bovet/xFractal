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

struct Uniforms {
    float2 center;
    float  scale;
    float  aspect;
    uint   maxIterations;
};

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]]) {
    float2 p = in.uv * 2.0 - 1.0;
    p.x *= u.aspect;
    float2 c = u.center + p * u.scale;

    float2 z = float2(0.0);
    uint   iter = 0;
    bool   escaped = false;

    for (uint i = 0; i < u.maxIterations; i++) {
        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        if (dot(z, z) > 4.0) {
            iter = i;
            escaped = true;
            break;
        }
    }

    if (!escaped) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float smoothIter = float(iter) + 1.0 - log2(log2(dot(z, z)) * 0.5);
    float t = smoothIter / float(u.maxIterations);

    float3 color = 0.5 + 0.5 * cos(6.2831 * (t + float3(0.0, 0.33, 0.67)));
    return float4(color, 1.0);
}
