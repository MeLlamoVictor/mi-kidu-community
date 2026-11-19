# Perfil Familia de Kidual

**Estado inicial.** La edición pública tiene la vinculación desactivada. **Entrar con Kidual** lleva a la web oficial y una visita a la web no vincula el perfil. El alta con un nombre se puede usar desde el primer arranque.

## Configurar una distribución autorizada

El operador de esa distribución recibe los parámetros de Kidual por separado y los incorpora a `Config/FamilyLink.local.xcconfig`, excluido de Git. El archivo de la edición pública no contiene URLs de autorización o canje ni sus campos de intercambio. Sus pruebas usan un origen reservado para ejemplos.

| Ajuste | Valor que aporta la distribución autorizada |
| --- | --- |
| `KIDU_FAMILY_LINK_ENABLED` | `YES` solo después de verificar la disponibilidad oficial |
| `KIDU_FAMILY_AUTHORIZATION` y `KIDU_FAMILY_EXCHANGE` | Las dos URLs HTTPS oficiales. Si Xcode interpreta `//` como comentario en un valor, compón las dos barras usando una variable local con valor `/`. |
| `KIDU_FAMILY_CLIENT_ID` | El identificador asignado por Kidual |
| `KIDU_FAMILY_REDIRECT` y `KIDU_FAMILY_CALLBACK_SCHEME` | La URI registrada y su esquema |
| `KIDU_FAMILY_EXCHANGE_FIELDS` | Nombres de cuatro campos, separados por comas, para el cliente, retorno, código y verificador en ese orden |
| `KIDU_FAMILY_PROFILE_FIELDS` | Nombres de los dos campos devueltos para el identificador opaco y la semilla |

La app acepta endpoints únicamente del origen HTTPS oficial de Kidual. La autorización se realiza en el navegador con estado de un solo uso y PKCE S256. El canje rechaza las redirecciones y no usa cookies ni tokens de sesión de Kidual. La respuesta esperada permite crear la forma de un perfil y no da acceso a otros datos de Familia. El primer enlace requiere un almacén vacío y los perfiles ya guardados se conservan.

Antes de habilitar la función, comprueba consentimiento, cancelación, caducidad y reintento con datos sintéticos en el entorno aprobado por Kidual. Verifica que el retorno llega a la app firmada y que una segunda instalación autorizada recibe la misma forma. Los fixtures del repositorio prueban las validaciones locales y la creación del perfil con respuestas sintéticas.

Referencias del patrón nativo y PKCE. [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252.html) · [RFC 7636](https://www.rfc-editor.org/rfc/rfc7636.html)
