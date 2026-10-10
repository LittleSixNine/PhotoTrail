> Los cinco modos de la página de fechas usan el archivo Swift fijado para vistas previas asíncronas y borradores validados, pendientes de aceptación. Compile primero el host siguiendo [estas instrucciones](../../DateHost/README.md). Las otras entradas de fecha siguen en C#; el despliegue limpio y la distribución están pendientes.

# PhotoTrail Windows

### Estado de Windows

La versión local de prueba para Windows permite 27 campos XMP habituales, guardar copias, intercambio CSV/XMP, fechas por lotes desde nombres de archivo, vista previa JPEG/PNG y JPEG incrustado en DNG, mapas/rutas y renombrado recuperable. La apariencia se conserva al reiniciar. OpenFreeMap con MapLibre es el mapa predeterminado; Google requiere una clave propia y su API real sigue pendiente de validación. Faltan campos completos, traducciones de la interfaz, más formatos y pruebas en otros equipos. Sin lanzamiento oficial. Consulte la [guía de desarrollo](../../README.md).

Las rutas recientes se combinan entre instancias de la misma sesión de Windows.

El portapapeles GPS copia coordenadas de una foto; revise la vista previa antes de crear borradores GPS y guardar copias. No incluye altitud, hora de medición ni regiones.

Fabricante, modelo, objetivo y número de serie del objetivo se editan en XMP. Los campos EXIF originales se conservan, incluidos los ceros iniciales del número de serie en XMP.

Las fechas XMP de digitalización, creación y modificación se editan por separado; las fechas por lotes solo ajustan la fecha de captura.

Se añaden siete parámetros de exposición XMP con números o fracciones validados; los valores EXIF originales se conservan. Hay 27 campos manuales.
