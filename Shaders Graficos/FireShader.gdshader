shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
render_mode depth_draw_opaque;

group_uniforms general_parameters;
uniform int raymarch_steps : hint_range(2, 24) = 9; //3-4 for low end (very slow), 6-12 for mid-range, 16-24 high-end ultra quality (very slow).
uniform sampler3D sample_noise; // Your 3D noise texture!
uniform bool billboard = true;
uniform sampler2D depth_texture : hint_depth_texture;
uniform float proximity_fade_distance = 0.5;
uniform float time_scale = 0.027; // Animation speed for noise flow
uniform float noise_scale = 0.45; // Overall spatial scale of the 3D noise
uniform float noise_threshold = 0.45; // Controls density/cutouts of the flame
group_uniforms shape_composition;
// New uniforms for the box shape
uniform float fire_height = 2.45;
uniform float fire_width = 2.25; // Width, Height, Depth of the base fire volume
uniform vec3 box_center = vec3(0.0, 0.0, 0.0); // Center of the fire volume
uniform vec3 box_rotation = vec3(0.0); // Euler angles for rotating the fire (e.g., wind direction)
// New uniform for controlling the tapering effect
uniform float taper_factor = 0.425; // How much the top tapers (0.0 = no taper, 1.0 = tapers to a point)

// --- Wobble Uniforms ---
uniform float wobble_strength = 2.0; // Overall amplitude of the wobble displacement
uniform float wobble_speed = 6.0;    // Speed of the internal noise animation
uniform float wobble_noise_frequency : hint_range(0.1, 10.0) = 0.125; // Controls the spatial scale/granularity of the wobble noise

// --- INTERNAL SHAPE SHARPNESS CONTROL ---
uniform float sharpness_cutoff : hint_range(0.0, 20.0) = 4.5; // Controls the softness/sharpness of the fire's internal density (0.0 = sharp, higher values = softer)




group_uniforms visual_composition;
// Fire color gradient uniforms
uniform float emission_strength = 12.5; // Overall brightness of the fire
// --- Core Glow Density Multiplier ---
uniform float core_glow_multiplier : hint_range(0.0, 20.0) = 16.0; // Multiplies the density factor for the core color mix

uniform vec3 color_core = vec3(1.0, 0.9, 0.5); // Bright yellow/white
uniform vec3 color_mid = vec3(1.0, 0.625, 0.0); // Orange
uniform vec3 color_outer = vec3(0.8, 0.01, 0.0); // Red
uniform vec3 color_smoke = vec3(-0.067, -0.067, -0.067); // Darker for smoke/top


varying vec3 world_position;
varying vec3 world_camera;


// --- Helper Functions ---

vec3 get_box_center(vec3 npw){
    vec3 result = box_center+npw;
    return result;
}

// Get animated time for noise
float get_animated_time(){
    return -TIME * time_scale;
}

// Construct a 3x3 rotation matrix from Euler angles (XYZ order)
mat3 rotation_matrix(vec3 angles) {
    float cx = cos(angles.x), sx = sin(angles.x);
    float cy = cos(angles.y), sy = sin(angles.y);
    float cz = cos(angles.z), sz = sin(angles.z);

    vec3 row0 = vec3(cy * cz, -cy * sz, sy);
    vec3 row1 = vec3(cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy);
    vec3 row2 = vec3(sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy);

    return mat3(row0, row1, row2);
}

// --- Main Noise Function (now exclusively samples the 3D texture) ---
float get_noise_value(vec3 p_coord, float scale_factor, float time_offset_z) {
    // Corrected: time_offset_z applied to Z-component for depth scrolling
    vec3 tex_coords = p_coord * scale_factor + vec3(0.0, time_offset_z, 0.0);
    return texture(sample_noise, fract(tex_coords)).r; // fract ensures seamless looping
}


// --- SDF for a Box (Prism) ---
float sdf_box(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(vec3(0.0), q)) + min(0.0, max(q.x, max(q.y, q.z)));
}

// --- Per-sample Noise-Based Wobble Function (now uses 3D texture) ---
vec3 get_per_sample_wobble(vec3 p, float strength, float noise_freq, float speed) {
    float time_val = get_animated_time();

    float wobble_time_offset_x = time_val * speed;
    float wobble_time_offset_y = time_val * speed * 1.2;
    float wobble_time_offset_z = time_val * speed * 0.8;

    // Sample the 3D texture for each component of the wobble
    // Use slightly different base offsets for x, y, z to ensure distinct noise patterns
    float wx = get_noise_value(p + vec3(100.0, 0.0, 0.0), noise_freq, wobble_time_offset_x);
    float wy = get_noise_value(p + vec3(0.0, 200.0, 0.0), noise_freq, wobble_time_offset_y);
    float wz = get_noise_value(p + vec3(0.0, 0.0, 300.0), noise_freq, wobble_time_offset_z);

    return vec3(wx - 0.5, wy - 0.5, wz - 0.5) * strength;
}


// --- Main SDF Function for Fire Volume ---
float fire_sdf(vec3 p, vec3 npw) {
    vec3 local_p = p - get_box_center(npw);
    local_p = transpose(rotation_matrix(box_rotation)) * local_p;
	vec3 box_size = vec3(fire_width,fire_height,fire_width);
    float normalized_height = (local_p.y + box_size.y * 0.5) / box_size.y;
    float current_taper = 1.0 - normalized_height * taper_factor;
    current_taper = max(0.01, current_taper);

    vec3 tapered_local_p = local_p;
    tapered_local_p.xz /= current_taper;

    vec3 per_sample_wobble_offset = get_per_sample_wobble(local_p, wobble_strength, wobble_noise_frequency, wobble_speed);

    float dist = sdf_box(tapered_local_p, box_size * 0.5);

    float sdf_noise_time_offset = get_animated_time() * 20.0;
    float distortion = get_noise_value(local_p + per_sample_wobble_offset, noise_scale * 0.5, sdf_noise_time_offset) * 0.3;
    dist += distortion;

    return dist;
}

void vertex() {
    if (billboard){
        mat3 cam_rotation = mat3(
            MAIN_CAM_INV_VIEW_MATRIX[0].xyz,
            MAIN_CAM_INV_VIEW_MATRIX[1].xyz,
            MAIN_CAM_INV_VIEW_MATRIX[2].xyz
        );
        VERTEX = cam_rotation * VERTEX;
        NORMAL = cam_rotation * NORMAL;
    }
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_camera = (inverse(VIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}


void fragment() {
    if (noise_threshold <= 0.001){
        discard;
    }

    vec3 ray_origin = world_camera;
    vec3 ray_direction = normalize(world_position - world_camera);

    // --- Calculate World-Space Bounding Box for the Fire Volume ---
    vec3 fire_world_center = get_box_center(NODE_POSITION_WORLD);
	vec3 box_size = vec3(fire_width,fire_height,fire_width);
    float max_dim = max(box_size.x, max(box_size.y, box_size.z));
    vec3 rotated_box_half_extents = vec3(max_dim); // A sphere-like bounding volume for the box

    vec3 box_min_world = fire_world_center - rotated_box_half_extents * 0.5; // Adjusted for half extents
    vec3 box_max_world = fire_world_center + rotated_box_half_extents * 0.5; // Adjusted for half extents


    // --- Ray-AABB Intersection for Initial Marching Range ---
    float t_enter = 0.0; // Ray's entry point into the overall volume of the fire
    float t_exit = length(fire_world_center - ray_origin) + length(rotated_box_half_extents); // A safe upper bound for initial ray length

    vec3 inv_ray_direction = 1.0 / ray_direction; // Precompute inverse to avoid division by zero (handle inf later)

    vec3 t0 = (box_min_world - ray_origin) * inv_ray_direction;
    vec3 t1 = (box_max_world - ray_origin) * inv_ray_direction;

    // Use specific components (x,y,z) for comparison
    vec3 t_smaller = min(t0, t1);
    vec3 t_larger = max(t0, t1);

    t_enter = max(t_enter, max(t_smaller.x, max(t_smaller.y, t_smaller.z)));
    t_exit = min(t_exit, min(t_larger.x, min(t_larger.y, t_larger.z)));

    // If ray doesn't intersect the conservative bounding box, or points away
    if (t_enter >= t_exit) { // Check if entry is past exit, or if ray starts inside but exits immediately
        discard;
    }
    // Ensure the ray starts marching at least at 0 (not behind the camera)
    t_enter = max(0.0, t_enter);

    float total_distance = t_enter; // Start marching from the entry point
    float march_range = t_exit - t_enter; // The distance range to march within the box

    // If for some reason the march range is zero or negative, discard to prevent errors
    if (march_range <= 0.0001) {
        discard;
    }

    vec3 final_color = vec3(0.0);
    float current_alpha = 0.0;

    float step_size = march_range / float(raymarch_steps); // Distribute steps evenly over the intersection range

    for (int i = 0; i < raymarch_steps; i++) {
        vec3 current_position = ray_origin + ray_direction * total_distance;

        // Exit loop if current_position is outside the actual march_range or goes beyond t_exit
        if (total_distance >= t_exit) {
            break;
        }

        float sdf_dist = fire_sdf(current_position,NODE_POSITION_WORLD);

        float density_noise_time_offset = get_animated_time() * 30.0;
        vec3 per_sample_wobble_offset_density = get_per_sample_wobble(current_position, wobble_strength * 0.7, wobble_noise_frequency * 1.1, wobble_speed * 0.9);

        float density_noise_value = get_noise_value(current_position + per_sample_wobble_offset_density, noise_scale * 0.7, density_noise_time_offset);

        float density = 0.0;
        if (sdf_dist < 0.0) {
            float noise_shaping = 1.0 - smoothstep(noise_threshold * 0.8, noise_threshold * 1.2, density_noise_value);
            density = smoothstep(0.0, sharpness_cutoff, -sdf_dist * 0.5 + noise_shaping);
            density = clamp(density, 0.0, 1.0);

            vec3 local_fire_pos = current_position - get_box_center(NODE_POSITION_WORLD);
            local_fire_pos = transpose(rotation_matrix(box_rotation)) * local_fire_pos;
            float height_alpha = smoothstep(0.5, 1.0, (local_fire_pos.y + box_size.y * 0.5) / box_size.y);
            density *= (1.0 - height_alpha * 0.7);

            float dist_to_center = length(local_fire_pos.xz);
            density *= smoothstep(0.7, 0.0, dist_to_center / (box_size.x * 0.5));
        }

        float alpha_step = 1.0 - exp(-density * step_size * 25.0);

        vec3 current_color_rgb = mix(color_outer, color_mid, density_noise_value);

        current_color_rgb = mix(current_color_rgb, color_core, smoothstep(0.7, 1.0, density * core_glow_multiplier));

        vec3 local_fire_pos_for_color = current_position - get_box_center(NODE_POSITION_WORLD);
        local_fire_pos_for_color = transpose(rotation_matrix(box_rotation)) * local_fire_pos_for_color;
        float height_factor = (local_fire_pos_for_color.y + box_size.y * 0.5) / box_size.y;
        current_color_rgb = mix(current_color_rgb, color_smoke, smoothstep(0.6, 1.0, height_factor * (1.0 - density)));

        final_color += current_color_rgb * alpha_step * (1.0 - current_alpha);
        current_alpha += alpha_step * (1.0 - current_alpha);

        if (current_alpha > 0.99) {
            break;
        }

        total_distance += step_size;
    }

    ALPHA = clamp(current_alpha, 0.0, 1.0);

    float proximity_depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    vec4 proximity_view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, proximity_depth_tex, 1.0);
    proximity_view_pos.xyz /= proximity_view_pos.w;
    ALPHA *= clamp(1.0 - smoothstep(proximity_view_pos.z + proximity_fade_distance, proximity_view_pos.z, VERTEX.z), 0.0, 1.0);

    ALBEDO = final_color * emission_strength;
    EMISSION = ALBEDO;
}