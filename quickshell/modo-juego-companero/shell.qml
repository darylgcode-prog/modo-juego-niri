//@ pragma UseQApplication
import QtQuick
import QtWebSockets
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Compañero de juego: una franja en el monitor libre mientras se juega.
// Muestra la sesión, las temperaturas, las guías abiertas en el navegador
// de al lado (que maneja sin quitarle el foco al juego), tus notas del
// juego y un asistente al que se le pregunta. Lo abre «modo-juego jugar».
//
// Variables de entorno:
//   MJC_PANTALLA        pantalla donde va la franja
//   MJC_PANTALLA_JUEGO  pantalla del juego (para la captura al preguntar)
//   MJC_ID, MJC_NOMBRE, MJC_CARATULA   el juego
//   MJC_GUIAS           JSON con las guías: [{titulo, url}]
//   MJC_PUERTO          puerto de control del navegador de guías
//   MJC_NOTAS           archivo de notas de este juego
//   MJC_HISTORIAL       archivo con las preguntas de esta sesión
//   MJC_MODELO          opus | sonnet | haiku
//   MJC_CAPTURA         «si» = las preguntas llevan una captura del juego
//   MJC_PRUEBA, MJC_FOTO   solo para pruebas: segundos de vida y dónde
//                          guardar lo que dibuja la franja
ShellRoot {
    id: raiz

    readonly property string nombre: Quickshell.env("MJC_NOMBRE") || "Juego"
    readonly property string caratula: Quickshell.env("MJC_CARATULA") || ""
    readonly property string puerto: Quickshell.env("MJC_PUERTO") || "9333"
    readonly property string archivoNotas: Quickshell.env("MJC_NOTAS") || ""
    readonly property string modelo: Quickshell.env("MJC_MODELO") || "opus"
    readonly property bool conCaptura: Quickshell.env("MJC_CAPTURA") !== "no"
    readonly property int prueba: parseInt(Quickshell.env("MJC_PRUEBA") || "0")
    readonly property color cian: "#19d9ff"
    readonly property color magenta: "#ff2a9e"

    // ── Sesión y sensores ─────────────────────────────────────────────
    property int segundos: 0
    property string gpuTemp: "–"
    property string gpuUso: "–"
    property string cpuTemp: "–"
    property string memLibre: "–"

    function reloj(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, x = s % 60
        return (h > 0 ? h + ":" : "") + String(m).padStart(h > 0 ? 2 : 1, "0") + ":" + String(x).padStart(2, "0")
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: raiz.segundos++ }

    Process {
        id: sensores
        command: ["sh", "-c", "nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1; "
            + "t=; for d in /sys/class/hwmon/hwmon*; do [ \"$(cat $d/name 2>/dev/null)\" = coretemp ] && t=$(cat $d/temp1_input) && break; done; echo \"${t:-0}\"; "
            + "awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n")
                if (l.length < 3)
                    return
                const gpu = l[0].split(",").map(x => x.trim())
                raiz.gpuTemp = gpu[0] ? Math.round(parseFloat(gpu[0])) + "°" : "–"
                raiz.gpuUso = gpu[1] ? gpu[1] + "%" : "–"
                raiz.cpuTemp = parseInt(l[1]) > 0 ? Math.round(parseInt(l[1]) / 1000) + "°" : "–"
                raiz.memLibre = (parseInt(l[2]) / 1024).toFixed(1).replace(".", ",") + " GB"
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: sensores.running = true }

    // ── Guías: el navegador de al lado, manejado por su puerto de control ─
    property var guias: []          // [{titulo, url}] lo que se pidió abrir
    property var pestanas: []       // lo que el navegador dice tener abierto
    property int guiaActual: 0

    function dominio(url) {
        const m = /^https?:\/\/([^\/]+)/.exec(url || "")
        return m ? m[1].replace(/^www\./, "") : ""
    }

    // Qué pestaña del navegador es cada guía. Se decide una vez, cuando la
    // página termina de cargar, y se recuerda por el identificador de la
    // pestaña: así sigue siendo la misma aunque navegues dentro de ella.
    property var asignadas: ({})        // índice de guía → id de pestaña

    function igualar(url) {
        let u = url || ""
        try { u = decodeURIComponent(u) } catch (e) {}
        return u.toLowerCase().replace(/[+_ ]/g, "_").replace(/\/+$/, "")
    }

    function asignar() {
        const nuevas = Object.assign({}, asignadas)
        const vivas = {}
        pestanas.forEach(p => vivas[p.id] = true)
        const tomadas = {}
        for (const g in nuevas) {
            if (vivas[nuevas[g]]) tomadas[nuevas[g]] = true
            else delete nuevas[g]
        }
        for (let g = 0; g < guias.length; g++) {
            if (nuevas[g])
                continue
            const libres = pestanas.filter(p => !tomadas[p.id])
            const delSitio = libres.filter(p => dominio(p.url) === dominio(guias[g].url))
            // La misma dirección (los sitios cambian «+» por «_» al cargar); si
            // no, la única pestaña libre de ese sitio.
            const p = libres.find(x => igualar(x.url) === igualar(guias[g].url))
                   || (delSitio.length === 1 ? delSitio[0] : null)
            if (p) {
                nuevas[g] = p.id
                tomadas[p.id] = true
            }
        }
        asignadas = nuevas
    }

    function pestanaDe(i) {
        return pestanas.find(p => p.id === asignadas[i]) || null
    }

    function pedir(ruta, alTerminar) {
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState === XMLHttpRequest.DONE && alTerminar)
                alTerminar(x.status === 200 ? x.responseText : "")
        }
        x.open("GET", "http://127.0.0.1:" + puerto + ruta)
        x.send()
    }

    function leerPestanas() {
        pedir("/json/list", texto => {
            if (!texto)
                return
            try {
                pestanas = JSON.parse(texto).filter(p => p.type === "page")
                asignar()
            } catch (e) {}
        })
    }
    Timer { interval: 2500; running: true; repeat: true; triggeredOnStart: true; onTriggered: raiz.leerPestanas() }

    function irA(i) {
        if (guias.length === 0)
            return
        guiaActual = (i + guias.length) % guias.length
        const p = pestanaDe(guiaActual)
        if (p)
            pedir("/json/activate/" + p.id, null)
    }

    // Desplazar la guía: una orden por el canal de depuración de la pestaña.
    property string ordenPendiente: ""
    function desplazar(cuanto) {
        const p = pestanaDe(guiaActual)
        if (!p || !p.webSocketDebuggerUrl)
            return
        ordenPendiente = JSON.stringify({ id: 1, method: "Runtime.evaluate",
            params: { expression: "window.scrollBy({top: " + cuanto + ", behavior: 'smooth'})" } })
        if (canal.url.toString() === p.webSocketDebuggerUrl && canal.status === WebSocket.Open) {
            canal.sendTextMessage(ordenPendiente)
            ordenPendiente = ""
        } else {
            canal.active = false
            canal.url = p.webSocketDebuggerUrl
            canal.active = true
        }
    }
    WebSocket {
        id: canal
        active: false
        onStatusChanged: {
            if (status === WebSocket.Open && raiz.ordenPendiente !== "") {
                sendTextMessage(raiz.ordenPendiente)
                raiz.ordenPendiente = ""
            }
        }
    }

    // ── Notas del juego ───────────────────────────────────────────────
    FileView { id: notasGuardadas; path: raiz.archivoNotas; blockLoading: true; printErrors: false }
    property string notasIniciales: ""
    Process {
        id: guardarNotas
        property string texto: ""
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && cat > \"$1\"", "sh", raiz.archivoNotas]
        stdinEnabled: true
        onStarted: { write(texto); stdinEnabled = false }
    }
    function guardar(texto) {
        if (archivoNotas === "" || guardarNotas.running)
            return
        guardarNotas.texto = texto
        guardarNotas.stdinEnabled = true
        guardarNotas.running = true
    }

    // ── Asistente ─────────────────────────────────────────────────────
    property bool escribiendo: false     // la franja tiene el teclado
    property bool pensando: false
    property string pregunta: ""
    property string bruto: ""            // todo lo que ha llegado del asistente
    property string respuesta: ""
    property string errorAsistente: ""
    property var meta: null

    function recibir(trozo) {
        bruto += trozo
        const corte = bruto.search(/\n@@(META|ERROR) /)
        respuesta = (corte >= 0 ? bruto.slice(0, corte) : bruto).trim()
    }

    function preguntar(texto) {
        if (pensando || texto.trim() === "")
            return
        pregunta = texto.trim()
        bruto = ""
        respuesta = ""
        errorAsistente = ""
        meta = null
        pensando = true
        escribiendo = false
        const orden = ["modo-juego", "preguntar", "--juego", nombre, "--modelo", modelo]
        if (Quickshell.env("MJC_HISTORIAL"))
            orden.push("--historial", Quickshell.env("MJC_HISTORIAL"))
        if (conCaptura && Quickshell.env("MJC_PANTALLA_JUEGO"))
            orden.push("--captura", Quickshell.env("MJC_PANTALLA_JUEGO"))
        procPreguntar.command = orden
        procPreguntar.stdinEnabled = true
        procPreguntar.running = true
    }

    Process {
        id: procPreguntar
        stdinEnabled: true
        onStarted: { write(raiz.pregunta + "\n"); stdinEnabled = false }
        stdout: SplitParser { splitMarker: ""; onRead: trozo => raiz.recibir(trozo) }
        onExited: {
            raiz.pensando = false
            const m = /\n@@META (.*)/.exec(raiz.bruto)
            const e = /\n@@ERROR (.*)/.exec(raiz.bruto)
            if (m) { try { raiz.meta = JSON.parse(m[1]) } catch (err) {} }
            if (e) raiz.errorAsistente = e[1].trim()
            else if (!m && raiz.respuesta === "") raiz.errorAsistente = "El asistente no respondió."
        }
    }

    // ── Atajos globales: llegan por aquí sin quitarle el foco al juego ─
    IpcHandler {
        target: "companero"
        function siguiente(): void { raiz.irA(raiz.guiaActual + 1) }
        function anterior(): void { raiz.irA(raiz.guiaActual - 1) }
        function bajar(): void { raiz.desplazar(520) }
        function subir(): void { raiz.desplazar(-520) }
        function preguntar(): void { raiz.escribiendo = !raiz.escribiendo }
    }

    Component.onCompleted: {
        try { guias = JSON.parse(Quickshell.env("MJC_GUIAS") || "[]") } catch (e) { guias = [] }
        notasIniciales = archivoNotas !== "" ? notasGuardadas.text() : ""
    }

    Timer { interval: Math.max(1, raiz.prueba) * 1000; running: raiz.prueba > 0; onTriggered: Qt.quit() }
    // Solo en modo prueba: hace una pregunta sin teclado.
    Timer {
        interval: 400
        running: raiz.prueba > 0 && !!Quickshell.env("MJC_PRUEBA_PREGUNTA")
        onTriggered: raiz.preguntar(Quickshell.env("MJC_PRUEBA_PREGUNTA"))
    }

    PanelWindow {
        id: franja
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("MJC_PANTALLA")) || Quickshell.screens[Quickshell.screens.length - 1]
        anchors { top: true; bottom: true; left: true }
        implicitWidth: 460
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: implicitWidth        // el navegador ocupa el resto de la pantalla
        color: "transparent"

        WlrLayershell.namespace: "modo-juego-companero"
        WlrLayershell.layer: WlrLayer.Top
        // Solo toma el teclado cuando vas a preguntar; para las notas basta un clic.
        WlrLayershell.keyboardFocus: raiz.escribiendo && raiz.prueba === 0 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        component Titulo: Text {
            color: raiz.cian
            font { family: "Inter Display"; weight: Font.Bold; pixelSize: 12; letterSpacing: 4 }
        }
        component Dato: Column {
            property string rotulo: ""
            property string valor: ""
            spacing: 2
            Text { text: parent.valor; color: "#ffffff"; font { family: "Inter Display"; weight: Font.Black; italic: true; pixelSize: 24 } }
            Text { text: parent.rotulo; color: "#8a8fa8"; font { family: "Inter Display"; weight: Font.Bold; pixelSize: 10; letterSpacing: 2 } }
        }

        Rectangle {
            id: fondo
            anchors.fill: parent
            color: "#f5070610"
            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Qt.alpha(raiz.cian, 0.45) }

            // Foto de lo que dibuja la franja, solo para pruebas.
            Timer {
                interval: parseInt(Quickshell.env("MJC_FOTO_MS") || "1600")
                running: raiz.prueba > 0 && !!Quickshell.env("MJC_FOTO")
                onTriggered: fondo.grabToImage(r => r.saveToFile(Quickshell.env("MJC_FOTO")))
            }

            Column {
                id: arriba
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 22 }
                spacing: 16

                // ── El juego y la sesión ──
                Row {
                    width: parent.width
                    spacing: 16
                    Rectangle {
                        width: 84; height: 126; radius: 10; color: "#12101c"; clip: true
                        border.width: 1; border.color: "#30ffffff"
                        Image {
                            anchors.fill: parent; anchors.margins: 1
                            source: raiz.caratula !== "" ? "file://" + raiz.caratula : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.height: 400
                            asynchronous: true
                        }
                    }
                    Column {
                        width: parent.width - 100
                        spacing: 6
                        Text {
                            width: parent.width
                            text: raiz.nombre
                            color: "#ffffff"
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font { family: "Inter Display"; weight: Font.Black; italic: true; pixelSize: 24 }
                        }
                        Text {
                            text: raiz.reloj(raiz.segundos)
                            color: raiz.cian
                            font { family: "Inter Display"; weight: Font.Light; pixelSize: 40 }
                        }
                        Text {
                            text: "EN ESTA SESIÓN"
                            color: "#8a8fa8"
                            font { family: "Inter Display"; weight: Font.Bold; pixelSize: 10; letterSpacing: 2 }
                        }
                    }
                }

                Row {
                    spacing: 30
                    Dato { rotulo: "TARJETA"; valor: raiz.gpuTemp }
                    Dato { rotulo: "USO"; valor: raiz.gpuUso }
                    Dato { rotulo: "PROCESADOR"; valor: raiz.cpuTemp }
                    Dato { rotulo: "MEMORIA LIBRE"; valor: raiz.memLibre }
                }

                Rectangle { width: parent.width; height: 1; color: "#22ffffff" }

                // ── Guías ──
                Titulo { text: "GUÍAS" }
                Column {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: raiz.guias
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool actual: index === raiz.guiaActual
                            width: parent.width; height: 38; radius: 10
                            color: actual ? Qt.alpha(raiz.cian, 0.2) : (zona.containsMouse ? "#1affffff" : "#0dffffff")
                            border.width: 1
                            border.color: actual ? raiz.cian : "#22ffffff"
                            Text {
                                anchors { left: parent.left; right: parent.right; margins: 14; verticalCenter: parent.verticalCenter }
                                text: modelData.titulo
                                color: "#ffffff"
                                elide: Text.ElideRight
                                font { family: "Inter Display"; weight: parent.actual ? Font.Bold : Font.Medium; pixelSize: 15 }
                            }
                            MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: raiz.irA(index) }
                        }
                    }
                    Text {
                        width: parent.width
                        text: raiz.guias.length === 0 ? "Este juego no tiene guías configuradas."
                              : "Mod+Alt+← →  cambia de guía     Mod+Alt+↑ ↓  la desplaza"
                        color: "#8a8fa8"
                        wrapMode: Text.WordWrap
                        font { family: "Inter Display"; pixelSize: 12 }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: "#22ffffff" }

                // ── Notas ──
                Titulo { text: "TUS NOTAS DE ESTE JUEGO" }
                Rectangle {
                    width: parent.width
                    height: 150
                    radius: 12
                    color: "#12ffffff"
                    border.width: notas.activeFocus ? 2 : 1
                    border.color: notas.activeFocus ? raiz.cian : "#30ffffff"
                    Flickable {
                        id: rodillo
                        anchors.fill: parent
                        anchors.margins: 12
                        contentHeight: notas.implicitHeight
                        clip: true
                        TextEdit {
                            id: notas
                            width: rodillo.width
                            text: raiz.notasIniciales
                            color: "#ffffff"
                            selectionColor: raiz.cian
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            font { family: "Inter Display"; pixelSize: 15 }
                            // Se guarda sola un momento después de dejar de escribir.
                            onTextChanged: if (activeFocus) esperaNotas.restart()
                            Keys.onEscapePressed: focus = false
                        }
                    }
                    Text {
                        anchors { left: parent.left; top: parent.top; margins: 12 }
                        visible: notas.text === "" && !notas.activeFocus
                        text: "Haz clic y escribe: jefes pendientes, dónde quedaste…"
                        color: "#7d8299"
                        font { family: "Inter Display"; pixelSize: 14 }
                    }
                    Timer { id: esperaNotas; interval: 900; onTriggered: raiz.guardar(notas.text) }
                }

                Rectangle { width: parent.width; height: 1; color: "#22ffffff" }
                Titulo { text: "ASISTENTE" }
            }

            // ── Asistente: ocupa lo que queda hasta abajo ──
            Item {
                anchors { top: arriba.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 22; topMargin: 12 }

                Flickable {
                    id: hoja
                    anchors { top: parent.top; left: parent.left; right: parent.right; bottom: entrada.top; bottomMargin: 12 }
                    contentHeight: conversacion.implicitHeight
                    clip: true
                    // Sigue el final mientras la respuesta va llegando.
                    onContentHeightChanged: if (raiz.pensando) contentY = Math.max(0, contentHeight - height)

                    Column {
                        id: conversacion
                        width: hoja.width
                        spacing: 10

                        Text {
                            width: parent.width
                            visible: raiz.pregunta === "" && raiz.errorAsistente === ""
                            text: "Pregunta algo del juego sin soltarlo: Mod+Alt+P, escribe y Enter."
                                  + (raiz.conCaptura ? " La pregunta lleva una captura de lo que ves en el juego." : "")
                            color: "#8a8fa8"
                            wrapMode: Text.WordWrap
                            lineHeight: 1.2
                            font { family: "Inter Display"; pixelSize: 14 }
                        }
                        Text {
                            width: parent.width
                            visible: raiz.pregunta !== ""
                            text: raiz.pregunta
                            color: raiz.cian
                            wrapMode: Text.WordWrap
                            font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 15 }
                        }
                        Text {
                            width: parent.width
                            visible: raiz.respuesta !== ""
                            text: raiz.respuesta
                            textFormat: Text.MarkdownText
                            color: "#ffffff"
                            wrapMode: Text.WordWrap
                            lineHeight: 1.2
                            font { family: "Inter Display"; pixelSize: 16 }
                        }
                        Text {
                            visible: raiz.pensando && raiz.respuesta === ""
                            text: raiz.conCaptura ? "Mirando la captura y buscando…" : "Buscando…"
                            color: "#8a8fa8"
                            font { family: "Inter Display"; italic: true; pixelSize: 14 }
                        }
                        Text {
                            width: parent.width
                            visible: raiz.errorAsistente !== ""
                            text: raiz.errorAsistente
                            color: "#ffb4c8"
                            wrapMode: Text.WordWrap
                            font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 14 }
                        }
                        Column {
                            width: parent.width
                            visible: raiz.meta !== null
                            spacing: 3
                            Repeater {
                                model: raiz.meta ? raiz.meta.fuentes : []
                                Text {
                                    required property var modelData
                                    width: parent.width
                                    text: "↗ " + modelData.titulo
                                    color: "#9fd8ea"
                                    elide: Text.ElideRight
                                    font { family: "Inter Display"; pixelSize: 12 }
                                }
                            }
                            Text {
                                text: raiz.meta ? "≈ US$ " + raiz.meta.costo.toFixed(3).replace(".", ",")
                                      + "   ·   " + raiz.meta.busquedas + (raiz.meta.busquedas === 1 ? " búsqueda" : " búsquedas") : ""
                                color: "#6f7590"
                                font { family: "Inter Display"; pixelSize: 11 }
                            }
                        }
                    }
                }

                Rectangle {
                    id: entrada
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 46
                    radius: 12
                    color: "#1affffff"
                    border.width: campo.activeFocus ? 2 : 1
                    border.color: campo.activeFocus ? raiz.cian : "#40ffffff"
                    TextInput {
                        id: campo
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: "#ffffff"
                        selectionColor: raiz.cian
                        selectByMouse: true
                        font { family: "Inter Display"; pixelSize: 16 }
                        onAccepted: { raiz.preguntar(text); text = ""; focus = false }
                        Keys.onEscapePressed: { raiz.escribiendo = false; focus = false }
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        visible: campo.text === ""
                        text: raiz.pensando ? "Respondiendo…" : "Pregunta sobre el juego (Mod+Alt+P)"
                        color: "#7d8299"
                        font { family: "Inter Display"; pixelSize: 15 }
                    }
                    // Al tomar el teclado con el atajo, el cursor va directo aquí.
                    Connections {
                        target: raiz
                        function onEscribiendoChanged() {
                            if (raiz.escribiendo) campo.forceActiveFocus()
                            else campo.focus = false
                        }
                    }
                }
            }
        }
    }
}
