#version 440
// Arte grande del juego elegido, detrás del lanzador. Funde entre dos
// imágenes (la que se va y la que llega), las recorta para que llenen el
// espacio sin deformarse y las disuelve hacia abajo y hacia la izquierda,
// para que se vea la rejilla del piso y se pueda leer el texto.
//
// Después de editar hay que recompilar:
//   /usr/lib/qt6/bin/qsb --qt6 -o heroe.frag.qsb heroe.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float mezcla;    // 0 = imagen A, 1 = imagen B
    float hayA;      // 1 si A tiene imagen
    float hayB;
    float aspA;      // ancho / alto de la imagen A
    float aspB;
    float aspecto;   // ancho / alto del espacio a llenar
    float acerca;    // acercamiento lento, 0..1
};
layout(binding = 1) uniform sampler2D a;
layout(binding = 2) uniform sampler2D b;

// Coordenadas dentro de la imagen para que cubra todo el espacio,
// recortando lo que sobre y pegada arriba.
vec2 cubrir(vec2 uv, float aspImagen) {
    vec2 escala = aspImagen > aspecto ? vec2(aspecto / aspImagen, 1.0) : vec2(1.0, aspImagen / aspecto);
    escala /= 1.0 + 0.06 * acerca;
    return vec2((uv.x - 0.5) * escala.x + 0.5, uv.y * escala.y);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec4 ca = texture(a, cubrir(uv, aspA)) * hayA;
    vec4 cb = texture(b, cubrir(uv, aspB)) * hayB;
    vec4 col = mix(ca, cb, mezcla);

    float abajo = 1.0 - smoothstep(0.38, 1.0, uv.y);                 // se disuelve hacia el piso
    float izquierda = mix(0.30, 1.0, smoothstep(0.0, 0.62, uv.x));   // más oscuro donde va el texto
    float arriba = mix(0.55, 1.0, smoothstep(0.0, 0.22, uv.y));      // y bajo la cabecera

    col.rgb *= izquierda * arriba * 0.92;
    fragColor = col * abajo * qt_Opacity;
}
