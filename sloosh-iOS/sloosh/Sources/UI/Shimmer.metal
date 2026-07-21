#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 shimmerEffect(float2 position, half4 color, float time, float2 size) {
    // Return early if fully transparent
    if (color.a == 0.0) {
        return color;
    }

    float angle = 0.5; // ~30 degrees
    float spread = 0.25;
    float speed = 1.0;
    
    float2 uv = position / size;
    float x = uv.x * cos(angle) - uv.y * sin(angle);
    
    // We want the shimmer to sweep across and pause, or just loop
    // fract(time) goes 0..1. Multiply to widen the range to let it sweep past edges.
    float offset = fract(time * speed) * 3.0 - 1.0;
    
    float distance = abs(x - offset);
    float intensity = 1.0 - smoothstep(0.0, spread, distance);
    
    // The base shimmer logic. Add a slight brightening.
    half shine = half(intensity * 0.4);
    
    return half4(clamp(color.r + shine, 0.0h, 1.0h),
                 clamp(color.g + shine, 0.0h, 1.0h),
                 clamp(color.b + shine, 0.0h, 1.0h),
                 color.a);
}
