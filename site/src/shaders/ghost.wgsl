struct Params {
  resolution : vec2f,
  center     : vec2f,
  velocity   : vec2f,
  time       : f32,
  fit        : f32,
  yaw        : f32,
  mouth      : f32,
  flow       : f32,
}

@group(0) @binding(0) var<uniform> params : Params;

const BODY_C   : vec2f = vec2f(300.0, 300.0);
const BODY_R   : f32   = 300.0;
const EYE_HALF : vec2f = vec2f(36.6275, 64.197);
const EYE_R    : f32   = 36.6275;
const EYE_Y    : f32   = 328.314;
const EYE_RING : f32   = 230.0;
const EYE_AZIM : f32   = 0.44680;
const MOUTH_RING : f32 = 200.0;
const MOUTH_Y  : f32   = 468.0;
const HEM_MID  : f32   = 738.6;
const HEM_AMP  : f32   = 64.86;
const HEM_FREQ : f32   = 6.28319;
const PIVOT    : vec2f = vec2f(300.0, 240.0);

const PAPER  : vec3f = vec3f(0.9725, 0.9725, 0.9490);

fn sd_box(p: vec2f, b: vec2f) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0);
}

fn sd_round_box(p: vec2f, b: vec2f, r: f32) -> f32 {
  let q = abs(p) - b + vec2f(r);
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn hash21(v: vec2f) -> f32 {
  var p3 = fract(vec3f(v.x, v.y, v.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hem_y(x: f32, flow: f32, speed: f32, yaw: f32) -> f32 {
  let k = (x - 300.0) / 300.0;
  let phase = HEM_FREQ * k + yaw * 1.1 + sin(flow * 0.30) * 0.15;
  let amp = HEM_AMP * (1.0 + sin(flow * 0.24 + 1.1) * 0.085) + speed * 20.0;
  let ripple = sin(HEM_FREQ * 2.0 * k - flow * 0.33 + yaw * 1.6 + 1.7) * (3.0 + speed * 13.0);
  return HEM_MID + sin(phase) * amp + ripple;
}

fn eye_sd(p: vec2f, azim: f32, yaw: f32) -> f32 {
  let a = azim + yaw;
  let depth = cos(a);
  if (depth <= 0.02) {
    return 1.0e5;
  }
  let squash = depth / cos(EYE_AZIM);
  let half = vec2f(EYE_HALF.x * squash, EYE_HALF.y);
  return sd_round_box(p - vec2f(300.0 + EYE_RING * sin(a), EYE_Y), half, min(half.x, half.y));
}

fn mouth_sd(p: vec2f, yaw: f32, open: f32) -> f32 {
  if (open <= 0.02) {
    return 1.0e5;
  }
  let depth = cos(yaw);
  if (depth <= 0.05) {
    return 1.0e5;
  }
  let half = vec2f(74.0 * depth * open, 3.0 + 5.5 * open);
  let c = vec2f(300.0 + MOUTH_RING * sin(yaw), MOUTH_Y);
  return sd_round_box(p - c, half, min(half.x, half.y));
}

fn sd_ghost(p: vec2f, flow: f32, speed: f32, yaw: f32, mouth: f32) -> f32 {
  let dome = length(p - BODY_C) - BODY_R;
  let trunk = sd_box(p - vec2f(300.0, 650.0), vec2f(300.0, 350.0));
  var d = min(dome, trunk);
  d = max(d, p.y - hem_y(p.x, flow, speed, yaw));

  let cuts = min(min(eye_sd(p, EYE_AZIM, yaw), eye_sd(p, -EYE_AZIM, yaw)), mouth_sd(p, yaw, mouth));
  return max(d, -cuts);
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let res = max(params.resolution, vec2f(1.0));
  let aspect = res.x / res.y;
  let t = params.time;
  let vel = params.velocity;
  let speed = min(length(vel), 1.8);

  let unit = 800.0 / max(params.fit, 0.02);
  let p = (uv - vec2f(0.5)) * vec2f(aspect, 1.0);
  var q = (p - params.center) * unit + vec2f(300.0, 400.0);

  if (length(q - vec2f(300.0, 460.0)) > 900.0) {
    return vec4f(0.0);
  }

  let yaw = params.yaw;
  let bank = clamp(-vel.x * 0.16, -0.30, 0.30);
  let c = cos(bank);
  let s = sin(bank);
  let r = q - PIVOT;
  q = PIVOT + vec2f(c * r.x - s * r.y, s * r.x + c * r.y);

  let calm = 1.0 - smoothstep(0.05, 0.9, speed);
  q.y += (sin(t * 1.15) * 15.0 + sin(t * 0.67 + 2.1) * 8.0) * calm;

  let squeeze = 1.0 - 0.13 * abs(sin(yaw));
  q.x = 300.0 + (q.x - 300.0) / squeeze;

  let trail = clamp((q.y - 210.0) / 620.0, 0.0, 1.0);
  let lag = trail * trail;
  q.x += clamp(vel.x, -1.8, 1.8) * lag * 105.0;
  q.y += clamp(vel.y, -1.8, 1.8) * lag * 70.0;

  let d = sd_ghost(q, params.flow, speed, yaw, params.mouth);

  let px = unit / res.y;
  let soft = max(px * 1.6, 4.0);

  let mask = 1.0 - smoothstep(-soft, soft, d);
  let grain = (hash21(q * 0.35) - 0.5) * 0.05;

  let across = clamp((q.x - 300.0) / 300.0, -1.0, 1.0);
  let form = 1.0 + across * sin(yaw) * 0.14;

  let body = PAPER * (1.0 + grain) * form;

  let border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let fade = smoothstep(0.0, 0.06, border);

  let alpha = mask * fade;
  return vec4f(body * alpha, alpha);
}
