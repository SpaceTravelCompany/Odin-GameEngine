#version 450

layout(set = 0, binding = 1) uniform UniformBufferObject4 {
    mat4 mat;
} colormat;
layout(set = 0, binding = 2) uniform UniformBufferObject5 {
    uint frame;
} frames;
layout(set = 2, binding = 0) uniform sampler2DArray texSampler;

layout(location = 0) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = colormat.mat * texture(texSampler, vec3(fragTexCoord, frames.frame));
}