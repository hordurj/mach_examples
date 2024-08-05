// A basic triangle shader

struct ShaderGlobal {
    modelviewprojection:  mat4x4<f32>
};

@group(0) @binding(0) var<uniform> shaderGlobal: ShaderGlobal;

const VERTICES: array<vec2<f32>,4> = array(
    vec2<f32>(0.0, 1.0),
    vec2<f32>(1.0, 0.0),
    vec2<f32>(-0.5, 0.0),
    vec2<f32>(1.0, 1.0),
);

struct Vertex {
    @location(0) pos: vec4<f32>,
    @location(1) color: vec4<f32>
};

struct Fragment {
    @builtin(position) pos: vec4<f32>,
    @location(0) color: vec4<f32>
};

@vertex
fn vertMain(vertex: Vertex, @builtin(vertex_index) vertex_index: u32) -> Fragment {
    var p = shaderGlobal.modelviewprojection * vertex.pos; 
    //var v = vec4<f32>(VERTICES[vertex_index], 0.0, 1.0);

    var out: Fragment;
    out.pos = p;
    out.color = vertex.color;

    return out;
}

@fragment
fn fragMain(fragment: Fragment) -> @location(0) vec4<f32> {
    return fragment.color;
}
