"""Build a clean installable mod folder and ZIP, excluding tests and git metadata."""
from pathlib import Path
import hashlib
import re
import shutil
import zipfile

source = Path(__file__).resolve().parents[1]
version = re.search(r'version\s*=\s*"([^"]+)"', (source / 'modinfo.lua').read_text(encoding='utf-8')).group(1)
dist = source / 'dist'
payload = dist / 'nearby_autofuel'
payload.mkdir(parents=True, exist_ok=True)
files = [source / name for name in ('modinfo.lua', 'modmain.lua', 'README.md', 'CHANGELOG.md')]
files += sorted((source / 'scripts').rglob('*.lua'))
files += sorted(p for p in (source / 'assets').iterdir() if p.is_file())
for path in files:
    dest = payload / path.relative_to(source)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dest)
archive = dist / f'nearby_autofuel_v{version}.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for path in files:
        z.write(path, 'nearby_autofuel/' + path.relative_to(source).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(digest + '  ' + archive.name + '\n', encoding='ascii')
print('Upload folder:', payload)
print('ZIP:', archive)
print('SHA256:', digest)
