![NetManZX Banner](images/netmanzxlogo-white.png)

# NetManZX

**Gestor de Redes WiFi para ZX Spectrum**

[English version](README.md)

## Que es NetManZX?

NetManZX es una utilidad de configuracion de redes WiFi para ordenadores ZX Spectrum equipados con modulos WiFi basados en ESP8266. Soporta sistemas basados en divMMC (como DivTIESUS, ZX-Badaloc o similares), ZX-Uno y ZX Spectrum Next. Proporciona una interfaz amigable para escanear, seleccionar y conectarse a redes inalambricas directamente desde tu Spectrum.

## Origen

NetManZX esta basado en el proyecto original [netman-zx](https://github.com/nihirash/netman-zx) de **Alex Nihirash**. Esta version ha sido significativamente mejorada con nuevas funcionalidades, mayor fiabilidad y mejor experiencia de usuario.

**Versión actual:** [v1.4.6](https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.6)

## Capturas de Pantalla

*Capturas de v1.4.4; algunos textos difieren en v1.4.6. Los SSID están difuminados por privacidad.*

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
- **Escaneo de redes**: Descubre hasta 25 puntos de acceso WiFi, ordenados por señal, con reintentos si falla el escaneo. Los puntos de acceso con el mismo nombre permanecen separados; la selección conecta al punto elegido
- **Deteccion robusta al inicio**: Desactiva el echo del ESP (ATE0) antes del primer escaneo para prevenir fallos del parser. Multiples intentos de escaneo con mensajes diagnosticos en caso de timeout o resultados vacios
- **Soporte de Redes Ocultas**: Introduce manualmente el SSID de redes que no emiten su nombre
- **Deteccion Inteligente de Conexion**: Al iniciar, detecta si ya esta conectado a una WiFi y actualiza la barra de estado; el arranque en frio va directo al menu principal + primer escaneo en todos los casos. Si la red "ya conectada" se selecciona desde la lista, una pantalla de detalle muestra su informacion con un aviso en rojo `Already connected to this network!`
- **Pantalla de informacion de conexion**: Pulsa ENTER sobre la red ya conectada para ver IP, gateway, mascara de subred y direccion MAC
- **Guardar y reconectar** (solo UNO/NEXT): Guarda credenciales en SD (`/SYS/CONFIG/NETMAN.CFG` en divMMC, `c:/sys/config/netman.cfg` en Next). C ofrece reconectar a la red guardada; S guarda tras una conexión correcta. La red guardada aparece en cyan
- **Entrada de Contrasena**: Soporte completo de teclado con opcion de mostrar/ocultar, entrada en doble altura con edicion de cursor (flechas izquierda/derecha)
- **Soporte WPS**: Conexión por pulsación con W y cancelación con BREAK, conservando la política de conexión automática guardada en el ESP
- **Opcion de Desconexion**: Desconecta de la red actual con dialogo de confirmacion, sin salir de la aplicacion
- **Monitorizacion de Estado en Tiempo Real**: Detecta automaticamente caidas y reconexiones mediante parseo asincrono de eventos del ESP
- **Diagnostico de fallos de conexion**: Mensajes especificos de error: contrasena incorrecta, AP no encontrado, timeout o conexion rechazada
- **Cancelación con BREAK**: Cancela intentos de conexión y operaciones AT. El tiempo de respuesta depende del hardware y de la operación

### Menu de Diagnosticos
1. **Ping test** - Probar conectividad con IP configurable (por defecto: 8.8.8.8)
2. **Module info** - Mostrar version del firmware del ESP8266 y conjunto de comandos AT
3. **Network info** - Mostrar direccion IP y direccion MAC actual
4. **UART baud rate** - Muestra por separado `Current:` y `Default:` del ESP, haciendo visible el override de sesion (solo Next, `AT+UART_CUR=115200`) sin dar a entender que la flash ha sido modificada
5. **Static IP** - Configurar direccion IP estatica, gateway y mascara de subred
6. **Hostname** - Establecer un nombre de host personalizado para el modulo ESP
7. **Config summary** - Ver todos los ajustes WiFi actuales de un vistazo (SSID, IP, MAC, hostname, firmware, red guardada, version de la app)

### Interfaz de Usuario
- **Texto en doble altura**: Banner, estado, entradas y mensajes grandes, con actualizaciones más suaves de la lista de redes
- **Detalle de red**: Consulta el nombre, la seguridad, el canal y la señal antes de conectar
- **Pantalla de conexion**: "Connecting to..." muestra el SSID en doble altura amarillo con contador de intentos
- **Badge arcoiris**: Triangulo decorativo con transiciones de color en el banner
- **Barras de senal RSSI de 8 niveles**: Indicador visual de intensidad de senal WiFi para cada red, con glifos personalizados de circulo cerrado/abierto
- **Barra de estado anti-parpadeo**: Renderizado por sobreescritura directa con actualizaciones agrupadas que elimina el parpadeo visual
- **Indicadores de scroll**: Flechas visuales que indican cuando hay mas redes disponibles
- **Click de tecla audible**: Feedback sonoro claro en cada pulsacion durante la entrada de texto

### Otros
- **Pantalla de arranque**: Logo de carga en todos los equipos, con imagen en color Layer 2 en Next. Los mensajes descriptivos informan de la inicialización y recuperación del WiFi
- **Pantalla Acerca de** (tecla I): Muestra version, fecha de compilacion, autor, URL de GitHub y licencia
- **Log UART**: Se activa con L; un indicador rojo muestra su estado. Los comandos se registran en pantalla al terminar el intercambio, con un aviso si el texto queda truncado
- **Fuente integrada**: Texto compacto de seis píxeles de ancho, sin archivo de fuente externo para ejecutar el programa
- **Tres backends UART**: Soporta hardware ZX-Uno, AY-UART (ZX-Badaloc) y ZX Spectrum Next
- **Detección automática de baudios** (solo Next): Prueba 1152000, 2000000, 9600 y 57600 baudios si el ESP no responde a 115200. Restablece 115200 para la sesión sin cambiar la velocidad guardada; reinicia el ESP si la recuperación lo requiere
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

Los archivos compilados se guardan en `build/`. Los binarios listos para cargar están en las [releases de GitHub](https://github.com/IgnacioMonge/NetManZX/releases).

| Target | Archivo | Descripcion |
|--------|---------|-------------|
| UNO | `netmanzx-uno.tap` | ZX-Uno / DivMMC |
| AY | `netmanzx-ay.tap` | AY-UART / ZX-Badaloc |
| NEXT | `netmanzx-next.nex` | ZX Spectrum Next (NEX nativo) |

### Carga

**TAP (cinta/emuladores):**
Simplemente carga el archivo TAP - el cargador BASIC se ejecutara automaticamente y cargara el programa.

**NEX (Next):**
Copia `netmanzx-next.nex` a la tarjeta SD y ejecútalo desde el navegador de archivos del Next.

## Uso

1. **Carga el programa** en tu Spectrum
2. **Espera al escaneo de redes** - las redes disponibles apareceran en una lista
3. **Navega** usando las teclas de cursor (arriba/abajo) o Q/A, O/P para pagina arriba/abajo
4. **Selecciona una red** con ENTER - una pantalla de detalle muestra seguridad, canal y senal
5. **Introduce la contrasena** (si es necesaria) - usa flecha arriba para mostrar/ocultar contrasena
6. **Espera a la conexión** — BREAK cancela; los fallos muestran su motivo
7. **Accede a diagnosticos** pulsando D desde la lista de redes

### Controles

| Tecla | Accion |
|-------|--------|
| Arriba/Abajo o Q/A | Navegar lista de redes |
| O/P | Pagina Arriba/Abajo |
| ENTER | Seleccionar red / Confirmar |
| BREAK | Cancelar / Volver; salir desde el menú principal |
| H | Conectar a red oculta (introducir SSID manualmente) |
| X | Desconectar de la red actual |
| D | Menu de diagnosticos |
| R | Reescanear redes |
| L | Alternar log de depuracion UART |
| W | Conexion WPS por pulsacion |
| C | Reconectar a la red guardada (UNO/NEXT) |
| S | Guardar credenciales tras conexion exitosa (UNO/NEXT) |
| I | Pantalla Acerca de |

Desde el menú principal, BREAK vuelve a BASIC en UNO/AY. En Next reinicia la máquina; no restaura la sesión anterior de NextZXOS.

### Recuperación de la conexión

NetManZX supervisa los eventos del ESP y comprueba periódicamente el enlace. Los escaneos y comandos de conexión pausan temporalmente la navegación; la respuesta a BREAK varía según el controlador UART. El escaneo automático descarta la entrada pendiente al terminar, pero una tecla mantenida puede repetirse.

Next puede recuperar automáticamente desajustes habituales de baudios. En UNO/AY, comprueba la velocidad del módulo y la configuración de la interfaz si el arranque no consigue comunicarse con el ESP.

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
