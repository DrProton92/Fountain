//
//  Shaders.metal
//  ipadgameapp
//
//  Created by Dave Schmid on 8/15/26.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/ObjC source
#import "ShaderTypes.h"

using namespace metal;

constant uint kMaxParticleCount = 100000000;
constant uint kMaxTrailHistorySamples = 8;

inline float stableRandom(uint seed) {
    uint x = seed;
    x ^= x >> 16;
    x *= 0x7feb352d;
    x ^= x >> 15;
    x *= 0x846ca68b;
    x ^= x >> 16;
    return float(x) / 4294967295.0;
}

inline float sampledLaunchSpeed(uint id, constant Uniforms& uniforms) {
    if (uniforms.velocityMode == 0u) {
        return uniforms.launchSpeed;
    }

    float weights[10] = {
        max(0.0f, uniforms.velocityWeight0),
        max(0.0f, uniforms.velocityWeight1),
        max(0.0f, uniforms.velocityWeight2),
        max(0.0f, uniforms.velocityWeight3),
        max(0.0f, uniforms.velocityWeight4),
        max(0.0f, uniforms.velocityWeight5),
        max(0.0f, uniforms.velocityWeight6),
        max(0.0f, uniforms.velocityWeight7),
        max(0.0f, uniforms.velocityWeight8),
        max(0.0f, uniforms.velocityWeight9)
    };

    const float dx = 1.0f / 9.0f;
    float segmentAreas[9];
    float total = 0.0f;
    for (uint i = 0; i < 9; ++i) {
        float area = 0.5f * (weights[i] + weights[i + 1]) * dx;
        segmentAreas[i] = area;
        total += area;
    }
    if (total <= 0.000001f) {
        return uniforms.launchSpeed;
    }

    float target = stableRandom(id * 334214459u + 220428349u) * total;
    float cumulative = 0.0f;
    float normalized = 0.5f;
    for (uint i = 0; i < 9; ++i) {
        float segmentArea = segmentAreas[i];
        if (segmentArea <= 0.000001f) {
            continue;
        }

        float nextCumulative = cumulative + segmentArea;
        if (target <= nextCumulative || i == 8) {
            float localArea = max(0.0f, target - cumulative);
            float w0 = weights[i];
            float w1 = weights[i + 1];
            float dw = w1 - w0;

            float t = 0.0f;
            if (fabs(dw) <= 0.000001f) {
                float denom = max(0.000001f, w0 * dx);
                t = clamp(localArea / denom, 0.0f, 1.0f);
            } else {
                float a = 0.5f * dw * dx;
                float b = w0 * dx;
                float c = -localArea;
                float discriminant = max(0.0f, (b * b) - (4.0f * a * c));
                float root = sqrt(discriminant);
                float t1 = (-b + root) / (2.0f * a);
                float t2 = (-b - root) / (2.0f * a);
                if (t1 >= 0.0f && t1 <= 1.0f) {
                    t = t1;
                } else if (t2 >= 0.0f && t2 <= 1.0f) {
                    t = t2;
                } else {
                    t = clamp(t1, 0.0f, 1.0f);
                }
            }

            normalized = (float(i) + t) / 9.0f;
            break;
        }
        cumulative = nextCumulative;
    }

    float minV = max(0.0f, uniforms.minVelocityRange);
    float maxV = max(minV, uniforms.maxVelocityRange);
    return minV + ((maxV - minV) * normalized);
}

inline float3 buildLaunchVelocity(uint id, constant Uniforms& uniforms) {
    float launch = clamp(uniforms.launchAngleRadians, 0.0f, M_PI_F * 0.5f);
    float coneHalf = clamp(uniforms.angleVarianceRadians, 0.0f, M_PI_F * 0.5f) * 0.5f;
    float velocityVariance = clamp(uniforms.velocityVariance, 0.0f, 1.0f);

    // Azimuth 0 means the launch axis tilts only in the +X direction.
    float3 axis = normalize(float3(sin(launch), cos(launch), 0.0f));

    float u = stableRandom(id * 1664525u + 1013904223u);
    float v = stableRandom(id * 22695477u + 1u);
    float w = stableRandom(id * 1103515245u + 12345u);

    float cosAlpha = mix(cos(coneHalf), 1.0f, u);
    float sinAlpha = sqrt(max(0.0f, 1.0f - cosAlpha * cosAlpha));
    float phi = 2.0f * M_PI_F * v;

    float3 helper = fabs(axis.y) < 0.99f ? float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
    float3 tangent = normalize(cross(helper, axis));
    float3 bitangent = cross(axis, tangent);

    float3 direction = normalize(axis * cosAlpha + tangent * (cos(phi) * sinAlpha) + bitangent * (sin(phi) * sinAlpha));
    float baseSpeed = sampledLaunchSpeed(id, uniforms);
    float speedScale = mix(1.0f, 1.0f + ((w * 2.0f) - 1.0f), velocityVariance);
    return direction * (baseSpeed * max(0.0f, speedScale));
}

// --- Compute Shader ---
// Updates particle physics on the GPU
kernel void particle_compute(device Particle* particles [[buffer(BufferIndexParticles)]],
                             constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                             device float3* trailHistory [[buffer(BufferIndexTrails)]],
                             uint id [[thread_position_in_grid]])
{
    if (id >= kMaxParticleCount || id >= uniforms.particleCount) {
        return;
    }

    float3 previousPosition = particles[id].position;

    // Simple 3D fountain physics with gravity.
    particles[id].velocity.y -= 0.0009;
    particles[id].position += particles[id].velocity;

    if (uniforms.trailsEnabled != 0u && uniforms.trailSampleCount > 0u) {
        uint base = id * kMaxTrailHistorySamples;
        for (uint t = kMaxTrailHistorySamples - 1; t > 0; --t) {
            trailHistory[base + t] = trailHistory[base + t - 1];
        }
        trailHistory[base] = previousPosition;
    }
    
    // Use a per-particle decay rate so respawns do not line up in visible waves.
    float lifeDecay = mix(0.0035f, 0.0065f, stableRandom(id * 747796405u + 2891336453u));
    particles[id].life -= lifeDecay;

     // If particle "dies", respawn with varied life and tiny source jitter.
     if (particles[id].life <= 0.0) {
         uint respawnSeed = id * 1597334677u;
         respawnSeed ^= as_type<uint>(particles[id].position.x);
         respawnSeed ^= as_type<uint>(particles[id].position.z);

         particles[id].life = mix(0.55f, 1.0f, stableRandom(respawnSeed));

         float jitterX = (stableRandom(respawnSeed ^ 0xA511E9B3u) - 0.5f) * 0.01f;
         float jitterZ = (stableRandom(respawnSeed ^ 0x63D83595u) - 0.5f) * 0.01f;
         particles[id].position = float3(jitterX, 0.0f, jitterZ);

         if (uniforms.trailsEnabled != 0u && uniforms.trailSampleCount > 0u) {
             uint base = id * kMaxTrailHistorySamples;
             for (uint t = 0; t < kMaxTrailHistorySamples; ++t) {
                 trailHistory[base + t] = particles[id].position;
             }
         }

         particles[id].velocity = buildLaunchVelocity(id, uniforms);
         // Size will be set by the CPU based on size configuration
     }
}

// --- Render Shaders ---
struct ParticleVertexOutput {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
    float alphaMultiplier;
};

vertex ParticleVertexOutput particle_vertex(uint vid [[vertex_id]],
                                           const device Particle* particles [[buffer(BufferIndexParticles)]],
                                           constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                                           const device float3* trailHistory [[buffer(BufferIndexTrails)]])
{
    ParticleVertexOutput out;

    uint trailSamples = uniforms.trailsEnabled != 0u ? min(uniforms.trailSampleCount, kMaxTrailHistorySamples) : 0u;
    uint verticesPerParticle = trailSamples + 1u;
    uint particleIndex = vid / verticesPerParticle;
    uint sampleIndex = vid % verticesPerParticle;

    if (particleIndex >= uniforms.particleCount) {
        out.position = float4(2.0f, 2.0f, 2.0f, 1.0f);
        out.color = float4(0.0f);
        out.pointSize = 1.0f;
        out.alphaMultiplier = 0.0f;
        return out;
    }

    Particle p = particles[particleIndex];
    float3 renderPosition = p.position;
    if (sampleIndex > 0u && trailSamples > 0u) {
        uint base = particleIndex * kMaxTrailHistorySamples;
        uint historyIndex = min(sampleIndex - 1u, kMaxTrailHistorySamples - 1u);
        renderPosition = trailHistory[base + historyIndex];
    }

    // Convert particle position to clip space
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * float4(renderPosition, 1.0);
    out.color = p.color;

    float ageT = trailSamples > 0u ? (float(sampleIndex) / float(verticesPerParticle - 1u)) : 0.0f;
    out.alphaMultiplier = mix(1.0f, 0.08f, ageT);
    out.pointSize = max(1.0f, p.size * mix(1.0f, 0.55f, ageT));
    
    return out;
}

fragment float4 fragmentShader(ParticleVertexOutput in [[stage_in]],
                               float2 pointCoord [[point_coord]]) {
    float2 centered = pointCoord - float2(0.5, 0.5);
    float distanceFromCenter = length(centered);

    // Keep only fragments inside a circular footprint and soften the edge slightly.
    if (distanceFromCenter > 0.5) {
        discard_fragment();
    }

    float edgeAlpha = smoothstep(0.5, 0.45, distanceFromCenter);
    return float4(in.color.rgb, in.color.a * edgeAlpha * in.alphaMultiplier);
}
