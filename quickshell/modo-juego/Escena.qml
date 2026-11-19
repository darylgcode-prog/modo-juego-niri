import QtQuick
import QtQuick.Effects
import QtQuick.Particles

// Lo que se ve en una pantalla: el fondo animado, la entrada épica, la
// secuencia de salida y, en la pantalla principal, el lanzador. Las demás
// pantallas muestran solo la entrada o la salida y después se apartan.
Item {
    id: esc

    required property bool principal
    required property var centro      // el ShellRoot: catálogo, memoria, modo
    property bool acabada: false      // esta pantalla ya no tiene nada que mostrar

    property string fase: "espera"    // espera → intro → lanzador → saliendo, o espera → salida
    property real tiempo: 0
    property real energia: 0
    property real onda: 0
    property real sacude: 0
    property real aberracion: 0
    readonly property real u: Math.min(width / 1920, height / 1200)
    readonly property color cian: "#19d9ff"
    readonly property color magenta: "#ff2a9e"

    function empezar() {
        if (fase !== "espera")
            return
        if (centro.modo === "intro") {
            fase = "intro"
            animIntro.start()
        } else if (centro.modo === "salida") {
            fase = "salida"
            animSalidaModo.start()
        } else if (principal) {
            fondo.atenuar = 1
            fase = "lanzador"
            animAparecer.start()
        } else {
            acabada = true
        }
    }

    function finIntro() {
        if (principal) {
            fase = "lanzador"
            animALanzador.start()
        } else {
            animRetirada.start()
        }
    }

    // Cierra todo con un fundido; al terminar avisa para salir.
    function salir(conDestello) {
        if (fase === "saliendo")
            return
        fase = "saliendo"
        if (conDestello) {
            destello.opacity = 0.55
            animOndaCorta.start()
        }
        animSalida.start()
    }

    function accionMando(cual) {
        if (fase === "lanzador" && cargaLanzador.item)
            cargaLanzador.item.accion(cual)
    }

    function gb(mb) { return (mb / 1024).toFixed(1).replace(".", ",") + " GB" }
    function duracion(minutos) {
        const h = Math.floor(minutos / 60), m = minutos % 60
        return h > 0 ? h + " h " + m + " min" : m + " min"
    }

    FrameAnimation { running: true; onTriggered: esc.tiempo += frameTime }

    // Todo lo que se apaga junto al final de la secuencia de salida.
    Item {
        id: pantalla
        anchors.fill: parent
        transform: Scale {
            id: apagado
            origin.x: pantalla.width / 2
            origin.y: pantalla.height / 2
        }

        // ── El mundo: fondo, partículas y título ──────────────────────
        Item {
            id: mundo
            anchors.fill: parent
            opacity: 0
            transform: Translate {
                x: esc.sacude * 18 * Math.sin(esc.tiempo * 97)
                y: esc.sacude * 13 * Math.cos(esc.tiempo * 83)
            }

            ShaderEffect {
                id: fondo
                anchors.fill: parent
                anchors.margins: -24          // para que la sacudida no muestre bordes
                fragmentShader: Qt.resolvedUrl("shaders/fondo.frag.qsb")
                property real tiempo: esc.tiempo
                property real energia: esc.energia
                property real onda: esc.onda
                property real aspecto: width / Math.max(1, height)
                property real atenuar: 0
                Behavior on atenuar { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
            }

            ParticleSystem { id: particulas }
            ImageParticle {
                system: particulas; groups: ["cian"]
                source: "qrc:///particleresources/glowdot.png"
                color: esc.cian; colorVariation: 0.15; alpha: 0.9
                entryEffect: ImageParticle.Fade
            }
            ImageParticle {
                system: particulas; groups: ["magenta"]
                source: "qrc:///particleresources/glowdot.png"
                color: esc.magenta; colorVariation: 0.15; alpha: 0.9
                entryEffect: ImageParticle.Fade
            }
            // Estallido del impacto.
            Emitter {
                id: chispasC
                system: particulas; group: "cian"; enabled: false
                x: mundo.width / 2; y: mundo.height / 2
                lifeSpan: 1500; lifeSpanVariation: 700
                size: 16 * esc.u; sizeVariation: 12 * esc.u; endSize: 2
                velocity: AngleDirection { angleVariation: 180; magnitude: 760 * esc.u; magnitudeVariation: 560 * esc.u }
                acceleration: PointDirection { y: 140 * esc.u }
            }
            Emitter {
                id: chispasM
                system: particulas; group: "magenta"; enabled: false
                x: mundo.width / 2; y: mundo.height / 2
                lifeSpan: 1700; lifeSpanVariation: 700
                size: 12 * esc.u; sizeVariation: 10 * esc.u; endSize: 2
                velocity: AngleDirection { angleVariation: 180; magnitude: 520 * esc.u; magnitudeVariation: 420 * esc.u }
                acceleration: PointDirection { y: 140 * esc.u }
            }
            // Brasas que suben desde el piso, siempre.
            Emitter {
                system: particulas; group: "cian"
                enabled: esc.fase !== "espera"
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 8
                emitRate: 22; lifeSpan: 5200; lifeSpanVariation: 1800
                size: 7 * esc.u; sizeVariation: 5 * esc.u; endSize: 1
                velocity: PointDirection { y: -85 * esc.u; yVariation: 45 * esc.u; xVariation: 36 * esc.u }
            }

            // Rayo horizontal que se carga antes del impacto.
            Rectangle {
                id: rayo
                property real largo: 0
                anchors.centerIn: parent
                width: parent.width * largo
                height: Math.max(2, 4 * esc.u)
                opacity: 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#0019d9ff" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "#00ff2a9e" }
                }
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: esc.cian; shadowBlur: 1.0; blurMax: 40; shadowVerticalOffset: 0 }
            }

            // Título.
            Item {
                id: titulo
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -70 * esc.u
                width: letras.implicitWidth
                height: letras.implicitHeight
                opacity: 0

                component Letras: Text {
                    text: esc.centro.modo === "salida" ? "FIN DEL JUEGO" : "MODO JUEGO"
                    font { family: "Inter Display"; weight: Font.Black; italic: true; pixelSize: 176 * esc.u; letterSpacing: 4 * esc.u }
                }

                // Las dos copias de color parten separadas y se juntan: el
                // efecto de «imagen que se enfoca» después del golpe.
                Letras { x: -esc.aberracion * esc.u; color: esc.magenta; opacity: 0.85 }
                Letras { x: esc.aberracion * esc.u; color: esc.cian; opacity: 0.85 }
                Letras {
                    id: letras
                    color: "#ffffff"
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: esc.cian; shadowBlur: 1.0; blurMax: 56; shadowVerticalOffset: 0; shadowOpacity: 0.9 }
                }

                Rectangle {
                    id: reglaArriba
                    property real largo: 0
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 6 * esc.u }
                    width: parent.width * largo; height: Math.max(1, 2 * esc.u); color: esc.cian
                }
                Rectangle {
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 6 * esc.u }
                    width: parent.width * reglaArriba.largo; height: Math.max(1, 2 * esc.u); color: esc.magenta
                }

                Text {
                    id: lema
                    property real espaciado: 34
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 34 * esc.u }
                    text: esc.centro.modo === "salida" ? "TODO VUELVE A SU LUGAR" : "LO QUE SOBRA, FUERA   ·   A JUGAR"
                    color: "#e8f6ff"
                    opacity: 0
                    font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 24 * esc.u; letterSpacing: espaciado * esc.u }
                }

                component Dato: Column {
                    property string rotulo: ""
                    property string valor: ""
                    property color tinte: esc.cian
                    spacing: 6 * esc.u
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.valor
                        color: "#ffffff"
                        font { family: "Inter Display"; weight: Font.Black; italic: true; pixelSize: 52 * esc.u }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.rotulo
                        color: parent.tinte
                        font { family: "Inter Display"; weight: Font.Bold; pixelSize: 14 * esc.u; letterSpacing: 4 * esc.u }
                    }
                }

                // Entrada: lo que está pasando de verdad, en vivo.
                Row {
                    id: datos
                    visible: esc.centro.modo !== "salida"
                    anchors { horizontalCenter: parent.horizontalCenter; top: lema.bottom; topMargin: 54 * esc.u }
                    spacing: 90 * esc.u
                    opacity: 0

                    // El número sube suave en vez de saltar.
                    property real memoria: esc.centro.memLibre
                    property real cerrados: esc.centro.cerrados
                    Behavior on memoria { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                    Behavior on cerrados { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                    Dato { rotulo: "MEMORIA LIBRE"; valor: esc.gb(datos.memoria) }
                    Dato { rotulo: "CERRADOS"; valor: Math.round(datos.cerrados); tinte: esc.magenta }
                    Dato { visible: esc.centro.gpu !== ""; rotulo: "LISTA"; valor: esc.centro.gpu }
                }

                // Salida: el resumen de la sesión.
                Column {
                    id: resumen
                    visible: esc.centro.modo === "salida"
                    anchors { horizontalCenter: parent.horizontalCenter; top: lema.bottom; topMargin: 50 * esc.u }
                    spacing: 16 * esc.u
                    opacity: 0

                    readonly property var r: esc.centro.resumen
                    component Linea: Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "#dfe8ff"
                        font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 26 * esc.u }
                    }
                    Linea {
                        text: "Sesión de " + esc.duracion(resumen.r.minutos || 0)
                        color: "#ffffff"
                        font.pixelSize: 34 * esc.u
                        font.weight: Font.Bold
                    }
                    Repeater {
                        model: (resumen.r.partidas || []).slice(0, 3)
                        Linea {
                            required property var modelData
                            text: modelData.nombre + "   ·   " + (modelData.minutos > 0 ? esc.duracion(modelData.minutos) : "menos de un minuto")
                            color: esc.cian
                        }
                    }
                    Linea {
                        visible: (resumen.r.vuelven || []).length > 0
                        text: "Vuelven:  " + (resumen.r.vuelven || []).join("  ·  ")
                        color: "#a9b2d0"
                        font.pixelSize: 21 * esc.u
                    }
                }
            }
        }

        // ── Lanzador (solo en la pantalla principal) ──────────────────
        Loader {
            id: cargaLanzador
            anchors.fill: parent
            active: esc.principal && esc.centro.modo !== "salida"
            sourceComponent: Lanzador {
                u: esc.u
                tiempo: esc.tiempo
                catalogo: esc.centro.catalogo
                memLibre: esc.centro.memLibre
                liberados: esc.centro.liberados
                aviso: esc.centro.aviso
                onLanzar: (item, fila) => esc.centro.lanzar(item, fila)
                onCerrar: esc.centro.cerrar(false)
                onSalirModo: esc.centro.salirModo()
                onSonar: cual => esc.centro.sonar(cual)
                ajustes: esc.centro.ajustes
                mensajeClave: esc.centro.mensajeClave
                claveBien: esc.centro.claveBien
                guardando: esc.centro.guardando
                buscando: esc.centro.buscando
                registroCaratulas: esc.centro.registroCaratulas
                onPonerAjuste: (nombre, valor) => esc.centro.ponerAjuste(nombre, valor)
                onGuardarClave: texto => esc.centro.guardarClave(texto)
                onQuitarClave: esc.centro.quitarClave()
                onBuscarCaratulas: esc.centro.buscarCaratulas()
                onAbrirPaginaClave: esc.centro.abrirPaginaClave()
                mensajeClaveIa: esc.centro.mensajeClaveIa
                claveIaBien: esc.centro.claveIaBien
                guardandoIa: esc.centro.guardandoIa
                onGuardarClaveIa: texto => esc.centro.guardarClaveIa(texto)
                onQuitarClaveIa: esc.centro.quitarClaveIa()
                onPonerModelo: nombre => esc.centro.ponerModelo(nombre)
                onActivoChanged: if (activo && esc.centro.abrirEnAjustes) abrirAjustes()
            }
        }
    }

    // Destello blanco del impacto, y la línea en que se apaga la salida.
    Rectangle {
        id: destello
        anchors.fill: parent
        color: "#eaf8ff"
        opacity: 0
    }
    Rectangle {
        id: lineaFinal
        anchors.centerIn: parent
        width: parent.width
        height: Math.max(2, 3 * esc.u)
        color: "#ffffff"
        opacity: 0
    }

    // En la salida, un clic la corta.
    MouseArea {
        anchors.fill: parent
        enabled: esc.fase === "salida"
        onClicked: { esc.acabada = true; esc.centro.terminar() }
    }

    // ── Animaciones ───────────────────────────────────────────────────
    SequentialAnimation {
        id: animIntro
        // Se carga: aparece el mundo y el rayo cruza la pantalla.
        ParallelAnimation {
            NumberAnimation { target: mundo; property: "opacity"; from: 0; to: 1; duration: 460; easing.type: Easing.OutQuad }
            NumberAnimation { target: rayo; property: "opacity"; from: 0; to: 1; duration: 200 }
            NumberAnimation { target: rayo; property: "largo"; from: 0; to: 1; duration: 620; easing.type: Easing.InExpo }
            NumberAnimation { target: esc; property: "energia"; from: 0; to: 0.5; duration: 620; easing.type: Easing.InQuad }
        }
        // Impacto.
        ScriptAction {
            script: {
                chispasC.burst(280)
                chispasM.burst(220)
                if (esc.principal)
                    esc.centro.impacto()
            }
        }
        ParallelAnimation {
            NumberAnimation { target: destello; property: "opacity"; from: 0.92; to: 0; duration: 560; easing.type: Easing.OutQuad }
            NumberAnimation { target: esc; property: "onda"; from: 0.001; to: 1.9; duration: 1300; easing.type: Easing.OutCubic }
            NumberAnimation { target: esc; property: "energia"; from: 1; to: 0.12; duration: 1500; easing.type: Easing.OutQuad }
            NumberAnimation { target: esc; property: "sacude"; from: 1; to: 0; duration: 650; easing.type: Easing.OutQuad }
            NumberAnimation { target: titulo; property: "scale"; from: 3.2; to: 1; duration: 420; easing.type: Easing.OutExpo }
            NumberAnimation { target: titulo; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: esc; property: "aberracion"; from: 46; to: 0; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: rayo; property: "opacity"; to: 0; duration: 350 }
            NumberAnimation { target: reglaArriba; property: "largo"; from: 0; to: 1; duration: 750; easing.type: Easing.OutExpo }
            SequentialAnimation {
                PauseAnimation { duration: 260 }
                ParallelAnimation {
                    NumberAnimation { target: lema; property: "opacity"; from: 0; to: 1; duration: 500 }
                    NumberAnimation { target: lema; property: "espaciado"; from: 34; to: 9; duration: 760; easing.type: Easing.OutCubic }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 620 }
                NumberAnimation { target: datos; property: "opacity"; from: 0; to: 1; duration: 420 }
            }
        }
        // Se queda un momento para que se lean los números.
        PauseAnimation { duration: 1350 }
        ScriptAction { script: esc.finIntro() }
    }

    // El título se va y entra el lanzador.
    ParallelAnimation {
        id: animALanzador
        NumberAnimation { target: titulo; property: "opacity"; to: 0; duration: 320; easing.type: Easing.InQuad }
        NumberAnimation { target: titulo; property: "scale"; to: 0.82; duration: 320; easing.type: Easing.InQuad }
        ScriptAction { script: { fondo.atenuar = 1; cargaLanzador.item.activo = true } }
    }

    // Lanzador abierto sin entrada (Mod+Alt+J).
    ParallelAnimation {
        id: animAparecer
        NumberAnimation { target: mundo; property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutQuad }
        ScriptAction { script: cargaLanzador.item.activo = true }
    }

    // Pantalla secundaria: se aparta.
    SequentialAnimation {
        id: animRetirada
        NumberAnimation { target: esc; property: "opacity"; to: 0; duration: 520; easing.type: Easing.InQuad }
        ScriptAction { script: esc.acabada = true }
    }

    NumberAnimation { id: animOndaCorta; target: esc; property: "onda"; from: 0.001; to: 1.6; duration: 420; easing.type: Easing.OutCubic }

    SequentialAnimation {
        id: animSalida
        ParallelAnimation {
            NumberAnimation { target: esc; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
            NumberAnimation { target: destello; property: "opacity"; to: 0; duration: 300 }
        }
        ScriptAction { script: { esc.acabada = true; esc.centro.terminar() } }
    }

    // Salir del modo juego: aparece el resumen, la onda se recoge hacia
    // el centro y la imagen se apaga como una tele vieja.
    SequentialAnimation {
        id: animSalidaModo
        ParallelAnimation {
            NumberAnimation { target: mundo; property: "opacity"; from: 0; to: 1; duration: 380; easing.type: Easing.OutQuad }
            NumberAnimation { target: titulo; property: "opacity"; from: 0; to: 1; duration: 380 }
            NumberAnimation { target: titulo; property: "scale"; from: 1.25; to: 1; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: esc; property: "aberracion"; from: 26; to: 0; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: reglaArriba; property: "largo"; from: 0; to: 1; duration: 700; easing.type: Easing.OutExpo }
            NumberAnimation { target: esc; property: "energia"; from: 0.5; to: 0.1; duration: 900 }
            SequentialAnimation {
                PauseAnimation { duration: 220 }
                ParallelAnimation {
                    NumberAnimation { target: lema; property: "opacity"; from: 0; to: 1; duration: 450 }
                    NumberAnimation { target: lema; property: "espaciado"; from: 30; to: 9; duration: 700; easing.type: Easing.OutCubic }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 520 }
                NumberAnimation { target: resumen; property: "opacity"; from: 0; to: 1; duration: 500 }
            }
        }
        PauseAnimation { duration: 1700 }
        ParallelAnimation {
            NumberAnimation { target: esc; property: "onda"; from: 1.7; to: 0.001; duration: 620; easing.type: Easing.InCubic }
            NumberAnimation { target: esc; property: "energia"; to: 0.9; duration: 620; easing.type: Easing.InQuad }
        }
        // Apagado: se aplasta a una línea, la línea se cierra a un punto.
        ParallelAnimation {
            NumberAnimation { target: apagado; property: "yScale"; from: 1; to: 0.004; duration: 190; easing.type: Easing.InQuad }
            NumberAnimation { target: lineaFinal; property: "opacity"; from: 0; to: 1; duration: 190 }
        }
        ScriptAction { script: pantalla.visible = false }
        NumberAnimation { target: lineaFinal; property: "width"; to: 0; duration: 240; easing.type: Easing.InCubic }
        NumberAnimation { target: lineaFinal; property: "opacity"; to: 0; duration: 120 }
        ScriptAction { script: { esc.acabada = true; esc.centro.terminar() } }
    }
}
