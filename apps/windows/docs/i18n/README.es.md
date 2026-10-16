R10: visibilidad por pista y recuperación del espacio de trabajo. Genere GPX de las fotos seleccionadas y guarde, verifique y añada explícitamente. Se omiten fechas sin desfase y referencias desconocidas; no se guardan las fotos.

R09b: regiones manuales independientes con selección congelada y sobrescritura explícita. La persistencia de resultados en línea sigue bloqueada por licencia.

R09a: favoritos manuales sin conexión y preferencias del mapa. La vista previa no aplica GPS; servicio y ubicación real sin verificar.

R08b: secuencias avanzadas, contadores persistentes y sufijos de conflicto por grupo. La conversión de Mac admite un subconjunto explícito.

R07: la comparación muestra hasta 20 fotos, pero CSV opera sobre toda la selección congelada. Se separan valores del disco y borradores. Se ignoran columnas desconocidas y se omiten filas inválidas completas; identidades duplicadas, rutas inseguras y errores de estructura rechazan el archivo. XMP distingue instantánea del disco y exportación con borradores; no sobrescribe archivos ni remapea identidades entre plataformas automáticamente.

R06b: vista previa nativa JPEG/PNG/TIFF y JPEG integrado en DNG. Quitar un grupo de la lista no cambia el disco y permite recuperar miembros y borradores. Los originales cambiados o ausentes quedan obsoletos y sin escritura; se rechazan identidades duplicadas. Otros RAW siguen sin verificar y HEIC no tiene vista previa.

> 2026-10-14 · R06a añade importación recursiva, grupos JPEG/RAW, preparación pausable, miniaturas según DPI y tira de fotos del mapa. Cada archivo conserva su origen y permisos. Pendiente de aceptación; límites en [IMPORT-THUMBNAILS](../IMPORT-THUMBNAILS.md)。

> 2026-10-14 · R05 añade acciones de fecha ordenadas y copia compatible entre fuentes de cada foto, aplicación y deshacer en un lote y restauración de parámetros del último preset guardado. R04c aceptado; R05 pendiente. Se conservan los riesgos existentes. [Contract](../DATE-PRESETS.md).

> El candidato R04c añade 21 campos EXIF numéricos, de enumeración, orientación y resolución, dos componentes IPTC de fecha/hora y dos tiempos del archivo original, solo en JPEG sin archivos auxiliares. Los tiempos Windows exigen precisión de 100 ns sin pérdida y no se pueden borrar; las copias de solo tiempo conservan los bytes. El guardado mixto y la restauración v2 verifican los atributos reales; v1 sigue protegido. R04b fue aceptado como entrega del agente Windows; R04c espera aceptación. Los riesgos anteriores permanecen. [R04c](../NUMERIC-TIME.md).

> La versión de desarrollo R04b añade doce campos IPTC de texto/lista para JPEG sin archivos asociados. Se validan los límites en bytes UTF8 y la codificación explícita; se rechazan cambios con codificación desconocida y la eliminación conserva los datos restantes. R04a fue aceptada; R04b está pendiente. [Scope / 支持範圍](../IPTC-FIELDS.md).

> 2026-10-14 · Candidato R04a: listas XMP, fuentes exactas, texto/equipo EXIF en JPEG y tres grupos de fecha. La fecha principal usa la captura EXIF del JPEG o XMP CreateDate del archivo auxiliar; al borrarla no se usa otra fecha. Entrega del agente R03b aceptada; R04a pendiente de aceptación. Se mantienen las limitaciones existentes. [Campos admitidos](../METADATA-FIELDS.md).

## 2026-10-13 · R03b

R03b añade guardado explícito en el archivo con copia de seguridad completa y única obligatoria, lectura del destino real, registros persistentes y restauración por registro revisado. La copia sigue siendo el modo predeterminado; Ctrl+S guarda solo copias seleccionadas y conserva borradores. Solo se habilitan JPEG, XMP asociado a JPEG/DNG y XMP independiente verificados en NTFS local. Los resultados desconocidos conservan archivos, copias y borradores y bloquean escrituras, reasignación por relectura y renombrado sin verificar. Se rechazan ACL personalizadas, enlaces, flujos adicionales y sistemas no verificados. Siguen pendientes el borrado GPS con retorno a EXIF y los límites SDK/NOTICE/SwiftPM. R03a fue aceptado como entrega del agente; R03b requiere aceptación separada. [Details](../SAVE-TARGETS.md).

> 2026-10-13 · R03a añade un resumen explícito, todos los borradores de la biblioteca y el alcance de campos del espacio actual, además de nuevos XMP junto al JPEG/DNG. Ctrl+S sigue preparando copias de la selección; confirme antes de escribir. Las copias conservan los borradores. Los XMP existentes se modifican mediante copias; no hay escritura directa. Se rechaza borrar coordenadas XMP si el GPS EXIF original puede reaparecer.

## 2026-10-13 · Inspector de fuentes R02

Las vistas comunes/completas comparten el modelo. Los 24 campos predeterminados se pueden buscar, seleccionar, vaciar y restaurar; una lista vaciada explícitamente sigue vacía tras reiniciar. La búsqueda completa y la copia conservan fuentes, espacios de nombres e instancias duplicadas. Se mantienen filas de referencia ausentes y se indican lecturas pendientes, fallidas y obsoletas. La relectura manual prepara instantáneas en segundo plano, omite borradores o entradas sin aplicar y comprueba identidades, revisiones y fuentes antes de aceptar. Cancelar o fallar conserva la instantánea anterior. Se separan los recuentos de instancias de origen y campos de borrador netos; GPS cuenta como un campo lógico. Guardar copias conserva el borrador de la sesión original. Se mantienen los permisos XMP y date-core-v2. Se aceptó la entrega del agente v2; R02 espera aceptación. Siguen pendientes el despliegue sin SDK, las licencias/NOTICE y SwiftPM/14001. Las excepciones aprobadas de Apple Photos, Apple Maps y etiquetas Finder no eximen otras funciones Windows.

> 2026-10-13 · Las fechas históricas usan la proyección compartida date-core-v2 para ordenar fotos, ordenar y filtrar nombres por fecha y convertir la hora de la foto para las rutas. Se conservan segundos enteros, nanosegundos y texto original. Las rutas requieren zona explícita, precisión representable de 100 ns y rango compatible; no se supone UTC ni se redondea. Candidato pendiente de aceptación. Siguen pendientes el despliegue sin Swift SDK, licencias/NOTICE y SwiftPM/14001; no es una distribución formal.

> R01b utiliza validación compartida para fechas. La proyección histórica para ordenar y asociar recorridos sigue incompleta. R01a está aceptado; R01b espera aceptación. Siguen pendientes despliegue, licencias y SwiftPM.

> 2026-10-12: La biblioteca local de preajustes de metadatos permite guardar nuevos, actualizar, copiar, renombrar, eliminar con confirmación e importar/exportar JSON individuales. Seleccionar solo carga el editor; aplicar sigue siendo explícito. Copiar, renombrar y exportar usan el contenido guardado y conservan los cambios pendientes. Cambiar, releer y cerrar protegen la edición; por defecto se cancela o continúa editando. Reiniciar restaura solo la lista, sin activación, migración ni plantillas automáticas. La biblioteca vacía permanece vacía. UTF-8: 1MiB/256 entradas; JSON individual v1: 128KiB/27 operaciones. Local mutex y SHA rechazan escrituras obsoletas en una misma sesión de Windows; no se garantizan transacciones globales entre sesiones o escritores externos. Implementado y verificado localmente, pendiente de aceptación. La tanda anterior fue aceptada a partir de resultados del agente Windows. [Format / 用法](../METADATA-PRESETS.md).

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

## Ajustes de metadatos ordenados

La pestaña permite añadir, editar, eliminar y ordenar operaciones sobre los 27 campos XMP existentes y guardar/cargar JSON. Cargar solo modifica la cadena; se aplica una vez a los borradores seleccionados y se puede deshacer la última aplicación. Solo guardar copias explícitamente escribe archivos. Se admiten asignación, borrado, completar ausentes, texto, palabras clave y copia por foto. Añadir texto se repite en cada aplicación; los algoritmos de fecha y acciones desconocidas se rechazan íntegramente. Solo se admite un subconjunto de Mac v1.


R08a añade reglas por grafemas, regex limitada y fuentes verificadas; comprueba identidad/SHA/System/ACL, sin sobrescribir. [Límites](../RENAME-RULES.md).


## M8 / M9

Candidato M8/M9: emparejamiento y fuentes de fecha ordenados, conversión estricta de preajustes, zona horaria de sesión, guardado total o de la página actual y edición de mapa reversible. Borrar ubicación se limita a copias JPEG/JPEG+XMP verificadas. Las copias conservan borradores. Servicios, formatos, accesibilidad y aceptación del usuario siguen pendientes.
