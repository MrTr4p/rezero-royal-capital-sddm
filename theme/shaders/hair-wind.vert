#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float windSeconds;
    float windStrength;
    float itemWidth;
    float itemHeight;
    float cropV;
    float cropU;
};

float ribbon(float x, float center, float halfWidth) {
    return 1.0 - smoothstep(0.45, 1.0, abs(x - center) / halfWidth);
}

void main() {
    // Sample the original illustration with the same aspect crop as QML Image.
    vec2 uv = (qt_MultiTexCoord0 - 0.5) * vec2(cropU, cropV) + 0.5;
    float depth = smoothstep(0.24, 0.98, uv.y);

    // The broad rear locks are rooted behind the ornament, then trail left.
    float rearCenter = 0.646 - 0.158 * depth;
    float rear = ribbon(uv.x, rearCenter, 0.039 + 0.022 * depth);
    rear *= smoothstep(0.24, 0.53, uv.y);

    // Narrow masks follow the two loose front locks without displacing the face.
    float frontDepth = smoothstep(0.43, 0.99, uv.y);
    float front = ribbon(uv.x, 0.674 + 0.059 * frontDepth, 0.013);
    front *= smoothstep(0.44, 0.67, uv.y) * 0.55;
    float outer = ribbon(uv.x, 0.733 + 0.107 * frontDepth, 0.019);
    outer *= smoothstep(0.46, 0.72, uv.y) * 0.65;

    float weight = max(rear, max(front, outer));
    // Fully pin the flower, crown, face and the image edges.
    weight *= smoothstep(0.25, 0.40, uv.y);
    weight *= 1.0 - smoothstep(0.97, 1.0, uv.y);
    float breeze = sin(windSeconds * 1.12 - uv.y * 5.5);
    float ripple = sin(windSeconds * 1.85 - uv.y * 11.0 + uv.x * 7.0);
    float sway = (breeze * 0.78 + ripple * 0.22) * weight * windStrength;
    vec4 position = qt_Vertex;
    position.x += sway * itemWidth * 0.008;
    position.y += cos(windSeconds * 1.12 - uv.y * 6.0) * weight * itemHeight * 0.002;
    gl_Position = qt_Matrix * position;
    qt_TexCoord0 = uv;
}
