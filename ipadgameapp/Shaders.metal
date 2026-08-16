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

// --- Compute Shader ---
// Updates particle physics on the GPU
kernel void particle_compute(device Particle* particles [[buffer(BufferIndexParticles)]],
                             constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                             uint id [[thread_position_in_grid]]) 
{
    if (id >= 10000) {
        return;
    }

    // Basic physics: position += velocity
    particles[id].position += particles[id].velocity;
    
    // Age the particle
    particles[id].life -= 0.005; 

    // If particle "dies", reset it to the center with a new velocity
    if (particles[id].life <= 0.0) {
        particles[id].life = 1.0;
        particles[id].position = float2(0.0, 0.0);
        
        // Use the thread index to create a deterministic pseudo-random velocity
        float angle = float(id) / 1000.0 * 2.0 * M_PI_F;
        particles[id].velocity = float2(cos(angle), sin(angle)) * 0.01;
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
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * float4(p.position, 0.0, 1.0);
    out.color = p.color;
    out.pointSize = 5.0; // Size of the particle in pixels
    
    return out;
}

fragment float4 fragmentShader(ParticleVertexOutput in [[stage_in]]) {
    return in.color;
}
