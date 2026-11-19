# Entregar un encargo a un proveedor

**Revisar encargo** crea un texto editable a partir de lo que has escrito. En Mac puedes enviarlo a un ejecutable de confianza que hayas elegido. En iPhone, copia el texto revisado y pégalo en tu propia sesión del proveedor. La app no abre un puerto de escucha ni instala los proveedores.

## Conexión optativa en Mac

En la revisión, selecciona el proveedor y pulsa **Elegir ejecutable**. Busca el archivo del CLI que instalaste en tu equipo. Kidu recuerda la ruta para ese proveedor y muestra la respuesta o el error cuando pulsas **Enviar**. El portapapeles sigue disponible si prefieres una sesión interactiva.

| Proveedor | Configuración y comportamiento |
| --- | --- |
| OpenClaw | Usa tu [instalación](https://docs.openclaw.ai/start/getting-started) y el ID de un agente dedicado a conversación. Configura en OpenClaw sus [permisos de herramientas](https://docs.openclaw.ai/gateway/configuration-reference) para el uso que quieras. Kidu solicita un turno con ese agente y un UUID de conversación propio. No activa la entrega a canales. [Referencia de `agent`](https://docs.openclaw.ai/cli/agent). |
| Codex CLI | Inicia sesión en tu [CLI](https://developers.openai.com/codex/cli/) antes de elegirla en Kidu. El turno usa una sesión efímera, directorio temporal, sandbox de solo lectura y herramientas de shell y búsqueda web desactivadas. |
| Claude Code | Inicia sesión en tu [CLI](https://code.claude.com/docs/en/cli-reference) antes de elegirla. El turno usa modo restringido, con herramientas y comandos de sesión retirados, sin conservar un hilo que se pueda reanudar. |
| Otro agente | Elige tu adaptador local con el contrato descrito abajo. El adaptador decide sus permisos y proveedores. |

Las cuentas, claves y permisos se gestionan en cada producto. Kidu lanza el archivo elegido con argumentos fijos, desde un directorio temporal, y entrega el texto por entrada estándar. No ejecuta el texto como comando, no inicia una sesión de shell y no le añade datos del perfil. El programa elegido conserva los permisos de tu usuario y los de su propia configuración. Usa un agente de OpenClaw configurado para conversación y un adaptador que controles. Los proveedores pueden registrar el texto o aplicar sus propias condiciones de uso.

OpenClaw solicita un turno de hasta 60 segundos. Kidu limita la espera a 70 segundos, la entrada a 16 KiB y la salida a 64 KiB para todos los adaptadores. Tras un fallo de transporte, revisa el historial del proveedor antes de reenviar.

## Contrato del adaptador «Otro agente»

- El ejecutable se invoca con cero argumentos y recibe texto UTF-8 por `stdin` hasta EOF.
- Devuelve la respuesta como texto UTF-8 en `stdout` y termina con código 0.
- Si falla, termina con un código distinto de 0. Kidu muestra el código y reserva `stderr` para el terminal del proveedor.
- No incluyas diagnósticos en `stdout`. Son parte de la respuesta visible.

Puedes probar con este adaptador inerte. Guárdalo fuera del checkout, dale permiso de ejecución y selecciónalo en Kidu. Repite el texto y no requiere ninguna cuenta.

```sh
#!/bin/sh
exec /bin/cat
```
