shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.7, 0.7, 0.8, 0.1);
uniform float opacity : hint_range(0.0, 1.0) = 0.2;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;
uniform float refraction : hint_range(0.0, 1.0) = 0.05;
uniform float thickness : hint_range(0.0, 10.0) = 0.2;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

uniform bool use_tint = false;
uniform vec4 tint_color : source_color = vec4(0.0, 0.2, 0.4, 1.0);
uniform float tint_intensity : hint_range(0.0, 1.0) = 0.5;

uniform bool use_custom_texture = false;
uniform sampler2D custom_texture : source_color;
uniform float texture_mix : hint_range(0.0, 1.0) = 0.5;
uniform vec2 texture_scale = vec2(1.0, 1.0);
uniform vec2 texture_offset = vec2(0.0, 0.0);

uniform bool use_lens_distortion = false;
uniform float lens_distortion_amount : hint_range(0.0, 1.0) = 0.2;
uniform float lens_distortion_scale : hint_range(0.1, 10.0) = 1.0;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    ALBEDO = albedo.rgb;
    METALLIC = metallic;
    ROUGHNESS = roughness;
    SPECULAR = specular;
    
    vec3 normal = NORMAL;
    vec2 screen_uv = SCREEN_UV;
    
    vec2 distorted_uv = screen_uv;
    if (use_lens_distortion) {
        vec2 center = vec2(0.5, 0.5);
        vec2 uv_centered = screen_uv - center;
        float dist = length(uv_centered);
        float distortion = 1.0 + lens_distortion_amount * pow(dist * lens_distortion_scale, 2.0);
        distorted_uv = center + uv_centered * distortion;
    }
    
    vec2 ref_ofs = distorted_uv - normal.xy * refraction * thickness;
    
    vec4 refr_color = texture(SCREEN_TEXTURE, ref_ofs);
    
    if (use_tint) {
        refr_color.rgb = mix(refr_color.rgb, tint_color.rgb, tint_intensity);
    }
    
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), 5.0);
    
    vec4 tex_color = vec4(0.0);
    if (use_custom_texture) {
        vec2 tex_uv = UV * texture_scale + texture_offset;
        tex_color = texture(custom_texture, tex_uv);
        ALBEDO = mix(ALBEDO, tex_color.rgb, texture_mix);
    }
    
    ALBEDO = mix(ALBEDO, refr_color.rgb, 1.0 - opacity);
    
    ALPHA = opacity + fresnel * (1.0 - opacity);
    
    EMISSION += vec3(fresnel) * 0.05;
}