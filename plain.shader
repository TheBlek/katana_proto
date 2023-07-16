#shader vertex
#version 330 core

layout(location = 0) in vec3 position;

uniform mat4 projection;
uniform mat4 model;
uniform mat4 view;

out mediump vec4 v_Color;

void main()
{
	v_Color = vec4(1.0f, 0.0f, 0.0f, 1.0f); 
    gl_Position = projection * view * model * vec4(position, 1.0f);
};

#shader fragment
#version 330 core

layout(location = 0) out vec4 o_Color;

in mediump vec4 v_Color;

void main()
{
   o_Color = v_Color; 
};

