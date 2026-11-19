#version 440
// Fondo del modo juego: cielo con nebulosa, horizonte encendido y un piso
// de rejilla que avanza hacia la cámara. La onda de choque y el destello
// los maneja la animación de entrada.
//
// Después de editar hay que recompilar:
//   /usr/lib/qt6/bin/qsb --qt6 -o fondo.frag.qsb fondo.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float tiempo;    // segundos
    float energia;   // 0..1, sube en el impacto: acelera la rejilla y enciende el núcleo
    float onda;      // radio de la onda de choque (0 = sin onda)
    float aspecto;   // ancho / alto
    float atenuar;   // 0 = entrada, 1 = lanzador (más oscuro para poder leer)
};

float azar(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float ruido(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(azar(i), azar(i + vec2(1.0, 0.0)), f.x),
               mix(azar(i + vec2(0.0, 1.0)), azar(i + vec2(1.0, 1.0)), f.x), f.y);
}

float nubes(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * ruido(p);
        p = p * 2.03 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = qt_TexCoord0 - 0.5;   // y crece hacia abajo
    uv.x *= aspecto;

    const float horizonte = 0.07;
    const vec3 cian = vec3(0.10, 0.85, 1.00);
    const vec3 magenta = vec3(1.00, 0.16, 0.62);
    const vec3 violeta = vec3(0.36, 0.14, 0.95);

    vec3 col = vec3(0.012, 0.010, 0.035);
    vec3 luzHorizonte = mix(magenta, cian, 0.5 + 0.5 * sin(tiempo * 0.3));

    if (uv.y < horizonte) {
        // Cielo: dos capas de nubes que derivan en sentidos opuestos.
        float n = nubes(vec2(uv.x * 1.6 + tiempo * 0.02, uv.y * 2.6 - tiempo * 0.015));
        float n2 = nubes(vec2(uv.x * 3.1 - tiempo * 0.03, uv.y * 4.0) + n);
        col += violeta * pow(n, 3.0) * 0.60 + magenta * pow(n2, 4.0) * 0.40;

        // Estrellas que titilan.
        vec2 celda = floor(qt_TexCoord0 * vec2(260.0 * aspecto, 260.0));
        float e = azar(celda);
        col += vec3(step(0.9965, e)) * (0.5 + 0.5 * sin(tiempo * 2.0 + e * 40.0)) * 0.8;

        // Resplandor del horizonte y núcleo de energía en el centro.
        float d = horizonte - uv.y;
        col += luzHorizonte * exp(-d * 9.0) * 0.55;
        float r = length(vec2(uv.x, (uv.y - horizonte) * 1.6));
        col += cian * 0.10 / (r * r * 18.0 + 0.05) * (0.6 + energia);
    } else {
        // Piso: rejilla en perspectiva. Cerca del horizonte la profundidad
        // se dispara, así que ahí se apaga para que no parpadee.
        float y = uv.y - horizonte;
        float prof = 0.16 / y;
        vec2 gp = vec2(uv.x * prof * 3.2, prof * 2.4 + tiempo * (0.9 + energia * 3.0));
        vec2 borde = abs(fract(gp) - 0.5);
        float ancho = 0.018 + 0.016 * prof;
        float linea = smoothstep(0.5 - ancho, 0.5, max(borde.x, borde.y));
        float lejos = exp(-prof * 0.30) * smoothstep(0.0, 0.03, y);
        col += mix(cian, magenta, clamp(prof * 0.14, 0.0, 1.0)) * linea * lejos * 0.95;
        col += luzHorizonte * exp(-y * 16.0) * 0.50;
        col += cian * exp(-y * 5.0) * exp(-abs(uv.x) * 2.5) * 0.10 * (0.6 + energia);
    }

    // Onda de choque: un anillo que se abre desde el centro y se apaga.
    if (onda > 0.0) {
        float rr = length(uv);
        float anillo = exp(-pow((rr - onda) * 16.0, 2.0));
        float estela = exp(-pow((rr - onda * 0.86) * 7.0, 2.0)) * 0.25;
        col += (cian * 0.9 + vec3(0.35)) * (anillo + estela) * (1.0 - smoothstep(0.8, 1.8, onda));
    }

    col += vec3(0.5, 0.8, 1.0) * energia * 0.10;                 // destello general
    col *= 1.0 - 0.55 * dot(uv, uv);                              // viñeta
    col *= 0.95 + 0.05 * sin(qt_TexCoord0.y * 900.0);             // líneas de barrido
    col *= mix(1.0, 0.42, atenuar);

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
