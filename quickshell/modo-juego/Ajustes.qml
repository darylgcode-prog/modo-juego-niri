import QtQuick

// Pantalla de ajustes del lanzador (F2). Solo dibuja y avisa: quien guarda
// es shell.qml, a través del script «modo-juego».
FocusScope {
    id: panel

    property real u: 1
    property var ajustes: ({ sonido: true, animacion: true, caratulasAuto: true, clave: false })
    property string mensajeClave: ""     // resultado del último guardado
    property bool claveBien: false       // si ese resultado fue bueno
    property bool guardando: false
    property bool buscando: false
    property string registro: ""         // lo que dijo la última búsqueda

    signal cerrar()
    signal ponerAjuste(string nombre, bool valor)
    signal guardarClave(string texto)
    signal quitarClave()
    signal buscarCaratulas()
    signal abrirPagina()

    // Asistente del compañero (clave de Anthropic y modelo).
    property string mensajeClaveIa: ""
    property bool claveIaBien: false
    property bool guardandoIa: false
    signal guardarClaveIa(string texto)
    signal quitarClaveIa()
    signal ponerModelo(string nombre)

    function enviarClaveIa() {
        if (campoIa.text.trim() === "" || panel.guardandoIa)
            return
        panel.guardarClaveIa(campoIa.text.trim())
        campoIa.text = ""
    }

    readonly property color cian: "#19d9ff"
    readonly property color magenta: "#ff2a9e"

    function enfocar() { campo.forceActiveFocus() }
    function escribirClave(texto) { campo.text = texto }
    function enviarClave() {
        if (campo.text.trim() === "" || panel.guardando)
            return
        panel.guardarClave(campo.text.trim())
        campo.text = ""
    }

    component Boton: Rectangle {
        id: boton
        property string texto: ""
        property bool principal: false
        property bool activo: true
        signal pulsado()

        height: 42 * panel.u
        width: etiqueta.implicitWidth + 36 * panel.u
        radius: height / 2
        opacity: activo ? 1 : 0.4
        activeFocusOnTab: activo
        color: principal ? Qt.alpha(panel.cian, zona.containsMouse || activeFocus ? 0.42 : 0.24)
                         : (zona.containsMouse || activeFocus ? "#2effffff" : "#14ffffff")
        border.width: activeFocus ? 2 : 1
        border.color: activeFocus ? "#ffffff" : (principal ? panel.cian : "#40ffffff")
        Behavior on color { ColorAnimation { duration: 120 } }
        Keys.onReturnPressed: if (activo) pulsado()
        Keys.onEnterPressed: if (activo) pulsado()
        Keys.onSpacePressed: if (activo) pulsado()

        Text {
            id: etiqueta
            anchors.centerIn: parent
            text: boton.texto
            color: "#ffffff"
            font { family: "Inter Display"; weight: Font.Bold; pixelSize: 14 * panel.u; letterSpacing: 1 * panel.u }
        }
        MouseArea {
            id: zona
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: boton.activo ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (boton.activo) { boton.forceActiveFocus(); boton.pulsado() }
        }
    }

    component Interruptor: Item {
        id: inter
        property string texto: ""
        property string detalle: ""
        property bool valor: false
        signal cambiado(bool nuevo)

        width: parent ? parent.width : 0
        height: 58 * panel.u
        activeFocusOnTab: true
        Keys.onReturnPressed: cambiado(!valor)
        Keys.onEnterPressed: cambiado(!valor)
        Keys.onSpacePressed: cambiado(!valor)

        Rectangle {
            anchors.fill: parent
            anchors.margins: -6 * panel.u
            radius: 12 * panel.u
            color: "transparent"
            border.width: inter.activeFocus ? 2 : 0
            border.color: "#ffffff"
        }
        Column {
            anchors { left: parent.left; right: pastilla.left; rightMargin: 20 * panel.u; verticalCenter: parent.verticalCenter }
            spacing: 3 * panel.u
            Text {
                width: parent.width
                text: inter.texto
                color: "#ffffff"
                elide: Text.ElideRight
                font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 18 * panel.u }
            }
            Text {
                width: parent.width
                visible: inter.detalle !== ""
                text: inter.detalle
                color: "#9aa0b8"
                elide: Text.ElideRight
                font { family: "Inter Display"; pixelSize: 14 * panel.u }
            }
        }
        Rectangle {
            id: pastilla
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 62 * panel.u; height: 32 * panel.u; radius: height / 2
            color: inter.valor ? Qt.alpha(panel.cian, 0.45) : "#1fffffff"
            border.width: 1
            border.color: inter.valor ? panel.cian : "#50ffffff"
            Behavior on color { ColorAnimation { duration: 140 } }
            Rectangle {
                width: 24 * panel.u; height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: inter.valor ? parent.width - width - 4 * panel.u : 4 * panel.u
                color: inter.valor ? "#ffffff" : "#b0b4c8"
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { inter.forceActiveFocus(); inter.cambiado(!inter.valor) }
        }
    }

    component Titulo: Text {
        color: panel.cian
        font { family: "Inter Display"; weight: Font.Bold; pixelSize: 14 * panel.u; letterSpacing: 5 * panel.u }
    }

    // Velo: oscurece el lanzador y se traga los clics de afuera.
    Rectangle {
        anchors.fill: parent
        color: "#c8040310"
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: panel.cerrar() }
    }

    Rectangle {
        id: tarjeta
        anchors.centerIn: parent
        width: Math.min(parent.width - 80 * panel.u, 1380 * panel.u)
        height: contenido.implicitHeight + 76 * panel.u
        radius: 24 * panel.u
        color: "#f4110f1e"
        border.width: 1
        border.color: Qt.alpha(panel.cian, 0.55)
        MouseArea { anchors.fill: parent }    // los clics dentro no cierran

        Column {
            id: contenido
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 38 * panel.u }
            spacing: 16 * panel.u

            Item {
                width: parent.width
                height: 44 * panel.u
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AJUSTES"
                    color: "#ffffff"
                    font { family: "Inter Display"; weight: Font.Black; italic: true; pixelSize: 36 * panel.u; letterSpacing: 2 * panel.u }
                }
                Boton {
                    id: botonCerrar
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    texto: "ESC   CERRAR"
                    onPulsado: panel.cerrar()
                }
                Text {
                    anchors { right: botonCerrar.left; rightMargin: 18 * panel.u; verticalCenter: parent.verticalCenter }
                    visible: (panel.ajustes.version || "") !== ""
                    text: "Versión " + (panel.ajustes.version || "") + "   ·   se actualiza con «modo-juego actualizar»"
                    color: "#7d8299"
                    font { family: "Inter Display"; pixelSize: 13 * panel.u }
                }
            }

            Row {
                width: parent.width
                spacing: 52 * panel.u

            // ── Columna izquierda: carátulas ───────────────────────────
            Column {
                width: (parent.width - parent.spacing) * 0.54
                spacing: 16 * panel.u

            Titulo { text: "CARÁTULAS" }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#c4c9de"
                lineHeight: 1.25
                text: "Carátulas, fondos y logos de tus juegos de Steam se bajan solos. Para emuladores, lanzadores y lo que Steam no tiene se usa SteamGridDB, que pide una clave gratuita."
                font { family: "Inter Display"; pixelSize: 16 * panel.u }
            }

            Row {
                spacing: 10 * panel.u
                Rectangle {
                    width: 12 * panel.u; height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: panel.ajustes.clave ? "#3ddc84" : "#ffb020"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.ajustes.clave ? "Clave de SteamGridDB guardada" : "Sin clave de SteamGridDB"
                    color: "#ffffff"
                    font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 17 * panel.u }
                }
            }

            Row {
                width: parent.width
                spacing: 12 * panel.u
                Rectangle {
                    width: parent.width - btnPegar.width - btnGuardar.width - 24 * panel.u
                    height: 46 * panel.u
                    radius: 12 * panel.u
                    color: "#1affffff"
                    border.width: campo.activeFocus ? 2 : 1
                    border.color: campo.activeFocus ? panel.cian : "#40ffffff"
                    TextInput {
                        id: campo
                        anchors { fill: parent; leftMargin: 16 * panel.u; rightMargin: 16 * panel.u }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        clip: true
                        focus: true
                        activeFocusOnTab: true
                        selectByMouse: true
                        color: "#ffffff"
                        selectionColor: panel.cian
                        font { family: "Inter Display"; pixelSize: 17 * panel.u }
                        onAccepted: panel.enviarClave()
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 16 * panel.u; verticalCenter: parent.verticalCenter }
                        visible: campo.text === ""
                        text: panel.ajustes.clave ? "Pega otra clave para reemplazarla" : "Pega aquí tu clave (no se muestra)"
                        color: "#7d8299"
                        font { family: "Inter Display"; pixelSize: 16 * panel.u }
                    }
                }
                Boton { id: btnPegar; texto: "PEGAR"; anchors.verticalCenter: parent.verticalCenter; onPulsado: { campo.forceActiveFocus(); campo.paste() } }
                Boton {
                    id: btnGuardar
                    anchors.verticalCenter: parent.verticalCenter
                    principal: true
                    texto: panel.guardando ? "COMPROBANDO…" : "GUARDAR"
                    activo: campo.text.trim() !== "" && !panel.guardando
                    onPulsado: panel.enviarClave()
                }
            }

            Text {
                width: parent.width
                visible: panel.mensajeClave !== ""
                wrapMode: Text.WordWrap
                text: panel.mensajeClave
                color: panel.claveBien ? "#7df0a8" : "#ffb4c8"
                font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 15 * panel.u }
            }

            Flow {
                width: parent.width
                spacing: 12 * panel.u
                Boton { texto: "CONSEGUIR CLAVE (ABRE EL NAVEGADOR)"; onPulsado: panel.abrirPagina() }
                Boton { texto: "QUITAR CLAVE"; activo: panel.ajustes.clave; onPulsado: panel.quitarClave() }
                Boton {
                    principal: true
                    texto: panel.buscando ? "BUSCANDO…" : "BUSCAR CARÁTULAS AHORA"
                    activo: !panel.buscando
                    onPulsado: panel.buscarCaratulas()
                }
            }

            Rectangle {
                width: parent.width
                visible: panel.registro !== ""
                height: Math.min(textoRegistro.implicitHeight, 170 * panel.u) + 22 * panel.u
                radius: 12 * panel.u
                color: "#66000000"
                clip: true
                Text {
                    id: textoRegistro
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 11 * panel.u }
                    text: panel.registro
                    color: "#b8bed6"
                    wrapMode: Text.WordWrap
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 * panel.u }
                }
            }

            Interruptor {
                texto: "Buscar arte sola al abrir el lanzador"
                detalle: "Solo para juegos con número de Steam. Lo demás se busca con el botón de arriba."
                valor: panel.ajustes.caratulasAuto === true
                onCambiado: nuevo => panel.ponerAjuste("CARATULAS_AUTO", nuevo)
            }

            // ── Asistente del compañero ────────────────────────────────
            Item { width: 1; height: 2 * panel.u }
            Titulo { text: "ASISTENTE DEL COMPAÑERO" }
            Row {
                spacing: 10 * panel.u
                Rectangle {
                    width: 12 * panel.u; height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: panel.ajustes.claveIa ? "#3ddc84" : "#ffb020"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.ajustes.claveIa ? "Clave de Anthropic guardada" : "Sin clave de Anthropic (se saca en la consola de Anthropic)"
                    color: "#ffffff"
                    font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 16 * panel.u }
                }
            }
            Row {
                width: parent.width
                spacing: 12 * panel.u
                Rectangle {
                    width: parent.width - btnPegarIa.width - btnGuardarIa.width - 24 * panel.u
                    height: 46 * panel.u
                    radius: 12 * panel.u
                    color: "#1affffff"
                    border.width: campoIa.activeFocus ? 2 : 1
                    border.color: campoIa.activeFocus ? panel.cian : "#40ffffff"
                    TextInput {
                        id: campoIa
                        anchors { fill: parent; leftMargin: 16 * panel.u; rightMargin: 16 * panel.u }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        clip: true
                        activeFocusOnTab: true
                        selectByMouse: true
                        color: "#ffffff"
                        selectionColor: panel.cian
                        font { family: "Inter Display"; pixelSize: 17 * panel.u }
                        onAccepted: panel.enviarClaveIa()
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 16 * panel.u; verticalCenter: parent.verticalCenter }
                        visible: campoIa.text === ""
                        text: panel.ajustes.claveIa ? "Pega otra clave para reemplazarla" : "Pega aquí tu clave de Anthropic (no se muestra)"
                        color: "#7d8299"
                        font { family: "Inter Display"; pixelSize: 16 * panel.u }
                    }
                }
                Boton { id: btnPegarIa; texto: "PEGAR"; anchors.verticalCenter: parent.verticalCenter; onPulsado: { campoIa.forceActiveFocus(); campoIa.paste() } }
                Boton {
                    id: btnGuardarIa
                    anchors.verticalCenter: parent.verticalCenter
                    principal: true
                    texto: panel.guardandoIa ? "COMPROBANDO…" : "GUARDAR"
                    activo: campoIa.text.trim() !== "" && !panel.guardandoIa
                    onPulsado: panel.enviarClaveIa()
                }
            }
            Text {
                width: parent.width
                visible: panel.mensajeClaveIa !== ""
                wrapMode: Text.WordWrap
                text: panel.mensajeClaveIa
                color: panel.claveIaBien ? "#7df0a8" : "#ffb4c8"
                font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 15 * panel.u }
            }
            Flow {
                width: parent.width
                spacing: 12 * panel.u
                Repeater {
                    model: [
                        { clave: "opus", texto: "OPUS 5.5  ·  el más capaz" },
                        { clave: "sonnet", texto: "SONNET 5.5" },
                        { clave: "haiku", texto: "HAIKU 5.5  ·  el más barato" }
                    ]
                    Boton {
                        required property var modelData
                        texto: modelData.texto
                        principal: panel.ajustes.modelo === modelData.clave
                        onPulsado: panel.ponerModelo(modelData.clave)
                    }
                }
                Boton { texto: "QUITAR CLAVE"; activo: panel.ajustes.claveIa === true; onPulsado: panel.quitarClaveIa() }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#9aa0b8"
                text: "Cada pregunta se cobra en tu cuenta de Anthropic: unos centavos de dólar según el modelo, más 1 centavo por búsqueda web."
                font { family: "Inter Display"; pixelSize: 13 * panel.u }
            }
            }

            // ── Columna derecha: qué hace el modo juego ────────────────
            Column {
                width: (parent.width - parent.spacing) * 0.46
                spacing: 12 * panel.u

                Titulo { text: "AL ACTIVAR EL MODO JUEGO" }
                Interruptor {
                    texto: "Animaciones de entrada y de salida"
                    detalle: "Apagado, solo cierra lo que sobra y avisa con una notificación."
                    valor: panel.ajustes.animacion === true
                    onCambiado: nuevo => panel.ponerAjuste("ANIMACION", nuevo)
                }
                Interruptor {
                    texto: "Sonidos"
                    detalle: "El de la entrada, el de la salida y los del lanzador."
                    valor: panel.ajustes.sonido === true
                    onCambiado: nuevo => panel.ponerAjuste("SONIDO", nuevo)
                }
                Interruptor {
                    visible: panel.ajustes.hayTeclado === true
                    texto: "El teclado reacciona"
                    detalle: "Destella con el golpe y queda en color de juego; al salir vuelve."
                    valor: panel.ajustes.teclado === true
                    onCambiado: nuevo => panel.ponerAjuste("TECLADO", nuevo)
                }
                Interruptor {
                    texto: "No molestar"
                    detalle: "Silencia las notificaciones mientras dura el modo juego."
                    valor: panel.ajustes.noMolestar === true
                    onCambiado: nuevo => panel.ponerAjuste("NO_MOLESTAR", nuevo)
                }
                Interruptor {
                    texto: "Apagar las otras pantallas"
                    detalle: "Deja encendida solo la que estás usando; al salir vuelven."
                    valor: panel.ajustes.apagarPantallas === true
                    onCambiado: nuevo => panel.ponerAjuste("APAGAR_OTRAS_PANTALLAS", nuevo)
                }

                Item { width: 1; height: 4 * panel.u }
                Titulo { text: "AL JUGAR" }
                Interruptor {
                    texto: "Volver al lanzador al cerrar un juego"
                    detalle: "También con los emuladores. No con Steam ni Battle.net."
                    valor: panel.ajustes.volver === true
                    onCambiado: nuevo => panel.ponerAjuste("VOLVER_AL_LANZADOR", nuevo)
                }
                Interruptor {
                    texto: "Compañero de juego"
                    detalle: (panel.ajustes.pantallas || 1) < 2 ? "Con una sola pantalla va encima del juego: Mod+Alt+C lo muestra y lo oculta."
                             : "Guías, notas, sesión y asistente en la pantalla que no usa el juego."
                    valor: panel.ajustes.companero === true
                    onCambiado: nuevo => panel.ponerAjuste("COMPANERO", nuevo)
                }
                Interruptor {
                    texto: "Las preguntas llevan una captura del juego"
                    detalle: "Solo al preguntar, solo la pantalla del juego, y se borra al responder."
                    valor: panel.ajustes.captura === true
                    onCambiado: nuevo => panel.ponerAjuste("ASISTENTE_CAPTURA", nuevo)
                }
                Interruptor {
                    visible: panel.ajustes.hayHud === true
                    texto: "Mostrar FPS y temperaturas"
                    detalle: "En los juegos abiertos desde aquí. Shift derecho + F12 lo oculta."
                    valor: panel.ajustes.hud === true
                    onCambiado: nuevo => panel.ponerAjuste("HUD", nuevo)
                }
            }
            }
        }
    }
}
