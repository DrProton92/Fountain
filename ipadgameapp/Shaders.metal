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

inline float stableRandom(uint seed) {
    uint x = seed;
    x ^= x >> 16;
    x *= 0x7feb352d;
    x ^= x >> 15;
    x *= 0x846ca68b;
    x ^= x >> 16;
    return float(x) / 4294967295.0;
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
    float speedScale = mix(1.0f, 1.0f + ((w * 2.0f) - 1.0f), velocityVariance);
    return direction * (uniforms.launchSpeed * max(0.0f, speedScale));
}

// --- Compute Shader ---
// Updates particle physics on the GPU
kernel void particle_compute(device Particle* particles [[buffer(BufferIndexParticles)]],
                             constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                             uint id [[thread_position_in_grid]])
{
    if (id >= kMaxParticleCount || id >= uniforms.particleCount) {
        return;
    }

    // Simple 3D fountain physics with gravity.
    particles[id].velocity.y -= 0.0009;
    particles[id].position += particles[id].velocity;
    
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

         particles[id].velocity = buildLaunchVelocity(id, uniforms);
         // Size will be set by the CPU based on size configuration
     }
}

// --- Render Shaders ---
struct ParticleVertexOutput {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

vertex ParticleVertexOutput particle_vertex(uint vid [[vertex_id]],
                                           const device Particle* particles [[buffer(BufferIndexParticles)]],
                                           constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    Particle p = particles[vid];
    ParticleVertexOutput out;
    
    // Convert particle position to clip space
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * float4(p.position, 1.0);
    out.color = p.color;
    out.pointSize = p.size;
    
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
    return float4(in.color.rgb, in.color.a * edgeAlpha);
}
