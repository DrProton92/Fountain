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
    
    // Age the particle
    particles[id].life -= 0.005;

     // If particle "dies", reset it to the center with a new velocity
     if (particles[id].life <= 0.0) {
         particles[id].life = 1.0;
         particles[id].position = float3(0.0, 0.0, 0.0);
         
         // Deterministic spread using thread index.
         float angle = float(id) / 1000.0 * 2.0 * M_PI_F;
         float radial = 0.008 + 0.004 * fract(sin(float(id) * 12.9898) * 43758.5453);
         float upward = 0.03 + 0.02 * fract(sin(float(id) * 78.233) * 43758.5453);
         particles[id].velocity = float3(cos(angle) * radial, upward, sin(angle) * radial);
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
