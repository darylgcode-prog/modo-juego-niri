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
//   MJC_SUPERPUESTO     «si» = una sola pantalla: va encima del juego, translúcido,
//                       oculto hasta que se pide, con la guía transmitida en vivo
//                       al lado (se usa con el ratón)
//   MJC_OPACIDAD        cuán opaco es cuando va superpuesto (30 a 100)
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
    readonly property bool superpuesto: Quickshell.env("MJC_SUPERPUESTO") === "si"
    readonly property real opacidad: Math.max(0.3, Math.min(1, (parseInt(Quickshell.env("MJC_OPACIDAD") || "88") || 88) / 100))
    // Superpuesto parte oculto, para no tapar el juego; se muestra con el atajo.
    property bool aLaVista: !superpuesto || prueba > 0
    property bool ocultoPorCaptura: false   // se quita un instante para no salir en la captura
    property bool editando: false           // superpuesto: estás escribiendo en las notas
    property string imagenGuia: ""          // la guía como imagen (solo superpuesto)
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
                if (raiz.superpuesto && raiz.aLaVista && raiz.imagenGuia === "")
                    transmitir()
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
        if (superpuesto) {
            imagenGuia = ""
            transmitir()
        }
    }

    // Órdenes a la pestaña de la guía, por su canal de depuración. Si la
    // guía cambió, se abre el canal de la nueva y lo pendiente de la
    // anterior se descarta.
    property var cola: []
    property int numeroOrden: 10
    function enviar(metodo, parametros) {
        const p = pestanaDe(guiaActual)
        if (!p || !p.webSocketDebuggerUrl)
            return
        const orden = { id: ++numeroOrden, method: metodo, params: parametros || {} }
        if (canal.url.toString() !== p.webSocketDebuggerUrl) {
            cola = []
            canal.active = false
            canal.url = p.webSocketDebuggerUrl
            canal.active = true
        } else if (canal.status !== WebSocket.Open && canal.status !== WebSocket.Connecting) {
            canal.active = false
            canal.active = true
        }
        if (canal.status === WebSocket.Open)
            canal.sendTextMessage(JSON.stringify(orden))
        else
            cola = cola.concat([orden])
    }

    function desplazar(cuanto) {
        enviar("Runtime.evaluate", { expression:
            "window.scrollBy({top: " + cuanto + ", behavior: '" + (superpuesto ? "instant" : "smooth") + "'})" })
    }

    // ── Superpuesto: la guía se ve y se usa a distancia ───────────────
    // No hay ventana de navegador: la página corre sin ventana, transmite
    // lo que dibuja y recibe de vuelta el ratón y el teclado.
    property int anchoGuia: 0       // tamaño del espacio donde se dibuja la guía
    property int altoGuia: 0
    property bool enGuia: false     // el teclado va a la página (Esc lo devuelve)
    property int cuadros: 0         // imágenes recibidas (para medir en las pruebas)
    property real ultimoMovimiento: 0

    function transmitir() {
        if (!superpuesto || !aLaVista || anchoGuia < 100 || altoGuia < 100 || !pestanaDe(guiaActual))
            return
        // La página se dibuja al tamaño exacto del espacio: nítida, y con
        // el ratón cayendo donde se hace clic.
        enviar("Emulation.setDeviceMetricsOverride", { width: anchoGuia, height: altoGuia, deviceScaleFactor: 1, mobile: false })
        enviar("Page.bringToFront")
        enviar("Page.startScreencast", { format: "jpeg", quality: 78, everyNthFrame: 1 })
    }
    onALaVistaChanged: {
        if (!superpuesto)
            return
        if (aLaVista) {
            transmitir()
        } else {
            enGuia = false
            enviar("Page.stopScreencast")
        }
    }
    onAnchoGuiaChanged: transmitir()
    onAltoGuiaChanged: transmitir()
    // Mientras no llegue la primera imagen (la página todavía carga), se insiste.
    Timer { interval: 2500; running: raiz.superpuesto && raiz.aLaVista && raiz.imagenGuia === ""; repeat: true; onTriggered: raiz.transmitir() }

    function raton(tipo, x, y, apretado) {
        enviar("Input.dispatchMouseEvent", {
            type: tipo, x: Math.round(x), y: Math.round(y),
            button: tipo === "mouseMoved" ? (apretado ? "left" : "none") : "left",
            buttons: apretado ? 1 : 0, clickCount: tipo === "mouseMoved" ? 0 : 1 })
    }
    function ratonMovido(x, y, apretado) {
        // Sin apretar basta de vez en cuando (para que la página resalte lo
        // que hay bajo el puntero); arrastrando, todos los movimientos.
        const ahora = Date.now()
        if (!apretado && ahora - ultimoMovimiento < 60)
            return
        ultimoMovimiento = ahora
        raton("mouseMoved", x, y, apretado)
    }
    function rueda(x, y, dx, dy) {
        enviar("Input.dispatchMouseEvent", { type: "mouseWheel", x: Math.round(x), y: Math.round(y), deltaX: -dx, deltaY: -dy })
    }
    // Una tecla hacia la página: el texto va tal cual; las de control, por nombre.
    readonly property var teclasEspeciales: ({
        [Qt.Key_Backspace]: ["Backspace", 8], [Qt.Key_Tab]: ["Tab", 9], [Qt.Key_Return]: ["Enter", 13],
        [Qt.Key_Enter]: ["Enter", 13], [Qt.Key_PageUp]: ["PageUp", 33], [Qt.Key_PageDown]: ["PageDown", 34],
        [Qt.Key_End]: ["End", 35], [Qt.Key_Home]: ["Home", 36], [Qt.Key_Left]: ["ArrowLeft", 37],
        [Qt.Key_Up]: ["ArrowUp", 38], [Qt.Key_Right]: ["ArrowRight", 39], [Qt.Key_Down]: ["ArrowDown", 40],
        [Qt.Key_Delete]: ["Delete", 46]
    })
    function tecla(codigo, texto) {
        const especial = teclasEspeciales[codigo]
        if (especial) {
            const base = { key: especial[0], code: especial[0], windowsVirtualKeyCode: especial[1], nativeVirtualKeyCode: especial[1] }
            enviar("Input.dispatchKeyEvent", Object.assign({ type: especial[0] === "Enter" ? "keyDown" : "rawKeyDown" },
                                                           base, especial[0] === "Enter" ? { text: "\r" } : {}))
            enviar("Input.dispatchKeyEvent", Object.assign({ type: "keyUp" }, base))
        } else if (texto !== "" && texto.charCodeAt(0) >= 32) {
            enviar("Input.insertText", { text: texto })
        }
    }

    WebSocket {
        id: canal
        active: false
        onStatusChanged: {
            if (canal.status === WebSocket.Open) {
                const pendientes = raiz.cola
                raiz.cola = []
                pendientes.forEach(orden => sendTextMessage(JSON.stringify(orden)))
            }
        }
        onTextMessageReceived: mensaje => {
            try {
                const m = JSON.parse(mensaje)
                if (m.method === "Page.screencastFrame") {
                    raiz.cuadros++
                    raiz.imagenGuia = "data:image/jpeg;base64," + m.params.data
                    // Sin este acuse el navegador no manda la imagen siguiente.
                    raiz.enviar("Page.screencastFrameAck", { sessionId: m.params.sessionId })
                }
            } catch (e) {}
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
        if (superpuesto && orden.indexOf("--captura") >= 0) {
            // Va encima del juego: se quita un instante para no salir en la captura.
            ocultoPorCaptura = true
            esperaCaptura.start()
        } else {
            procPreguntar.stdinEnabled = true
            procPreguntar.running = true
        }
    }
    Timer {
        id: esperaCaptura
        interval: 220
        onTriggered: { procPreguntar.stdinEnabled = true; procPreguntar.running = true; vueltaCaptura.start() }
    }
    Timer { id: vueltaCaptura; interval: 900; onTriggered: raiz.ocultoPorCaptura = false }

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
        function alternar(): void {
            raiz.aLaVista = !raiz.aLaVista
            if (!raiz.aLaVista) {
                raiz.escribiendo = false
                raiz.editando = false
                raiz.enGuia = false
            }
        }
        function preguntar(): void { raiz.aLaVista = true; raiz.escribiendo = !raiz.escribiendo }
    }

    Component.onCompleted: {
        try { guias = JSON.parse(Quickshell.env("MJC_GUIAS") || "[]") } catch (e) { guias = [] }
        notasIniciales = archivoNotas !== "" ? notasGuardadas.text() : ""
    }

    Timer { interval: Math.max(1, raiz.prueba) * 1000; running: raiz.prueba > 0; onTriggered: Qt.quit() }
    // Solo en modo prueba: un clic, una vuelta de rueda y texto hacia la guía.
    Timer {
        interval: 6000
        running: raiz.prueba > 0 && Quickshell.env("MJC_PRUEBA_ENTRADA") === "1"
        onTriggered: {
            // Primero el texto: el clic de después le quita el foco al campo.
            raiz.tecla(0, "a")
            raiz.tecla(0, "b")
            raiz.tecla(0, "c")
            raiz.tecla(Qt.Key_Backspace, "")
            raiz.raton("mousePressed", 300, 400, true)
            raiz.raton("mouseReleased", 300, 400, false)
            raiz.rueda(300, 400, 0, -360)
        }
    }
    // Solo en modo prueba: pasea el puntero por la guía, como haría una mano.
    Timer {
        property int paso: 0
        interval: 30
        repeat: true
        running: raiz.prueba > 0 && Quickshell.env("MJC_PRUEBA_PASEO") === "1" && raiz.imagenGuia !== ""
        onTriggered: {
            paso++
            raiz.raton("mouseMoved", 120 + (paso * 9) % 700, 140 + (paso * 5) % 800, false)
            if (paso % 25 === 0)
                raiz.rueda(400, 500, 0, paso % 50 === 0 ? 240 : -240)
        }
    }
    // Solo en modo prueba: hace una pregunta sin teclado.
    Timer {
        interval: 400
        running: raiz.prueba > 0 && !!Quickshell.env("MJC_PRUEBA_PREGUNTA")
        onTriggered: raiz.preguntar(Quickshell.env("MJC_PRUEBA_PREGUNTA"))
    }

    PanelWindow {
        id: franja
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("MJC_PANTALLA")) || Quickshell.screens[Quickshell.screens.length - 1]
        // Con dos pantallas es una franja que le deja el resto al navegador.
        // Superpuesto cubre la pantalla del juego, pero solo se ve (y solo
        // recibe clics) donde hay contenido.
        anchors { top: true; bottom: true; left: true; right: raiz.superpuesto }
        implicitWidth: 460
        exclusionMode: raiz.superpuesto ? ExclusionMode.Ignore : ExclusionMode.Normal
        exclusiveZone: raiz.superpuesto ? 0 : implicitWidth
        color: "transparent"
        visible: raiz.aLaVista && !raiz.ocultoPorCaptura
        mask: Region { item: contenido }

        WlrLayershell.namespace: "modo-juego-companero"
        WlrLayershell.layer: raiz.superpuesto ? WlrLayer.Overlay : WlrLayer.Top
        // Toma el teclado solo cuando vas a preguntar o a escribir una nota.
        // Con dos pantallas, para las notas basta un clic. Superpuesto no
        // toma nada por su cuenta: mostrarlo no debe sacarte del juego.
        WlrLayershell.keyboardFocus: raiz.prueba > 0 ? WlrKeyboardFocus.None
            : (raiz.escribiendo || raiz.editando || raiz.enGuia) ? WlrKeyboardFocus.Exclusive
            : raiz.superpuesto ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand

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

        Item {
            id: contenido
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: fondo.width + (visor.visible ? visor.width : 0)
            opacity: raiz.superpuesto ? raiz.opacidad : 1

            // La guía, en vivo (solo superpuesto): se ve y se usa con el ratón.
            Rectangle {
                id: visor
                visible: raiz.superpuesto && raiz.guias.length > 0
                anchors { left: parent.left; leftMargin: 460; top: parent.top; bottom: parent.bottom }
                width: Math.max(0, Math.min(franja.width - 460, Math.round(franja.height * 0.85)))
                color: "#f5070610"
                Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Qt.alpha(raiz.cian, 0.45) }

                Text {
                    id: rotuloGuia
                    anchors { left: parent.left; top: parent.top; leftMargin: 16; topMargin: 15 }
                    text: raiz.guias[raiz.guiaActual] ? raiz.guias[raiz.guiaActual].titulo.toUpperCase() : ""
                    color: raiz.cian
                    font { family: "Inter Display"; weight: Font.Bold; pixelSize: 12; letterSpacing: 3 }
                }
                // Para escribir en la página (el buscador de una wiki) hay que
                // prestarle el teclado; Esc lo devuelve al juego.
                Rectangle {
                    id: botonEscribir
                    anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 8 }
                    height: 28; width: textoEscribir.implicitWidth + 26; radius: 14
                    color: raiz.enGuia ? Qt.alpha(raiz.cian, 0.35) : (zonaEscribir.containsMouse ? "#2effffff" : "#14ffffff")
                    border.width: 1
                    border.color: raiz.enGuia ? raiz.cian : "#40ffffff"
                    Text {
                        id: textoEscribir
                        anchors.centerIn: parent
                        text: raiz.enGuia ? "ESCRIBIENDO EN LA PÁGINA   ·   ESC TERMINA" : "ESCRIBIR EN LA PÁGINA"
                        color: "#ffffff"
                        font { family: "Inter Display"; weight: Font.Bold; pixelSize: 11; letterSpacing: 1 }
                    }
                    MouseArea {
                        id: zonaEscribir
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: raiz.enGuia = !raiz.enGuia
                    }
                }
                Text {
                    anchors { right: botonEscribir.left; rightMargin: 14; verticalCenter: botonEscribir.verticalCenter }
                    text: "Mod+Alt+C oculta"
                    color: "#8a8fa8"
                    font { family: "Inter Display"; pixelSize: 12 }
                }

                Item {
                    id: lienzo
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom
                              leftMargin: 10; rightMargin: 11; topMargin: 44; bottomMargin: 10 }
                    // El navegador dibuja la página a este mismo tamaño.
                    onWidthChanged: raiz.anchoGuia = Math.round(width)
                    onHeightChanged: raiz.altoGuia = Math.round(height)
                    Component.onCompleted: { raiz.anchoGuia = Math.round(width); raiz.altoGuia = Math.round(height) }
                    clip: true

                    // Dos capas que se turnan. La imagen nueva carga en la de
                    // atrás y pasa al frente recién cuando está lista: si se
                    // cambiara en el mismo recuadro, quedaría vacío un instante
                    // cada vez, y con el puntero encima eso es un parpadeo
                    // continuo. Si llegan imágenes más rápido de lo que cargan,
                    // se salta a la más nueva.
                    property int frente: 0          // 0 = capaA, 1 = capaB
                    property bool cargando: false
                    property string enEspera: ""

                    function poner(datos) {
                        if (cargando) {
                            enEspera = datos
                            return
                        }
                        cargando = true
                        if (frente === 0) capaB.source = datos
                        else capaA.source = datos
                    }
                    function lista(cual) {
                        frente = cual
                        cargando = false
                        if (enEspera !== "") {
                            const datos = enEspera
                            enEspera = ""
                            poner(datos)
                        }
                    }
                    function fallo() {
                        cargando = false
                        enEspera = ""
                    }
                    Connections {
                        target: raiz
                        function onImagenGuiaChanged() {
                            if (raiz.imagenGuia !== "") {
                                lienzo.poner(raiz.imagenGuia)
                            } else {
                                // Otra guía: se limpia para mostrar «Cargando».
                                lienzo.cargando = false
                                lienzo.enEspera = ""
                                capaA.source = ""
                                capaB.source = ""
                            }
                        }
                    }
                    Image {
                        id: capaA
                        anchors.fill: parent
                        z: lienzo.frente === 0 ? 1 : 0
                        fillMode: Image.Stretch
                        cache: false
                        onStatusChanged: {
                            if (status === Image.Ready && lienzo.cargando && lienzo.frente === 1) lienzo.lista(0)
                            else if (status === Image.Error) lienzo.fallo()
                        }
                    }
                    Image {
                        id: capaB
                        anchors.fill: parent
                        z: lienzo.frente === 1 ? 1 : 0
                        fillMode: Image.Stretch
                        cache: false
                        onStatusChanged: {
                            if (status === Image.Ready && lienzo.cargando && lienzo.frente === 0) lienzo.lista(1)
                            else if (status === Image.Error) lienzo.fallo()
                        }
                    }
                    // Solo en modo prueba: mide si la capa del frente queda
                    // alguna vez sin imagen (eso es lo que se vería parpadear).
                    property int muestras: 0
                    property int enBlanco: 0
                    Timer {
                        interval: 8
                        repeat: true
                        running: raiz.prueba > 0 && raiz.imagenGuia !== ""
                        onTriggered: {
                            const delFrente = lienzo.frente === 0 ? capaA : capaB
                            lienzo.muestras++
                            if (delFrente.status !== Image.Ready)
                                lienzo.enBlanco++
                        }
                    }
                    Timer {
                        interval: Math.max(500, raiz.prueba * 1000 - 600)
                        running: raiz.prueba > 0
                        onTriggered: console.warn("PARPADEO muestras=" + lienzo.muestras + " en-blanco=" + lienzo.enBlanco + " imagenes-recibidas=" + raiz.cuadros)
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: raiz.imagenGuia === ""
                        text: "Cargando la guía…"
                        color: "#8a8fa8"
                        font { family: "Inter Display"; italic: true; pixelSize: 15 }
                    }
                    // El ratón sobre la guía va a la página: clic, arrastre y rueda.
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        onPressed: m => raiz.raton("mousePressed", m.x, m.y, true)
                        onReleased: m => raiz.raton("mouseReleased", m.x, m.y, false)
                        onPositionChanged: m => raiz.ratonMovido(m.x, m.y, pressed)
                        onWheel: w => raiz.rueda(w.x, w.y, w.angleDelta.x, w.angleDelta.y)
                    }
                    // Con «escribir en la página» activo, las teclas van a ella.
                    Item {
                        id: tecladoGuia
                        focus: raiz.enGuia
                        Keys.onPressed: ev => {
                            if (ev.key === Qt.Key_Escape)
                                raiz.enGuia = false
                            else
                                raiz.tecla(ev.key, ev.text)
                            ev.accepted = true
                        }
                        Connections {
                            target: raiz
                            function onEnGuiaChanged() { if (raiz.enGuia) tecladoGuia.forceActiveFocus() }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: fondo
            parent: contenido
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 460
            color: "#f5070610"
            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Qt.alpha(raiz.cian, 0.45) }

            // Foto de lo que dibuja la franja, solo para pruebas.
            Timer {
                interval: parseInt(Quickshell.env("MJC_FOTO_MS") || "1600")
                running: raiz.prueba > 0 && !!Quickshell.env("MJC_FOTO")
                onTriggered: contenido.grabToImage(r => r.saveToFile(Quickshell.env("MJC_FOTO")))
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
                                + (raiz.superpuesto ? "     Mod+Alt+C  oculta todo" : "")
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
                            Keys.onEscapePressed: { focus = false; raiz.editando = false }
                        }
                    }
                    // Superpuesto, el primer clic sobre las notas pide el teclado
                    // (Esc lo devuelve al juego).
                    MouseArea {
                        anchors.fill: parent
                        enabled: raiz.superpuesto && !raiz.editando
                        cursorShape: Qt.IBeamCursor
                        onClicked: { raiz.editando = true; notas.forceActiveFocus() }
                    }
                    Text {
                        anchors { left: parent.left; top: parent.top; margins: 12 }
                        visible: notas.text === "" && !notas.activeFocus
                        text: raiz.superpuesto ? "Haz clic y escribe; Esc vuelve al juego."
                                               : "Haz clic y escribe: jefes pendientes, dónde quedaste…"
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

    // Superpuesto parte oculto: un aviso chico, unos segundos, dice que
    // está listo y con qué atajo se ve.
    PanelWindow {
        screen: franja.screen
        anchors { top: true; left: true }
        margins { top: 24; left: 24 }
        implicitWidth: pista.implicitWidth + 36
        implicitHeight: 40
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: raiz.superpuesto && raiz.prueba === 0 && !raiz.aLaVista && raiz.segundos < 7
        mask: Region {}
        WlrLayershell.namespace: "modo-juego-companero-aviso"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "#e6070610"
            border.width: 1
            border.color: Qt.alpha(raiz.cian, 0.6)
            Text {
                id: pista
                anchors.centerIn: parent
                text: "Compañero listo   ·   Mod+Alt+C lo muestra y lo oculta"
                color: "#ffffff"
                font { family: "Inter Display"; weight: Font.DemiBold; pixelSize: 14 }
            }
        }
    }
}
