#version 450

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
	vec4 OutputSize;
	vec4 OriginalSize;
	vec4 SourceSize;
} global;

const mat3 matrix = mat3(
	0.493, 0.1418, 0.0084,  //red channel
	0.2025, 0.7247, 0.3365,    //green channel
	0.2675, 0.1, 0.6345  //blue channel
);

const vec3 intercepts = vec3(
    0.0293, 0.0195, 0.0105
);

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
	gl_Position = global.MVP * Position;
	vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

void main()
{
	// our adjustments need to happen in linear gamma
	vec3 screen = texture(Source, vTexCoord).rgb;
	screen = matrix * screen + intercepts;
	FragColor = vec4(screen, 1.0);
}