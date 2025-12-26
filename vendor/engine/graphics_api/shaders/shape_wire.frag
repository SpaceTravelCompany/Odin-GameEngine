#version 450

layout(set = 0, binding = 3) uniform UniformBufferObject4 {
    mat4 mat;
} colormat;

layout(location = 1) in vec3 inUv;
layout(location = 2) in vec4 inColor;

layout(location = 0) out vec4 outColor;

void main() {
    // float res = (pow(inUv.x, 3) - inUv.y * inUv.z);
    // if (res <= 0) discard;

    outColor = colormat.mat * vec4(inColor.rgb, inColor.a);
}