struct Uniforms {
  // The view * orthographic projection matrix
  view_projection: mat4x4<f32>,
};

const RECT = 1;
const CIRCLE = 2;
const LINE = 3;
const QUAD = 4;
const CUBIC = 5;

const VERTICES: array<vec2<f32>,4> = array(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(-1.0, 1.0),
    vec2<f32>(1.0, -1.0),
    vec2<f32>(1.0, 1.0),
);

struct VertexOutput {
  @location(0) frag_uv : vec4<f32>,
  @location(1) params: vec4<u32>,
  @builtin(position) Position : vec4<f32>,
};

struct UintParams {
  param1: vec4<u32>,
  // 1 - Type (0..7), Idx to dynamic data (8..31)
  // 2 - LineCap, Line Join  
  // 3 - Pattern (0..15 Line dash, 16..31 4x4 pattern)
  // 4 - Gradient type (1 - direction, radial (distance from center), angular (angle from center))
}

struct FloatParams {
  line_color: vec4<f32>,  // Line Color
  fill_color: vec4<f32>,  // Fill Color 
  param3: vec4<f32>,     
    // 1 - Border width, 
    // 2 - Border smooth size
    // 3 - Gradient direction 
  gradient_end_color: vec4<f32>,  // If gradient enabled fill_color is used as start
};

// TODO: dynamic extra parameters.
// TODO: decrease binding and use structs ?
@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var<storage, read> transforms: array<mat4x4<f32>>;
@group(0) @binding(2) var<storage, read> positions: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read> sizes: array<vec2<f32>>;
@group(0) @binding(4) var<storage, read> uint_params: array<UintParams>;
@group(0) @binding(5) var<storage, read> float_params: array<FloatParams>;
//@group(0) @binding(6) var<storage, read> dynamic_params: array<vec4<f32>>;

@vertex fn vertMain(@builtin(instance_index) instance_index : u32, @builtin(vertex_index) vertex_index: u32) -> VertexOutput {
  let transform = transforms[instance_index];
  let t = uint_params[instance_index].param1.x & 255;
  var v = vec4<f32>(VERTICES[vertex_index], 0.0, 1.0);

  if (t == LINE) {
    // TODO: change to a transform
    v.xy = positions[instance_index];

    // A line (starts on edge 1,2 and finish on edge 3,4)
    let d = sizes[instance_index] - positions[instance_index];
    let l = normalize(d);
    let w = float_params[instance_index].param3.x;
    if (vertex_index == 0) {
      v.xy += vec2<f32>(l.y, -l.x)*w - l*w;
    } else if (vertex_index == 1) {
      v.xy += vec2<f32>(-l.y, l.x)*w - l*w;
    } else if (vertex_index == 2) {
      v.xy += d + vec2<f32>(l.y, -l.x)*w + l*w;
    } else if (vertex_index == 3) {
      v.xy += d + vec2<f32>(-l.y, l.x)*w + l*w;        
    }
  } else {
    v.xy *= sizes[instance_index] / 2.0;
    v.xy += positions[instance_index];
  }

  var output: VertexOutput;    
  output.Position = uniforms.view_projection * transform * v;
  output.frag_uv = vec4<f32>(VERTICES[vertex_index], 0.0, 0.0);
  output.params = vec4<u32>(instance_index, 0.0, 0.0, 0.0);

  return output;
}

@fragment fn fragMain(
  @location(0) frag_uv: vec4<f32>,
  @location(1) params_in: vec4<u32>,
) -> @location(0) vec4<f32> {
  let shape_index = params_in[0];
  let size = sizes[shape_index];

  let color = float_params[shape_index].line_color;
  var fill_color = float_params[shape_index].fill_color;
  
  var d = 0.0;
  let t = uint_params[shape_index].param1.x & 255;
  let w = float_params[shape_index].param3.x;
  var col = fill_color;

  if (t == RECT)
  {
    // Pos relative to center
    let s = 100.0; // step sharpness
    let border = w;
    d = min(size.x-abs(frag_uv.x*size.x), size.y-abs(frag_uv.y*size.y));
    if (d > border) {
      if (fill_color.a == 0) {
        discard;
      }
    } else {
      col = color;
    }
  } else if (t == CIRCLE) {
    // Pos relative to center
    let r = length(frag_uv.xy);
    if (r > 1.0) {
      discard;
    } else if (r > 1.0 - w / size.x) {
      col = color;
    } else if (fill_color.a == 0.0) {
      discard;
    }
  } else if (t == LINE) {
    // Line
    col = color;
  }
  return col;

    // t == 4.0   bezier qudratic
    // t == 5.0   bezier cubic

    // TODO:
    //    smooth step
    //    gradients: horizontal, vertial, diag, radial, angular
    //
    //    arc
    //    dash 
    //    pattern
    //
    //    rounded rect
    //
}

