#version 450
/*
    zfast_crt - A very simple CRT shader.

    Copyright (C) 2017 Greg Hogan (SoltanGris42)
	edited by metallic 77.
	ported to slang by gregoricavichioli & hunterk.

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the Free
    Software Foundation; either version 2 of the License, or (at your option)
    any later version.

*/

layout(push_constant) uniform Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
float pi, blurx, blury, HIGHSCANAMOUNT1, HIGHSCANAMOUNT2, MASK_DARK, MASK_FADE, sat, FLICK;
} params;

#pragma parameter blurx "Convergence X-Axis" 0.45 -1.0 2.0 0.05
#pragma parameter blury "Convergence Y-Axis" -0.25 -1.0 1.0 0.05
#pragma parameter HIGHSCANAMOUNT1 "Scanline Amount (Low)" 0.4 0.0 1.0 0.05
#pragma parameter HIGHSCANAMOUNT2 "Scanline Amount (High)" 0.3 0.0 1.0 0.05
#pragma parameter MASK_DARK "Mask Effect Amount" 0.3 0.0 1.0 0.05
#pragma parameter MASK_FADE "Mask/Scanline Fade" 0.7 0.0 1.0 0.05
#pragma parameter sat "Saturation" 1.0 0.0 3.0 0.05
#pragma parameter FLICK "Flicker" 10.0 0.0 50.0 1.0

#define pi 3.14159
#define blurx params.blurx
#define blury params.blury
#define HIGHSCANAMOUNT1 params.HIGHSCANAMOUNT1
#define HIGHSCANAMOUNT2 params.HIGHSCANAMOUNT2
#define BRIGHTBOOST params.BRIGHTBOOST
#define MASK_DARK params.MASK_DARK
#define MASK_FADE params.MASK_FADE
#define sat params.sat
#define FLICK params.FLICK
#define SourceSize params.SourceSize
#define OriginalSize params.OriginalSize
#define OutputSize params.OutputSize

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) out float maskFade;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord*1.0001;
    maskFade = 0.3333*MASK_FADE;
}


#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in float maskFade;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

#define blur_y blury/(SourceSize.y*2.0)
#define blur_x blurx/(SourceSize.x*2.0)
#define iTimer (float(params.FrameCount)*2.0)
#define flicker FLICK/1000.0


void main()
{
     vec2 pos = vTexCoord;    
     float cent = floor(vTexCoord.y*SourceSize.y)+0.5;
     float ycoord = cent*SourceSize.w; 
     pos = vec2(vTexCoord.x,ycoord);
     vec3 sample1 = sin(iTimer)*flicker + texture(Source,vec2(pos.x + blur_x, pos.y - blur_y)).rgb;
     vec3 sample2 =                0.5*texture(Source,pos).rgb;
     vec3 sample3 = sin(iTimer)*flicker + texture(Source,vec2(pos.x - blur_x, pos.y + blur_y)).rgb;
    
     vec3 colour = vec3 (sample1.r*0.5  + sample2.r, 
                         sample1.g*0.25 + sample2.g + sample3.g*0.25, 
                                          sample2.b + sample3.b*0.5);
    
     vec3 lumweight=vec3(0.22,0.71,0.07);
     float lum = dot(colour,lumweight);
   
     vec3 graycolour = vec3(lum);
     colour = vec3(mix(graycolour,colour.rgb,sat));

     float SCANAMOUNT = mix(HIGHSCANAMOUNT1,HIGHSCANAMOUNT2,max(max(colour.r,colour.g),colour.b));
    
     float scanLine = SCANAMOUNT * sin(fract(vTexCoord.y*SourceSize.y)*3.14159)+1.0-SCANAMOUNT;
        
     if (OriginalSize.y > 400.0) scanLine = 1.0;

     float whichmask = fract(vTexCoord.x*OutputSize.x*0.4999);
     float mask = 1.0 + float(whichmask < 0.5) * -MASK_DARK;

     colour *= colour;
    colour.rgb *= mix(mask*scanLine, scanLine, dot(colour.rgb,vec3(maskFade)));
    colour = sqrt(colour);
    FragColor.rgb = colour.rgb;
} 
