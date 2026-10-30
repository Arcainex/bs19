"""Builds the BS19 release zips (bs19-part1.zip ... bs19-partN.zip).

txAdmin gives every recipe download 150 seconds, so the framework is split
into parts of roughly MAX_MB each. Only files committed in the public repo
are packed. Run: python make_release_zips.py [repo_dir] [out_dir]
"""
import os, subprocess, sys, zipfile

REPO = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'bs19')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(__file__))
MAX_MB = 85
PATHS = ['resources', 'server.cfg', 'myLogo.png', 'How to update.txt', 'update-v1.05.json']

def git(*args):
    return subprocess.run(['git', '-C', REPO, *args], check=True, capture_output=True, text=True).stdout

if git('status', '--porcelain', '--', *PATHS).strip():
    sys.exit('Uncommitted changes in the release files. Commit first.')

files = [f for f in git('ls-files', '-z', '--', *PATHS).split('\0') if f]
sizes = {f: os.path.getsize(os.path.join(REPO, f)) for f in files}
total = sum(sizes.values())
count = max(1, -(-total // (MAX_MB * 1024 * 1024)))

# Biggest files first, each into the lightest part
parts = [[0, []] for _ in range(count)]
for f in sorted(files, key=lambda f: -sizes[f]):
    p = min(parts, key=lambda p: p[0])
    p[0] += sizes[f]
    p[1].append(f)

for i, (size, names) in enumerate(parts, 1):
    path = os.path.join(OUT, f'bs19-part{i}.zip')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for f in sorted(names):
            z.write(os.path.join(REPO, f), f)
    print(f'bs19-part{i}.zip  {len(names)} files  {os.path.getsize(path) / 1048576:.1f} MB')
print(f'{count} parts, {len(files)} files')
