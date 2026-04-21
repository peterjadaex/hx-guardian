# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for hxg-runner (privileged runner daemon)
# onedir mode: produces app/dist/hxg-runner/ directory (no /tmp extraction)
# Build: pyinstaller hxg_runner.spec --distpath ../dist --workpath /tmp/hxg_build --noconfirm

block_cipher = None

a = Analysis(
    ['hxg_runner.py'],
    pathex=['.'],
    binaries=[],
    datas=[],
    hiddenimports=[
        'runner.executor',
        'runner.protocol',
    ],
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
    name='hxg-runner',
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
    name='hxg-runner',
)
