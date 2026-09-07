import simd

// Matrix math utilities
func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4(columns: (
        vector_float4(1, 0, 0, 0),
        vector_float4(0, 1, 0, 0),
        vector_float4(0, 0, 1, 0),
        vector_float4(translationX, translationY, translationZ, 1)
    ))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4(columns: (
        vector_float4(xs, 0, 0, 0),
        vector_float4(0, ys, 0, 0),
        vector_float4(0, 0, zs, -1),
        vector_float4(0, 0, zs * nearZ, 0)
    ))
}

func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let normalizedAxis = simd_normalize(axis)
    let x = normalizedAxis.x
    let y = normalizedAxis.y
    let z = normalizedAxis.z
    let c = cos(radians)
    let s = sin(radians)
    let mc = 1.0 - c

    return matrix_float4x4(columns: (
        SIMD4<Float>(c + x * x * mc, x * y * mc + z * s, x * z * mc - y * s, 0),
        SIMD4<Float>(y * x * mc - z * s, c + y * y * mc, y * z * mc + x * s, 0),
        SIMD4<Float>(z * x * mc + y * s, z * y * mc - x * s, c + z * z * mc, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

func matrix_look_at_right_hand(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    let zAxis = simd_normalize(eye - target)
    let xAxis = simd_normalize(simd_cross(up, zAxis))
    let yAxis = simd_cross(zAxis, xAxis)

    let translation = SIMD3<Float>(
        -simd_dot(xAxis, eye),
        -simd_dot(yAxis, eye),
        -simd_dot(zAxis, eye)
    )

    return matrix_float4x4(columns: (
        SIMD4<Float>(xAxis.x, xAxis.y, xAxis.z, 0),
        SIMD4<Float>(yAxis.x, yAxis.y, yAxis.z, 0),
        SIMD4<Float>(zAxis.x, zAxis.y, zAxis.z, 0),
        SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    ))

}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi

}
