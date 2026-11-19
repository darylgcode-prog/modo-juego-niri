#!/usr/bin/env bash
# Instala el modo juego para niri en tu carpeta personal. No pide sudo ni
# toca nada del sistema.
#
#   ./install.sh               instala los programas, la interfaz y los ejemplos
#   ./install.sh --asistente   además prepara el asistente con IA (crea un
#                              entorno de Python y baja el paquete de Anthropic)
#
# Volver a ejecutarlo actualiza los programas y la interfaz, y deja tu
# configuración (~/.config/modo-juego) como esté.
set -euo pipefail

AQUI=$(cd "$(dirname "$0")" && pwd)
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATOS="${XDG_DATA_HOME:-$HOME/.local/share}"
CON_ASISTENTE=no

for arg in "$@"; do
  case $arg in
    --asistente) CON_ASISTENTE=si ;;
    -h | --help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "No conozco la opción «$arg». Prueba con --help." >&2; exit 2 ;;
  esac
done

hay() { command -v "$1" >/dev/null 2>&1; }

echo "== Lo que hace falta =="
faltan=0
revisar() {   # programa | para qué | obligatorio(si/no)
  if hay "$1"; then
    printf '  %-16s está\n' "$1"
  elif [[ $3 = si ]]; then
    printf '  %-16s FALTA   %s\n' "$1" "$2"
    faltan=1
  else
    printf '  %-16s no está (opcional: %s)\n' "$1" "$2"
  fi
}
revisar niri "el escritorio para el que está hecho" si
revisar qs "Quickshell 0.2 o más nuevo: la animación y el lanzador" si
revisar jq "lo usa el script en todas partes" si
revisar python3 "el catálogo de juegos y las carátulas" si
revisar magick "ImageMagick: convierte iconos y carátulas" si
revisar notify-send "avisos cuando no hay animación" no
revisar pw-play "PipeWire: los sonidos" no
revisar grim "la captura que acompaña las preguntas al asistente" no
revisar powerprofilesctl "perfil de energía de rendimiento al jugar" no
revisar mangohud "contador de FPS en los juegos" no
revisar asusctl "el teclado reacciona (portátiles ASUS)" no
revisar dms "«no molestar» en DankMaterialShell" no
if ! hay google-chrome-stable && ! hay chromium && ! hay brave && ! hay vivaldi-stable && ! hay microsoft-edge-stable; then
  echo "  (no hay un navegador tipo Chromium: el compañero no abrirá las guías web)"
fi
python3 -c "import evdev" 2>/dev/null || echo "  (falta python-evdev: el lanzador no se podrá manejar con mando)"
if ((faltan)); then
  echo
  echo "Instala lo que dice FALTA y vuelve a ejecutar esto." >&2
  exit 1
fi

echo
echo "== Programas → $BIN =="
mkdir -p "$BIN"
for f in "$AQUI"/bin/*; do
  install -m 755 "$f" "$BIN/$(basename "$f")"
  echo "  $(basename "$f")"
done

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
    echo "== Atajos de niri: $CONFIG/niri/modo-juego.kdl ya existe, se deja como está =="
  else
    cp "$AQUI/niri/modo-juego.kdl" "$CONFIG/niri/modo-juego.kdl"
    echo "== Atajos de niri → $CONFIG/niri/modo-juego.kdl =="
  fi
fi

if [[ $CON_ASISTENTE = si ]]; then
  echo "== Asistente con IA → $DATOS/modo-juego/venv =="
  mkdir -p "$DATOS/modo-juego"
  if hay uv; then
    uv venv -q "$DATOS/modo-juego/venv"
    uv pip install -q --python "$DATOS/modo-juego/venv/bin/python" anthropic
  else
    python3 -m venv "$DATOS/modo-juego/venv"
    "$DATOS/modo-juego/venv/bin/pip" install -q anthropic
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
echo "  · Mira qué cerraría en tu equipo, sin tocar nada:   modo-juego simular"
echo "  · Mira la entrada y el lanzador, sin cerrar nada:   modo-juego animacion"
