# Estado de esta edición

19 de noviembre de 2026. Candidata de desarrollo de Mi Kidu Community.

- `swift test` pasó 25 pruebas en Mac. Incluye creación y reapertura de un perfil local, estabilidad del dibujo en perfiles independientes, generación del encargo, contrato Familia en un origen ficticio y CLI ficticios para OpenClaw, Codex, Claude Code y el adaptador local. También comprueba errores de proceso, salida demasiado grande y límite de espera.
- Los esquemas `MiKidu-Mac` y `MiKidu-iPhone` compilaron sin firma. La build de iPhone incluye el widget y Xcode validó el producto Watch. El producto Watch quedó junto a la app de iPhone, por lo que su empaquetado para distribución sigue pendiente. La generación del proyecto coincide con `python3 tools/generate_project.py --check` para el árbol de esta entrega.
- En una compilación de prueba anterior con SQLite aislado en Mac se comprobó la bienvenida, la creación y vista del perfil ficticio, la pantalla oficial de Kidual deshabilitada y la revisión del encargo. La selección final de CLI y sus límites se verificaron mediante pruebas automatizadas.
- En una prueba de integración separada, Codex CLI autenticado procesó una consulta sintética y devolvió exactamente `KIDU_OK`. No se usaron cuentas reales de OpenClaw ni Claude Code para esta comprobación.
- La vinculación Familia está apagada y sus valores de instalación se aportan fuera del repositorio. La autorización y el canje se probaron con fixtures. Queda pendiente la prueba con consentimiento en una instalación firmada y un entorno habilitado por Kidual.

Las compilaciones no equivalen a instalación en hardware, emparejamiento con Apple Watch ni distribución. Los datos y perfiles de prueba son ficticios.
