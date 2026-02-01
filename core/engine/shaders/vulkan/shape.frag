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
    float alpha = 1.0;

    if (inEdgeBoundary.w == 1u) {
    } else if (inEdgeBoundary.w == 0u) {
        float res = pow(k, 3) - l * m;
        if (res >= 1.0) { res = 1.0;
		}else if (res <= 0.0) { res = 0.0; }
		alpha = res;
    } else {
        float res = pow(k, 2) - l;
       	if (res >= 1.0) { res = 1.0;
		}else if (res <= 0.0) { res = 0.0; }
		alpha = res;
    }

    vec4 color = colormat.mat * inColor;
    outColor = vec4(color.rgb, color.a * alpha);
}