#version 460

uniform mat4 u_model;
uniform mat4 u_view;
uniform mat4 u_proj;
uniform sampler2DArray texSampler;

layout(location = 0) out vec2 fragTexCoord;

vec2 quad[6] = {
    vec2(-0.5,-0.5),
    vec2(0.5, -0.5),
    vec2(-0.5, 0.5),
    vec2(0.5, -0.5),
    vec2(0.5, 0.5),
    vec2(-0.5, 0.5)
};

void main() {
    gl_Position = u_proj * u_view * u_model * vec4(quad[gl_VertexID] * vec2(textureSize(texSampler, 0)), 0.0, 1.0);
    fragTexCoord = (quad[gl_VertexID] + vec2(0.5,0.5)) * vec2(1,-1);
}