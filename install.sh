#!/usr/bin/env bash
# Instala el modo juego para niri en tu carpeta personal.
#
#   ./install.sh                    instala; si falta algo, te pregunta si lo instala
#   ./install.sh --si               responde que sí a todo (lo necesario y lo recomendado)
#   ./install.sh --sin-dependencias no instala paquetes: solo dice qué falta
#   ./install.sh --asistente        además prepara el asistente con IA (crea un
#                                   entorno de Python y baja el paquete de Anthropic)
#   ./install.sh --actualizar       baja la última versión del repositorio y la instala
#                                   (lo mismo que hace «modo-juego actualizar»)
#
# Los programas van a tu carpeta personal, sin sudo. Lo único que pide tu
# contraseña es instalar paquetes del sistema, y solo si dices que sí.
# Volver a ejecutarlo actualiza los programas y la interfaz, y deja tu
# configuración (~/.config/modo-juego) como esté.
set -euo pipefail

AQUI=$(cd "$(dirname "$0")" && pwd)
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATOS="${XDG_DATA_HOME:-$HOME/.local/share}"
CON_ASISTENTE=no
ACTUALIZAR=no
DEPENDENCIAS=preguntar      # preguntar | si | no
RESTO=()

for arg in "$@"; do
  [[ $arg == --actualizar ]] || RESTO+=("$arg")
  case $arg in
    --actualizar) ACTUALIZAR=si ;;
    --asistente) CON_ASISTENTE=si ;;
    --si) DEPENDENCIAS=si ;;
    --sin-dependencias) DEPENDENCIAS=no ;;
    -h | --help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "No conozco la opción «$arg». Prueba con --help." >&2; exit 2 ;;
  esac
done

hay() { command -v "$1" >/dev/null 2>&1; }

# ── Actualizar: traer lo nuevo y seguir con el instalador que llegó ──
if [[ $ACTUALIZAR = si ]]; then
  if ! hay git || [[ ! -d $AQUI/.git ]]; then
    echo "Esta carpeta no es un repositorio de git: no puedo traer lo nuevo." >&2
    echo "Baja la última versión del proyecto y ejecuta su ./install.sh" >&2
    exit 1
  fi
  antes=$(git -C "$AQUI" rev-parse --short HEAD)
  echo "== Buscando lo nuevo =="
  if ! git -C "$AQUI" pull --ff-only; then
    echo "No pude traer lo nuevo (mira el mensaje de git arriba). No cambié nada." >&2
    exit 1
  fi
  despues=$(git -C "$AQUI" rev-parse --short HEAD)
  if [[ $antes == "$despues" ]]; then
    echo "Ya tenías lo último ($despues). Reinstalo igual, por si lo instalado quedó atrás."
  else
    echo "De $antes a $despues:"
    git -C "$AQUI" log --format='  · %s' "$antes..$despues"
  fi
  echo
  # El propio instalador pudo cambiar: se sigue con el que acaba de llegar.
  exec "$AQUI/install.sh" ${RESTO[@]+"${RESTO[@]}"}
fi

# ── Con qué se instalan paquetes en este sistema ─────────────────────
GESTOR=''
if hay pacman; then
  GESTOR=pacman
elif hay apt-get; then
  GESTOR=apt
elif hay dnf; then
  GESTOR=dnf
fi

# Lo que se necesita. Una línea por cosa:
#   cómo se comprueba | clase | para qué | paquete en pacman | apt | dnf
# Clases: necesario (sin esto no funciona), recomendado (se ofrece instalar),
# aparte (no se instala solo: depende de tu equipo o puede chocar con algo).
# La comprobación es un programa, o «py:módulo» o «fuente:nombre».
# Un guion en el paquete = en ese sistema hay que instalarlo a mano.
# Los nombres de pacman están comprobados; los de apt y dnf no.
REQUISITOS='
niri|necesario|el escritorio para el que está hecho|niri|-|-
qs|necesario|Quickshell: la animación, el lanzador y el compañero|quickshell|-|-
jq|necesario|lo usa el script en todas partes|jq|jq|jq
python3|necesario|el catálogo de juegos y las carátulas|python|python3|python3
magick|necesario|ImageMagick: convierte iconos y carátulas|imagemagick|imagemagick|ImageMagick
pw-play|recomendado|los sonidos|pipewire-audio|pipewire-bin|pipewire-utils
notify-send|recomendado|avisos cuando no hay animación|libnotify|libnotify-bin|libnotify
grim|recomendado|la captura que acompaña las preguntas al asistente|grim|grim|grim
py:evdev|recomendado|manejar el lanzador con mando|python-evdev|python3-evdev|python3-evdev
mangohud|recomendado|contador de FPS en los juegos|mangohud|mangohud|mangohud
fuente:Inter|recomendado|la letra con que está diseñado|inter-font|fonts-inter|rsms-inter-fonts
powerprofilesctl|aparte|perfil de rendimiento al jugar (choca con TLP)|power-profiles-daemon|power-profiles-daemon|power-profiles-daemon
asusctl|aparte|que el teclado reaccione (solo portátiles ASUS)|-|-|-
dms|aparte|«no molestar» (solo con DankMaterialShell)|-|-|-
'

esta() {   # ¿está lo que pide esta comprobación?
  case $1 in
    py:*) python3 -c "import ${1#py:}" >/dev/null 2>&1 ;;
    # (Sin «grep -q»: al cortar antes de tiempo, fc-list falla y con
    # pipefail eso se leería como que la fuente no está.)
    fuente:*) hay fc-list && fc-list : family 2>/dev/null | grep -ci "^${1#fuente:}" >/dev/null ;;
    *) hay "$1" ;;
  esac
}

paquete_de() {   # pacman | apt | dnf (campos 4, 5 y 6)
  case $GESTOR in
    pacman) echo "$1" ;;
    apt) echo "$2" ;;
    dnf) echo "$3" ;;
    *) echo "-" ;;
  esac
}

orden_instalar() {   # la orden completa para instalar los paquetes dados
  case $GESTOR in
    pacman) echo "sudo pacman -S --needed $*" ;;
    apt) echo "sudo apt-get install $*" ;;
    dnf) echo "sudo dnf install $*" ;;
  esac
}

# Recorre los requisitos y llena las listas de lo que falta.
revisar() {
  PAQ_NECESARIOS=() PAQ_RECOMENDADOS=() A_MANO=() FALTA_NECESARIO=0
  local prueba clase para p_pacman p_apt p_dnf nombre paquete
  while IFS='|' read -r prueba clase para p_pacman p_apt p_dnf; do
    [[ -n $prueba ]] || continue
    nombre=${prueba#*:}
    if esta "$prueba"; then
      [[ ${1:-} = callado ]] || printf '  %-16s está\n' "$nombre"
      continue
    fi
    paquete=$(paquete_de "$p_pacman" "$p_apt" "$p_dnf")
    case $clase in
      necesario)
        FALTA_NECESARIO=1
        [[ ${1:-} = callado ]] || printf '  %-16s FALTA    %s\n' "$nombre" "$para"
        if [[ $paquete = - ]]; then A_MANO+=("$nombre"); else PAQ_NECESARIOS+=("$paquete"); fi
        ;;
      recomendado)
        [[ ${1:-} = callado ]] || printf '  %-16s no está  (recomendado: %s)\n' "$nombre" "$para"
        [[ $paquete = - ]] || PAQ_RECOMENDADOS+=("$paquete")
        ;;
      aparte)
        [[ ${1:-} = callado ]] || printf '  %-16s no está  (opcional: %s)\n' "$nombre" "$para"
        ;;
    esac
  done <<<"$REQUISITOS"
}

preguntar() {   # pregunta | respuesta por defecto (s/n). Devuelve 0 si es sí.
  local respuesta
  case $DEPENDENCIAS in
    si) return 0 ;;
    no) return 1 ;;
  esac
  # Sin una terminal delante no hay a quién preguntar: no se instala nada.
  [[ -t 0 ]] || return 1
  if [[ $2 = s ]]; then
    read -r -p "$1 [S/n] " respuesta
    [[ -z $respuesta || $respuesta =~ ^[sSyY] ]]
  else
    read -r -p "$1 [s/N] " respuesta
    [[ $respuesta =~ ^[sSyY] ]]
  fi
}

echo "== Lo que hace falta =="
revisar
if ! hay google-chrome-stable && ! hay chromium && ! hay brave && ! hay vivaldi-stable && ! hay microsoft-edge-stable; then
  echo "  (no hay un navegador tipo Chromium: el compañero no abrirá las guías web)"
fi

# Lo que este sistema no trae en sus paquetes va primero: sin eso no tiene
# sentido pedir la contraseña para instalar lo demás.
if ((${#A_MANO[@]})); then
  echo
  echo "En este sistema hay que instalar a mano: ${A_MANO[*]}" >&2
  echo "  niri:       https://github.com/YaLTeR/niri" >&2
  echo "  Quickshell: https://quickshell.org  (el programa se llama «qs»)" >&2
  echo "Instálalos y vuelve a ejecutar esto." >&2
  exit 1
fi

if ((${#PAQ_NECESARIOS[@]})); then
  echo
  echo "Faltan paquetes necesarios. Se instalan con:"
  echo "    $(orden_instalar "${PAQ_NECESARIOS[@]}")"
  if preguntar "¿Los instalo ahora? (te pedirá tu contraseña)" s; then
    # shellcheck disable=SC2046
    $(orden_instalar "${PAQ_NECESARIOS[@]}") || echo "La instalación de paquetes no terminó bien." >&2
  fi
fi
if ((${#PAQ_RECOMENDADOS[@]})); then
  echo
  echo "Recomendados que no están (funciona sin ellos, con menos cosas):"
  echo "    $(orden_instalar "${PAQ_RECOMENDADOS[@]}")"
  if preguntar "¿Los instalo también?" n; then
    # shellcheck disable=SC2046
    $(orden_instalar "${PAQ_RECOMENDADOS[@]}") || echo "La instalación de los recomendados no terminó bien." >&2
  fi
fi

# Después de instalar (o de no hacerlo), ¿quedó lo necesario?
revisar callado
if ((FALTA_NECESARIO)); then
  echo
  echo "Siguen faltando paquetes necesarios: ${PAQ_NECESARIOS[*]}" >&2
  echo "Instálalos y vuelve a ejecutar esto." >&2
  exit 1
fi

echo
echo "== Programas → $BIN =="
mkdir -p "$BIN"
for f in "$AQUI"/bin/*; do
  install -m 755 "$f" "$BIN/$(basename "$f")"
  echo "  $(basename "$f")"
done

# Programas de versiones anteriores que ya no existen.
rm -f "$BIN/modo-juego-trucos" "$BIN/modo-juego-entrenador"

echo "== Interfaz → $CONFIG/quickshell =="
mkdir -p "$CONFIG/quickshell"
for d in modo-juego modo-juego-companero; do
  # Se reemplaza entera para que no queden archivos de una versión anterior.
  rm -rf "${CONFIG:?}/quickshell/$d"
  cp -r "$AQUI/quickshell/$d" "$CONFIG/quickshell/$d"
  echo "  $d"
done

echo "== Configuración → $CONFIG/modo-juego =="
mkdir -p "$CONFIG/modo-juego"
for f in guias.conf roms.conf MangoHud.conf; do
  if [[ -e $CONFIG/modo-juego/$f ]]; then
    echo "  $f ya existe: se deja como está"
  else
    cp "$AQUI/config/$f" "$CONFIG/modo-juego/$f"
    echo "  $f"
  fi
done
cp "$AQUI/config/config.sh.ejemplo" "$CONFIG/modo-juego/config.sh.ejemplo"
echo "  config.sh.ejemplo (cópialo a config.sh para cambiar qué se cierra)"

if [[ -d $CONFIG/niri ]]; then
  if [[ -e $CONFIG/niri/modo-juego.kdl ]]; then
    if cmp -s "$AQUI/niri/modo-juego.kdl" "$CONFIG/niri/modo-juego.kdl"; then
      echo "== Atajos de niri: al día =="
    else
      # El tuyo puede tener cambios propios: no se pisa. El de esta versión
      # queda al lado, por si trae atajos nuevos que quieras copiar.
      cp "$AQUI/niri/modo-juego.kdl" "$CONFIG/niri/modo-juego.kdl.nuevo"
      echo "== Atajos de niri: tu modo-juego.kdl es distinto del de esta versión =="
      echo "  Se deja como está. El de esta versión quedó al lado, como modo-juego.kdl.nuevo:"
      echo "  mira si trae atajos nuevos que quieras copiar."
    fi
  else
    cp "$AQUI/niri/modo-juego.kdl" "$CONFIG/niri/modo-juego.kdl"
    echo "== Atajos de niri → $CONFIG/niri/modo-juego.kdl =="
  fi
fi

# De dónde se instaló y qué versión es: lo usan «modo-juego actualizar» y
# la pantalla de Ajustes.
mkdir -p "$DATOS/modo-juego"
echo "$AQUI" >"$DATOS/modo-juego/origen"
if hay git && [[ -d $AQUI/.git ]]; then
  git -C "$AQUI" log -1 --format='%h del %cs' >"$DATOS/modo-juego/version" 2>/dev/null || rm -f "$DATOS/modo-juego/version"
else
  rm -f "$DATOS/modo-juego/version"
fi

if [[ $CON_ASISTENTE = si ]]; then
  echo "== Asistente con IA → $DATOS/modo-juego/venv =="
  mkdir -p "$DATOS/modo-juego"
  if hay uv; then
    uv venv -q "$DATOS/modo-juego/venv"
    uv pip install -q --python "$DATOS/modo-juego/venv/bin/python" anthropic
  elif python3 -m venv "$DATOS/modo-juego/venv" 2>/dev/null; then
    "$DATOS/modo-juego/venv/bin/pip" install -q anthropic
  else
    echo "  No pude crear el entorno de Python. Instala «uv» (o el paquete python3-venv) y repite con --asistente." >&2
    exit 1
  fi
  echo "  listo: guarda tu clave de Anthropic en Ajustes (F2 en el lanzador)"
fi

echo
echo "== Instalado. Lo que falta hacer a mano =="
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "  · $BIN no está en tu PATH: agrégalo para que niri encuentre «modo-juego»." ;;
esac
if [[ -d $CONFIG/niri ]] && ! grep -qs 'modo-juego.kdl' "$CONFIG/niri/config.kdl"; then
  echo "  · Agrega esta línea a $CONFIG/niri/config.kdl para tener los atajos:"
  echo '        include "modo-juego.kdl"'
fi
echo "  · Para actualizar más adelante:                     modo-juego actualizar"
echo "  · Mira qué cerraría en tu equipo, sin tocar nada:   modo-juego simular"
echo "  · Mira la entrada y el lanzador, sin cerrar nada:   modo-juego animacion"
