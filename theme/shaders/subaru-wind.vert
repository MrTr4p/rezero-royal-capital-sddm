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
    float sceneMode;
};
float mask(vec2 uv, vec2 center, vec2 extent) { return 1.0-smoothstep(0.3,1.0,length((uv-center)/extent)); }
void main() {
    vec2 uv=(qt_MultiTexCoord0-.5)*vec2(cropU,cropV)+.5;
    float coat=mask(uv,vec2(sceneMode<1.5?.63:.72,.76),vec2(.15,.27));
    float hair=sceneMode<1.5?mask(uv,vec2(.89,.63),vec2(.10,.25)):0.;
    float pinned=smoothstep(.45,.57,uv.y)*(1.0-smoothstep(.94,1.,uv.y));
    float breeze=sin(windSeconds*1.2-uv.y*6.)*.7+sin(windSeconds*2.1-uv.y*12.)*.3;
    vec4 position=qt_Vertex;
    position.x+=breeze*(coat*.45+hair)*pinned*windStrength*itemWidth*.0045;
    position.y+=sin(windSeconds*1.25)*(coat*.7+hair*.2)*pinned*windStrength*itemHeight*.0018;
    gl_Position=qt_Matrix*position; qt_TexCoord0=uv;
}
