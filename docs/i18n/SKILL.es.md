[简体中文](SKILL.zh-Hans.md) · [English](SKILL.en.md) · [繁體中文](SKILL.zh-Hant.md) · [日本語](SKILL.ja.md) · [한국어](SKILL.ko.md) · **Español** · [Português do Brasil](SKILL.pt-BR.md)

# Guía del Skill de PhotoTrail

Crea GPX desde fotos ubicadas o copias JPEG/HEIC con ubicación e informes JSON a partir de GPX. No necesita la app Mac. Requiere Python 3.11+, ExifTool y un agente con acceso local y ejecución de comandos. Verificado en macOS.

## Instalación

Obtén todo el directorio skill de un mismo commit y cópialo como phototrail en la carpeta de skills admitida por tu cliente. Conserva licencia, scripts, pruebas y documentación. No mezcles commits ni sobrescribas una instalación sin autorización.

[PhotoTrail / skill](https://github.com/LittleSixNine/PhotoTrail/tree/phototrail/skill) · [ExifTool](https://exiftool.org/install.html)

## Comprobación y vista previa de solo lectura

Sustituye las rutas y la zona horaria de la cámara. La carpeta de salida debe estar fuera de la de originales y aún no existir; su carpeta superior debe existir. La vista previa no escribe archivos. Quita --dry-run solo después de autorizar la escritura.

```sh
python3 -B "/absolute/path/phototrail/scripts/phototrail.py" check

python3 -B "/absolute/path/phototrail/scripts/phototrail.py" export-gpx \
  --photos "/absolute/photos" --timezone Asia/Shanghai \
  --output "/absolute/output/photos.gpx"

python3 -B "/absolute/path/phototrail/scripts/phototrail.py" geotag \
  --photos "/absolute/photos" --gpx "/absolute/track.gpx" \
  --timezone Asia/Shanghai --time-offset-seconds 120 \
  --output "/absolute/new-output" --dry-run
```

## Datos y resultados

No se adivinan fechas ni se interpola a través de discontinuidades. Se omiten conflictos y formatos no admitidos. Se conserva el GPS existente por defecto. No se escribe RAW/XMP ni se admiten enlaces simbólicos. Se comprueban hashes del original antes y después y se releen las copias; las fallidas se eliminan. Se sustituye todo el grupo EXIF GPS de la copia, sin conservar la hora ni dirección GPS anteriores.

Las claves JSON, estados, códigos de error y argumentos no cambian con el idioma. Los informes contienen rutas locales y ubicaciones; no los publiques en incidencias. Salidas: 0 completo, 3 omisiones o fallos, 2 error de entrada o entorno, 130 cancelación. Cancelar normalmente conserva los resultados correctos y el informe; no revierte todo el lote.

Consulta los parámetros y límites completos en la guía en inglés o en las instrucciones originales.

[English: full reference](SKILL.en.md) · [简体中文：完整安装说明](../../skill/INSTALL.md)
