#shader vertex
#version 330 core

layout(location = 0) in vec4 position;

out mediump vec4 v_Color;

void main()
{
	v_Color = vec4(1.0f, 0.0f, 0.0f, 1.0f); 
	gl_Position = position;
};

#shader fragment
#version 330 core

layout(location = 0) out vec4 o_Color;

in mediump vec4 v_Color;

void main()
{
   o_Color = v_Color; 
};

