#version 450

layout(set = 0, binding = 1) uniform UniformBufferObject4 {
    mat4 mat;
} colormat;

layout(location = 1) in vec3 inUv;
layout(location = 2) in vec4 inColor;

layout(location = 0) out vec4 outColor;

void main() {
    // Cubic curve: c(x,y) = k^3 - l*m = 0
    // where k = inUv.x, l = inUv.y, m = inUv.z
    float k = inUv.x;
    float l = inUv.y;
    float m = inUv.z;
    
    float res = pow(k, 3) - l * m;
    
    // GPU Gems 3 방법: 체인 룰을 사용한 정확한 도함수 계산
    // Gradients for each component
    float dk_dx = dFdx(k);
    float dk_dy = dFdy(k);
    float dl_dx = dFdx(l);
    float dl_dy = dFdy(l);
    float dm_dx = dFdx(m);
    float dm_dy = dFdy(m);
    
    // Chain rule for cubic: fx = 3*k^2 * ddx(k) - ddx(l)*m - l*ddx(m)
    //                      fy = 3*k^2 * ddy(k) - ddy(l)*m - l*ddy(m)
    float fx = 3.0 * k * k * dk_dx - dl_dx * m - l * dm_dx;
    float fy = 3.0 * k * k * dk_dy - dl_dy * m - l * dm_dy;
    
    // Signed distance to boundary (in pixel units)
    float gradientLength = sqrt(fx * fx + fy * fy);
    float sd = res / gradientLength;
    
    // Linear alpha based on signed distance
    // Boundary interval: ±0.5 pixel
    float alpha = 0.5 + sd;
    
    if (alpha > 1.0) {
        // Inside - fully opaque
        alpha = 1.0;
    } else if (alpha <= 0.0) {
        // Outside - discard
        discard;
    }
    // else: Near boundary - use computed alpha
    
    vec4 color = colormat.mat * inColor;
    outColor = vec4(color.rgb, color.a * alpha);
}