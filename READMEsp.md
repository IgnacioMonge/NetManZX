![NetManZX Banner](images/netmanzxlogo-white.png)

# NetManZX

**Gestor de Redes WiFi para ZX Spectrum**

[English version](README.md)

## Que es NetManZX?

NetManZX es una utilidad de configuracion de redes WiFi para ordenadores ZX Spectrum equipados con modulos WiFi basados en ESP8266 (como ZX-Badaloc o similares). Proporciona una interfaz amigable para escanear, seleccionar y conectarse a redes inalambricas directamente desde tu Spectrum.

## Origen

NetManZX esta basado en el proyecto original [netman-zx](https://github.com/nihirash/netman-zx) de **Alex Nihirash**. Esta version ha sido significativamente mejorada con nuevas funcionalidades, mayor fiabilidad y mejor experiencia de usuario.

## Capturas de Pantalla

| | | |
|:---:|:---:|:---:|
| [![Startup](images/screenshot_startup.png)](images/screenshot_startup.png) | [![Network List](images/screenshot_network_list.png)](images/screenshot_network_list.png) | [![Connected Prompt](images/screenshot_connected_prompt.png)](images/screenshot_connected_prompt.png) |
| *Inicio y escaneo* | *Lista de redes con barras RSSI* | *Dialogo de red ya conectada* |
| [![Network Detail](images/screenshot_password_masked.png)](images/screenshot_password_masked.png) | [![Password Visible](images/screenshot_password_visible.png)](images/screenshot_password_visible.png) | [![Hidden Network](images/screenshot_hidden_network.png)](images/screenshot_hidden_network.png) |
| *Detalle de red y password* | *Password visible* | *Red oculta (SSID manual)* |
| [![Diagnostics](images/screenshot_diagnostics.png)](images/screenshot_diagnostics.png) | [![Config Summary](images/screenshot_config_summary.png)](images/screenshot_config_summary.png) | [![About](images/screenshot_about.png)](images/screenshot_about.png) |
| *Menu de diagnosticos (7 opciones)* | *Resumen de configuracion* | *Pantalla Acerca de* |

## Caracteristicas

### Interfaz de Usuario
- **Renderizado en doble altura**: Banner, barra de estado, campos de entrada y mensajes renderizados en texto de doble altura sin parpadeo mediante un renderizador a nivel de pixel
- **Pantalla de Detalle de Red**: Al seleccionar una red, una vista de detalle muestra el SSID (doble altura), tipo de seguridad, canal WiFi y barras de intensidad de senal antes de solicitar la contrasena
- **Badge arcoiris**: Triangulo decorativo con transiciones de color en el banner
- **Barras de senal RSSI de 8 niveles**: Indicador visual de intensidad de senal WiFi para cada red, con glifos personalizados de circulo cerrado/abierto
- **Barra de estado anti-parpadeo**: Renderizado por sobreescritura directa con actualizaciones agrupadas que elimina el parpadeo visual
- **Indicadores de scroll**: Flechas visuales que indican cuando hay mas redes disponibles

### Gestion de Redes
- **Escaneo de Redes**: Descubre automaticamente las redes WiFi disponibles con ordenacion por intensidad de senal
- **Soporte de Redes Ocultas**: Introduce manualmente el SSID de redes que no emiten su nombre
- **Deteccion Inteligente de Conexion**: Al iniciar, detecta si ya esta conectado y ofrece mantener o reconfigurar
- **Entrada de Contrasena**: Soporte completo de teclado con opcion de mostrar/ocultar, entrada en doble altura con edicion de cursor
- **Soporte WPS**: Conexion WPS por pulsacion de boton (tecla W), con dialogo de confirmacion si ya esta conectado
- **Opcion de Desconexion**: Desconecta de la red actual sin salir de la aplicacion
- **Monitorizacion de Estado en Tiempo Real**: Detecta automaticamente caidas y reconexiones
- **Mensajes de Error Detallados**: Informacion especifica sobre fallos de conexion (contrasena incorrecta, AP no encontrado, timeout, etc.)
- **Cancelacion con BREAK**: Cancelacion casi instantanea (~5ms de respuesta) durante cualquier comando AT o intento de conexion

### Menu de Diagnosticos
1. **Ping test** - Probar conectividad con IP configurable (por defecto: 8.8.8.8)
2. **Module info** - Mostrar version del firmware del ESP8266 y conjunto de comandos AT
3. **Network info** - Mostrar direccion IP y direccion MAC actual
4. **UART baud rate** - Mostrar velocidad de comunicacion actual
5. **Static IP** - Configurar direccion IP estatica, gateway y mascara de subred
6. **Hostname** - Establecer un nombre de host personalizado para el modulo ESP
7. **Config summary** - Ver todos los ajustes WiFi actuales de un vistazo (SSID, IP, MAC, hostname, firmware, version de la app)

### Otros
- **Pantalla Acerca de** (tecla I): Muestra version, fecha de compilacion, autor, URL de GitHub y licencia
- **Log de Depuracion UART**: Muestra/oculta el log UART en tiempo real con la tecla L
- **Fuente comprimida**: Sistema de fuente comprimida por nibbles integrado (sin dependencia de archivo font.bin externo)
- **Tres backends UART**: Soporta hardware ZX-Uno, AY-UART (ZX-Badaloc) y ZX Spectrum Next
- **Recuperacion de baudios NextSync** (solo build Next): Detecta y recupera automaticamente si el ESP fue dejado a velocidad incorrecta por NextSync
- **Fecha de compilacion**: Incrustada automaticamente en tiempo de ensamblado via Lua

## Requisitos

- ZX Spectrum (48K o superior) o compatible
- Modulo WiFi basado en ESP8266:
  - **ZX-Uno**: UART integrado (target por defecto)
  - **AY-UART**: ZX-Badaloc o implementaciones similares bit-banged AY-3-8912
  - **ZX Spectrum Next**: UART hardware con FIFO
- Sistema compatible con +3DOS para carga (o tap2wav para carga desde cinta)

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
| NEXT | `netmanzx-next.tap` | ZX Spectrum Next |

### Carga

**TAP (cinta/emuladores):**
Simplemente carga el archivo TAP - el cargador BASIC se ejecutara automaticamente y cargara el programa.

**+3DOS:**
Pon el fichero NETMANZX.BAS y netmanzx.cod en el mismo directorio. Ejecuta NETMANZX.BAS desde el navegador de ficheros de esxDOS.

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
| I | Pantalla Acerca de |
| ESC | Salir del programa |

### Robustez de Conectividad

- **Deteccion BREAK**: Tecla BREAK comprobada cada ~5ms durante comandos AT para cancelacion casi instantanea
- **Deteccion Automatica de Caida WiFi**: Parseo asincrono de eventos del ESP para detectar desconexiones inesperadas al instante
- **Chequeo Periodico en Idle**: Validacion periodica mediante comandos AT para comprobar que el enlace sigue activo
- **Proteccion UART Busy**: Mecanismo tipo mutex que evita que el parser asincrono interfiera durante operaciones criticas
- **Reintento de IP al Conectar**: 3 intentos con intervalos de 1 segundo tras la asociacion WiFi exitosa
- **Recuperacion Automatica de Estado**: Al perder conexion, la interfaz pasa a Disconnected y programa un rescaneo seguro
- **Recuperacion NextSync** (solo build Next): Detecta ESP dejado a 1152000 baudios por NextSync y reinicia automaticamente a la velocidad correcta

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
