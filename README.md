# Master System en Tang Nano 9K

Z80 (T80), VDP modo 4, PSG, HDMI 480p, juegos .sms desde la SD (FAT32, SDHC,
cualquier carpeta) a la PSRAM; mapper Sega, Codemasters y coreano, RAM de
cartucho (no se guarda en la SD).

- Menu: arriba/abajo elige, izq/der pagina, boton 1 abre, boton 2 vuelve.
- `bash menu/build.sh`    menu (SDCC); `python menu/test_fat.py` lo prueba (gcc)
- `bash rom/build.sh`     en su lugar, la prueba de PSRAM y mapper (rom/boot.s)
- `bash tools/build.sh`   bitstream build/pnr/impl/pnr/sms_top.fs
- `bash sim/run_sys.sh 30`  simula el netlist; con SDIMG=imagen (sim/mkimg.py)

Mando: up 30, down 33, left 34, right 40, boton 1 29, boton 2 35, Pause 85.
S1: reset. S2: menu. Audio: pines 77/76 con filtro RC. SD: pines 36-39.
LEDs: 0 HDMI sincronizado, 1 latido, 2 boton, 3 menu, 4 cargando.

src/cpu es el T80 de pengo_arcade; T80sed.vhd anade el ciclo de espera de E/S.
Pendiente: guardar la RAM de cartucho, modos TMS9918 y 224 lineas.
