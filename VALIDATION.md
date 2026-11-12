# Estado de esta edición

Fecha: 2026-11-12. Edición comunitaria de desarrollo.

La exportación usa una lista explícita de archivos fuente, pruebas y plantillas. Su historial comienza aquí; no hereda historial, documentación operativa ni configuración privada. Los identificadores y el contenedor local están separados de las instalaciones privadas.

Comprobaciones realizadas sobre esta exportación:

- `swift test` terminó correctamente en macOS ARM con Swift 6. La suite del núcleo ejecutó nueve pruebas sin fallos; aparecen avisos de aislamiento de actor en el montaje de algunos XCTest.
- La demo sintética pasó importación, health, acción y repetición entre procesos: la repetición conserva revisión y devuelve `duplicate`.
- El proyecto Xcode generado coincide con `python3 tools/generate_project.py --check`.
- El target `MiKidu-Mac` compiló con `CODE_SIGNING_ALLOWED=NO`.
- La revisión de los archivos seleccionados no encontró credenciales, direcciones de infraestructura ni rutas personales. Los correos de prueba usan `example.com`. No es una garantía de ausencia de cualquier vulnerabilidad.

Continúan pendientes la validación visual completa del compañero entre aplicaciones, la firma y distribución, los builds de esta edición para iPhone/Watch, el emparejamiento real con Watch y una conexión funcional con asistentes externos.

Los builds o pruebas de otra edición no prueban esta edición. No se incluyen binarios firmados ni se promete un lanzamiento estable.
