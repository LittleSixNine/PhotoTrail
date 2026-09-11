# Third-party components and data

## ExifTool

PhotoTrail invokes the user-installed ExifTool executable to read photo
metadata. The documented geotagging workflow also uses ExifTool. This repository
does not bundle ExifTool's source code, executable, test images, or documentation.

- Project and author: [ExifTool by Phil Harvey](https://exiftool.org/).
- Upstream copyright: Copyright 2003–2026, Phil Harvey.
- Upstream license statement: distributed under the same terms as Perl itself,
  either the Perl Artistic License or GPL.
- Authoritative license source: [ExifTool README, Copyright and License](https://github.com/exiftool/exiftool/blob/master/README).

The project's MIT license does not replace the license of ExifTool or any other
separately installed dependency. Any future distribution that bundles dependencies
must include the notices and license material required by those dependencies.

## Python and GPX

The Python source currently imports Python's standard library and the project's
own modules. `requirements.txt` has no active Python dependencies.
The optional package names in its comments are suggestions, not bundled code.

GPX output follows the [GPX 1.1 specification](https://www.topografix.com/gpx/1/1/).
The repository does not bundle the GPX schema or third-party GPX datasets.

## Photographs, tracks, and map data

Users retain the applicable rights to their own photographs and tracks. These
files are not covered by the project's code license merely because the tool
processes them. The examples and tests added in September 2026 generate synthetic data from
authored formulas and a tiny generated PNG; no photographs, road data, or map
assets were downloaded for these examples.

No map SDK, map tiles, road network, or map-provider response is bundled in the
current project. Any future map integration must document its attribution,
storage, export, and usage conditions before such data is distributed.
