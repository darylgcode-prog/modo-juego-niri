import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

// Una tarjeta del lanzador. Con carátula la muestra entera; sin carátula
// usa el icono: agrandado y desenfocado de fondo, y nítido al centro.
Item {
    id: tarjeta

    required property var item
    property bool seleccionada: false
    property real u: 1
    readonly property bool conCaratula: item.caratula !== ""
    // Una carátula vertical ya trae el título del juego: no se le pone encima.
    readonly property bool sinRotulo: conCaratula && height > width
    readonly property color cian: "#19d9ff"

    signal raton(real gx, real gy)   // el puntero se movió encima (coordenadas globales)
    signal activada()

    scale: seleccionada ? 1.09 : 1.0
    z: seleccionada ? 2 : 0
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

    RectangularShadow {
        anchors.fill: marco
        radius: marco.radius
        blur: 46 * tarjeta.u
        spread: 3 * tarjeta.u
        color: Qt.alpha(tarjeta.cian, 0.75)
        opacity: tarjeta.seleccionada ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    ClippingRectangle {
        id: marco
        anchors.fill: parent
        radius: 16 * tarjeta.u
        color: "#12101c"
        border.width: Math.max(1, Math.round((tarjeta.seleccionada ? 3 : 1) * tarjeta.u))
        border.color: tarjeta.seleccionada ? tarjeta.cian : "#30ffffff"

        Image {
            id: fondo
            anchors.fill: parent
            source: tarjeta.conCaratula ? "file://" + tarjeta.item.caratula
                  : tarjeta.item.icono !== "" ? "file://" + tarjeta.item.icono : ""
            sourceSize: Qt.size(512, 512)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: tarjeta.conCaratula
        }

        MultiEffect {
            anchors.fill: parent
            anchors.margins: -30 * tarjeta.u
            source: fondo
            visible: !tarjeta.conCaratula && fondo.status === Image.Ready
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            brightness: -0.18
            saturation: 0.45
        }

        Image {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -parent.height * 0.08
            width: Math.min(parent.width, parent.height) * (parent.height > parent.width ? 0.66 : 0.50)
            height: width
            source: !tarjeta.conCaratula && tarjeta.item.icono !== "" ? "file://" + tarjeta.item.icono : ""
            sourceSize: Qt.size(512, 512)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: !tarjeta.conCaratula
        }

        // Sin imagen: la inicial, grande.
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -parent.height * 0.08
            visible: !tarjeta.conCaratula && tarjeta.item.icono === ""
            text: tarjeta.item.nombre.charAt(0).toUpperCase()
            color: "#40ffffff"
            font { family: "Inter Display"; weight: Font.Black; italic: true; pixelSize: parent.height * 0.5 }
        }

        // Las ROMs llevan arriba la consola a la que pertenecen.
        Rectangle {
            visible: (tarjeta.item.sistema || "") !== ""
            anchors { left: parent.left; top: parent.top; margins: 10 * tarjeta.u }
            height: 22 * tarjeta.u
            width: consola.implicitWidth + 16 * tarjeta.u
            radius: 6 * tarjeta.u
            color: "#d9070610"
            border.width: 1
            border.color: Qt.alpha(tarjeta.cian, 0.7)
            Text {
                id: consola
                anchors.centerIn: parent
                text: (tarjeta.item.sistema || "").toUpperCase()
                color: "#ffffff"
                font { family: "Inter Display"; weight: Font.Bold; pixelSize: 11 * tarjeta.u; letterSpacing: 1.5 * tarjeta.u }
            }
        }

        Rectangle {
            visible: !tarjeta.sinRotulo
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * 0.55
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 0.75; color: "#e6070610" }
                GradientStop { position: 1.0; color: "#f5070610" }
            }
        }

        Text {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 * tarjeta.u }
            visible: !tarjeta.sinRotulo
            text: tarjeta.item.nombre
            color: tarjeta.seleccionada ? "#ffffff" : "#d0d4e4"
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font { family: "Inter Display"; weight: Font.Bold; pixelSize: 17 * tarjeta.u }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: mouse => { const g = mapToGlobal(mouse.x, mouse.y); tarjeta.raton(g.x, g.y) }
        onClicked: tarjeta.activada()
    }
}
