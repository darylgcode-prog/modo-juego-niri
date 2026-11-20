# Región de Xbox Cloud

Extensión de navegador que le pide a Xbox Cloud Gaming una región de
servidor. La abre `modo-juego xcloud` junto con Xbox Cloud; los ajustes
se cambian con `modo-juego xcloud region` (Mod+Alt+X).

Es una **copia adaptada** de
[xCloud Region Switcher](https://github.com/BlaNkS01/xcloud-region-switcher)
v1.5.1, de BlaNkS01, tomada del commit `d50b81f` (13-11-2026) y
distribuida bajo su licencia MIT (ver `LICENSE`). No tiene relación con
Microsoft ni con Xbox.

## Qué se cambió respecto del original

- Textos en español.
- Por defecto no toca nada («elige Xbox»). El original partía en «más
  cercana», que mide la distancia desde Europa central y solo conoce
  regiones europeas; ese modo se quitó.
- «La que responde más rápido», si no logra medir, deja elegir a Xbox en
  vez de caer al modo europeo.
- La ventana de ajustes se abre como ventana propia: al guardar recarga
  todas las pestañas de Xbox y se cierra.

## Qué hace y qué no

- Solo actúa en `www.xbox.com`, `xbox.com` y `play.xbox.com`. No envía
  nada a terceros; sus ajustes quedan en el perfil del navegador.
- Reescribe la lista de regiones que Xbox entrega al iniciar sesión para
  dejar solo la elegida. Xbox puede usar otra igual.
- «Saltar la restricción regional» agrega la cabecera `X-Forwarded-For`
  al inicio de sesión. Viene apagado: puede no funcionar, va contra las
  reglas regionales de Xbox y el riesgo es de la cuenta de quien lo use.
- Probada por su autor solo en el sitio clásico `www.xbox.com/play`.
