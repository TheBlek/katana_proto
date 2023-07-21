#shader vertex
#version 330 core

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;

uniform mat4 projection;
uniform mat4 model;
uniform mat4 view;
uniform mat3 normal_matrix;

out vec3 v_normal;
out vec3 v_frag_position;
out vec2 v_uv;

void main()
{
    gl_Position = projection * view * model * vec4(position, 1.0f);
    v_frag_position = (model * vec4(position, 1.0f)).xyz;
    v_normal = normalize(normal_matrix * normal);
    v_uv = uv;
};

#shader fragment
#version 330 core

layout(location = 0) out vec4 o_color;

uniform vec4 light_color;
uniform vec3 light_position;
uniform vec3 viewer_position;
uniform sampler2D u_texture;

in vec3 v_normal;
in vec3 v_frag_position;
in vec2 v_uv;

void main()
{
    float ambient_strength = 0.15; 
    float specular_strength = 0.5;

    vec4 ambient = ambient_strength * light_color;
    
    vec3 light_dir = normalize(light_position - v_frag_position);
    vec4 diffuse = max(dot(light_dir, v_normal), 0) * light_color;

    vec3 reflection = reflect(-light_dir, v_normal);
    vec3 view_dir = normalize(viewer_position - v_frag_position);
    
    vec4 specular = pow(max(dot(view_dir, reflection), 0), 32) * specular_strength * light_color;

    vec4 object_color = texture(u_texture, vec2(v_uv.x, v_uv.y));
    o_color = (ambient + diffuse + specular) * object_color;
    //o_color = vec4(reflection, 1);
};

