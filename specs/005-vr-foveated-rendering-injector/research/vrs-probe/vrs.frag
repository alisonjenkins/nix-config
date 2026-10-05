#version 450
#extension GL_EXT_fragment_shading_rate : require
layout(location = 0) out uvec2 o;
void main() {
    o = uvec2(uint(gl_ShadingRateEXT),
              ((uint(gl_FragCoord.x) & 15u) << 4) | (uint(gl_FragCoord.y) & 15u));
}
