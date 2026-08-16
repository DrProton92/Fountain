//
//  ShaderTypes.h
//  ipadgameapp
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
typedef float2 shared_float2;
typedef float4 shared_float4;
typedef float4x4 shared_float4x4;
#else
#include <simd/simd.h>
typedef vector_float2 shared_float2;
typedef vector_float4 shared_float4;
typedef matrix_float4x4 shared_float4x4;
#endif

// Use standard enum types compatible with both Swift and Metal
typedef enum {
    BufferIndexParticles = 0,
    BufferIndexUniforms = 1
} BufferIndex;

// Shared CPU/GPU layout types.
typedef struct {
    shared_float2 position;
    shared_float2 velocity;
    shared_float4 color;
    float life;
} Particle;

typedef struct {
    shared_float4x4 projectionMatrix;
    shared_float4x4 modelViewMatrix;
} Uniforms;

#endif /* ShaderTypes_h */
