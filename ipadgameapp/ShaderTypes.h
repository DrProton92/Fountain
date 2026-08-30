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
typedef float3 shared_float3;
typedef float4 shared_float4;
typedef float4x4 shared_float4x4;
typedef uint shared_uint;
#else
#include <stdint.h>
#include <simd/simd.h>
typedef vector_float2 shared_float2;
typedef vector_float3 shared_float3;
typedef vector_float4 shared_float4;
typedef matrix_float4x4 shared_float4x4;
typedef uint32_t shared_uint;
#endif

// Use standard enum types compatible with both Swift and Metal
typedef enum {
    BufferIndexParticles = 0,
    BufferIndexUniforms = 1
} BufferIndex;

// Shared CPU/GPU layout types.
typedef struct {
    shared_float3 position;
    shared_float3 velocity;
    shared_float4 color;
    float life;
    float size;
} Particle;

typedef struct {
    shared_float4x4 projectionMatrix;
    shared_float4x4 viewMatrix;
    shared_uint particleCount;
    shared_uint _padding0;
    shared_uint _padding1;
    shared_uint _padding2;
    float launchAngleRadians;
    float angleVarianceRadians;
    float launchSpeed;
    float velocityVariance;
} Uniforms;

#endif /* ShaderTypes_h */
