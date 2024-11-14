#version 450

layout(push_constant) uniform Push {
    vec4 OutputSize;
    vec4 SourceSize;
} registers;

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
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
layout(set = 0, binding = 2) uniform sampler2D Source;

void main() {
    vec2 size = registers.OutputSize.xy;
    float maxJump = log2(min(size.x, size.y));
    float jump = pow(2.0, maxJump - 4.0);
    vec2 pre = jump / size;

    vec2 closestPos = vec2(-1.0);
    float minDist = 9999.0;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 samplePos = vTexCoord + vec2(x,y) * pre;

            if (samplePos.x < 0.0 || samplePos.x > 1.0 ||
                samplePos.y < 0.0 || samplePos.y > 1.0) {
                continue; 
            }

            vec4 sampleData = texture(Source, samplePos);
            vec2 pos = sampleData.xy;

            if (pos.x > 0.0 || pos.y > 0.0) {  // Valid point
                float dist = distance(vTexCoord, pos);
                if (dist < minDist) {
                    closestPos = pos;
                    minDist = dist;
                }
            }
        }
    }

    FragColor = vec4(closestPos, 0.0, 1.0);
}
