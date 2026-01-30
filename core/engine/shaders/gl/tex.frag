#version 460

uniform mat4 u_colormat;
uniform sampler2D texSampler;

layout(location = 0) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = u_colormat * texture(texSampler, fragTexCoord);
}