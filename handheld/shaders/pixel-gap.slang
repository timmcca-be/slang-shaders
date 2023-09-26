#version 450

layout(push_constant) uniform Push
{
    float BASE_RED;
    float BASE_GREEN;
    float BASE_BLUE;
    float DROP_SHADOW_INTENSITY;
    float GRID_INTENSITY;
    float FUZZ_INTENSITY;
    float FUZZ_RADIUS;
	vec4 OutputSize;
	vec4 OriginalSize;
	vec4 SourceSize;
} registers;

#pragma parameter BASE_RED "Base Red" 230 0 256 1
#pragma parameter BASE_GREEN "Base Green" 225 0 256 1
#pragma parameter BASE_BLUE "Base Blue" 212 0 256 1
#pragma parameter DROP_SHADOW_INTENSITY "Drop Shadow Intensity" 0.1 0.0 1.0 0.05
#pragma parameter GRID_INTENSITY "Grid Intensity" 0.65 0.0 1.0 0.05
#pragma parameter FUZZ_INTENSITY "Fuzz Intensity" 0.35 0.0 1.0 0.05
#pragma parameter FUZZ_RADIUS "Fuzz Radius" 0.8 0.0 1.0 0.05

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

// 2 * g(1, 0) = pi/2
const float totalFuzzWeight = 1.5707963268;

float g_internal(float x, float b)
{
    float asinX = asin(x);
    float negXSqPlusOne = -x*x + 1;

    return sin(4*asinX) / 16.0
        + (asinX + sin(2*asinX)) / 4.0
        + (b*b*b*x + b*x*x*x - x*negXSqPlusOne*sqrt(negXSqPlusOne)) / 3.0
        - b*x;
}

// how much glow lives in the portion of the glow radius from the top left corner (-1, 1) to (a, b)?
// i'm pretty sure everything will explode if b < 0, so don't do that please
float g(float a, float b)
{
    b = min(b, 1.0);
    float xMin = -sqrt(1 - b*b);
    float xMax = min(-xMin, max(a, xMin));

    // \int_{xMin}^{xMax} \int_{b}^{\sqrt{1-x^2}} 1 - x^2 - y^2 dx
    return g_internal(xMax, b) - g_internal(xMin, b);
}

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

    bool isInBounds = topOutOfBounds <= 0 && bottomOutOfBounds <= 0
        && leftOutOfBounds <= 0 && rightOutOfBounds <= 0;

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
    vec3 primaryPixelColor = texture(Source, registers.SourceSize.zw * inputPixelPosition).rgb;

    vec3 colorBelow = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(0.0, 1.0))).rgb;
    vec3 colorRight = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(1.0, 0.0))).rgb;
    vec3 colorBelowRightDiagonal = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(1.0, 1.0))).rgb;

    bool isOnVerticalGridLine = (uint(outputPixelPosition.x) - xOffset) % scale > scale - GRID_GAP - 1;
    bool isOnHorizontalGridLine = (uint(outputPixelPosition.y) - yOffset) % scale > scale - GRID_GAP - 1;

    float belowWeight = isOnHorizontalGridLine ? 1.0 : 0.0;
    float rightWeight = isOnVerticalGridLine ? 1.0 : 0.0;
    float diagonalWeight = isOnHorizontalGridLine && isOnVerticalGridLine ? 1.0 : 0.0;

    float cumulativeWeight = 1.0 + belowWeight;
    vec3 foregroundColor = mix(primaryPixelColor.rgb, colorBelow, belowWeight / cumulativeWeight);
    cumulativeWeight += rightWeight;
    foregroundColor = mix(foregroundColor.rgb, colorRight, rightWeight / cumulativeWeight);
    cumulativeWeight += diagonalWeight;
    foregroundColor = mix(foregroundColor.rgb, colorBelowRightDiagonal, diagonalWeight / cumulativeWeight);

    float gridLineWeight = isOnHorizontalGridLine || isOnVerticalGridLine ? registers.GRID_INTENSITY : 0.0;

    vec3 inBoundsColor = mix(foregroundColor.rgb, baseColor.rgb, gridLineWeight);
    vec3 color = isInBounds ? inBoundsColor : backgroundColor;

    uint xShift = scale * (xOffset / scale + 1) - xOffset;
    uint yShift = scale * (yOffset / scale + 1) - yOffset;

    uint xPositionInPixel = (uint(outputPixelPosition.x) + xShift) % scale;
    uint yPositionInPixel = (uint(outputPixelPosition.y) + yShift) % scale;

    float scaledXPosition = (1 + xPositionInPixel) / float(scale);
    float scaledYPosition = (1 + yPositionInPixel) / float(scale);

    float aboveLeftFuzzWeight = g(-scaledXPosition / registers.FUZZ_RADIUS, scaledYPosition / registers.FUZZ_RADIUS);
    float aboveRightFuzzWeight = g(-(1 - scaledXPosition) / registers.FUZZ_RADIUS, scaledYPosition / registers.FUZZ_RADIUS);
    float aboveFuzzWeight = g(1, scaledYPosition / registers.FUZZ_RADIUS) - aboveLeftFuzzWeight - aboveRightFuzzWeight;

    float belowLeftFuzzWeight = g(-scaledXPosition / registers.FUZZ_RADIUS, (1 - scaledYPosition) / registers.FUZZ_RADIUS);
    float belowRightFuzzWeight = g(-(1 - scaledXPosition) / registers.FUZZ_RADIUS, (1 - scaledYPosition) / registers.FUZZ_RADIUS);
    float belowFuzzWeight = g(1, (1 - scaledYPosition) / registers.FUZZ_RADIUS) - belowLeftFuzzWeight - belowRightFuzzWeight;

    float leftFuzzWeight = g(1, scaledXPosition / registers.FUZZ_RADIUS) - aboveLeftFuzzWeight - belowLeftFuzzWeight;
    float rightFuzzWeight = g(1, (1 - scaledXPosition) / registers.FUZZ_RADIUS) - aboveRightFuzzWeight - belowRightFuzzWeight;

    float selfFuzzWeight = totalFuzzWeight
        - aboveLeftFuzzWeight
        - aboveRightFuzzWeight
        - aboveFuzzWeight
        - belowLeftFuzzWeight
        - belowRightFuzzWeight
        - belowFuzzWeight
        - leftFuzzWeight
        - rightFuzzWeight;

    aboveLeftFuzzWeight *= registers.FUZZ_INTENSITY;
    aboveRightFuzzWeight *= registers.FUZZ_INTENSITY;
    aboveFuzzWeight *= registers.FUZZ_INTENSITY;
    belowLeftFuzzWeight *= registers.FUZZ_INTENSITY;
    belowRightFuzzWeight *= registers.FUZZ_INTENSITY;
    belowFuzzWeight *= registers.FUZZ_INTENSITY;
    leftFuzzWeight *= registers.FUZZ_INTENSITY;
    rightFuzzWeight *= registers.FUZZ_INTENSITY;
    selfFuzzWeight *= registers.FUZZ_INTENSITY;

    float left = inputPixelPosition.x - 1.0;
    float right = inputPixelPosition.x + 1.0;
    float above = inputPixelPosition.y - 1.0;
    float below = inputPixelPosition.y + 1.0;

    // different from the inbounds check toward the beginning of this function because we still count it if we're on the very last gridline
    bool isLeftInHorizontalBounds = left >= 0 && left < registers.SourceSize.x;
    bool isRightInHorizontalBounds = right >= 0 && right < registers.SourceSize.x;
    bool isAboveInVerticalBounds = above >= 0 && above < registers.SourceSize.y;
    bool isBelowInVerticalBounds = below >= 0 && below < registers.SourceSize.y;
    bool isInHorizontalBounds = inputPixelPosition.x >= 0 && inputPixelPosition.x < registers.SourceSize.x;
    bool isInVerticalBounds = inputPixelPosition.y >= 0 && inputPixelPosition.y < registers.SourceSize.y;

    bool hasAboveLeftNeighbor = isLeftInHorizontalBounds && isAboveInVerticalBounds;
    aboveLeftFuzzWeight = hasAboveLeftNeighbor ? aboveLeftFuzzWeight : 0.0;
    bool hasAboveRightNeighbor = isRightInHorizontalBounds && isAboveInVerticalBounds;
    aboveRightFuzzWeight = hasAboveRightNeighbor ? aboveRightFuzzWeight : 0.0;
    bool hasAboveNeighbor = isInHorizontalBounds && isAboveInVerticalBounds;
    aboveFuzzWeight = hasAboveNeighbor ? aboveFuzzWeight : 0.0;
    bool hasBelowLeftNeighbor = isLeftInHorizontalBounds && isBelowInVerticalBounds;
    belowLeftFuzzWeight = hasBelowLeftNeighbor ? belowLeftFuzzWeight : 0.0;
    bool hasBelowRightNeighbor = isRightInHorizontalBounds && isBelowInVerticalBounds;
    belowRightFuzzWeight = hasBelowRightNeighbor ? belowRightFuzzWeight : 0.0;
    bool hasBelowNeighbor = isInHorizontalBounds && isBelowInVerticalBounds;
    belowFuzzWeight = hasBelowNeighbor ? belowFuzzWeight : 0.0;
    bool hasLeftNeighbor = isLeftInHorizontalBounds && isInVerticalBounds;
    leftFuzzWeight = hasLeftNeighbor ? leftFuzzWeight : 0.0;
    bool hasRightNeighbor = isRightInHorizontalBounds && isInVerticalBounds;
    rightFuzzWeight = hasRightNeighbor ? rightFuzzWeight : 0.0;
    selfFuzzWeight = isInHorizontalBounds && isInVerticalBounds ? selfFuzzWeight : 0.0;

    vec3 colorAbove = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(0.0, -1.0))).rgb;
    vec3 colorAboveRightDiagonal = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(1.0, -1.0))).rgb;
    vec3 colorLeft = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(-1.0, 0.0))).rgb;
    vec3 colorAboveLeftDiagonal = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(-1.0, -1.0))).rgb;
    vec3 colorBelowLeftDiagonal = texture(Source, registers.SourceSize.zw * (inputPixelPosition + vec2(-1.0, 1.0))).rgb;

    float cumulativeFuzzWeight = 1.0 + selfFuzzWeight;
    color = mix(color, primaryPixelColor, selfFuzzWeight / cumulativeFuzzWeight);

    cumulativeFuzzWeight += aboveFuzzWeight;
    color = mix(color, colorAbove, aboveFuzzWeight / cumulativeFuzzWeight);

    cumulativeFuzzWeight += belowFuzzWeight;
    color = mix(color, colorBelow, belowFuzzWeight / cumulativeFuzzWeight);

    cumulativeFuzzWeight += leftFuzzWeight;
    color = mix(color, colorLeft, leftFuzzWeight / cumulativeFuzzWeight);

    cumulativeFuzzWeight += rightFuzzWeight;
    color = mix(color, colorRight, rightFuzzWeight / cumulativeFuzzWeight);

    cumulativeFuzzWeight += aboveRightFuzzWeight;
    color = mix(color, colorAboveRightDiagonal, aboveRightFuzzWeight / cumulativeFuzzWeight);

    cumulativeFuzzWeight += belowRightFuzzWeight;
    color = mix(color, colorBelowRightDiagonal, belowRightFuzzWeight / cumulativeFuzzWeight);

    cumulativeFuzzWeight += aboveLeftFuzzWeight;
    color = mix(color, colorAboveLeftDiagonal, aboveLeftFuzzWeight / cumulativeFuzzWeight);

    cumulativeFuzzWeight += belowLeftFuzzWeight;
    color = mix(color, colorBelowLeftDiagonal, belowLeftFuzzWeight / cumulativeFuzzWeight);

    FragColor = vec4(color, 1.0);
}
