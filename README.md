# Mi Kidu Community

An experimental, local-first companion built with Swift and SwiftUI. Contributions welcome.

Un compañero personal para Mac, iPhone y Apple Watch: avatar procedural, cuidados locales y una base para presencia en el escritorio. Esta edición comunitaria funciona con datos de ejemplo y no necesita una cuenta de Kidual.

**Estado: código de desarrollo.** No es una app terminada, un instalador firmado ni un asistente capaz de controlar todo el equipo. No contiene la configuración personal de iVictor/OpenClaw. Consulta [VALIDATION.md](VALIDATION.md) para distinguir comprobaciones realizadas de trabajo pendiente.

## Probar el proyecto

Requisitos: Swift 6, Xcode compatible con macOS 15 / iOS 18 / watchOS 11 y Python 3 para generar el proyecto. SQLite procede del sistema. No hay dependencias de paquetes remotos.

```sh
swift test
python3 tools/generate_project.py
open MiKidu.xcodeproj
```

Para Mac, selecciona `MiKidu-Mac`. Los identificadores de esta edición usan `org.example.mikidu.community`; el estado local se guarda en un contenedor `MiKiduCommunity` separado. Los dispositivos Apple necesitan tu propia configuración de firma. Copia `Config/Signing.local.xcconfig.example` a `Config/Signing.local.xcconfig` si la necesitas; ese archivo está excluido de Git. No se requiere contratar un servidor ni activar un proveedor de IA para probar los cuidados locales.

En la primera apertura pulsa **Abrir Kidu** e importa [Examples/demo-kidu.json](Examples/demo-kidu.json). Es un personaje ficticio, sin datos de personas reales. Permite probar alimentar, beber, acariciar, jugar, dormir y despertar. En Mac, **Ven aquí** muestra el panel flotante básico. El movimiento autónomo entre aplicaciones sigue siendo experimental; no lo presentamos como validado.

## Qué contiene

| Módulo | Alcance |
| --- | --- |
| `MiKiduCore` | Estado y cuidados, SQLite, revisión y deduplicación de acciones |
| `MiKiduPresentation` | Avatar procedural y componentes SwiftUI |
| `MiKiduShell` / `MiKiduWindowMotion` | Panel de escritorio y base de movimiento macOS |
| `MiKiduWidgetWatch` | Componentes para widget y Watch |
| `mi-kidu-service` | Operador local JSON por stdin/stdout; no es un servidor de red autenticado |

## Mejoras que buscamos

- Comprobar presencia, foco, clics y varios monitores en Mac.
- Mejorar accesibilidad, teclado, texto grande y reducción de movimiento.
- Dar más expresividad al personaje manteniendo un consumo bajo.
- Mejorar el primer uso, la documentación y las pruebas de los componentes.

Lee [CONTRIBUTING.md](CONTRIBUTING.md) antes de enviar una propuesta. Las pull requests se revisan antes de incorporarlas; una propuesta no se instala automáticamente en equipos personales. No se promete respuesta inmediata ni que publicar el proyecto atraiga colaboradores.

## Privacidad y recursos

No hay telemetría de instalaciones ni rastreo de usuarios. Los cuidados básicos son locales. Esta distribución no incluye bases de datos reales, historiales privados, claves, infraestructura, correos, recursos comerciales comprados ni integraciones privadas. Los datos que introduzcas o importes se quedan en tu instalación salvo las transferencias explícitas entre tus propios dispositivos Apple.

Código bajo [MIT](LICENSE). El motor de avatar conserva la licencia y atribución de [Blobatar](LICENSE-Blobatar.txt). Las ilustraciones, tipografías o recursos externos que quieras aportar deben tener una licencia compatible y redistribuible; no incluyas packs comprados.
