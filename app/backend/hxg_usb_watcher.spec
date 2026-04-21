# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for hxg-usb-watcher (USB enforcement daemon)
# onedir mode: produces app/dist/hxg-usb-watcher/ directory (no /tmp extraction)
# Build: pyinstaller hxg_usb_watcher.spec --distpath ../dist --workpath /tmp/hxg_build --noconfirm

block_cipher = None

a = Analysis(
    ['usb_watcher.py'],
    pathex=['.'],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='hxg-usb-watcher',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name='hxg-usb-watcher',
)
