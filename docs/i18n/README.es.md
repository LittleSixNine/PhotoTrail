[简体中文](../../README.md) · [English](../../docs/i18n/README.en.md) · [繁體中文](../../docs/i18n/README.zh-Hant.md) · [日本語](../../docs/i18n/README.ja.md) · [한국어](../../docs/i18n/README.ko.md) · **Español** · [Português do Brasil](../../docs/i18n/README.pt-BR.md)

<p align="center"><img src="../images/phototrail-icon.png" width="160" alt="PhotoTrail"></p>

# PhotoTrail

Organiza ubicaciones, metadatos y nombres de fotos en macOS.

PhotoTrail reúne **la asociación de fotos con recorridos, la edición de metadatos y el renombrado por lotes**. Añade ubicaciones de un viaje, corrige fechas y datos y aplica un criterio común a los nombres. Puedes combinar estos flujos o usarlos por separado. Parte del procesamiento de fotos procede de [GeoTag](https://github.com/marchyman/GeoTag).

| Qué quieres organizar | Función | Ejemplos |
| --- | --- | --- |
| Lugares de captura | Recorridos y mapas | Asociar un recorrido y revisar ubicaciones en el mapa |
| Información de las fotos | Consulta y edición de metadatos | Fechas, autoría, palabras clave y datos del equipo |
| Nombres de archivos | Renombrado por lotes | Fecha y secuencia, sustitución de texto y archivos asociados |

## Descarga y requisitos

[Descargar la última versión estable](https://github.com/LittleSixNine/PhotoTrail/releases/latest) · [Historial de versiones](https://github.com/LittleSixNine/PhotoTrail/releases)

Requiere **macOS 26 o posterior**. Compatible con Apple silicon e Intel. La distribución actual usa firma ad-hoc y aún no tiene firma Developer ID ni notarización de Apple, por lo que macOS puede bloquear el primer inicio.

PhotoTrail es gratuito. La descarga automática de actualizaciones está desactivada por defecto. La instalación es manual: abre el DMG, sal de PhotoTrail y arrastra la app a Aplicaciones.

## Funciones

### 1. Recorridos y ubicación en mapas

- **Asocia fotos por hora:** importa GPX, KML o KMZ con marcas de tiempo por punto. Previsualiza los resultados en la lista o usa la barra del mapa para completar ubicaciones ausentes o sustituirlas explícitamente. Las coincidencias se limitan al mismo segmento y su cobertura; no se extrapola a través de interrupciones ni se resuelven conflictos sin avisar.
- **Revisa y ajusta en el mapa:** usa Mapas de Apple o AMap, búsquedas, favoritos y miniaturas. Aplica una ubicación a varias fotos o arrastra un marcador individual. Las ubicaciones confirmadas de AMap se verifican y convierten a WGS84.
- **Crea y exporta recorridos:** genera GPX a partir de fotos con ubicación y fecha; los intervalos largos crean segmentos. Muestra, oculta, almacena y exporta recorridos, o exporta copias de fotos con ubicación y un informe de verificación a una carpeta nueva.

Los recorridos sin hora por punto son solo de consulta. No se admite CSV de recorridos; los generados con fotos se exportan como GPX. KMZ lee doc.kml en la raíz o el único KML del archivo, sin cargar enlaces externos ni adjuntos.

### 2. Consulta y edición de metadatos

- **Edita campos habituales:** formularios para información, fechas y dispositivos. Completa títulos, descripciones, autoría, derechos y palabras clave; elige el nombre comercial o el modelo de metadatos, o escribe un valor propio. Consulta el [catálogo y sus fuentes](../DEVICE_CATALOG.md).
- **Consulta los campos completos:** filas compactas con nombre, valor y origen, búsqueda, grupos, filtros y etiquetas adicionales. La lectura en segundo plano prioriza las fotos seleccionadas y distingue EXIF, IPTC, XMP y datos del fabricante.
- **Edita varias fotos y campos:** selecciona con ⌘/Mayús para asignar valores comunes o copiarlos de otro campo. Por ejemplo, copia la fecha de creación EXIF de cada foto a varios campos de fecha. Revisa las operaciones por lotes antes de añadirlas como borradores que se pueden deshacer.
- **Organiza e intercambia:** correcciones de fechas, cámara, objetivo y exposición, ajustes predefinidos, comparación entre fotos e importación/exportación controlada de metadatos CSV/XMP.

**No todas las etiquetas que se pueden consultar son editables.** Los nuevos editores admiten 62 campos EXIF/IPTC/XMP en JPEG y archivos XMP asociados existentes. Los campos de solo lectura muestran un candado. Los RAW originales, HEIC y la fototeca de Apple no admiten estos nuevos editores; conservan las herramientas previas de fecha y ubicación. El CSV de metadatos es distinto del CSV de recorridos aún no admitido. Consulta los [destinos y límites](../BEHAVIOR.md) (chino).

### 3. Renombrado por lotes

- **Empieza con una opción habitual:** fecha de captura y secuencia, prefijo o buscar y reemplazar. Combina texto, fechas, secuencias, metadatos, listas y expresiones regulares: 97 entradas de acciones, filtros y opciones avanzadas.
- **Compara antes y después:** ordena reglas a la izquierda y revisa nombres originales y finales, archivos asociados y conflictos a la derecha. Puedes mostrar pasos intermedios y guardar ajustes predefinidos.
- **Mantén unidos los archivos relacionados:** previsualiza fotos y archivos asociados como un grupo, sin sobrescribir archivos existentes. El historial permite restaurar nombres si la identidad y el contenido coinciden con el registro.

Usa fotos locales importadas o Añadir archivos para archivos normales. Se excluyen carpetas y elementos de la fototeca. Si quedan cambios de información o ubicación, se te pide guardarlos primero; revisa la vista previa actualizada antes de confirmar el renombrado. Este se ejecuta por separado del guardado de metadatos.

### Guardar los cambios

**Guardar todos los metadatos** (⌘S) escribe todos los cambios pendientes de información y ubicación de la ventana actual, sin limitarse a la pestaña, selección o filtro activos. Consultar y previsualizar no escribe archivos; puedes deshacer antes de guardar. Las escrituras locales respetan los ajustes de copia de seguridad y verifican los resultados mediante una nueva lectura, sin recomprimir los píxeles. Los pares JPG + RAW pueden compartir cambios de ubicación, pero los campos nuevos no se copian automáticamente a RAW. La fototeca usa la interfaz del sistema y tiene otro alcance de edición.

## Primeros pasos

1. **Importa y comprueba:** configura idioma, copias y mapa; abre o arrastra fotos. Revisa fechas y zona horaria de la cámara y corrígelas en el espacio de metadatos si es necesario.
2. **Añade ubicaciones:** importa GPX/KML/KMZ, selecciona fotos, revisa coincidencias y aplica los resultados fiables. Sin recorrido, usa el mapa, la búsqueda o los favoritos.
3. **Completa la información:** usa los campos habituales para editar rápido y la lista completa para otras etiquetas y herramientas por lotes.
4. **Guarda todo junto:** revisa los cambios y pulsa Guardar todos los metadatos. AMap requiere tu Web JS API Key y securityJsCode; Mapas de Apple no necesita credenciales de AMap.
5. **Ordena los nombres:** elige el alcance y las reglas, comprueba archivos asociados, conflictos y nombres finales, y confirma. Omite este paso si quieres conservar los nombres.

Puedes usar cada función por separado. Generar GPX o exportar copias con ubicación no sobrescribe los originales; quitar fotos de la lista no borra sus archivos. Las copias de seguridad de archivos locales no incluyen elementos de la fototeca.

## Idiomas y configuración

Disponible en chino simplificado, inglés, chino tradicional, japonés, coreano, español y portugués de Brasil. Elige el idioma en el primer paso de configuración. **El chino simplificado usa AMap por defecto; los demás idiomas usan Mapas de Apple.** Puedes cambiarlo en el paso del mapa. Se conserva el mapa elegido por los usuarios existentes.

Puedes cambiar el idioma en Ajustes. Guarda tu trabajo y vuelve a abrir la app para aplicarlo a todas las ventanas y avisos del sistema. El idioma no cambia la zona horaria de la cámara ni las fechas de las fotos.

![Configuración del idioma](../screenshots/es/setup.png)

## Mapas y privacidad

AMap convierte las ubicaciones seleccionadas a WGS84 antes de aplicarlas. Los cambios solo se escriben en las fotos al guardar. También puedes editar correctamente la ubicación de fotos tomadas en China continental.

- Las coordenadas existentes sin datum declarado se muestran provisionalmente como WGS84; esto no modifica sus metadatos.
- AMap recibe términos de búsqueda y coordenadas necesarias para mostrar el mapa y validar ubicaciones. No se suben archivos de fotos.
- Mostrar una ruta sin caché local válida envía sus coordenadas a AMap por lotes para convertirlas. El archivo del recorrido no se sube ni modifica, y las coincidencias siguen usando los datos WGS84 originales.
- Las claves de AMap se guardan en el llavero local de macOS; los favoritos y las cachés, en la carpeta local de la app.
- Las etiquetas, los resultados de búsqueda y los nombres de lugares dependen del proveedor. Siete idiomas de interfaz no garantizan mapas en siete idiomas.
- La validación ayuda a evitar errores al mezclar sistemas de coordenadas, pero no confirma la precisión del GPS original ni de un punto elegido manualmente.

Obtén tus propias credenciales de AMap. Superar la cuota gratuita o usar servicios de pago puede generar cargos en tu cuenta. PhotoTrail no recauda esas tarifas; gestiona los pagos en AMap.

## Skill para agentes y desarrollo

La [guía del Skill independiente](SKILL.es.md) explica cómo crear GPX desde fotos o generar copias JPEG/HEIC con ubicación e informes a partir de fotos y GPX. Requiere **Python 3.11+ y ExifTool** y se ha verificado en macOS. El agente debe poder acceder a archivos locales y ejecutar comandos; un chat solo con navegador no basta.

El Skill procesa localmente y no accede a mapas, credenciales de la app ni fototeca. Su escritura actual no admite RAW/XMP. Los comandos, claves JSON, estados y códigos de error no cambian con el idioma.

Consulta la [guía de desarrollo en inglés](DEVELOPMENT.en.md). Gracias a Marco S Hyman por GeoTag y al proyecto ExifTool. Consulta la [licencia original](../../LICENSE), su [traducción de referencia al inglés](LICENSE.en.md) y los [avisos de terceros](../../THIRD_PARTY_NOTICES.md). Se permite el uso personal y profesional y la redistribución gratuita; cobrar por distribuir el software o acceder a él requiere permiso conforme a la licencia aplicable. PhotoTrail es independiente y no está afiliado oficialmente a Apple ni a AMap.
