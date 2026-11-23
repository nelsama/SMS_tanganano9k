# Master System en Tang Nano 9K con cartucho SD

Sega Master System en una Sipeed Tang Nano 9K (GW1NR-LV9QN88PC6/I5): Z80, VDP
modo 4, PSG, HDMI 480p y un cartucho tipo EverDrive que carga juegos `.sms`
desde una SD y guarda las partidas.

## Uso rápido

1. Graba `build/pnr/impl/pnr/sms_top.fs` en la placa (ver *Compilar*).
2. Formatea la SD en **FAT32** y copia los `.sms`, en cualquier carpeta.
3. Inserta la SD y enciende: aparece el menú.

### Menú

| Control | Acción |
|---|---|
| Arriba / abajo | elegir (se repite al mantener) |
| Izquierda / derecha | página anterior / siguiente |
| Botón 1 | abrir carpeta o juego |
| Botón 2 | volver a la carpeta anterior |

Las carpetas llevan `/` delante. Límites: 6 niveles de subcarpetas, unas 9500
entradas por carpeta, 27 caracteres de nombre y orden de la SD (no alfabético).
Solo se muestran los `.sms`; hasta 4 MB, con o sin cabecera de 512 bytes.

### Durante el juego

| Control | Acción |
|---|---|
| S2 | volver al menú (**y guardar la partida**) |
| S1 | reset del juego |
| Pin 85 | Pausa |

### Partidas guardadas

1. Guarda dentro del juego, como en la consola.
2. Pulsa **S2**. Si la partida cambió aparece `SAVING...` (unos 2 s).
3. La próxima vez que abras el juego se carga sola.

**Si apagas sin pulsar S2, la partida se pierde.** No apagues ni saques la SD
mientras dice `SAVING...`.

El archivo es `<nombre corto>.SAV` (por ejemplo `PHANTA~1.SAV`), de 32 KB, en la
carpeta del juego. Si ya existe uno de otro tamaño, se usan sus sectores
completos, hasta 32 KB. No se escribe si la RAM no cambió o si la SD es otra. Si
falla, el menú ofrece reintentar (botón 1) o descartar (botón 2).

Guardado verificado en simulación y en el PC (`menu/test_fat.py`), **aún no en
la placa**: haz una copia de la SD y pasa `chkdsk` la primera vez.

### Mensajes

| Mensaje | Causa |
|---|---|
| `NO SD CARD` | no hay tarjeta o no responde (al guardar, también: es otra SD) |
| `SD READ ERROR` | fallo de lectura o escritura |
| `NOT FAT32` | exFAT, FAT16 o sin formato (solo mira la primera partición) |
| `BAD SIZE` | archivo vacío, truncado o de más de 4 MB |
| `SD FULL` / `FOLDER FULL` | no cabe el `.SAV`, o no hay entradas libres en la carpeta |

## Conexiones

Botones a masa (activos en bajo, pull-up interno).

| Señal | Pin | Señal | Pin |
|---|---|---|---|
| Arriba | 30 | Pausa | 85 (banco de 1,8 V) |
| Abajo | 33 | SD SCK | 36 |
| Izquierda | 34 | SD CMD (MOSI) | 37 |
| Derecha | 40 | SD CS | 38 |
| Botón 1 | 29 | SD DAT0 (MISO) | 39 |
| Botón 2 | 35 | Audio L / R | 77 / 76, con filtro RC |

S1, S2, HDMI y SD son los de la placa. LEDs: 0 HDMI sincronizado, 1 latido,
2 algún botón, 3 menú, 4 cargando.

## Compatibilidad

- **Mappers**, detectados solos: Sega, Codemasters, coreano (`$A000`) y sin
  mapper. Codemasters y coreano, sin probar a fondo.
- **RAM de cartucho**: 2 x 16 KB.
- **Sin implementar**: modos TMS9918 (SG-1000), 224/240 líneas (algunos juegos
  de Codemasters), FM (YM2413), Game Gear, segundo mando (sin pines), PAL.
- La máquina va a 60,27 Hz (consola NTSC: 59,92).

## Compilar

Requiere Gowin V1.9.12.03 (`GW_SH` cambia la ruta), Git Bash y Python. Para el
menú, SDCC (`winget install SDCC.SDCC`); para pruebas y simulación, gcc de MSYS2
(`/c/msys64/ucrt64/bin`) y ffmpeg.

| Comando | Qué hace |
|---|---|
| `bash menu/build.sh` | compila el menú: `menu/menu.hex` y `src/board/rom_cfg.vh` |
| `bash tools/build.sh` | bitstream; al final muestra recursos y violaciones de tiempo (deben ser 0) |
| `python menu/test_fat.py` | prueba FAT32, cargador y guardado en el PC |
| `bash rom/build.sh` | en lugar del menú, prueba de PSRAM y mapper (`rom/boot.s`) |
| `bash sim/run_sys.sh 30` | simula el netlist 30 cuadros; imágenes en `build/sim` |

`rom_cfg.vh` lleva la ruta absoluta de la ROM: ejecuta `menu/build.sh` si mueves
el proyecto. Desde el IDE (`SMS_TN9K.gprj`), pon *place_option* y *route_option*
en 1; con los valores por defecto una compilación no cumplió los tiempos de la
PSRAM.

Uso actual: 46 % de lógica, 23 de 26 BSRAM.

### Simular

```
python sim/mkimg.py build/sd.img juego.sms
SDIMG=D:/ruta/build/sd.img bash sim/run_sys.sh 130 10@30-33
```

Los eventos son `botones@desde-hasta`, en hexadecimal y en cuadros: 01 arriba,
02 abajo, 04 izquierda, 08 derecha, 10 botón 1, 20 botón 2, 100 Pausa, 200 S2
(en un solo cuadro). Va a menos de un cuadro por segundo. `rom/save.s` es una ROM
de prueba del guardado. `SKIP_SYN=1` reutiliza el netlist.

## Pruebas en la placa

- `rom/test.sms` (cópialo a la SD): 10 pruebas de CPU, VDP e interrupciones; todo
  debe dar OK y el contador de ciclos `0712` o muy cercano.
- `bash rom/build.sh && bash tools/build.sh`: prueba de la PSRAM y el mapper; para
  volver al menú, `bash menu/build.sh && bash tools/build.sh`.

## Cómo está hecho

- `src/board/sms_sys.v`: sistema, mapper, puertos del cartucho (documentados en su
  cabecera). Todo va con un reloj de 21,6 MHz: punto = /4, CPU = /6.
- `src/sms/`: VDP y PSG. `src/board/sms2hdmi.v`: escalado 2,5 x 2 a 720x480p.
- `src/memory/psram_chan.vhd`: PSRAM a 86,4 MHz. ROM en el chip 0 y RAM de
  cartucho en el chip 1; la lectura empieza en T1 y no hay ciclos de espera.
- `src/cpu/`: T80. Cambios en `T80sed.vhd` (espera de E/S, aviso de lectura en T1)
  y SP inicial `$DFF0` en `T80.vhd`.
- `menu/`: menú en C. Guarda en orden datos, FAT y directorio, así un corte de
  energía no deja entradas a medias; solo puede perder clústeres libres.
- `tools/z80asm.py`: ensamblador Z80 de las ROM de prueba.

## Licencias

T80: licencia de sus autores, en la cabecera de los archivos. `psram_chan.vhd`:
Apache 2.0 (`LICENSE-APACHE-2.0.txt`). No se incluyen juegos comerciales.
