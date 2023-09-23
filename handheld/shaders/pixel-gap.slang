#version 450

layout(push_constant) uniform Push
{
    float BASE_RED;
    float BASE_GREEN;
    float BASE_BLUE;
    float DROP_SHADOW_INTENSITY;
    float GRID_INTENSITY;
	vec4 OutputSize;
	vec4 OriginalSize;
	vec4 SourceSize;
} registers;

#pragma parameter BASE_RED "Base Red" 230 0 256 1
#pragma parameter BASE_GREEN "Base Green" 225 0 256 1
#pragma parameter BASE_BLUE "Base Blue" 212 0 256 1
#pragma parameter DROP_SHADOW_INTENSITY "Drop Shadow Intensity" 0.1 0.0 1.0 0.05
#pragma parameter GRID_INTENSITY "Grid Intensity" 0.5 0.0 1.0 0.05

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
} global;

#pragma stage vertex

layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

/*
    VERTEX_SHADER
*/
void main()
{
	gl_Position = global.MVP * Position;
	vTexCoord   = TexCoord;
}

#pragma stage fragment

layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

// ### Magic Numbers...

#define GRID_GAP 1

// Colour correction
#define TARGET_GAMMA 1
const float INV_DISPLAY_GAMMA = 1.0 / 2.2;
#define CC_LUM 0.94
#define CC_R 0.493
#define CC_G 0.7247
#define CC_B 0.6345
#define CC_RG 0.1418
#define CC_RB 0.0084
#define CC_GR 0.2025
#define CC_GB 0.3365
#define CC_BR 0.2675
#define CC_BG 0.1

/*
    FRAGMENT SHADER
*/
void main()
{
    uint maxXScale = (uint(registers.OutputSize.x) - GRID_GAP) / uint(registers.SourceSize.x + 2);
    uint maxYScale = (uint(registers.OutputSize.y) - GRID_GAP) / uint(registers.SourceSize.y + 2);

    uint scale = min(maxXScale, maxYScale);

    uint xSize = scale * uint(registers.SourceSize.x) - GRID_GAP;
    uint ySize = scale * uint(registers.SourceSize.y) - GRID_GAP;

    uint xOffset = (uint(registers.OutputSize.x) - xSize) / 2;
    uint yOffset = (uint(registers.OutputSize.y) - ySize) / 2;

    vec2 outputPixelPosition = vTexCoord.xy * registers.OutputSize.xy;

    vec3 baseColor = vec3(registers.BASE_RED / 256, registers.BASE_GREEN / 256, registers.BASE_BLUE / 256);

    uint leftBound = xOffset;
    uint rightBound = xOffset + xSize - 1;
    uint topBound = yOffset;
    uint bottomBound = yOffset + ySize - 1;

    int leftOutOfBounds = int(leftBound) - int(outputPixelPosition.x);
    int rightOutOfBounds = int(outputPixelPosition.x) - int(rightBound);
    int topOutOfBounds = int(topBound) - int(outputPixelPosition.y);
    int bottomOutOfBounds = int(outputPixelPosition.y) - int(bottomBound);

    bool isInBounds = leftOutOfBounds <= 0 && rightOutOfBounds <= 0 &&
        topOutOfBounds <= 0 && bottomOutOfBounds <= 0;

    // feather out drop shadow from a box that shares the bottom left corner with the actual game render box,
    // but is a third of one "pixel box" smaller in both dimensions.
    // "pixel box" here is the box with a width of scale - GRID_GAP; i.e. the size that maps to one
    // source pixel.
    int topAndRightInset = int(scale - GRID_GAP) / 3;
    int shadowFeatherDistance = max(
        max(leftOutOfBounds, rightOutOfBounds + topAndRightInset),
        max(topOutOfBounds + topAndRightInset, bottomOutOfBounds)
    );
    float dropShadowProportion = clamp(1 - float(shadowFeatherDistance) / (scale - GRID_GAP), 0.0, 1.0);
    vec3 backgroundColor = mix(baseColor.rgb, vec3(0.0), dropShadowProportion * registers.DROP_SHADOW_INTENSITY);

    vec2 inputPixelPosition = vec2((outputPixelPosition.x - xOffset) / scale, (outputPixelPosition.y - yOffset) / scale);
    vec3 foregroundColor = texture(Source, registers.SourceSize.zw * inputPixelPosition).rgb;

    vec3 colorBelow = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(0.0, 1.0))).rgb;
    vec3 colorRight = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(1.0, 0.0))).rgb;
    vec3 colorBelowRightDiagonal = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(1.0, 1.0))).rgb;

    bool isOnVerticalGridLine = (uint(outputPixelPosition.x) - xOffset) % scale > scale - GRID_GAP - 1;
    bool isOnHorizontalGridLine = (uint(outputPixelPosition.y) - yOffset) % scale > scale - GRID_GAP - 1;

    float belowWeight = isOnHorizontalGridLine ? 1.0 : 0.0;
    float rightWeight = isOnVerticalGridLine ? 1.0 : 0.0;
    float diagonalWeight = isOnHorizontalGridLine && isOnVerticalGridLine ? 1.0 : 0.0;

    float cumulativeWeight = 1.0 + belowWeight;
    foregroundColor = mix(foregroundColor.rgb, colorBelow, belowWeight / cumulativeWeight);
    cumulativeWeight += rightWeight;
    foregroundColor = mix(foregroundColor.rgb, colorRight, rightWeight / cumulativeWeight);
    cumulativeWeight += diagonalWeight;
    foregroundColor = mix(foregroundColor.rgb, colorBelowRightDiagonal, diagonalWeight / cumulativeWeight);

    float gridLineWeight = isOnHorizontalGridLine || isOnVerticalGridLine ? registers.GRID_INTENSITY : 0.0;

    vec3 inBoundsColor = mix(foregroundColor.rgb, baseColor.rgb, gridLineWeight);
    vec3 color = isInBounds ? inBoundsColor : backgroundColor;

    FragColor = vec4(color, 1.0);
}
