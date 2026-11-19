import QtQuick
import Quickshell

// El lanzador: tres filas (juegos, lanzadores, emuladores) que se
// recorren con las flechas o con el mando. Solo dibuja y avisa; quien
// lanza es shell.qml.
FocusScope {
    id: lanz

    property var catalogo: ({ juegos: [], lanzadores: [], emuladores: [] })
    property int memLibre: 0     // MB
    property int liberados: -1   // MB; -1 = todavía no se sabe
    property string aviso: ""    // algo que no salió redondo al activar
    property real u: 1           // escala según la pantalla
    property bool activo: false  // al pasar a true entran las filas
    property real tiempo: 0      // segundos, para el acercamiento lento del fondo

    signal lanzar(var item, string fila)
    signal cerrar()
    signal salirModo()
    signal sonar(string cual)

    // Pantalla de ajustes (F2). Los datos vienen de shell.qml.
    property bool ajustesAbiertos: false
    property var ajustes: ({})
    property string mensajeClave: ""
    property bool claveBien: false
    property bool guardando: false
    property bool buscando: false
    property string registroCaratulas: ""
    signal ponerAjuste(string nombre, bool valor)
    signal guardarClave(string texto)
    signal quitarClave()
    signal buscarCaratulas()
    signal abrirPaginaClave()
    property string mensajeClaveIa: ""
    property bool claveIaBien: false
    property bool guardandoIa: false
    signal guardarClaveIa(string texto)
    signal quitarClaveIa()
    signal ponerModelo(string nombre)

    // Trucos del juego elegido (F3), para los emuladores que se pueden manejar.
    property bool trucosAbiertos: false
    property var trucos: ({})
    property string errorTruco: ""
    property bool trucosOcupado: false
    signal pedirTrucos(string id)
    signal ponerTruco(string clave, bool activo, string opcion)
    readonly property bool hayTrucos: actual !== null && actual.trucos === true

    function abrirTrucos() {
        if (!hayTrucos)
            return
        trucosAbiertos = true
        pedirTrucos(actual.id)
        panelTrucos.enfocar()
    }
    function cerrarTrucos() { trucosAbiertos = false; lanz.forceActiveFocus() }

    function abrirAjustes() { ajustesAbiertos = true; panelAjustes.enfocar() }
    function cerrarAjustes() { ajustesAbiertos = false; lanz.forceActiveFocus() }

    readonly property color cian: "#19d9ff"
    readonly property color magenta: "#ff2a9e"
    readonly property real margen: 84 * u

    readonly property var filas: [
        { clave: "juegos", titulo: "JUEGOS", tipo: "Juego", items: catalogo.juegos || [], vertical: true },
        { clave: "lanzadores", titulo: "LANZADORES", tipo: "Lanzador", items: catalogo.lanzadores || [], vertical: false },
        { clave: "emuladores", titulo: "EMULADORES", tipo: "Emulador", items: catalogo.emuladores || [], vertical: false }
    ].filter(f => f.items.length > 0)

    // Cuántas tarjetas se ven enteras en cada fila. El ancho de la tarjeta
    // sale de ahí, así que se cumple en cualquier pantalla.
    readonly property int porFila: 8
    readonly property real separacion: 24 * u
    readonly property real anchoTarjeta: (width - 2 * margen - (porFila - 1) * separacion) / porFila
    // Las de juegos son verticales, con la proporción de una carátula
    // (2:3 aprox.), sin pasarse del alto que deja la pantalla.
    function altoDe(f) { return f.vertical ? Math.min(anchoTarjeta * 1.39, 300 * u) : 150 * u }

    property int fila: 0
    property var columnas: [0, 0, 0]
    readonly property var actual: {
        if (filas.length === 0)
            return null
        const f = filas[Math.min(fila, filas.length - 1)]
        return f.items[Math.min(columnas[fila] || 0, f.items.length - 1)] || null
    }
    // Lo último que se jugó va primero en la fila de juegos.
    readonly property bool esElUltimo: actual !== null && filas[fila].clave === "juegos"
                                       && columnas[fila] === 0 && (actual.ultimo || 0) > 0

    function elegir(f, c) {
        if (f < 0 || f >= filas.length)
            return
        const destino = Math.max(0, Math.min(filas[f].items.length - 1, c))
        if (f === fila && destino === columnas[f])
            return
        const cols = columnas.slice()
        cols[f] = destino
        columnas = cols
        fila = f
        sonar("mover")
    }

    // Una acción, venga del teclado o del mando.
    function accion(cual) {
        if (trucosAbiertos) {
            panelTrucos.accion(cual)
            return
        }
        if (ajustesAbiertos) {
            if (cual === "atras" || cual === "menu")
                cerrarAjustes()
            return
        }
        switch (cual) {
        case "izq": elegir(fila, columnas[fila] - 1); break
        case "der": elegir(fila, columnas[fila] + 1); break
        case "arr": elegir(fila - 1, columnas[Math.max(0, fila - 1)]); break
        case "aba": elegir(fila + 1, columnas[Math.min(filas.length - 1, fila + 1)]); break
        case "ok": if (actual) lanzar(actual, filas[fila].clave); break
        case "atras": cerrar(); break
        case "menu": abrirAjustes(); break
        }
    }

    // Elegir con el ratón solo si de verdad se movió: las tarjetas entran
    // animadas y pasan bajo un puntero quieto, y eso no debe cambiar nada.
    property var ultimoRaton: null
    function ratonEn(f, c, gx, gy) {
        const antes = ultimoRaton
        ultimoRaton = Qt.point(gx, gy)
        if (antes !== null && Math.abs(antes.x - gx) + Math.abs(antes.y - gy) > 1)
            elegir(f, c)
    }

    function gb(mb) { return (mb / 1024).toFixed(1).replace(".", ",") + " GB" }

    function hace(cuando) {
        const dias = Math.floor((Date.now() / 1000 - cuando) / 86400)
        if (dias <= 0) return "hoy"
        if (dias === 1) return "ayer"
        if (dias < 30) return "hace " + dias + " días"
        if (dias < 365) return "hace " + Math.floor(dias / 30) + (dias < 60 ? " mes" : " meses")
        return "hace más de un año"
    }

    function detalleDe(item, tipo) {
        // Una ROM dice de qué consola es, en vez de «JUEGO».
        const partes = [(item.sistema || tipo).toUpperCase()]
        if ((item.horas || 0) >= 0.1)
            partes.push(String(item.horas).replace(".", ",") + " h jugadas")
        if ((item.ultimo || 0) > 0)
            partes.push("última vez " + hace(item.ultimo))
        else if (item.detalle)
            partes.push(item.detalle)
        return partes.join("   ·   ")
    }

    focus: true
    Keys.onPressed: ev => {
        // Con los trucos abiertos, todas las teclas son del panel.
        if (trucosAbiertos)
            return
        // Con los ajustes abiertos las teclas son suyas: aquí solo llega
        // lo que no usaron, y de eso solo importa Esc.
        if (ajustesAbiertos) {
            if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_F2) {
                cerrarAjustes()
                ev.accepted = true
            }
            return
        }
        switch (ev.key) {
        case Qt.Key_Left: case Qt.Key_H: accion("izq"); break
        case Qt.Key_Right: case Qt.Key_L: accion("der"); break
        case Qt.Key_Up: case Qt.Key_K: accion("arr"); break
        case Qt.Key_Down: case Qt.Key_J: accion("aba"); break
        case Qt.Key_Home: elegir(fila, 0); break
        case Qt.Key_End: elegir(fila, 9999); break
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: accion("ok"); break
        case Qt.Key_Escape: accion("atras"); break
        case Qt.Key_F10: salirModo(); break
        case Qt.Key_F2: accion("menu"); break
        case Qt.Key_F3: abrirTrucos(); break
        default: return
        }
        ev.accepted = true
    }

    SystemClock { id: reloj; precision: SystemClock.Minutes }

    // ── Fondo: el arte grande del juego elegido ───────────────────────
    // Dos imágenes que se turnan: la nueva carga escondida y, cuando está
    // lista, se funde sobre la anterior.
    Item {
        id: telon
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: parent.height * 0.74
        opacity: lanz.activo ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 700 } }

        property bool haciaB: false
        readonly property string pedido: lanz.actual && lanz.actual.fondo ? "file://" + lanz.actual.fondo : ""

        // Se espera un momento: al pasar rápido por las tarjetas no se
        // carga el fondo de cada una.
        onPedidoChanged: espera.restart()
        Component.onCompleted: espera.restart()
        Timer {
            id: espera
            interval: 240
            onTriggered: {
                const destino = telon.haciaB ? imagenA : imagenB
                if (destino.source.toString() === telon.pedido) {
                    telon.haciaB = !telon.haciaB
                } else {
                    destino.source = telon.pedido
                    if (telon.pedido === "")
                        telon.haciaB = !telon.haciaB
                }
            }
        }

        Image {
            id: imagenA
            visible: false
            asynchronous: true
            sourceSize.width: 3840
            onStatusChanged: if (status === Image.Ready && telon.haciaB) telon.haciaB = false
        }
        Image {
            id: imagenB
            visible: false
            asynchronous: true
            sourceSize.width: 3840
            onStatusChanged: if (status === Image.Ready && !telon.haciaB) telon.haciaB = true
        }

        ShaderEffect {
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("shaders/heroe.frag.qsb")
            property variant a: imagenA
            property variant b: imagenB
            property real mezcla: telon.haciaB ? 1 : 0
            property real hayA: imagenA.status === Image.Ready ? 1 : 0
            property real hayB: imagenB.status === Image.Ready ? 1 : 0
            property real aspA: imagenA.implicitHeight > 0 ? imagenA.implicitWidth / imagenA.implicitHeight : 1
            property real aspB: imagenB.implicitHeight > 0 ? imagenB.implicitWidth / imagenB.implicitHeight : 1
            property real aspecto: width / Math.max(1, height)
            property real acerca: 0.5 + 0.5 * Math.sin(lanz.tiempo * 0.12)
            Behavior on mezcla { NumberAnimation { duration: 520; easing.type: Easing.InOutQuad } }
        }
    }

    // ── Cabecera ──────────────────────────────────────────────────────
    Item {
        id: cabecera
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 44 * lanz.u; leftMargin: lanz.margen; rightMargin: lanz.margen }
        height: 56 * lanz.u
        opacity: lanz.activo ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 500 } }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 16 * lanz.u
            Rectangle { width: 6 * lanz.u; height: 40 * lanz.u; radius: 3; color: lanz.cian; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "MODO JUEGO"
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
                font { family: "Inter Display"; weight: Font.Black; italic: true; pixelSize: 34 * lanz.u; letterSpacing: 2 * lanz.u }
            }
        }

        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 14 * lanz.u

            Rectangle {
                visible: lanz.liberados > 50
                height: 40 * lanz.u; width: txtLib.implicitWidth + 32 * lanz.u; radius: height / 2
                color: Qt.alpha(lanz.magenta, 0.18); border.color: Qt.alpha(lanz.magenta, 0.7); border.width: 1
                Text {
                    id: txtLib
                    anchors.centerIn: parent
                    text: "+" + lanz.gb(lanz.liberados) + " LIBERADOS"
                    color: "#ffd0ea"
                    font { family: "Inter Display"; weight: Font.Bold; pixelSize: 15 * lanz.u; letterSpacing: 1.5 * lanz.u }
                }
            }
            Rectangle {
                visible: lanz.memLibre > 0
                height: 40 * lanz.u; width: txtMem.implicitWidth + 32 * lanz.u; radius: height / 2
                color: "#1affffff"; border.color: "#33ffffff"; border.width: 1
                Text {
                    id: txtMem
                    anchors.centerIn: parent
                    text: "RAM LIBRE  " + lanz.gb(lanz.memLibre)
                    color: "#d6e9ff"
                    font { family: "Inter Display"; weight: Font.Bold; pixelSize: 15 * lanz.u; letterSpacing: 1.5 * lanz.u }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(reloj.date, "HH:mm")
                color: "#ffffff"
                font { family: "Inter Display"; weight: Font.Light; pixelSize: 38 * lanz.u }
            }
        }
    }

    // ── Lo elegido, en grande ─────────────────────────────────────────
    Item {
        id: heroe
        anchors { top: cabecera.bottom; left: parent.left; right: parent.right; topMargin: 18 * lanz.u; leftMargin: lanz.margen; rightMargin: lanz.margen }
        height: 152 * lanz.u
        opacity: lanz.activo ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 600 } }

        readonly property bool conLogo: lanz.actual !== null && (lanz.actual.logo || "") !== "" && logo.status === Image.Ready

        Rectangle {
            id: seguir
            visible: lanz.esElUltimo
            height: 24 * lanz.u; width: txSeguir.implicitWidth + 22 * lanz.u; radius: height / 2
            color: Qt.alpha(lanz.cian, 0.22); border.color: lanz.cian; border.width: 1
            Text {
                id: txSeguir
                anchors.centerIn: parent
                text: "SEGUIR JUGANDO"
                color: "#ffffff"
                font { family: "Inter Display"; weight: Font.Bold; pixelSize: 12 * lanz.u; letterSpacing: 2.5 * lanz.u }
            }
        }

        // El logo del juego, si lo hay; si no, su nombre.
        Image {
            id: logo
            anchors { left: parent.left; bottom: lineaDetalle.top; bottomMargin: 10 * lanz.u }
            width: 620 * lanz.u
            height: (lanz.esElUltimo ? 88 : 114) * lanz.u
            source: lanz.actual && lanz.actual.logo ? "file://" + lanz.actual.logo : ""
            sourceSize.height: 400
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            verticalAlignment: Image.AlignBottom
            asynchronous: true
            visible: heroe.conLogo
        }
        Text {
            anchors { left: parent.left; right: parent.right; bottom: lineaDetalle.top; bottomMargin: 4 * lanz.u }
            visible: !heroe.conLogo
            text: lanz.actual ? lanz.actual.nombre : "No encontré juegos instalados"
            color: "#ffffff"
            elide: Text.ElideRight
            style: Text.Raised
            styleColor: "#a0000000"
            font { family: "Inter Display"; weight: Font.Black; italic: true; pixelSize: 62 * lanz.u }
        }
        Text {
            id: lineaDetalle
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            text: lanz.actual ? lanz.detalleDe(lanz.actual, lanz.filas[lanz.fila].tipo) : ""
            color: lanz.cian
            elide: Text.ElideRight
            style: Text.Raised
            styleColor: "#a0000000"
            font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 17 * lanz.u; letterSpacing: 2.5 * lanz.u }
        }
    }

    // ── Filas ─────────────────────────────────────────────────────────
    Column {
        anchors { top: heroe.bottom; left: parent.left; right: parent.right; topMargin: 16 * lanz.u }
        spacing: 6 * lanz.u

        Repeater {
            model: lanz.filas

            Item {
                id: bloque
                required property var modelData
                required property int index
                readonly property bool enFoco: lanz.fila === index

                width: parent.width
                height: lanz.altoDe(bloque.modelData) + 58 * lanz.u

                opacity: 0
                transform: Translate { id: entrada; y: 80 * lanz.u }
                states: State {
                    when: lanz.activo
                    PropertyChanges { target: bloque; opacity: 1 }
                    PropertyChanges { target: entrada; y: 0 }
                }
                transitions: Transition {
                    SequentialAnimation {
                        PauseAnimation { duration: 120 + bloque.index * 110 }
                        ParallelAnimation {
                            NumberAnimation { target: bloque; property: "opacity"; duration: 380 }
                            NumberAnimation { target: entrada; property: "y"; duration: 520; easing.type: Easing.OutExpo }
                        }
                    }
                }

                Text {
                    id: rotulo
                    x: lanz.margen
                    text: bloque.modelData.titulo + "   " + bloque.modelData.items.length
                    color: bloque.enFoco ? lanz.cian : "#8a8fa8"
                    font { family: "Inter Display"; weight: Font.Bold; pixelSize: 15 * lanz.u; letterSpacing: 5 * lanz.u }
                    Behavior on color { ColorAnimation { duration: 160 } }
                }

                ListView {
                    id: lista
                    anchors { top: rotulo.bottom; left: parent.left; right: parent.right; topMargin: 20 * lanz.u }
                    height: lanz.altoDe(bloque.modelData)
                    orientation: ListView.Horizontal
                    spacing: lanz.separacion
                    leftMargin: lanz.margen
                    rightMargin: lanz.margen
                    clip: false
                    model: bloque.modelData.items
                    currentIndex: lanz.columnas[bloque.index]
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 260
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: lanz.margen
                    preferredHighlightEnd: width - lanz.margen
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Tarjeta {
                        required property var modelData
                        required property int index
                        width: lanz.anchoTarjeta
                        height: lanz.altoDe(bloque.modelData)
                        u: lanz.u
                        item: modelData
                        seleccionada: bloque.enFoco && lanz.columnas[bloque.index] === index
                        onRaton: (gx, gy) => lanz.ratonEn(bloque.index, index, gx, gy)
                        onActivada: { lanz.elegir(bloque.index, index); lanz.lanzar(modelData, bloque.modelData.clave) }
                    }
                }
            }
        }
    }

    // ── Aviso: algo no salió redondo al activar ───────────────────────
    Rectangle {
        anchors { bottom: pie.top; bottomMargin: 14 * lanz.u; left: parent.left; leftMargin: lanz.margen }
        visible: lanz.aviso !== "" && lanz.activo
        height: 36 * lanz.u
        width: Math.min(txAviso.implicitWidth + 34 * lanz.u, parent.width - 2 * lanz.margen)
        radius: height / 2
        color: "#33ffb020"; border.color: "#ffb020"; border.width: 1
        Text {
            id: txAviso
            anchors { fill: parent; leftMargin: 17 * lanz.u; rightMargin: 17 * lanz.u }
            verticalAlignment: Text.AlignVCenter
            text: lanz.aviso.trim()
            color: "#ffe2a8"
            elide: Text.ElideRight
            font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 15 * lanz.u }
        }
    }

    // ── Pie: las teclas ───────────────────────────────────────────────
    Item {
        id: pie
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: 34 * lanz.u; leftMargin: lanz.margen; rightMargin: lanz.margen }
        height: 40 * lanz.u
        opacity: lanz.activo ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 900 } }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 26 * lanz.u
            Repeater {
                model: [
                    { tecla: "ENTER", accion: "Lanzar" },
                    { tecla: "← → ↑ ↓", accion: "Moverse" },
                    { tecla: "ESC", accion: "Cerrar" },
                    { tecla: "MOD+ALT+J", accion: "Volver a abrirlo" }
                ]
                Row {
                    required property var modelData
                    spacing: 9 * lanz.u
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28 * lanz.u; width: tx.implicitWidth + 18 * lanz.u; radius: 7 * lanz.u
                        color: "#14ffffff"; border.color: "#40ffffff"; border.width: 1
                        Text {
                            id: tx
                            anchors.centerIn: parent
                            text: modelData.tecla
                            color: "#ffffff"
                            font { family: "Inter Display"; weight: Font.Bold; pixelSize: 13 * lanz.u; letterSpacing: 1 }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.accion
                        color: "#a9aec4"
                        font { family: "Inter Display"; weight: Font.Medium; pixelSize: 15 * lanz.u }
                    }
                }
            }
        }

        // Solo cuando el juego elegido tiene trucos que se pueden manejar.
        Rectangle {
            visible: lanz.hayTrucos
            anchors { right: botonAjustes.left; rightMargin: 12 * lanz.u; verticalCenter: parent.verticalCenter }
            height: 40 * lanz.u; width: txTrucos.implicitWidth + 40 * lanz.u; radius: height / 2
            color: zonaTrucos.containsMouse ? Qt.alpha(lanz.magenta, 0.3) : Qt.alpha(lanz.magenta, 0.12)
            border.color: zonaTrucos.containsMouse ? lanz.magenta : Qt.alpha(lanz.magenta, 0.6); border.width: 1
            Behavior on color { ColorAnimation { duration: 140 } }
            Text {
                id: txTrucos
                anchors.centerIn: parent
                text: "F3   TRUCOS"
                color: "#ffffff"
                font { family: "Inter Display"; weight: Font.Bold; pixelSize: 14 * lanz.u; letterSpacing: 1.5 * lanz.u }
            }
            MouseArea {
                id: zonaTrucos
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: lanz.abrirTrucos()
            }
        }

        Rectangle {
            id: botonAjustes
            anchors { right: botonSalir.left; rightMargin: 12 * lanz.u; verticalCenter: parent.verticalCenter }
            height: 40 * lanz.u; width: txAjustes.implicitWidth + 40 * lanz.u; radius: height / 2
            color: zonaAjustes.containsMouse ? Qt.alpha(lanz.cian, 0.3) : "#14ffffff"
            border.color: zonaAjustes.containsMouse ? lanz.cian : "#40ffffff"; border.width: 1
            Behavior on color { ColorAnimation { duration: 140 } }
            Text {
                id: txAjustes
                anchors.centerIn: parent
                text: "F2   AJUSTES"
                color: "#ffffff"
                font { family: "Inter Display"; weight: Font.Bold; pixelSize: 14 * lanz.u; letterSpacing: 1.5 * lanz.u }
            }
            MouseArea {
                id: zonaAjustes
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: lanz.abrirAjustes()
            }
        }

        Rectangle {
            id: botonSalir
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            height: 40 * lanz.u; width: txSalir.implicitWidth + 40 * lanz.u; radius: height / 2
            color: zonaSalir.containsMouse ? Qt.alpha(lanz.magenta, 0.35) : "#14ffffff"
            border.color: zonaSalir.containsMouse ? lanz.magenta : "#40ffffff"; border.width: 1
            Behavior on color { ColorAnimation { duration: 140 } }
            Text {
                id: txSalir
                anchors.centerIn: parent
                text: "F10   SALIR DEL MODO JUEGO"
                color: "#ffffff"
                font { family: "Inter Display"; weight: Font.Bold; pixelSize: 14 * lanz.u; letterSpacing: 1.5 * lanz.u }
            }
            MouseArea {
                id: zonaSalir
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: lanz.salirModo()
            }
        }
    }

    // ── Trucos (encima de todo) ───────────────────────────────────────
    Trucos {
        id: panelTrucos
        anchors.fill: parent
        z: 11
        u: lanz.u
        visible: opacity > 0
        opacity: lanz.trucosAbiertos ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        datos: lanz.trucos
        error: lanz.errorTruco
        ocupado: lanz.trucosOcupado
        onCerrar: lanz.cerrarTrucos()
        onPoner: (clave, activo, opcion) => lanz.ponerTruco(clave, activo, opcion)
    }

    // ── Ajustes (encima de todo) ──────────────────────────────────────
    Ajustes {
        id: panelAjustes
        anchors.fill: parent
        z: 10
        u: lanz.u
        visible: opacity > 0
        opacity: lanz.ajustesAbiertos ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        ajustes: lanz.ajustes
        mensajeClave: lanz.mensajeClave
        claveBien: lanz.claveBien
        guardando: lanz.guardando
        buscando: lanz.buscando
        registro: lanz.registroCaratulas
        onCerrar: lanz.cerrarAjustes()
        onPonerAjuste: (nombre, valor) => lanz.ponerAjuste(nombre, valor)
        onGuardarClave: texto => lanz.guardarClave(texto)
        onQuitarClave: lanz.quitarClave()
        onBuscarCaratulas: lanz.buscarCaratulas()
        onAbrirPagina: lanz.abrirPaginaClave()
        mensajeClaveIa: lanz.mensajeClaveIa
        claveIaBien: lanz.claveIaBien
        guardandoIa: lanz.guardandoIa
        onGuardarClaveIa: texto => lanz.guardarClaveIa(texto)
        onQuitarClaveIa: lanz.quitarClaveIa()
        onPonerModelo: nombre => lanz.ponerModelo(nombre)
    }
}
