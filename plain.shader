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

struct PointLight {
    vec3 position;
    
    float constant;
    float linear;
    float quadratic;

    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};

struct DirectionalLight {
    vec3 direction;

    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};
#define POINT_LIGHT_NUM 16

uniform PointLight point_lights[POINT_LIGHT_NUM];
uniform int point_light_count;
uniform DirectionalLight dir_light;

in vec3 v_normal;
in vec3 v_frag_position;

vec3 calculate_dir_light(vec3 view_dir) {
    vec3 ambient = dir_light.ambient * object_color;
    vec3 diffuse = dir_light.diffuse * max(dot(dir_light.direction, v_normal), 0) * object_color;
    vec3 reflection = reflect(-dir_light.direction, v_normal);
    vec3 specular = dir_light.specular * pow(max(dot(view_dir, reflection), 0), 32); // * specularity at fragment;
    return (ambient + diffuse + specular);
}

void main()
{
    vec3 res = vec3(0);
    vec3 view_dir = normalize(viewer_position - v_frag_position);
    res = calculate_dir_light(view_dir);

    for (int i = 0; i < point_light_count; i++) {
        PointLight source = point_lights[i];

        vec3 light_to_frag = source.position - v_frag_position;
        float distance_to_light = length(light_to_frag);
        vec3 light_dir = light_to_frag / distance_to_light; // Basicly normalizing while reusing length calculations

        float attenuation = 1 / (source.constant + source.linear * distance_to_light 
            + source.quadratic * distance_to_light * distance_to_light);

        vec3 ambient = source.ambient * object_color;
        vec3 diffuse = source.diffuse * max(dot(light_dir, v_normal), 0) * object_color;
        vec3 reflection = reflect(-light_dir, v_normal);
        vec3 specular = source.specular * pow(max(dot(view_dir, reflection), 0), 32); // * specularity at fragment;

        res += (ambient + diffuse + specular) * attenuation;
    }
    o_color = vec4(res, 1);
};

