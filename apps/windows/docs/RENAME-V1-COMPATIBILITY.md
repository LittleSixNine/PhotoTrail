WIN-RELEASE-GATES-20261023 approved scope: action32 is unimplemented and deferred until after launch; runtime counter-value migration is also deferred, with local values and existing safeguards retained. Ordinary name sorting is accepted as FIXED_WITH_LIMITS; this is not full Foundation equivalence. These items are no longer pending launch-scope decisions. Other action/parameter restrictions below have not been collectively accepted or deferred. No mapping, strict rejection or serialization changed in this documentation batch.

WIN-LAUNCH-CLOSEOUT-20261019: Music is deferred from the first Windows release. Actions72–77, including disabled/mixed schemes, reject the whole import/export. Local old libraries still decode without deleting or migrating entries. Music-only unqualified aliases/derived tokens in generic template actions66–71 also reject the whole scheme: ARTIST/artist, Song/Album/AlbumArtist, Track/TrackNum/NumTracks/CDNum/numCds, AudioSampleRate, derived duration and Artist/Album/Song/AlbumArtist case tokens. Ordinary `<Artist>`, family-qualified photo metadata tokens and general FileName/date/photo templates remain supported; this is not a global Artist field ban. Historical journals remain restorable. PRE-REL-MAC-REV-01 is DEFERRED, not FIXED; Mac is unchanged. The older music implementation description below is historical and unavailable in the first release.

# Mac v1 / Windows compatibility

Fixed behavior source: Mac `cbeccc015c416c6a82d02645eeb6ccfadb8cef99` (0.5.10/build1970). This table describes the Windows implementation, not a Mac runtime acceptance result. Unsupported actions, unknown/duplicate fields and unsupported parameter values reject the entire input. The original input file is not rewritten.

| Object/field | Windows behavior |
|---|---|
| root id/version/name/rules/settings/example | v1 only; nonempty UUID; at most 64 ordered rules; optional example retained; imported local scheme gets a new local identity |
| rule id/enabled/part | nested unique UUID and enable flag retained; stem/entire/dottedExtension/extensionOnly validated |
| action | explicit mapping below; unsupported actions reject even when disabled |
| text/replacement/anchor/position/length/occurrence/matchNumber/caseSensitive | copied and strictly validated; positions use grapheme clusters; case-insensitive actions 1–16 reject because broad Unicode equivalence is unproven |
| start/counter/step/padding/alphabetStart/alphabetWidth/prefix/suffix/numberOperation/numberValue | validated ranges and checked arithmetic; counters are local state, not runtime values embedded in a preset |
| lexicalCases | exact default dictionary only; nondefault lexical parameters reject; action32 is unavailable |
| dateSource/dateFormat/timeZone/nightHour/skipMissing/fullMatch/perDirectory | copied; platform-unsupported zones/date patterns reject; missing metadata produces an explicit skipped preview, preserving the original name |
| filterAny/filters | 1–32 conditions; nested UUID/order retained; known fields/operators and Unicode parameters validated |
| metadataField | optional field token retained, no guessed metadata injected |
| settings | conflict/sort/descending/keepFirst/pair/sourceExtensions/targetExtensions/datePriority retained; optional metadataSortTag/numberSuffixFormat/letterSuffixFormat/conflictDigits validated |
| current counter values | importing does not reset them; preview/cancel do not advance; successful execution advances; file restore does not rewind; pending unknown reservations block reuse |

Music actions72–77 reuse the existing metadata template engine with Mac's six insertion modes. They read already imported photo metadata; they do not add an audio importer, library, or player. Raw aliases include Artist/Creator, Song/Title, AlbumArtist/Band, Track/TrackNumber, track/disc number and total fallbacks, and AudioSampleRate. Arbitrary exact family-qualified tokens still resolve exactly. Derived upper/lower/sentence/capitalized music tokens and bounded duration seconds/minute/hour formats are implemented using existing standard-library rules. ASCII and duration boundary vectors follow the fixed Mac source; full Unicode casing and all binary-floating formatting boundaries are not a Mac runtime equivalence claim. Missing tokens remain visible as missingTag instead of generating incomplete names. Local tests use real XMP fields in synthetic JPEGs. General Foundation/Unicode equivalence and Mac consumption of the final Windows export remain separate gates.

| Mac action | Windows action | Local support | Mac runtime parity |
|---|---|---|---|
| 1 | add-begin | v1 explicit mapping | not inferred from Windows tests |
| 2 | add-end | v1 explicit mapping | not inferred from Windows tests |
| 3 | add-before | v1 explicit mapping | not inferred from Windows tests |
| 4 | add-after | v1 explicit mapping | not inferred from Windows tests |
| 5 | add-position | v1 explicit mapping | not inferred from Windows tests |
| 6 | remove-begin | v1 explicit mapping | not inferred from Windows tests |
| 7 | remove-end | v1 explicit mapping | not inferred from Windows tests |
| 8 | remove-text | v1 explicit mapping | not inferred from Windows tests |
| 9 | replace-begin | v1 explicit mapping | not inferred from Windows tests |
| 10 | replace-end | v1 explicit mapping | not inferred from Windows tests |
| 11 | replace-text | v1 explicit mapping | not inferred from Windows tests |
| 12 | move-front | v1 explicit mapping | not inferred from Windows tests |
| 13 | move-end | v1 explicit mapping | not inferred from Windows tests |
| 14 | move-position | v1 explicit mapping | not inferred from Windows tests |
| 15 | move-before | v1 explicit mapping | not inferred from Windows tests |
| 16 | move-after | v1 explicit mapping | not inferred from Windows tests |
| 17 | replace-characters | Windows only; v1 rejected | not inferred from Windows tests |
| 18 | remove-characters | Windows only; v1 rejected | not inferred from Windows tests |
| 19 | keep-characters | Windows only; v1 rejected | not inferred from Windows tests |
| 20 | trim-begin | Windows only; v1 rejected | not inferred from Windows tests |
| 21 | trim-end | Windows only; v1 rejected | not inferred from Windows tests |
| 22 | remove-vowels | Windows only; v1 rejected | not inferred from Windows tests |
| 23 | remove-emoji | Windows only; v1 rejected | not inferred from Windows tests |
| 24 | drop-begin | v1 explicit mapping | not inferred from Windows tests |
| 25 | drop-end | v1 explicit mapping | not inferred from Windows tests |
| 26 | remove-range | v1 explicit mapping | not inferred from Windows tests |
| 27 | move-range | v1 explicit mapping | not inferred from Windows tests |
| 28 | lower | Windows only; v1 rejected | not inferred from Windows tests |
| 29 | sentence | Windows only; v1 rejected | not inferred from Windows tests |
| 30 | title | Windows only; v1 rejected | not inferred from Windows tests |
| 31 | upper | Windows only; v1 rejected | not inferred from Windows tests |
| 32 | — | unimplemented; decision required | not inferred from Windows tests |
| 33 | percent-decode | Windows only; v1 rejected | not inferred from Windows tests |
| 34 | camel-expand | Windows only; v1 rejected | not inferred from Windows tests |
| 35 | remove-diacritics | Windows only; v1 rejected | not inferred from Windows tests |
| 36 | mac9-name | Windows only; v1 rejected | not inferred from Windows tests |
| 37 | windows-name | Windows only; v1 rejected | not inferred from Windows tests |
| 38 | truncate | v1 explicit mapping | not inferred from Windows tests |
| 39 | dos83-name | Windows only; v1 rejected | not inferred from Windows tests |
| 40 | date-set | v1 explicit mapping | not inferred from Windows tests |
| 41 | date-begin | v1 explicit mapping | not inferred from Windows tests |
| 42 | date-end | v1 explicit mapping | not inferred from Windows tests |
| 43 | date-before | v1 explicit mapping | not inferred from Windows tests |
| 44 | date-after | v1 explicit mapping | not inferred from Windows tests |
| 45 | date-position | v1 explicit mapping | not inferred from Windows tests |
| 46 | number-set | v1 explicit mapping | not inferred from Windows tests |
| 47 | number-begin | v1 explicit mapping | not inferred from Windows tests |
| 48 | number-end | v1 explicit mapping | not inferred from Windows tests |
| 49 | number-before | v1 explicit mapping | not inferred from Windows tests |
| 50 | number-after | v1 explicit mapping | not inferred from Windows tests |
| 51 | number-position | v1 explicit mapping | not inferred from Windows tests |
| 52 | number-change | v1 explicit mapping | not inferred from Windows tests |
| 53 | number-remove | v1 explicit mapping | not inferred from Windows tests |
| 54 | roman-set | v1 explicit mapping | not inferred from Windows tests |
| 55 | roman-begin | v1 explicit mapping | not inferred from Windows tests |
| 56 | roman-end | v1 explicit mapping | not inferred from Windows tests |
| 57 | roman-before | v1 explicit mapping | not inferred from Windows tests |
| 58 | roman-after | v1 explicit mapping | not inferred from Windows tests |
| 59 | roman-position | v1 explicit mapping | not inferred from Windows tests |
| 60 | alphabet-set | v1 explicit mapping | not inferred from Windows tests |
| 61 | alphabet-begin | v1 explicit mapping | not inferred from Windows tests |
| 62 | alphabet-end | v1 explicit mapping | not inferred from Windows tests |
| 63 | alphabet-before | v1 explicit mapping | not inferred from Windows tests |
| 64 | alphabet-after | v1 explicit mapping | not inferred from Windows tests |
| 65 | alphabet-position | v1 explicit mapping | not inferred from Windows tests |
| 66 | template-set | Windows only; v1 rejected | not inferred from Windows tests |
| 67 | template-begin | Windows only; v1 rejected | not inferred from Windows tests |
| 68 | template-end | Windows only; v1 rejected | not inferred from Windows tests |
| 69 | template-position | Windows only; v1 rejected | not inferred from Windows tests |
| 70 | template-before | Windows only; v1 rejected | not inferred from Windows tests |
| 71 | template-after | Windows only; v1 rejected | not inferred from Windows tests |
| 72 | music-set | DEFERRED; whole scheme rejected | not inferred from Windows tests |
| 73 | music-end | DEFERRED; whole scheme rejected | not inferred from Windows tests |
| 74 | music-begin | DEFERRED; whole scheme rejected | not inferred from Windows tests |
| 75 | music-before | DEFERRED; whole scheme rejected | not inferred from Windows tests |
| 76 | music-after | DEFERRED; whole scheme rejected | not inferred from Windows tests |
| 77 | music-position | DEFERRED; whole scheme rejected | not inferred from Windows tests |
| 78 | size-end | Windows only; v1 rejected | not inferred from Windows tests |
| 79 | size-begin | Windows only; v1 rejected | not inferred from Windows tests |
| 80 | size-set | Windows only; v1 rejected | not inferred from Windows tests |
| 81 | size-before | Windows only; v1 rejected | not inferred from Windows tests |
| 82 | size-after | Windows only; v1 rejected | not inferred from Windows tests |
| 83 | size-position | Windows only; v1 rejected | not inferred from Windows tests |
| 84 | parent-begin | Windows only; v1 rejected | not inferred from Windows tests |
| 85 | parent-end | Windows only; v1 rejected | not inferred from Windows tests |
| 86 | parent-before | Windows only; v1 rejected | not inferred from Windows tests |
| 87 | parent-after | Windows only; v1 rejected | not inferred from Windows tests |
| 88 | parent-position | Windows only; v1 rejected | not inferred from Windows tests |
| 89 | path-begin | Windows only; v1 rejected | not inferred from Windows tests |
| 90 | path-end | Windows only; v1 rejected | not inferred from Windows tests |
| 91 | path-before | Windows only; v1 rejected | not inferred from Windows tests |
| 92 | path-after | Windows only; v1 rejected | not inferred from Windows tests |
| 93 | path-position | Windows only; v1 rejected | not inferred from Windows tests |
| 94 | name-list | Windows only; v1 rejected | not inferred from Windows tests |
| 95 | regex-replace | v1 explicit mapping | not inferred from Windows tests |
| 96 | regex-rearrange | v1 explicit mapping | not inferred from Windows tests |
| 97 | set | v1 explicit mapping | not inferred from Windows tests |
| 98 | filter-following | v1 explicit mapping | not inferred from Windows tests |
| 99 | — | settings UI; not a rename rule | not inferred from Windows tests |
| 100 | device-set | Windows only; v1 rejected | not inferred from Windows tests |
| 101 | device-begin | Windows only; v1 rejected | not inferred from Windows tests |
| 102 | device-end | Windows only; v1 rejected | not inferred from Windows tests |
| 103 | device-position | Windows only; v1 rejected | not inferred from Windows tests |
| 104 | device-before | Windows only; v1 rejected | not inferred from Windows tests |
| 105 | device-after | Windows only; v1 rejected | not inferred from Windows tests |
| 106 | location-set | Windows only; v1 rejected | not inferred from Windows tests |
| 107 | location-begin | Windows only; v1 rejected | not inferred from Windows tests |
| 108 | location-end | Windows only; v1 rejected | not inferred from Windows tests |
| 109 | location-position | Windows only; v1 rejected | not inferred from Windows tests |
| 110 | location-before | Windows only; v1 rejected | not inferred from Windows tests |
| 111 | location-after | Windows only; v1 rejected | not inferred from Windows tests |
