#version 450
#extension GL_ARB_shader_viewport_layer_array : require
void main() {
    vec2 p = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(p * 2.0 - 1.0, 0.5, 1.0);
    gl_Layer = gl_InstanceIndex;
}
