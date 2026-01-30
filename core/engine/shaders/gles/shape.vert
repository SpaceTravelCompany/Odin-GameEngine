#version 300 es

uniform mat4 u_model;
uniform mat4 u_view;
uniform mat4 u_proj;

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec3 inUv;
layout(location = 2) in vec4 inColor;
layout(location = 1) out vec3 outUv;
layout(location = 2) out vec4 outColor;

void main() {
    gl_Position = u_proj * u_view * u_model * vec4(inPosition, 0.0, 1.0);
    outUv = inUv;
    outColor = inColor;
}