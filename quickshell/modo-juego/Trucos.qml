import QtQuick

// Panel de trucos del juego elegido (F3 en el lanzador). Muestra los que
// el emulador trae para ese juego y los enciende o apaga. Solo dibuja y
// avisa: quien cambia la configuración del emulador es «modo-juego-trucos».
FocusScope {
    id: panel

    property real u: 1
    property var datos: ({ disponible: false, trucos: [], motivo: "", juego: "" })
    property string error: ""        // lo que respondió el último cambio, si falló
    property bool ocupado: false

    signal cerrar()
    signal poner(string clave, bool activo, string opcion)

    readonly property color cian: "#19d9ff"
    readonly property color magenta: "#ff2a9e"
    readonly property var lista: datos.trucos || []
    property int indice: 0

    function enfocar() { indice = 0; forceActiveFocus() }

    function alternar(i) {
        const t = lista[i]
        if (t && !ocupado)
            poner(t.clave, !t.activo, t.opcion || "")
    }
    function cambiarVariante(i, paso) {
        const t = lista[i]
        if (!t || ocupado || !t.opciones || t.opciones.length === 0)
            return
        const n = t.opciones.length
        const k = (Math.max(0, t.opciones.indexOf(t.opcion)) + paso + n) % n
        poner(t.clave, true, t.opciones[k])
    }
    // Una acción, venga del teclado o del mando.
    function accion(cual) {
        switch (cual) {
        case "arr": indice = Math.max(0, indice - 1); break
        case "aba": indice = Math.min(lista.length - 1, indice + 1); break
        case "izq": cambiarVariante(indice, -1); break
        case "der": cambiarVariante(indice, 1); break
        case "ok": alternar(indice); break
        case "atras": case "menu": cerrar(); break
        }
    }

    Keys.onPressed: ev => {
        switch (ev.key) {
        case Qt.Key_Up: case Qt.Key_K: accion("arr"); break
        case Qt.Key_Down: case Qt.Key_J: accion("aba"); break
        case Qt.Key_Left: case Qt.Key_H: accion("izq"); break
        case Qt.Key_Right: case Qt.Key_L: accion("der"); break
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: accion("ok"); break
        case Qt.Key_Escape: case Qt.Key_F3: case Qt.Key_T: accion("atras"); break
        default: return
        }
        ev.accepted = true
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
        width: Math.min(parent.width - 80 * panel.u, 1040 * panel.u)
        height: Math.min(parent.height - 120 * panel.u, contenido.implicitHeight + 76 * panel.u)
        radius: 24 * panel.u
        color: "#f4110f1e"
        border.width: 1
        border.color: Qt.alpha(panel.cian, 0.55)
        MouseArea { anchors.fill: parent }    // los clics dentro no cierran

        Column {
            id: contenido
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 38 * panel.u }
            spacing: 14 * panel.u

            Item {
                width: parent.width
                height: 44 * panel.u
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "TRUCOS"
                    color: "#ffffff"
                    font { family: "Inter Display"; weight: Font.Black; italic: true; pixelSize: 36 * panel.u; letterSpacing: 2 * panel.u }
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: "ESC   CERRAR"
                    color: "#a9aec4"
                    font { family: "Inter Display"; weight: Font.Bold; pixelSize: 14 * panel.u; letterSpacing: 1 * panel.u }
                }
            }

            Text {
                width: parent.width
                text: (panel.datos.juego || "") + (panel.datos.emulador ? "   ·   " + panel.datos.emulador : "")
                color: panel.cian
                elide: Text.ElideRight
                font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 17 * panel.u; letterSpacing: 2 * panel.u }
            }
            Text {
                width: parent.width
                visible: text !== ""
                wrapMode: Text.WordWrap
                text: panel.datos.disponible ? (panel.datos.nota || "") : (panel.datos.motivo || "Buscando los trucos…")
                color: panel.datos.disponible ? "#c4c9de" : "#ffe2a8"
                lineHeight: 1.25
                font { family: "Inter Display"; pixelSize: 16 * panel.u }
            }
            Text {
                width: parent.width
                visible: panel.error !== ""
                wrapMode: Text.WordWrap
                text: panel.error
                color: "#ffb4c8"
                font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 15 * panel.u }
            }

            ListView {
                id: vista
                width: parent.width
                visible: panel.lista.length > 0
                height: Math.min(panel.lista.length * 66 * panel.u,
                                 Math.max(66 * panel.u, tarjeta.parent.height - 420 * panel.u))
                clip: true
                model: panel.lista
                currentIndex: panel.indice
                highlightFollowsCurrentItem: true
                highlightMoveDuration: 120
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: fila
                    required property var modelData
                    required property int index
                    readonly property bool elegida: index === panel.indice
                    readonly property bool conVariantes: modelData.opciones && modelData.opciones.length > 0

                    width: vista.width
                    height: 62 * panel.u
                    radius: 12 * panel.u
                    color: elegida ? Qt.alpha(panel.cian, 0.14) : "transparent"
                    border.width: elegida ? 1 : 0
                    border.color: Qt.alpha(panel.cian, 0.7)

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: panel.indice = fila.index
                        onClicked: { panel.indice = fila.index; panel.alternar(fila.index) }
                    }

                    Column {
                        anchors { left: parent.left; leftMargin: 16 * panel.u; right: derecha.left; rightMargin: 18 * panel.u; verticalCenter: parent.verticalCenter }
                        spacing: 2 * panel.u
                        Text {
                            width: parent.width
                            text: fila.modelData.nombre
                            color: "#ffffff"
                            elide: Text.ElideRight
                            font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 18 * panel.u }
                        }
                        Text {
                            width: parent.width
                            text: fila.modelData.varias_listas ? fila.modelData.descripcion + " (Sus variantes se eligen en Cemu.)"
                                                               : fila.modelData.descripcion
                            color: "#9aa0b8"
                            elide: Text.ElideRight
                            font { family: "Inter Display"; pixelSize: 13 * panel.u }
                        }
                    }

                    Row {
                        id: derecha
                        anchors { right: parent.right; rightMargin: 16 * panel.u; verticalCenter: parent.verticalCenter }
                        spacing: 14 * panel.u

                        // Variante elegida, con flechas para cambiarla.
                        Row {
                            visible: fila.conVariantes && fila.modelData.activo
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * panel.u
                            Text {
                                text: "◀"
                                color: zonaMenos.containsMouse ? "#ffffff" : panel.cian
                                font.pixelSize: 15 * panel.u
                                anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: zonaMenos; anchors.fill: parent; anchors.margins: -8 * panel.u; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.cambiarVariante(fila.index, -1) }
                            }
                            Text {
                                text: fila.modelData.opcion || ""
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                                font { family: "Inter Display"; weight: Font.Bold; pixelSize: 15 * panel.u }
                            }
                            Text {
                                text: "▶"
                                color: zonaMas.containsMouse ? "#ffffff" : panel.cian
                                font.pixelSize: 15 * panel.u
                                anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: zonaMas; anchors.fill: parent; anchors.margins: -8 * panel.u; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.cambiarVariante(fila.index, 1) }
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 62 * panel.u; height: 32 * panel.u; radius: height / 2
                            color: fila.modelData.activo ? Qt.alpha(panel.magenta, 0.5) : "#1fffffff"
                            border.width: 1
                            border.color: fila.modelData.activo ? panel.magenta : "#50ffffff"
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Rectangle {
                                width: 24 * panel.u; height: width; radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                x: fila.modelData.activo ? parent.width - width - 4 * panel.u : 4 * panel.u
                                color: fila.modelData.activo ? "#ffffff" : "#b0b4c8"
                                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: panel.lista.length > 0
                text: "↑ ↓  elegir      ENTER  enciende o apaga      ← →  cambia la variante      ESC  cierra"
                color: "#7d8299"
                elide: Text.ElideRight
                font { family: "Inter Display"; pixelSize: 13 * panel.u }
            }
        }
    }
}
