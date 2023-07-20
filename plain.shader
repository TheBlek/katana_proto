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
    v_normal = normal_matrix * normal;
};

#shader fragment
#version 330 core

layout(location = 0) out vec4 o_color;

uniform vec4 object_color;
uniform vec4 light_color;
uniform vec3 light_position;
uniform vec3 viewer_position;

in vec3 v_normal;
in vec3 v_frag_position;

void main()
{
    float ambient_strength = 0.1; 
    float specular_strength = 0.5;

    vec4 ambient = ambient_strength * light_color;
    
    vec3 light_dir = normalize(light_position - v_frag_position);
    vec4 diffuse = max(dot(light_dir, v_normal), 0) * light_color;

    vec3 reflection = reflect(-light_dir, v_normal);
    vec3 view_dir = normalize(viewer_position - v_frag_position);
    
    vec4 specular = pow(max(dot(view_dir, reflection), 0), 64) * light_color;

    o_color = (ambient + diffuse + specular) * object_color;
};

