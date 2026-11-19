//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Entrada épica, lanzador y secuencia de salida del modo juego. Lo abre
// el script «modo-juego».
//
// Variables de entorno:
//   MJ_MODO       intro (animación y después lanzador) | lanzador | salida
//   MJ_PANTALLA   nombre de la pantalla donde va el lanzador (p. ej. eDP-1)
//   MJ_CATALOGO   JSON que arma modo-juego-catalogo
//   MJ_RESULTADO  archivo donde el script va dejando cuánto cerró y liberó
//   MJ_RESUMEN    JSON con el resumen de la sesión, para la salida
//   MJ_SONIDO     «no» = sin sonido
//   MJ_TECLADO    «si» = el golpe de la entrada también destella el teclado
//   MJ_GPU        nombre corto de la tarjeta de video, para la entrada
//   MJ_PRUEBA     segundos: se cierra solo, sin tomar el teclado ni lanzar nada
//   MJ_AJUSTES    «1» = abre directo en la pantalla de ajustes
ShellRoot {
    id: raiz

    readonly property string modo: Quickshell.env("MJ_MODO") || "intro"
    readonly property int prueba: parseInt(Quickshell.env("MJ_PRUEBA") || "0")
    readonly property string gpu: Quickshell.env("MJ_GPU") || ""
    readonly property string pantallaPedida: Quickshell.env("MJ_PANTALLA") || ""
    // Si la pantalla pedida no existe, el lanzador va en la primera.
    readonly property string pantallaPrincipal: {
        const nombres = Quickshell.screens.map(s => s.name)
        return nombres.indexOf(pantallaPedida) >= 0 ? pantallaPedida : (nombres[0] || "")
    }

    property var catalogo: ({ juegos: [], lanzadores: [], emuladores: [] })
    property var resumen: ({ minutos: 0, partidas: [], vuelven: [] })
    property int memLibre: 0
    property int liberados: -1
    property int cerrados: 0
    property bool listo: false       // el script ya terminó de cerrar
    property string aviso: ""
    property bool enMarcha: false
    property bool cerrando: false

    signal pedirSalida(bool conDestello)
    signal mando(string cual)

    readonly property bool conSonido: Quickshell.env("MJ_SONIDO") !== "no" && ajustes.sonido !== false

    function tocar(archivo, volumen) {
        if (conSonido)
            Quickshell.execDetached(["pw-play", "--volume", String(volumen), Quickshell.shellDir + "/sonido/" + archivo])
    }

    // Sonidos cortos de la interfaz.
    function sonar(cual) {
        if (cual === "mover")
            tocar("mover.wav", 0.4)
    }

    function impacto() {
        if (prueba === 0 && Quickshell.env("MJ_TECLADO") === "si")
            Quickshell.execDetached(["modo-juego", "teclado-impacto"])
    }

    function lanzar(item, fila) {
        if (cerrando)
            return
        // «modo-juego jugar» lanza, espera a que termine y anota la partida.
        if (prueba === 0)
            Quickshell.execDetached(["niri", "msg", "action", "spawn", "--", "modo-juego", "jugar", fila, item.id])
        tocar("lanzar.wav", 0.55)
        cerrar(true)
    }

    function cerrar(conDestello) {
        cerrando = true
        pedirSalida(conDestello)
    }

    function salirModo() {
        if (cerrando)
            return
        if (prueba === 0)
            Quickshell.execDetached(["modo-juego", "desactivar"])
        cerrar(false)
    }

    function terminar() { Qt.quit() }

    // ── Ajustes (pantalla F2 del lanzador) ────────────────────────────
    readonly property bool abrirEnAjustes: Quickshell.env("MJ_AJUSTES") === "1"
    property var ajustes: ({ sonido: true, animacion: true, caratulasAuto: true, teclado: true, noMolestar: true,
                             apagarPantallas: false, hud: true, clave: false, hayTeclado: true, hayHud: true })
    property string mensajeClave: ""
    property bool claveBien: false
    property bool guardando: false
    property bool buscando: false
    property string registroCaratulas: ""

    function ponerAjuste(nombre, valor) {
        if (procPoner.running)
            return
        procPoner.command = ["modo-juego", "ajuste", nombre, valor ? "si" : "no"]
        procPoner.running = true
    }

    // La clave va por la entrada estándar del script, no como argumento:
    // así no queda a la vista en la lista de procesos.
    function guardarClave(texto) {
        if (guardando)
            return
        guardando = true
        mensajeClave = ""
        procClave.pendiente = texto
        procClave.stdinEnabled = true
        procClave.running = true
    }

    function quitarClave() {
        if (!procQuitar.running)
            procQuitar.running = true
    }

    // Asistente del compañero: clave de Anthropic y modelo.
    property string mensajeClaveIa: ""
    property bool claveIaBien: false
    property bool guardandoIa: false

    function guardarClaveIa(texto) {
        if (guardandoIa)
            return
        guardandoIa = true
        mensajeClaveIa = ""
        procClaveIa.pendiente = texto
        procClaveIa.stdinEnabled = true
        procClaveIa.running = true
    }

    function quitarClaveIa() {
        if (!procQuitarIa.running)
            procQuitarIa.running = true
    }

    function ponerModelo(nombre) {
        if (procPoner.running)
            return
        procPoner.command = ["modo-juego", "ajuste", "ASISTENTE_MODELO", nombre]
        procPoner.running = true
    }

    function buscarCaratulas() {
        if (buscando)
            return
        buscando = true
        registroCaratulas = "Buscando…"
        procBuscar.running = true
    }

    function abrirPaginaClave() {
        if (prueba === 0)
            Quickshell.execDetached(["xdg-open", "https://www.steamgriddb.com/profile/preferences/api"])
        cerrar(false)
    }

    Process {
        id: procAjustes
        command: ["modo-juego", "ajustes"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { raiz.ajustes = JSON.parse(text) } catch (e) { console.warn("modo-juego: ajustes ilegibles:", text) }
            }
        }
    }
    Process { id: procPoner; onExited: procAjustes.running = true }
    Process {
        id: procClave
        property string pendiente: ""
        command: ["modo-juego", "guardar-clave"]
        stdinEnabled: true
        onStarted: {
            write(pendiente + "\n")
            pendiente = ""
            stdinEnabled = false
        }
        stdout: StdioCollector { onStreamFinished: raiz.mensajeClave = text.trim() }
        onExited: (codigo, estado) => {
            raiz.guardando = false
            raiz.claveBien = codigo === 0
            procAjustes.running = true
            if (codigo === 0)
                raiz.buscarCaratulas()
        }
    }
    Process {
        id: procClaveIa
        property string pendiente: ""
        command: ["modo-juego", "guardar-clave-ia"]
        stdinEnabled: true
        onStarted: {
            write(pendiente + "\n")
            pendiente = ""
            stdinEnabled = false
        }
        stdout: StdioCollector { onStreamFinished: raiz.mensajeClaveIa = text.trim() }
        onExited: (codigo, estado) => {
            raiz.guardandoIa = false
            raiz.claveIaBien = codigo === 0
            procAjustes.running = true
        }
    }
    Process {
        id: procQuitarIa
        command: ["modo-juego", "quitar-clave-ia"]
        onExited: { raiz.mensajeClaveIa = "Clave quitada."; raiz.claveIaBien = true; procAjustes.running = true }
    }
    Process {
        id: procQuitar
        command: ["modo-juego", "quitar-clave"]
        onExited: { raiz.mensajeClave = "Clave quitada."; raiz.claveBien = true; procAjustes.running = true }
    }
    Process {
        id: procBuscar
        command: ["modo-juego", "caratulas"]
        stdout: StdioCollector { onStreamFinished: raiz.registroCaratulas = text.trim() }
        onExited: {
            raiz.buscando = false
            archivoCatalogo.reload()
        }
    }

    // ── Trucos del juego elegido (F3) ─────────────────────────────────
    property var trucos: ({ disponible: false, trucos: [], motivo: "", juego: "" })
    property string errorTruco: ""
    property string juegoDeTrucos: ""
    readonly property bool trucosOcupado: procPonerTruco.running

    function pedirTrucos(id) {
        if (id !== juegoDeTrucos) {
            trucos = { disponible: false, trucos: [], motivo: "", juego: "" }
            errorTruco = ""
        }
        juegoDeTrucos = id
        if (procTrucos.running)
            return
        procTrucos.command = ["modo-juego-trucos", "listar", id]
        procTrucos.running = true
    }

    function ponerTruco(clave, activo, opcion) {
        if (procPonerTruco.running || juegoDeTrucos === "")
            return
        const orden = ["modo-juego-trucos", "poner", juegoDeTrucos, clave, activo ? "si" : "no"]
        if (opcion !== "")
            orden.push("--opcion", opcion)
        errorTruco = ""
        procPonerTruco.command = orden
        procPonerTruco.running = true
    }

    Process {
        id: procTrucos
        stdout: StdioCollector {
            onStreamFinished: {
                try { raiz.trucos = JSON.parse(text) } catch (e) { console.warn("modo-juego: trucos ilegibles:", text) }
            }
        }
    }
    Process {
        id: procPonerTruco
        stdout: StdioCollector { onStreamFinished: raiz.errorTruco = text.trim() }
        // Después de cada cambio se relee, para mostrar lo que quedó de verdad.
        onExited: raiz.pedirTrucos(raiz.juegoDeTrucos)
    }

    // ── Datos ─────────────────────────────────────────────────────────
    FileView {
        id: archivoCatalogo
        path: Quickshell.env("MJ_CATALOGO") || (Quickshell.env("HOME") + "/.cache/modo-juego/catalogo.json")
        blockLoading: true
        // Después de buscar carátulas el catálogo cambia: se relee.
        onLoaded: raiz.leerCatalogo()
    }

    function leerCatalogo() {
        try {
            catalogo = JSON.parse(archivoCatalogo.text())
        } catch (e) {
            console.warn("modo-juego: no pude leer el catálogo:", e)
        }
    }

    FileView {
        id: archivoResumen
        path: raiz.modo === "salida" ? (Quickshell.env("MJ_RESUMEN") || "") : ""
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        leerCatalogo()
        if (modo === "salida") {
            try { resumen = JSON.parse(archivoResumen.text()) } catch (e) { console.warn("modo-juego: sin resumen:", e) }
        }
    }

    // Memoria libre en vivo y lo que el script va informando.
    Process {
        id: sonda
        command: ["sh", "-c", "awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo; cat \"${MJ_RESULTADO:-/no-existe}\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lineas = text.trim().split("\n")
                raiz.memLibre = parseInt(lineas[0]) || 0
                if (lineas.length < 2)
                    return
                try {
                    const p = JSON.parse(lineas.slice(1).join("\n"))
                    raiz.cerrados = p.cerrados || 0
                    raiz.listo = p.listo === true
                    raiz.aviso = p.aviso || ""
                    if (raiz.listo)
                        raiz.liberados = p.liberados || 0
                } catch (e) {}
            }
        }
    }
    // Más seguido mientras el script todavía está cerrando cosas.
    Timer {
        interval: raiz.modo === "intro" && !raiz.listo ? 400 : 1500
        running: raiz.modo !== "salida"
        repeat: true
        triggeredOnStart: true
        onTriggered: sonda.running = true
    }

    // El mando: un ayudante lo traduce a acciones, una por línea.
    Process {
        command: ["modo-juego-mando"]
        running: raiz.modo !== "salida"
        stdout: SplitParser { onRead: linea => raiz.mando(linea.trim()) }
    }

    // Pequeña espera para que las ventanas ya estén en pantalla: así el
    // golpe del sonido cae junto con el de la imagen en todas.
    Timer {
        interval: 180; running: true
        onTriggered: {
            raiz.enMarcha = true
            if (raiz.modo === "intro")
                raiz.tocar("activar.wav", 0.6)
            else if (raiz.modo === "salida")
                raiz.tocar("salida.wav", 0.55)
        }
    }

    Timer { interval: Math.max(1, raiz.prueba) * 1000; running: raiz.prueba > 0; onTriggered: Qt.quit() }

    // Solo en modo prueba (MJ_PRUEBA): acciona los ajustes sin teclado,
    // para poder comprobar que guardar, cambiar y buscar funcionan.
    Timer {
        interval: 2200
        running: raiz.prueba > 0
        onTriggered: {
            const clave = Quickshell.env("MJ_PRUEBA_CLAVE"), ajuste = Quickshell.env("MJ_PRUEBA_AJUSTE")
            if (clave) raiz.guardarClave(clave)
            if (ajuste) raiz.ponerAjuste(ajuste.split("=")[0], ajuste.split("=")[1] === "si")
            if (Quickshell.env("MJ_PRUEBA_BUSCAR") === "1") raiz.buscarCaratulas()
            if (Quickshell.env("MJ_PRUEBA_CLAVE_IA")) raiz.guardarClaveIa(Quickshell.env("MJ_PRUEBA_CLAVE_IA"))
            // «id|clave»: pide los trucos de ese juego y enciende uno.
            const truco = (Quickshell.env("MJ_PRUEBA_TRUCO") || "").split("|")
            if (truco.length === 2) {
                raiz.pedirTrucos(truco[0])
                pruebaTruco.clave = truco[1]
                pruebaTruco.start()
            }
        }
    }

    Timer { id: pruebaTruco; property string clave: ""; interval: 1200; onTriggered: raiz.ponerTruco(clave, true, "") }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: ventana
            required property var modelData
            readonly property bool principal: modelData.name === raiz.pantallaPrincipal

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            visible: !escena.acabada

            WlrLayershell.namespace: "modo-juego"
            WlrLayershell.layer: WlrLayer.Overlay
            // La salida no pide nada: no toma el teclado.
            // (En las pruebas no se toma, salvo que la prueba sea justo del teclado.)
            WlrLayershell.keyboardFocus: principal && raiz.modo !== "salida"
                                         && (raiz.prueba === 0 || Quickshell.env("MJ_PRUEBA_TECLADO") === "1")
                                         ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Escena {
                id: escena
                anchors.fill: parent
                principal: ventana.principal
                centro: raiz
            }

            Connections {
                target: raiz
                function onEnMarchaChanged() { escena.empezar() }
                function onPedirSalida(conDestello) { escena.salir(conDestello && ventana.principal) }
                function onMando(cual) { if (ventana.principal) escena.accionMando(cual) }
            }
        }
    }
}
