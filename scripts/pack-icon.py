"""Package the generated PNG representations into a modern macOS ICNS file."""
from pathlib import Path
from struct import pack

representations = {
    'icp4': 'icon_16x16.png', 'icp5': 'icon_32x32.png',
    'ic07': 'icon_128x128.png', 'ic08': 'icon_256x256.png',
    'ic09': 'icon_512x512.png', 'ic10': 'icon_512x512@2x.png',
    'ic11': 'icon_16x16@2x.png', 'ic12': 'icon_32x32@2x.png',
    'ic13': 'icon_128x128@2x.png', 'ic14': 'icon_256x256@2x.png',
}
chunks = []
for kind, name in representations.items():
    data = (Path('build/PolishedHelper.iconset') / name).read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n'), name
    chunks.append(kind.encode('ascii') + pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
Path('build/DockHush.icns').write_bytes(b'icns' + pack('>I', len(payload) + 8) + payload)
