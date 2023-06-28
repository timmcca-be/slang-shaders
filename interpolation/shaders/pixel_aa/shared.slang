// This file has to be included at the frag shader stage so that fwidth() is
// defined.

// clang-format off
#pragma parameter PIX_AA_SETTINGS "=== Pixel AA v1.1 settings ===" 0.0 0.0 1.0 1.0
#pragma parameter PIX_AA_SHARP "Pixel AA sharpening amount" 1.0 1.0 4.0 0.05
#pragma parameter PIX_AA_GAMMA "Enable gamma-correct blending" 1.0 0.0 1.0 1.0
#pragma parameter PIX_AA_SUBPX "Enable subpixel AA" 0.0 0.0 1.0 1.0
#pragma parameter PIX_AA_SUBPX_BGR "Use BGR subpx. instead of RGB" 0.0 0.0 1.0 1.0
// clang-format on

// Similar to smoothstep, but has a configurable slope at x = 0.5.
// Original smoothstep has a slope of 1.5 at x = 0.5
#define INSTANTIATE_SLOPESTEP(T)                               \
    T slopestep(T edge0, T edge1, T x, float slope) {          \
        x = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);    \
        const T s = sign(x - 0.5);                             \
        const T o = (1.0 + s) * 0.5;                           \
        return o - 0.5 * s * pow(2.0 * (o - s * x), T(slope)); \
    }
INSTANTIATE_SLOPESTEP(float)
INSTANTIATE_SLOPESTEP(vec2)

vec3 to_lin(vec3 x) { return pow(x, vec3(2.2)); }

vec3 to_srgb(vec3 x) { return pow(x, vec3(1.0 / 2.2)); }

vec2 get_texel_size(vec2 pix_coord) {
    return clamp(fwidth(pix_coord), 1.0e-5, 1.0);
}

// Params:
// pix_coord: Coordinate in source pixel coordinates
// px_size_uv: 1 / source resolution
vec3 sample_aa(sampler2D tex, vec2 pix_coord, vec2 px_size_uv,
               bool gamma_correct, float sharpness, vec2 tx_size) {
    const vec2 tx_coord = pix_coord - 0.5 * tx_size;
    const vec2 tx_coord_i = floor(tx_coord);
    const vec2 tx_offset =
        slopestep(1.0 - tx_size, vec2(1.0), fract(tx_coord), sharpness);
    // With gamma correct blending, we have to do 4 taps and blend manually.
    // Without it, we can make use of a single tap using bilinear interpolation.
    if (gamma_correct) {
        const vec3 samples[] = {
            to_lin(texture(tex, (tx_coord_i + 0.5) * px_size_uv).rgb),
            to_lin(
                texture(tex, (tx_coord_i + vec2(1.5, 0.5)) * px_size_uv).rgb),
            to_lin(
                texture(tex, (tx_coord_i + vec2(0.5, 1.5)) * px_size_uv).rgb),
            to_lin(texture(tex, (tx_coord_i + 1.5) * px_size_uv).rgb)};
        return to_srgb(mix(mix(samples[0], samples[1], tx_offset.x),
                           mix(samples[2], samples[3], tx_offset.x),
                           tx_offset.y));
    } else {
        return texture(tex, (tx_coord_i + 0.5 + tx_offset) * px_size_uv).rgb;
    }
}

vec3 sample_aa(sampler2D tex, vec2 pix_coord, vec2 px_size_uv,
               bool gamma_correct, float sharpness) {
    const vec2 tx_size = get_texel_size(pix_coord);
    return sample_aa(tex, pix_coord, px_size_uv, gamma_correct, sharpness,
                     tx_size);
}
