![NetManZX Banner](images/netmanzxlogo-white.png)

# NetManZX

**Gestor de Redes WiFi para ZX Spectrum**

[English version](README.md)

## Que es NetManZX?

NetManZX es una utilidad de configuracion de redes WiFi para ordenadores ZX Spectrum equipados con modulos WiFi basados en ESP8266. Soporta sistemas basados en divMMC (como DivTIESUS, ZX-Badaloc o similares), ZX-Uno y ZX Spectrum Next. Proporciona una interfaz amigable para escanear, seleccionar y conectarse a redes inalambricas directamente desde tu Spectrum.

## Origen

NetManZX esta basado en el proyecto original [netman-zx](https://github.com/nihirash/netman-zx) de **Alex Nihirash**. Esta version ha sido significativamente mejorada con nuevas funcionalidades, mayor fiabilidad y mejor experiencia de usuario.

**Version actual:** v1.4.5

## Capturas de Pantalla

*Capturas de la interfaz v1.4.4, aun representativas de v1.4.5. Los SSID de las capturas estan difuminados por privacidad.*

| | | |
|:---:|:---:|:---:|
| [![Splash Next](images/1.4.4/release/01_splash_next.png)](images/1.4.4/release/01_splash_next.png) | [![Lista de redes](images/1.4.4/release/03_network_list.png)](images/1.4.4/release/03_network_list.png) | [![Ya conectado](images/1.4.4/release/04_already_connected.png)](images/1.4.4/release/04_already_connected.png) |
| *Pantalla de arranque (Spectrum Next, Layer 2)* | *Lista de redes con barras RSSI* | *Aviso "ya conectado" (v1.4.4+)* |
| [![Conectado](images/1.4.4/release/10_connected.png)](images/1.4.4/release/10_connected.png) | [![Diagnosticos](images/1.4.4/release/06_diagnostics_menu.png)](images/1.4.4/release/06_diagnostics_menu.png) | [![Ping](images/1.4.4/release/07_ping_test.png)](images/1.4.4/release/07_ping_test.png) |
| *Conexion exitosa* | *Menu de diagnosticos (7 opciones)* | *Test de ping* |
| [![UART baud rate](images/1.4.4/release/08_uart_baud.png)](images/1.4.4/release/08_uart_baud.png) | [![Resumen de configuracion](images/1.4.4/release/09_config_summary.png)](images/1.4.4/release/09_config_summary.png) | [![Acerca de](images/1.4.4/release/11_about.png)](images/1.4.4/release/11_about.png) |
| *Velocidad UART (actual / por defecto)* | *Resumen de configuracion* | *Pantalla Acerca de* |

## Caracteristicas

### Gestion de Redes
- **Escaneo de Redes**: Descubre automaticamente hasta 25 redes WiFi usando parametros de escaneo extendidos (`AT+CWLAP` con 200-1500ms de permanencia por canal) para mejor cobertura. Reintento con fallback en caso de fallo. Ordenadas por intensidad de senal
- **Deteccion robusta al inicio**: Desactiva el echo del ESP (ATE0) antes del primer escaneo para prevenir fallos del parser. Multiples intentos de escaneo con mensajes diagnosticos en caso de timeout o resultados vacios
- **Soporte de Redes Ocultas**: Introduce manualmente el SSID de redes que no emiten su nombre
- **Deteccion Inteligente de Conexion**: Al iniciar, detecta si ya esta conectado a una WiFi y actualiza la barra de estado; el arranque en frio va directo al menu principal + primer escaneo en todos los casos. Si la red "ya conectada" se selecciona desde la lista, una pantalla de detalle muestra su informacion con un aviso en rojo `Already connected to this network!`
- **Pantalla de informacion de conexion**: Pulsa ENTER sobre la red ya conectada para ver IP, gateway, mascara de subred y direccion MAC
- **Guardar y Reconectar** (tecla C, solo UNO/NEXT): Guarda las credenciales WiFi en la tarjeta SD (`/SYS/CONFIG/NETMAN.CFG` en divMMC, `c:/sys/config/netman.cfg` en Next). Pulsa C desde el menu principal para reconectar a la red guardada. Tambien ofrece guardar tras una conexion exitosa (tecla S). La red guardada se resalta en cyan en la lista de redes
- **Entrada de Contrasena**: Soporte completo de teclado con opcion de mostrar/ocultar, entrada en doble altura con edicion de cursor (flechas izquierda/derecha)
- **Soporte WPS**: Conexion WPS por pulsacion de boton (tecla W), con ventana real de sondeo ~60 segundos, cancelacion con BREAK y sin efectos secundarios sobre la flash del ESP (envuelto en `SYSSTORE=0` + `CWAUTOCONN=0` para evitar que una autoreconexion en segundo plano simule un exito falso)
- **Opcion de Desconexion**: Desconecta de la red actual con dialogo de confirmacion, sin salir de la aplicacion
- **Monitorizacion de Estado en Tiempo Real**: Detecta automaticamente caidas y reconexiones mediante parseo asincrono de eventos del ESP
- **Diagnostico de fallos de conexion**: Mensajes especificos de error: contrasena incorrecta, AP no encontrado, timeout o conexion rechazada
- **Cancelacion con BREAK**: Cancelacion casi instantanea (~5ms de respuesta) durante cualquier comando AT o intento de conexion

### Menu de Diagnosticos
1. **Ping test** - Probar conectividad con IP configurable (por defecto: 8.8.8.8)
2. **Module info** - Mostrar version del firmware del ESP8266 y conjunto de comandos AT
3. **Network info** - Mostrar direccion IP y direccion MAC actual
4. **UART baud rate** - Muestra por separado `Current:` y `Default:` del ESP, haciendo visible el override de sesion (solo Next, `AT+UART_CUR=115200`) sin dar a entender que la flash ha sido modificada
5. **Static IP** - Configurar direccion IP estatica, gateway y mascara de subred
6. **Hostname** - Establecer un nombre de host personalizado para el modulo ESP
7. **Config summary** - Ver todos los ajustes WiFi actuales de un vistazo (SSID, IP, MAC, hostname, firmware, red guardada, version de la app)

### Interfaz de Usuario
- **Renderizado en doble altura**: Banner, barra de estado, campos de entrada y mensajes renderizados en texto de doble altura sin parpadeo mediante un renderizador a nivel de pixel
- **Pantalla de Detalle de Red**: Vista de detalle con SSID (doble altura), tipo de seguridad, canal WiFi con indicador de banda (2.4/5 GHz) y barras de intensidad de senal
- **Pantalla de conexion**: "Connecting to..." muestra el SSID en doble altura amarillo con contador de intentos
- **Badge arcoiris**: Triangulo decorativo con transiciones de color en el banner
- **Barras de senal RSSI de 8 niveles**: Indicador visual de intensidad de senal WiFi para cada red, con glifos personalizados de circulo cerrado/abierto
- **Barra de estado anti-parpadeo**: Renderizado por sobreescritura directa con actualizaciones agrupadas que elimina el parpadeo visual
- **Indicadores de scroll**: Flechas visuales que indican cuando hay mas redes disponibles
- **Click de tecla audible**: Feedback sonoro claro en cada pulsacion durante la entrada de texto

### Otros
- **Pantalla de arranque (splash)**: Logo pintado antes de que aparezca la interfaz principal. En Spectrum Next se carga una imagen Layer 2 de 48 KB con paleta personalizada de 9 bits via el cargador NEX; la fila ULA 20 muestra mensajes de estado de inicializacion (`Configuring ESP...`, `Scanning baud rates...`, etc.) bajo una ventana de clip Layer 2. En UNO / AY se carga un logo SCR de 6912 B desde el TAP antes del codigo, suprimiendo los mensajes `Bytes: ...` de BASIC para una carga limpia
- **Pantalla Acerca de** (tecla I): Muestra version, fecha de compilacion, autor, URL de GitHub y licencia
- **Log de Depuracion UART**: Muestra/oculta el log UART en tiempo real con la tecla L (funciona globalmente). Indicador rojo en el area de log cuando esta activo
- **Fuente comprimida**: Sistema de fuente comprimida por nibbles integrado (sin dependencia de archivo font.bin externo)
- **Tres backends UART**: Soporta hardware ZX-Uno, AY-UART (ZX-Badaloc) y ZX Spectrum Next
- **Auto-deteccion de baud rate** (solo Next): Si el ESP no responde a 115200, escanea 1152000, 2000000, 9600 y 57600 baudios y establece 115200 para la sesion via `AT+UART_CUR` (no modifica la flash del ESP). Si ninguna tasa funciona, resetea el ESP por hardware. Maneja restos de NextSync/NextSync-fast, ESPs de fabrica y configuraciones erroneas sin overhead en arranques normales
- **Formato NEX** (solo Next): Binario nativo `.nex` para arranque directo sin menu de seleccion de modo
- **Fecha de compilacion**: Incrustada automaticamente en tiempo de ensamblado via Lua

## Requisitos

- ZX Spectrum (48K o superior) o compatible
- Modulo WiFi basado en ESP8266:
  - **ZX-Uno**: UART integrado (target por defecto)
  - **AY-UART**: ZX-Badaloc o implementaciones similares bit-banged AY-3-8912
  - **ZX Spectrum Next**: UART hardware con FIFO
- Metodo de carga compatible con TAP (divMMC, esxDOS, emulador, o tap2wav para cinta)

## Compilacion

### Prerrequisitos

- [SjASMPlus](https://github.com/z00m128/sjasmplus) Z80 Cross-Assembler v1.20+
- GNU Make

### Compilar

```bash
# Compilar para ZX-Uno / DivMMC (por defecto)
make uno

# Compilar para AY-UART / ZX-Badaloc
make ay

# Compilar para ZX Spectrum Next
make next

# Compilar todos los targets
make all
```

### Archivos de Salida

| Target | Archivo | Descripcion |
|--------|---------|-------------|
| UNO | `netmanzx-uno.tap` | ZX-Uno / DivMMC |
| AY | `netmanzx-ay.tap` | AY-UART / ZX-Badaloc |
| NEXT | `netmanzx-next.nex` | ZX Spectrum Next (NEX nativo) |

### Carga

**TAP (cinta/emuladores):**
Simplemente carga el archivo TAP - el cargador BASIC se ejecutara automaticamente y cargara el programa.

**NEX (Next):**
Copia `netmanzx-next.nex` a la tarjeta SD y ejecutalo directamente desde el navegador de ficheros o la linea de comandos (`.netmanzx-next`).

## Uso

1. **Carga el programa** en tu Spectrum
2. **Espera al escaneo de redes** - las redes disponibles apareceran en una lista
3. **Navega** usando las teclas de cursor (arriba/abajo) o Q/A, O/P para pagina arriba/abajo
4. **Selecciona una red** con ENTER - una pantalla de detalle muestra seguridad, canal y senal
5. **Introduce la contrasena** (si es necesaria) - usa flecha arriba para mostrar/ocultar contrasena
6. **Espera a la conexion** - BREAK cancela inmediatamente, mensajes de error detallados en caso de fallo
7. **Accede a diagnosticos** pulsando D desde la lista de redes

### Controles

| Tecla | Accion |
|-------|--------|
| Arriba/Abajo o Q/A | Navegar lista de redes |
| O/P | Pagina Arriba/Abajo |
| ENTER | Seleccionar red / Confirmar |
| BREAK | Cancelar / Volver (respuesta instantanea) |
| H | Conectar a red oculta (introducir SSID manualmente) |
| X | Desconectar de la red actual |
| D | Menu de diagnosticos |
| R | Reescanear redes |
| L | Alternar log de depuracion UART |
| W | Conexion WPS por pulsacion |
| C | Reconectar a red guardada / Guardar config (UNO/NEXT) |
| S | Guardar credenciales tras conexion exitosa (UNO/NEXT) |
| I | Pantalla Acerca de |

No existe una tecla "salir del programa" — la aplicacion es una herramienta independiente, no un TSR. Para abandonarla, resetea la maquina.

### Robustez de Conectividad

- **Deteccion BREAK**: Tecla BREAK comprobada cada ~5ms durante comandos AT para cancelacion casi instantanea. Pantalla dedicada de "Cancelled" con debounce
- **Deteccion Automatica de Caida WiFi**: Parseo asincrono de eventos del ESP para detectar desconexiones inesperadas al instante
- **Chequeo Periodico en Idle**: Validacion periodica mediante comandos AT con debounce (3 fallos consecutivos requeridos antes de declarar desconexion)
- **Proteccion UART Busy**: Mecanismo tipo mutex que evita que el parser asincrono interfiera durante operaciones criticas
- **Seguridad tras I/O en SD**: El estado usado despues de cargar/guardar configuracion vive fuera del area volatil de printer-buffer usada por esxDOS, y el estado UI/UART volatil se rearma tras cada operacion de fichero
- **Flush UART acotado**: Los bucles de drenaje UART tienen limite duro de bytes, asi el ruido continuo del ESP no puede dejar la interfaz atrapada vaciando datos
- **Seguridad de Registros UART**: Los tres backends UART (UNO, AY, Next) preservan los registros del llamante durante operaciones de escritura
- **Reintento de IP al Conectar**: 3 intentos con intervalos de 1 segundo tras la asociacion WiFi exitosa
- **Recuperacion Automatica de Estado**: Al perder conexion, la interfaz pasa a Disconnected y programa un rescaneo seguro. El auto-rescan preserva la lista anterior en caso de fallo
- **Busquedas de Buffer Acotadas**: Todas las busquedas CPIR limitadas al tamano real del buffer
- **Auto-deteccion de baud rate** (solo Next): Escanea 1152000, 2000000, 9600, 57600 baudios si el ESP no responde a 115200. Establece 115200 para la sesion via `AT+UART_CUR`. Reset hardware del ESP como fallback

## Historial de Versiones

Ver [CHANGELOG.md](CHANGELOG.md) para el historial detallado de versiones.

## Licencia

Licencia MIT. Ver [LICENSE](LICENSE) para mas detalles.

Basado en el trabajo original de Alex Nihirash.

## Copyright

- netman-zx original: **Alex Nihirash** (https://github.com/nihirash)
- Mejoras de NetManZX: **M. Ignacio Monge Garcia** (2025-2026)

---

*Hecho con amor para la comunidad del ZX Spectrum*
