#shader vertex
#version 330 core

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

uniform mat4 projection;
uniform mat4 model;
uniform mat4 view;
uniform mat3 normal_matrix;

out vec3 v_normal;
out vec3 v_frag_position;

void main()
{
    gl_Position = projection * view * model * vec4(position, 1.0f);
    v_frag_position = (model * vec4(position, 1.0f)).xyz;
    v_normal = normalize(normal_matrix * normal);
};

#shader fragment
#version 330 core

layout(location = 0) out vec4 o_color;

uniform vec3 viewer_position;
uniform vec3 object_color;

uniform vec3 light_color;
uniform vec4 light_vector; // if w == 0 then ~light_direction else ~light_position
uniform float constant;
uniform float linear;
uniform float quadratic;

in vec3 v_normal;
in vec3 v_frag_position;

void main()
{
    if (light_vector.w == 1) {
        // Point light
        vec3 light_to_frag = light_vector.xyz - v_frag_position;
        float distance_to_light = length(light_to_frag);

        float attenuation = 1 / (constant + linear * distance_to_light + quadratic * distance_to_light * distance_to_light);

        float ambient_strength = 0.15;
        float specular_strength = 0.15;

        vec4 diffuse_color = vec4(object_color, 1);
        vec4 ambient = ambient_strength * diffuse_color;
        
        vec3 light_dir = light_to_frag / distance_to_light; // Basicly normalizing while reusing calculations
        vec4 diffuse = max(dot(light_dir, v_normal), 0) * diffuse_color;

        vec3 reflection = reflect(-light_dir, v_normal);
        vec3 view_dir = normalize(viewer_position - v_frag_position);
        
        vec4 specular = pow(max(dot(view_dir, reflection), 0), 32) * specular_strength * vec4(light_color, 1);

        o_color = (ambient + diffuse + specular) * attenuation;
    } else {
        // Directional light
        float attenuation = 1;

        float ambient_strength = 0.15;
        float specular_strength = 0.15;

        vec4 diffuse_color = vec4(object_color, 1);
        vec4 ambient = ambient_strength * diffuse_color;
        
        vec3 light_dir = normalize(-light_vector.xyz);
        vec4 diffuse = max(dot(light_dir, v_normal), 0) * diffuse_color;

        vec3 reflection = reflect(-light_dir, v_normal);
        vec3 view_dir = normalize(viewer_position - v_frag_position);
        
        vec4 specular = pow(max(dot(view_dir, reflection), 0), 32) * specular_strength * vec4(light_color, 1);

        o_color = (ambient + diffuse + specular) * attenuation;
    }
};

