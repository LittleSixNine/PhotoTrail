#!/usr/bin/env python3
"""Validate bundled translations and local documentation without network access."""
import json, re, textwrap
from pathlib import Path
def tokens(s):
 i=0
 while i<len(s):
  if s.startswith('//',i):
   e=s.find('\n',i); i=e if e>=0 else len(s);continue
  if s.startswith('/*',i):
   e=s.find('*/',i+2);i=e+2 if e>=0 else len(s);continue
  if s[i]=='"' and (i==0 or s[i-1]!='#'):
   start=i; triple=s.startswith('"""',i); sep='"""' if triple else '"';i+=len(sep); body='';args=[]
   while i<len(s):
    if s.startswith(sep,i):i+=len(sep);break
    if s.startswith('\\(',i):
     j=i+2;depth=1;begin=j
     while j<len(s) and depth:
      if s[j]=='"':
       j+=1
       while j<len(s):
        if s[j]=='\\':j+=2;continue
        if s[j]=='"':j+=1;break
        j+=1
       continue
      if s[j]=='(':depth+=1
      if s[j]==')':depth-=1
      j+=1
     args.append(s[begin:j-1]); body+=f'%{len(args)}$@';i=j;continue
    if s[i]=='\\' and i+1<len(s):
     nxt=s[i+1]
     if nxt=='\n':
      i+=2
      while i<len(s) and s[i] in ' \t':i+=1
      continue
     body+= {'n':'\n','t':'\t','r':'\r','"':'"','\\':'\\'}.get(nxt,nxt);i+=2;continue
    body+=s[i];i+=1
   if triple:body=textwrap.dedent(body).strip('\n').lstrip(' ')
   yield start,i,body,args
  else:i+=1


def main():
    root = Path(__file__).resolve().parents[1]
    languages = {"en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "pt-BR"}
    catalog = json.loads((root / "Sources/PhotoTrail/Localizable.xcstrings").read_text())["strings"]
    placeholder = re.compile(r"%\d+\$@")
    errors = []
    for key, entry in catalog.items():
        values = entry.get("localizations", {})
        if set(values) != languages:
            errors.append(f"Incomplete languages: {key!r}")
        for language, item in values.items():
            unit = item.get("stringUnit", {})
            value = unit.get("value", "")
            if not value or unit.get("state") != "translated":
                errors.append(f"Incomplete translation: {language}: {key!r}")
            if sorted(placeholder.findall(key)) != sorted(placeholder.findall(value)):
                errors.append(f"Placeholder mismatch: {language}: {key!r}")
            if re.search(r"ZX\s*PH\s*\d+\s*XZ|PTID\d+", value, re.I):
                errors.append(f"Translation marker remains: {language}: {key!r}")
    for path in (root / "Sources/PhotoTrail").rglob("*.swift"):
        if "DevAssets" in path.parts:
            continue
        source = path.read_text()
        for start, _, key, _ in tokens(source):
            if source[:start].rstrip().endswith("L10n.text(") and key not in catalog:
                errors.append(f"Uncatalogued literal: {path.relative_to(root)}: {key!r}")
    web = (root / "Sources/PhotoTrail/Views/Maps/AMap.html").read_text()
    for key in re.findall(r'\bt\("([^"\n]+)"\)', web):
        if key not in catalog:
            errors.append(f"Uncatalogued map string: {key}")
    for language in languages:
        permission = root / f"Sources/PhotoTrail/{language}.lproj/InfoPlist.strings"
        text = permission.read_text()
        for key in ["NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription", "NSPhotoLibraryUsageDescription"]:
            if key not in text:
                errors.append(f"Permission text missing: {language}: {key}")
        for package in ["Metadata", "RunLogView"]:
            if not (root / f"Packages/{package}/Sources/{package}/Resources/{language}.lproj/Localizable.strings").is_file():
                errors.append(f"Missing package resources: {package}: {language}")
    docs = [root / "README.md", *sorted((root / "docs/i18n").glob("*.md"))]
    for path in docs:
        text = path.read_text()
        for link in re.findall(r'\]\(([^)]+)\)|src="([^"]+)"', text):
            target = next(part for part in link if part)
            if re.match(r"[a-z]+:|#", target):
                continue
            target = target.split("#", 1)[0]
            if not (path.parent / target).exists():
                errors.append(f"Broken local link: {path.relative_to(root)}: {target}")
        if path.name.startswith(("README", "SKILL")):
            for language in languages:
                expected = "README.md" if language == "zh-Hans" and path.name.startswith("README") else f"{path.name.split('.')[0]}.{language}.md"
                if expected != path.name and expected not in text:
                    errors.append(f"Missing language link: {path.name}: {language}")
    assert not errors, "\n".join(errors)
    print(f"Localization OK: {len(catalog)} messages × {len(languages)} languages; resources, placeholders, source keys and {len(docs)} documents.")

if __name__ == "__main__":
    main()
