#version 460

layout(set = 0, binding = 1) uniform UniformBufferObject4 {
    mat4 mat;
} colormat;

layout(location = 1) in vec3 inUv;
layout(location = 2) in vec4 inColor;

layout(location = 0) out vec4 outColor;

void main() {
    float k = inUv.x;
    float l = inUv.y;
    float m = inUv.z;

	float alpha = pow(k, 3) - l * m;
	if (alpha >= 1.0) { alpha = 1.0;
	} else if (alpha <= 0.0) { discard; }

    vec4 color = colormat.mat * inColor;
    outColor = vec4(color.rgb, color.a * alpha);
}