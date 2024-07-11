struct Uniforms {
  // The view * orthographic projection matrix
  view_projection: mat4x4<f32>,
};

const VERTICES: array<vec2<f32>,4> = array(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(-1.0, 1.0),
    vec2<f32>(1.0, -1.0),
    vec2<f32>(1.0, 1.0),
);

struct VertexOutput {
  @location(0) fragUV : vec4<f32>,
  @location(1) color: vec4<f32>,
  @location(2) params: vec4<f32>,
  @builtin(position) Position : vec4<f32>,
};

struct Params {
  param1: vec4<f32>,
  param2: vec4<f32> 
};

@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var<storage, read> transforms: array<mat4x4<f32>>;
@group(0) @binding(2) var<storage, read> positions: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read> sizes: array<vec2<f32>>;
@group(0) @binding(4) var<storage, read> colors: array<vec4<f32>>;

// Shape dependant params
@group(0) @binding(5) var<storage, read> params: array<Params>;

@vertex fn vertMain(@builtin(instance_index) instance_index : u32, @builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    let transform = transforms[instance_index];
    let t = params[instance_index].param1.x;
    var v = vec4<f32>(VERTICES[vertex_index], 0.0, 1.0);
    if (t == 3.0) {
      
      v.xy = positions[instance_index];

      // A line (starts on edge 1,2 and finish on edge 3,4)
      let d = sizes[instance_index] - positions[instance_index];
      let l = normalize(d);
      let w = params[instance_index].param1.y;
      if (vertex_index == 0) {
        v.xy += vec2<f32>(l.y, -l.x)*w;
      } else if (vertex_index == 1) {
        v.xy += vec2<f32>(-l.y, l.x)*w;
      } else if (vertex_index == 2) {
        v.xy += d + vec2<f32>(l.y, -l.x)*w;
      } else if (vertex_index == 3) {
        v.xy += d + vec2<f32>(-l.y, l.x)*w;        
      }
    } else {
      v.xy *= sizes[instance_index];
      v.xy += positions[instance_index];
    }

    var output: VertexOutput;    
    output.Position = uniforms.view_projection * transform * v;
    output.fragUV = vec4<f32>(VERTICES[vertex_index], 0.0, 0.0);
    output.color = colors[instance_index];
    output.params = vec4<f32>(f32(instance_index), 0.0, 0.0, 0.0);

    return output;
}

@fragment fn fragMain(
  @location(0) fragUV: vec4<f32>,
  @location(1) color: vec4<f32>,
  @location(2) params_in: vec4<f32>,
//  @location(1) shapeIndex: f32
) -> @location(0) vec4<f32> {
    let shape_index = u32(params_in[0]);
    let size = sizes[shape_index];

    var fill_color = params[shape_index].param2;

    var d = 0.0;
    let t = params[shape_index].param1.x;

    // uv relative to shape
    // If rectangle
    if (t == 1.0)
    {
      let s = 100.0; // step sharpness
      let border = 5.0;
      d = min(size.x-abs(fragUV.x*size.x), size.y-abs(fragUV.y*size.y));
      if (d > border) {
          d = 0.0;
      } else {
          d = 1.0;
      }
    } else if (t == 2.0) {
      // If circle        pos relative to center
      let r = (1.0-length(fragUV.xy));
      d = min(1.0, r * 1000.0);
    } else if (t == 3.0) {
      // Line
      d = 1.0;
      fill_color = vec4<f32>(0.0);
    }
    // t == 4.0   bezier qudratic
    // t == 5.0   bezier qudratic
    
    if (fill_color.a == 0.0 && d <= 0.0) {
      discard;
    }
    var col = color.xyz * d;
    col += fill_color.xyz * (1.0 - d);
    if (fill_color.a == 0.0) {
      return vec4<f32>(col, d);
    } else {
      return vec4<f32>(col, 1.0);
    }
}
