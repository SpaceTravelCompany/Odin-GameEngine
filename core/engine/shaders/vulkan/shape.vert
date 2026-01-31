#version 460

layout(set = 0, binding = 0) uniform UniformBufferObject0 {
    mat4 model;
} model;
layout(set = 1, binding = 0) uniform UniformBufferObject1 {
    mat4 view;
} view;
layout(set = 1, binding = 1) uniform UniformBufferObject2 {
    mat4 proj;
} proj;


//#extension GL_EXT_debug_printf : enable
layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec3 inUv;
layout(location = 2) in vec4 inColor;
layout(location = 3) in uvec4 inEdgeBoundary;

layout(location = 1) out vec3 outUv;
layout(location = 2) out vec4 outColor;
layout(location = 3) out flat uvec4 outEdgeBoundary;

void main() {
    gl_Position = proj.proj * view.view * model.model * vec4(inPosition, 0.0, 1.0);
    outUv = inUv;
    outColor = inColor;
    outEdgeBoundary = inEdgeBoundary;
}