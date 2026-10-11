> 2026-10-12: La biblioteca local de esquemas permite crear, actualizar, guardar como, renombrar, eliminar e importar/exportar JSON, con cinco plantillas iniciales. Los ejemplos son independientes; los cambios ofrecen Guardar/Descartar/Cancelar. Se restaura el último esquema guardado y una biblioteca vacía sigue vacía. Guardar no renombra fotos. Las reglas antiguas de Windows siguen siendo legibles; las nuevas requieren versión 2, sin intercambio directo con Mac. Implementado y verificado, pendiente de aceptación. El lote anterior de coincidencia con rutas fue aceptado a partir de la validación del agente Windows; permanecen las limitaciones anteriores.

> 2026-10-11: La coincidencia de pistas para fotos seleccionadas conserva Calcular resultados → Aplicar resultados. Por defecto completa solo ubicaciones ausentes; las opciones avanzadas permiten sobrescribir explícitamente o usar solo la pista cargada actual. Cada foto usa su fecha efectiva, incluidos borradores, sin adivinar zonas ni redondear precisión no representable. Las pistas se comparan por separado y la ambigüedad no se resuelve por orden de importación. El filtro de resultados fallidos solo cambia la vista. Solo se aplican éxitos con cambios netos, con deshacer del lote conservando borradores anteriores. Se verifican todas las fuentes antes de confirmar. CSV Aplicar añade borradores; solo guardar copias escribe archivos, sin sobrescribir. Implementado y verificado, pendiente de aceptación. Los lotes anteriores fueron aceptados por el usuario basándose en pruebas del agente Windows; quedan abiertas las limitaciones previas.

> 2026-10-11: Los modos de fecha, CSV y campos de metadatos usan Aplicar una vez para crear borradores. Cargar preajustes/XMP solo rellena parámetros; guardar un preajuste no guarda fotos. Deshacer la última aplicación restaura todos los borradores anteriores al lote; guardar o recargar lo invalida. Se conservan la comprobación final de todas las fuentes y el guardado de copias. Implementado y verificado; pendiente de aceptación del usuario, también las pistas.

> 2026-10-11: El ajuste de seis componentes en la página de fechas omite y marca las fechas confirmadas como ausentes. Si faltan todas, no permite añadir borradores de fecha. Los valores inválidos, errores de lectura y cambios del origen siguen rechazándose. Implementado y verificado localmente; pendiente de aceptación del usuario.

> Los cinco modos de la página de fechas usan el archivo Swift fijado para vistas previas asíncronas y borradores validados, pendientes de aceptación. Compile primero el host siguiendo [estas instrucciones](../../DateHost/README.md). Las otras entradas de fecha siguen en C#; el despliegue limpio y la distribución están pendientes.

# PhotoTrail Windows

### Estado de Windows

La versión local de prueba para Windows permite 27 campos XMP habituales, guardar copias, intercambio CSV/XMP, fechas por lotes desde nombres de archivo, vista previa JPEG/PNG y JPEG incrustado en DNG, mapas/rutas y renombrado recuperable. La apariencia se conserva al reiniciar. OpenFreeMap con MapLibre es el mapa predeterminado; Google requiere una clave propia y su API real sigue pendiente de validación. Faltan campos completos, traducciones de la interfaz, más formatos y pruebas en otros equipos. Sin lanzamiento oficial. Consulte la [guía de desarrollo](../../README.md).

Las rutas recientes se combinan entre instancias de la misma sesión de Windows.

El portapapeles GPS copia coordenadas de una foto; revise la vista previa antes de crear borradores GPS y guardar copias. No incluye altitud, hora de medición ni regiones.

Fabricante, modelo, objetivo y número de serie del objetivo se editan en XMP. Los campos EXIF originales se conservan, incluidos los ceros iniciales del número de serie en XMP.

Las fechas XMP de digitalización, creación y modificación se editan por separado; las fechas por lotes solo ajustan la fecha de captura.

Se añaden siete parámetros de exposición XMP con números o fracciones validados; los valores EXIF originales se conservan. Hay 27 campos manuales.


2026-10-11

Se añadieron tamaño y espaciado independientes de metadatos, nombres completos de etiquetas, orden persistente de fotos e historial de búsqueda de mapas de hasta 3 entradas. Valores predeterminados: tamaño y espaciado normales, nombres completos activados, nombre de archivo ascendente e historial activado. El nombre abreviado conserva la familia de origen; ayudas, accesibilidad, búsqueda y copia mantienen el nombre completo. Se guardan comparadores de nombre, fecha de captura y orden de importación, ascendentes o descendentes, sin cambiar selección ni orden de renombrado. Desactivar oculta y detiene nuevas entradas sin borrarlas; reactivar las muestra. Borrar afecta solo al historial; restablecer conserva historial y claves. La búsqueda usa la vía Google existente con autorización explícita. Implementado y verificado de forma dirigida; aceptación del usuario pendiente. La consulta real en línea no está verificada.


2026-10-11

Se añadieron orden de procesamiento por nombre, fecha, extensión, carpeta, tamaño, cámara, ciudad, valoración, metadatos y orden manual, filtros de entrada y arrastre de grupos. JPG/RAW/XMP permanecen unidos; los valores ausentes van al final en ambas direcciones y los empates son estables. Se ordena y filtra antes de numerar continuamente. Mover varios grupos conserva su orden y las posiciones ocultas; hay posición explícita, Alt+arriba/abajo y Ctrl+Z. La vista no cambia el alcance de ejecución; los cambios de procesamiento invalidan el plan congelado. Los esquemas antiguos se leen y agregan sort, descending y metadataSortTag opcionales, sin filtros ni IDs manuales. Se conservan las protecciones de ejecución, cancelación y recuperación. Verificación dirigida, arrastres reales y teclado completados; aceptación pendiente. Se mantienen los límites y pendientes anteriores.


## 2026-10-11

El reemplazo de componentes y el ajuste de seis componentes omiten las fechas ausentes confirmadas por foto. Los valores iguales y ajustes cero no habilitan Aplicar por borradores previos. Los parámetros o tipos inválidos y los cambios de origen de toda la selección rechazan el lote. Implementado y verificado; pendiente de aceptación del usuario.


## 2026-10-11

El mapa permite previsualizar/aplicar ajustes temporales y este/norte, deshacer el último ajuste de la sesión y recargar el original. Las instantáneas efectiva/original se guardan localmente y se restauran al reiniciar. Un origen modificado o ausente impide la coincidencia y nuevos ajustes. La exportación GPX crea un archivo nuevo y verifica su lectura, sin modificar el origen ni escribir fotos automáticamente. Conserva segmentos, puntos sin hora y alturas; precisión temporal de100ns, sin estilos/extensiones originales. Pendiente de aceptación del usuario.
