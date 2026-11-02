[简体中文](../../README.md) · [English](../../docs/i18n/README.en.md) · [繁體中文](../../docs/i18n/README.zh-Hant.md) · [日本語](../../docs/i18n/README.ja.md) · [한국어](../../docs/i18n/README.ko.md) · **Español** · [Português do Brasil](../../docs/i18n/README.pt-BR.md)

<p align="center"><img src="../images/phototrail-icon.png" width="160" alt="PhotoTrail"></p>

# PhotoTrail

Dale a cada foto su lugar en el viaje.

PhotoTrail es una herramienta gratuita para organizar fotos en macOS. Añade ubicaciones, corrige fechas y créditos, y convierte nombres dispersos en una secuencia clara. Importa una vez y combina los tres flujos de trabajo o utiliza solo el que necesites.

| Tu objetivo | Qué ofrece PhotoTrail |
| --- | --- |
| Recuperar ubicaciones | Asociar el recorrido del viaje y ajustar puntos en el mapa |
| Completar información | Corregir fechas y añadir autoría, derechos y palabras clave |
| Ordenar nombres | Combinar fechas, lugares y secuencias, manteniendo los archivos relacionados |

## Vista previa

![Vista de fotos, mapa y panel de recorridos](../screenshots/photo-detail.png)

![Editor de metadatos: fotos, campos habituales y preajustes por lotes](../screenshots/metadata-editor.png)

![Renombrado por lotes: reglas y vista previa de nombres](../screenshots/batch-rename.png)

## Tres formas de organizar tus fotos

### 1. Recorridos y ubicación en mapas

**Conserva el recorrido, aunque tu cámara no tenga GPS.**

- **Ubicar desde un recorrido:** importa GPX, KML o KMZ con marcas de tiempo, compara las horas de captura y revisa antes de aplicar.
- **Ajustar en el mapa:** usa Apple Maps o AMap para buscar, guardar favoritos, mover marcadores o asignar un lugar a varias fotos.
- **Crear recorridos desde fotos:** genera GPX con fotos geolocalizadas o exporta copias con ubicación y un informe de verificación.

También puedes completar datos de región, como provincia y ciudad. Las rutas sin tiempos por punto solo se visualizan. La asociación respeta los segmentos y el intervalo registrado.

### 2. Consulta y edición de metadatos

**Pon en orden fechas, autoría y derechos.**

- **Buscar y editar:** localiza información EXIF, IPTC, XMP y otros datos por nombre, etiqueta o valor; edita los campos habituales directamente.
- **Empezar con un preajuste:** suma una hora, recupera fechas desde los nombres, unifica campos de fecha o completa autor y derechos ausentes.
- **Combinar reglas:** ordena asignaciones, copias de campos y ajustes de tiempo, y guárdalos como preajuste. Describe la fecha del nombre con `YYYY`, `MM`, `DD` y otros símbolos, sin expresiones regulares.

Edita individualmente o por lotes JPEG, HEIC/HEIF, PNG, TIFF, WebP, AVIF, GIF, PSD/PSB, JPEG 2000 (JP2), JPEG XL, RAW compatibles y XMP existentes. Los campos editables dependen del formato; otras imágenes estáticas se pueden importar para consultar sus datos. Véase la [tabla de formatos](../FORMATS.md) (en chino).

### 3. Renombrado por lotes

**Cambia los números de cámara por nombres reconocibles.**

- **Crear tu formato:** combina fechas, lugares, dispositivos, texto y secuencias; arrastra las reglas para ordenarlas.
- **Revisar antes:** compara nombres originales, finales y conflictos para todas las fotos o una selección.
- **Mantener las relaciones:** procesa JPG, RAW y XMP asociados. Guarda esquemas y restaura los nombres desde el registro si los archivos no han cambiado.

Guarda primero los cambios de las fotos. Hay un modo compatible con ExFAT; los permisos de carpetas y el espacio adicional se explican en la [guía detallada](../BEHAVIOR.md).

## Guardar los cambios

**Primero revisa; escribe cuando esté listo.** Explorar, editar y aplicar preajustes no modifica los archivos de inmediato. Puedes deshacer antes de guardar.

Por defecto, Guardar todos los metadatos (⌘S) guarda ubicación y campos conjuntamente, sin depender de la selección o los filtros. En Ajustes puedes limitarlo a la página actual. El guardado local sigue la configuración de copias de seguridad y verifica mediante lectura, sin recomprimir píxeles. Los cambios fallidos quedan pendientes.

La fototeca de Apple usa la interfaz del sistema para ubicación y fecha, con límites de edición y copia diferentes. Las parejas JPG + RAW pueden compartir ubicación; los demás campos no se copian automáticamente.

## Primeros pasos

1. **Importa:** abre o arrastra fotos y comprueba la hora de captura y la zona horaria de la cámara.
2. **Añade lugares:** revisa la asociación con el recorrido o elige un punto en el mapa.
3. **Completa detalles:** edita campos o aplica un preajuste.
4. **Guarda:** revisa y escribe los cambios; después previsualiza y ejecuta el renombrado si lo necesitas.

Cada flujo funciona por separado. Quitar fotos de la lista no borra archivos; exportar copias no sobrescribe los originales.

## Muchas fotos y caché

La importación muestra progreso y tiempo restante estimado; las miniaturas se cargan según se necesitan. Ajustes, favoritos y caché de recorridos se conservan. Las cachés de miniaturas y lectura de metadatos se reconstruyen al iniciar de nuevo.

## Idiomas

Disponible en chino simplificado, English, 繁體中文, 日本語, 한국어, Español y Português do Brasil. Cambia el idioma en Ajustes, guarda el trabajo y vuelve a abrir la aplicación.

La configuración inicial propone AMap para chino simplificado y Apple Maps para los demás idiomas; puedes elegir otro. El idioma no altera las fechas. El idioma del mapa depende del proveedor.

## Descarga e instalación

[Descargar la última versión](https://github.com/LittleSixNine/PhotoTrail/releases/latest) · [Historial de versiones](https://github.com/LittleSixNine/PhotoTrail/releases)

Requiere **macOS 14 o posterior**, con Apple silicon o Intel. Abre el DMG, cierra PhotoTrail y arrastra la aplicación a Aplicaciones.

Es gratuito. Los paquetes actuales aún no cuentan con firma Developer ID ni notarización de Apple, por lo que macOS puede bloquear el primer inicio. La descarga automática de actualizaciones está desactivada por defecto; la instalación es manual.

## Servicio AMap y costes

AMap necesita tu Web JS API Key y securityJsCode, guardados en el llavero local de macOS. Apple Maps no necesita credenciales de AMap.

AMap factura a tu cuenta de desarrollador los servicios de pago o el uso que supere su cuota gratuita. PhotoTrail es gratuito y no cobra tarifas del mapa.

## Coordenadas y privacidad

- **Las fotos se procesan localmente.** AMap recibe búsquedas y coordenadas del mapa. Mostrar recorridos sin caché o renovar su conversión también envía las coordenadas necesarias del recorrido.
- **Se distinguen las coordenadas del mapa y de las fotos.** Los puntos confirmados en AMap se verifican y convierten a WGS84; los nuevos puntos se limitan a ubicaciones de China continental validadas por región administrativa. Las fotos sin sistema declarado solo se muestran provisionalmente como WGS84, sin reescribirlas.
- **Los recorridos originales se conservan.** La conversión no cambia la fuente; la asociación temporal usa los datos WGS84 originales. La verificación no garantiza la precisión del GPS o del punto elegido.

## Origen del proyecto

PhotoTrail comenzó añadiendo ubicaciones a fotos de cámara y escaneos de película, y se amplió a metadatos y nombres. Parte del procesamiento procede de [marchyman/GeoTag](https://github.com/marchyman/GeoTag).

## Skill para agentes

Trabaja con un agente sin abrir la aplicación Mac. El [PhotoTrail Skill](../../skill/) independiente genera GPX desde fotos o geolocaliza con GPX, creando copias JPEG/HEIC y un informe sin modificar los originales.

### Instalación

Envía esto a un agente con acceso a archivos locales y ejecución de comandos:

> Lee https://raw.githubusercontent.com/LittleSixNine/PhotoTrail/phototrail/skill/INSTALL.md , instala PhotoTrail Skill siguiendo las instrucciones y comprueba el entorno de ejecución.

Requiere **Python 3.11+ y ExifTool**; verificado en macOS. No accede a búsquedas de mapas ni a la fototeca de Apple y no escribe RAW/XMP. Consulta la [guía](SKILL.es.md) y los [parámetros](../../skill/SKILL.md).

## Desarrollo

Requiere Xcode completo (Swift 6.3+, SDK de macOS 26+), XcodeGen y SwiftLint. Consulta la [guía de desarrollo](DEVELOPMENT.en.md) para compilación y pruebas, y los [límites funcionales](../BEHAVIOR.md).

## Agradecimientos y licencia

Gracias a Marco S Hyman, autor de [GeoTag](https://github.com/marchyman/GeoTag), y a proyectos como [ExifTool](https://exiftool.org/).

Se permiten el uso personal y profesional y la redistribución gratuita. Cobrar por distribución o acceso al software requiere permiso escrito. Consulta la [licencia](../../LICENSE) y los [avisos de terceros](../../THIRD_PARTY_NOTICES.md). Es un proyecto derivado independiente, sin afiliación oficial con Apple o AMap.
