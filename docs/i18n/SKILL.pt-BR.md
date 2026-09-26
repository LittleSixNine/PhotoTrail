[简体中文](SKILL.zh-Hans.md) · [English](SKILL.en.md) · [繁體中文](SKILL.zh-Hant.md) · [日本語](SKILL.ja.md) · [한국어](SKILL.ko.md) · [Español](SKILL.es.md) · **Português do Brasil**

# Guia do Skill do PhotoTrail

Crie GPX a partir de fotos localizadas ou cópias JPEG/HEIC com localização e relatórios JSON usando GPX. Não precisa do app Mac. Requer Python 3.11+, ExifTool e um agente com acesso local e execução de comandos. Verificado no macOS.

## Instalação

Obtenha todo o diretório skill de um mesmo commit e copie como phototrail para a pasta de skills aceita pelo cliente. Preserve licença, scripts, testes e documentação. Não misture commits nem sobrescreva uma instalação sem autorização.

[PhotoTrail / skill](https://github.com/LittleSixNine/PhotoTrail/tree/phototrail/skill) · [ExifTool](https://exiftool.org/install.html)

## Verificação e prévia somente leitura

Substitua os caminhos e o fuso da câmera. A pasta de saída deve ficar fora da pasta dos originais e ainda não existir; a pasta superior deve existir. A prévia não grava arquivos. Remova --dry-run somente após autorizar a gravação.

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

## Dados e resultados

Não adivinha datas nem interpola através de descontinuidades. Conflitos e formatos não aceitos são ignorados. O GPS existente é preservado por padrão. Não grava RAW/XMP nem aceita links simbólicos. Confere os hashes do original antes e depois e relê as cópias; cópias com falha são excluídas. Todo o grupo EXIF GPS da cópia é substituído, sem manter horário e direção GPS anteriores.

Chaves JSON, estados, códigos de erro e argumentos não mudam com o idioma. Relatórios contêm caminhos locais e localizações; não os publique em relatos de problemas. Saídas: 0 completo, 3 itens ignorados ou falhas, 2 erro de entrada ou ambiente, 130 cancelamento. O cancelamento normal mantém os resultados corretos e o relatório; não desfaz todo o lote.

Consulte os parâmetros e limites completos no guia em inglês ou nas instruções originais.

[English: full reference](SKILL.en.md) · [简体中文：完整安装说明](../../skill/INSTALL.md)
