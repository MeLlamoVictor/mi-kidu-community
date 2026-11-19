# Mi Kidu Community

Kidu es un agente para preparar encargos en Mac y iPhone. Puedes ordenar un objetivo, contexto, permisos y resultado esperado, revisar el texto y llevarlo a OpenClaw, Codex o Claude. En Mac, puedes recibir respuestas de tus propios CLI de OpenClaw, Codex y Claude Code o de un adaptador compatible. El perfil y la preparación funcionan sin un servidor ni una cuenta.

## Probar

Requisitos de desarrollo: Swift 6, Xcode compatible con macOS 15, iOS 18 y watchOS 11, y Python 3 para regenerar el proyecto. SQLite es una biblioteca del sistema. El proyecto no instala paquetes remotos.

```sh
swift test
python3 tools/generate_project.py --check
open MiKidu.xcodeproj
```

Elige el esquema `MiKidu-Mac` o `MiKidu-iPhone`. Para un dispositivo físico, usa tu configuración de firma en `Config/Signing.local.xcconfig`, que Git ignora. Esta edición usa identificadores de desarrollo propios y el contenedor `MiKiduCommunity`.

1. Escribe un nombre o apodo ficticio, como **Nube de Tiza**, y pulsa **Continuar con mi nombre**. El mismo nombre normalizado da la misma forma. El perfil tiene un identificador local independiente.
2. Abre **Perfil** para ver el nombre y el origen del perfil.
3. En **Preparar contexto**, escribe un objetivo y añade los hechos, límites o formato de entrega que hagan falta. Por ejemplo, «Explica cómo organizar una reunión de 15 minutos y dame una agenda de tres puntos».
4. Pulsa **Revisar encargo**, edita el texto y elige un proveedor. **Copiar para…** pasa el texto revisado al portapapeles. Pégalo y envíalo cuando quieras en el proveedor elegido. En Mac, también puedes elegir el ejecutable del proveedor y pulsar **Enviar** para ver su respuesta en Kidu.

**Entrar con Kidual** explica el estado de la vinculación y ofrece la web oficial. El cliente de perfil Familia está preparado y queda apagado hasta que Kidual habilite y verifique el flujo oficial. Consulta [el contrato de vinculación](docs/PERFIL-FAMILIA.md).

Puedes probar también **Abrir una copia** con el perfil ficticio de [Examples/demo-kidu.json](Examples/demo-kidu.json) en un almacén vacío. En Mac, **Liberar** abre el avatar de escritorio y desde él se puede volver al espacio del agente. El Apple Watch emparejado puede solicitar el perfil de la instalación de iPhone.

### Icono del personaje

En Mac, el Dock dibuja el Kidu del perfil activo y adapta el fondo al aspecto claro u oscuro del sistema. En iPhone, abre **Perfil** para aplicar la variante incluida que más se parece a tu Kidu o recuperar el icono principal. El nombre y el dibujo del perfil se procesan en el dispositivo.

## Colaborar

Lee [CONTRIBUTING.md](CONTRIBUTING.md) antes de enviar una propuesta. Buscamos mejoras en la preparación de encargos, accesibilidad del editor y presencia en escritorio. Usa [la guía de proveedores](docs/PROVEEDORES.md) con cuentas y preferencias propias.

El repositorio distribuye código y datos ficticios. El código se ofrece con [licencia MIT](LICENSE) y el motor procedural conserva la [atribución de Blobatar](LICENSE-Blobatar.txt). Lee [PRIVACY.md](PRIVACY.md) para saber qué guarda la app y [VALIDATION.md](VALIDATION.md) para conocer las comprobaciones de esta edición.
