#!/usr/bin/env bash
# Quita el modo juego de tu carpeta personal.
#
#   ./uninstall.sh          quita los programas y la interfaz; deja tu
#                           configuración, tus notas, carátulas y claves
#   ./uninstall.sh --todo   quita también todo eso
set -euo pipefail

BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATOS="${XDG_DATA_HOME:-$HOME/.local/share}"
ESTADO="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
TODO=no
[[ ${1:-} == --todo ]] && TODO=si

if [[ -f $ESTADO/modo-juego/estado ]] && command -v modo-juego >/dev/null; then
  echo "El modo juego está activo: lo desactivo primero para devolver lo que cerró."
  MODO_JUEGO_SUELTO=1 modo-juego desactivar || true
fi

# (Los dos últimos son de versiones anteriores; se quitan si quedaron.)
for f in modo-juego modo-juego-catalogo modo-juego-caratulas modo-juego-mando modo-juego-asistente \
  modo-juego-trucos modo-juego-entrenador; do
  rm -f "$BIN/$f"
done
rm -rf "${CONFIG:?}/quickshell/modo-juego" "${CONFIG:?}/quickshell/modo-juego-companero"
echo "Quitados los programas y la interfaz."

if [[ $TODO = si ]]; then
  rm -rf "${CONFIG:?}/modo-juego" "${DATOS:?}/modo-juego" "${ESTADO:?}/modo-juego" "${CACHE:?}/modo-juego"
  rm -f "$CONFIG/niri/modo-juego.kdl"
  echo "Quitadas también tu configuración, notas, carátulas, claves y el entorno del asistente."
else
  echo "Quedaron tu configuración y tus datos en $CONFIG/modo-juego (usa --todo para quitarlos)."
fi
echo "Si agregaste «include \"modo-juego.kdl\"» a tu configuración de niri, quita esa línea."
