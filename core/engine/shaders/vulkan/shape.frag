#version 460

layout(set = 0, binding = 1) uniform UniformBufferObject4 {
    mat4 mat;
} colormat;

layout(location = 1) in vec3 inUv;
layout(location = 2) in vec4 inColor;
layout(location = 3) in flat uvec4 inEdgeBoundary;

layout(location = 0) out vec4 outColor;

void main() {
    float k = inUv.x;
    float l = inUv.y;
    float m = inUv.z;
    float alpha;

    float sum_uvw = k + l + m;
    if (inEdgeBoundary.w > 0.0) {
        // Barycentric (triangle): AA only on boundary edges via inEdgeBoundary.xyz
        float d0 = inEdgeBoundary.x != 0u ? k : 1.0;
        float d1 = inEdgeBoundary.y != 0u ? l : 1.0;
        float d2 = inEdgeBoundary.z != 0u ? m : 1.0;
        float edge = min(min(d0, d1), d2);
        float edgeFwidth = fwidth(edge);
        alpha = smoothstep(0.0, edgeFwidth * 0.5, edge);
        alpha = clamp(alpha, 0.0, 1.0);
    } else {
        // Cubic curve: c(x,y) = k^3 - l*m = 0
        float res = pow(k, 3) - l * m;
        vec3 dx = dFdx(inUv);
        vec3 dy = dFdy(inUv);
        float fx = 3.0 * k * k * dx.x - dx.y * m - l * dx.z;
        float fy = 3.0 * k * k * dy.x - dy.y * m - l * dy.z;
        float gradientLength = sqrt(fx * fx + fy * fy);

		float sd = res / gradientLength;
		alpha = 0.5 + sd;
		if (alpha > 1.0) alpha = 1.0;
		else if (alpha <= 0.0) { discard; return; }
    }

    vec4 color = colormat.mat * inColor;
    outColor = vec4(color.rgb, color.a * alpha);
}