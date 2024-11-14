#version 450

layout(std140, set = 0, binding = 0) uniform UBO {
    mat4 MVP;
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main() {
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 1) uniform sampler2D Original;   // Previous pass result
layout(set = 0, binding = 2) uniform sampler2D Source;       // Original scene texture
layout(set = 0, binding = 3) uniform sampler2D DistanceField;   // Distance field texture

// Constants (hardcoded parameters)
const float SQRT_2 = 1.41421356237;
const float PI = 3.14159265359;
const float TAU = 2.0 * PI;
const float GOLDEN_ANGLE = PI * 0.7639320225;
const float SUN_DISTANCE = 1.0;

const vec3 SKY_COLOR = vec3(0.2, 0.24, 0.35) * 4.0;
const vec3 SUN_COLOR = vec3(0.95, 0.9, 0.8) * 3.0;

// Hardcoded cascade parameters
const float CASCADE_COUNT = 6.0;
const float CASCADE_INDEX = 1.0;
const float BASE_PIXELS_BETWEEN_PROBES = 1.0;
const float CASCADE_INTERVAL = 1.0;
const float RAY_INTERVAL = 1.0;
const float INTERVAL_OVERLAP = 0.0;
const float BASE_RAY_COUNT = 4.0;
const bool ENABLE_SUN = false;
const float SUN_ANGLE = 4.2;
const float SRGB = 1.0;
const bool BILINEAR_FIX_ENABLED = true;  // Added this constant

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 sunAndSky(float rayAngle) {
    float angleToSun = mod(rayAngle - SUN_ANGLE, TAU);
    float sunIntensity = pow(max(0.0, cos(angleToSun)), 4.0 / SUN_DISTANCE);
    return mix(SUN_COLOR * sunIntensity, SKY_COLOR, 0.3);
}

vec4 raymarch(vec2 rayStart, vec2 rayEnd, float scale, vec2 oneOverSize, float minStepSize) {
    vec2 rayDir = normalize(rayEnd - rayStart);
    float rayLength = length(rayEnd - rayStart);
    vec2 rayUv = rayStart * oneOverSize;

    for (float dist = 0.0; dist < rayLength;) {
        if (any(lessThan(rayUv, vec2(0.0))) || any(greaterThan(rayUv, vec2(1.0))))
            return vec4(0.0);

        float df = texture(DistanceField, rayUv).r;

        if (df <= minStepSize) {
            vec4 color = texture(Original, rayUv);
            if (color.a < 0.99) {
                color.rgb = vec3(0);
            } else {
                color.rgb = pow(color.rgb, vec3(SRGB));
            }
            return color;
        }

        dist += df * scale;
        rayUv += rayDir * (df * scale * oneOverSize);
    }

    return vec4(0.0);
}

vec2 getUpperCascadeTextureUv(float index, vec2 offset, float spacingBase) {
    float upperSpacing = pow(spacingBase, CASCADE_INDEX + 1.0);
    vec2 upperSize = floor(global.OriginalSize.xy / upperSpacing);
    vec2 upperPosition = vec2(
        mod(index, upperSpacing),
        floor(index / upperSpacing)
    ) * upperSize;

    vec2 clamped = clamp(offset, vec2(0.5), upperSize - 0.5);
    return (upperPosition + clamped) / global.OriginalSize.xy;
}

vec4 merge(vec4 currentRadiance, float index, vec2 position, float spacingBase, vec2 localOffset) {
    if (currentRadiance.a > 0.0 || CASCADE_INDEX >= max(1.0, CASCADE_COUNT - 1.0)) {
        return currentRadiance;
    }

    vec2 offset = (position + localOffset) / spacingBase;
    vec2 upperProbePosition = getUpperCascadeTextureUv(index, offset, spacingBase);
    
    vec3 upperSample = textureLod(
        Source,
        upperProbePosition,
        BASE_PIXELS_BETWEEN_PROBES == 1.0 ? 0.0 : log2(BASE_PIXELS_BETWEEN_PROBES)
    ).rgb;

    return currentRadiance + vec4(upperSample, 1.0);
}

void main() {
    vec2 coord = floor(vTexCoord * global.OriginalSize.xy);
    float rayCount = pow(BASE_RAY_COUNT, CASCADE_INDEX + 1.0);
    float spacingBase = sqrt(BASE_RAY_COUNT);
    float spacing = pow(spacingBase, CASCADE_INDEX);
    
    float modifierHack = BASE_RAY_COUNT < 16.0 ? 
        pow(BASE_PIXELS_BETWEEN_PROBES, 1.0) : spacingBase;

    vec2 size = floor(global.OriginalSize.xy / spacing);
    vec2 probeRelativePosition = mod(coord, size);
    vec2 rayPos = floor(coord / size);

    float modifiedInterval = modifierHack * RAY_INTERVAL * CASCADE_INTERVAL;

    float start = (CASCADE_INDEX == 0.0 ? 0.0 : pow(BASE_RAY_COUNT, (CASCADE_INDEX - 1.0))) * modifiedInterval;
    float end = ((1.0 + 3.0 * INTERVAL_OVERLAP) * (pow(BASE_RAY_COUNT, CASCADE_INDEX)) - pow(CASCADE_INDEX, 2.0)) * modifiedInterval;

    vec2 interval = vec2(start, end);
    vec2 probeCenter = (probeRelativePosition + 0.5) * BASE_PIXELS_BETWEEN_PROBES * spacing;

    float scale = min(global.OriginalSize.x, global.OriginalSize.y);
    vec2 oneOverSize = 1.0 / global.OriginalSize.xy;
    float minStepSize = min(oneOverSize.x, oneOverSize.y) * 0.5;
    float avgRecip = 1.0 / BASE_RAY_COUNT;

    float baseIndex = (rayPos.x + (spacing * rayPos.y)) * BASE_RAY_COUNT;
    float angleStep = TAU / rayCount;

    vec4 totalRadiance = vec4(0.0);
    float noise = rand(vTexCoord * (CASCADE_INDEX + 1.0));
    
    vec2 factor = fract(probeCenter / spacing);  // Added for bilinear interpolation

    for (int i = 0; i < int(BASE_RAY_COUNT); i++) {
        float index = baseIndex + float(i);
        float angle = (index + 0.5 + noise) * angleStep;
        vec2 rayDir = vec2(cos(angle), -sin(angle));
        
        vec4 mergedRadiance;
        
        if (BILINEAR_FIX_ENABLED) {
            vec4 radiances[4];
            
            for (int j = 0; j < 4; j++) {
                vec2 jOffset = vec2(j % 2, j / 2);
                
                vec2 modifiedProbeCenter = (floor(probeCenter / spacing) + jOffset * spacingBase - 0.5) * spacing;
                vec2 modifiedRayEnd = modifiedProbeCenter + rayDir * interval.y;
                
                radiances[j] = raymarch(
                    probeCenter + rayDir * interval.x,
                    modifiedRayEnd,
                    scale, oneOverSize, minStepSize
                );
                
                radiances[j] = merge(
                    radiances[j],
                    index,
                    probeRelativePosition,
                    spacingBase,
                    vec2(jOffset * spacingBase - 0.5)
                );
            }
            
            mergedRadiance = mix(
                mix(radiances[0], radiances[1], factor.x),
                mix(radiances[2], radiances[3], factor.x),
                factor.y
            );
        } else {
            vec2 rayStart = probeCenter + rayDir * interval.x;
            vec2 rayEnd = rayStart + rayDir * interval.y;
            vec4 raymarched = raymarch(rayStart, rayEnd, scale, oneOverSize, minStepSize);
            mergedRadiance = merge(raymarched, index, probeRelativePosition, spacingBase, vec2(0.5));
        }

        if (ENABLE_SUN && CASCADE_INDEX == CASCADE_COUNT - 1.0) {
            mergedRadiance.rgb = max(sunAndSky(angle), mergedRadiance.rgb);
        }

        totalRadiance += mergedRadiance * avgRecip;
    }

    FragColor = vec4(pow(totalRadiance.rgb, vec3(1.0 / SRGB)), 1.0);
}
