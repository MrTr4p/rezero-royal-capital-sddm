#!/usr/bin/env python3
"""Install/select the native SDDM theme, preserving a reversible system backup."""
import argparse
import configparser
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'theme'
NAME = 'rezero-royal-capital'
DEST = Path('/usr/share/sddm/themes') / NAME
CONF = Path('/etc/sddm.conf.d/99-rezero-royal-capital.conf')
LEGACY_CONF = Path('/etc/sddm.conf')
BACKUPS = Path('/var/lib/sddm/theme-backups') / NAME


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_targets():
    if DEST.is_symlink() or CONF.is_symlink():
        raise RuntimeError('The installation target must not be a symlink.')
    if DEST.exists() and not DEST.is_dir():
        raise RuntimeError(f'The theme target must be a directory: {DEST}')
    if CONF.exists() and not CONF.is_file():
        raise RuntimeError(f'The selection target must be a file: {CONF}')


def preflight():
    for required in ('Main.qml', 'metadata.desktop', 'theme.conf', 'assets/royal-capital.png'):
        if not (SOURCE / required).is_file():
            raise RuntimeError(f'Missing theme file: {required}')
    if SOURCE.is_symlink() or any(path.is_symlink() for path in SOURCE.rglob('*')):
        raise RuntimeError('Theme source must contain regular files and directories, not symlinks.')
    validate_targets()
    if not shutil.which('sddm-greeter-qt6'):
        raise RuntimeError('Install Qt 6 SDDM before installing this theme.')
    # SDDM reads the legacy file after all snippets. Refuse hidden overrides.
    later = [p for p in CONF.parent.glob('*.conf') if p.name > CONF.name]
    later.append(LEGACY_CONF)
    for path in later:
        if not path.exists():
            continue
        config = configparser.RawConfigParser(strict=False)
        with path.open() as stream:
            config.read_file(stream)
        for key, expected in (('Current', NAME), ('ThemeDir', str(DEST.parent))):
            value = config.get('Theme', key, fallback='').strip()
            if config.has_option('Theme', key) and value.rstrip('/') != expected:
                raise RuntimeError(f'{path} overrides [Theme] {key}={value}. Resolve that override first.')


def atomic_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.' + path.name, delete=False) as f:
            temporary = Path(f.name)
            f.write(text)
        temporary.chmod(0o644)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def install():
    preflight()
    BACKUPS.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = BACKUPS / stamp
    backup.mkdir(mode=0o700)
    original = {'theme_existed': DEST.exists(), 'selection_existed': CONF.exists()}
    # A full reference snapshot is retained, but rollback changes only our files.
    if CONF.parent.exists():
        shutil.copytree(CONF.parent, backup / 'sddm.conf.d-reference')
    if LEGACY_CONF.exists():
        shutil.copy2(LEGACY_CONF, backup / 'sddm.conf-reference')
    if CONF.exists():
        shutil.copy2(CONF, backup / 'selection.conf')
    DEST.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.' + NAME + '-', dir=DEST.parent))
    moved_previous = False
    installed_new = False
    try:
        shutil.copytree(SOURCE, staging, dirs_exist_ok=True)
        for path in staging.rglob('*'):
            path.chmod(0o755 if path.is_dir() else 0o644)
        staging.chmod(0o755)
        for path in SOURCE.rglob('*'):
            if path.is_file() and digest(path) != digest(staging / path.relative_to(SOURCE)):
                raise RuntimeError(f'Copy verification failed: {path.name}')
        if DEST.exists():
            shutil.move(str(DEST), str(backup / 'theme'))
            moved_previous = True
        os.replace(staging, DEST)
        installed_new = True
        atomic_text(CONF, f'[Theme]\nCurrent={NAME}\nThemeDir={DEST.parent}\n')
        manifest = {**original, 'theme': str(DEST), 'selection': str(CONF), 'backup': str(backup)}
        atomic_text(backup / 'manifest.json', json.dumps(manifest, indent=2) + '\n')
        print(json.dumps({**manifest, 'selected': NAME, 'service_restarted': False}, indent=2))
    except Exception:
        if installed_new and DEST.exists():
            shutil.move(str(DEST), str(backup / 'failed-install'))
        if moved_previous:
            shutil.copytree(backup / 'theme', DEST)
        if original['selection_existed']:
            shutil.copy2(backup / 'selection.conf', CONF)
        else:
            CONF.unlink(missing_ok=True)
        raise
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def restore(backup_path):
    validate_targets()
    backup = Path(backup_path).resolve()
    if backup.parent != BACKUPS.resolve():
        raise RuntimeError(f'Choose an installation backup directly inside {BACKUPS}')
    manifest = json.loads((backup / 'manifest.json').read_text())
    if manifest.get('theme') != str(DEST) or manifest.get('selection') != str(CONF):
        raise RuntimeError('This backup belongs to a different installation.')
    if manifest['theme_existed'] and not (backup / 'theme').is_dir():
        raise RuntimeError('The original theme backup is missing.')
    if manifest['selection_existed'] and not (backup / 'selection.conf').is_file():
        raise RuntimeError('The original selection backup is missing.')
    # Prepare the old theme before touching the active installation, then put
    # the current theme back if either replacement or selection writing fails.
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    retained = backup / ('removed-theme-' + stamp)
    staging = None
    moved_current = False
    restored_theme = False
    try:
        if manifest['theme_existed']:
            DEST.parent.mkdir(parents=True, exist_ok=True)
            staging = Path(tempfile.mkdtemp(prefix='.' + NAME + '-restore-', dir=DEST.parent))
            shutil.copytree(backup / 'theme', staging, dirs_exist_ok=True)
        # Retain the removed copy in case an existing greeter still references it.
        if DEST.exists():
            shutil.move(str(DEST), str(retained))
            moved_current = True
        if staging is not None:
            os.replace(staging, DEST)
            restored_theme = True
        if manifest['selection_existed']:
            atomic_text(CONF, (backup / 'selection.conf').read_text())
        else:
            CONF.unlink(missing_ok=True)
    except Exception:
        if restored_theme and DEST.exists():
            shutil.move(str(DEST), str(backup / ('failed-restore-' + stamp)))
        if moved_current:
            shutil.move(str(retained), str(DEST))
        raise
    finally:
        if staging is not None and staging.exists():
            shutil.rmtree(staging)
    print(json.dumps({'restored_from': str(backup), 'retained_theme': str(retained), 'service_restarted': False}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='Read-only installation preflight')
    mode.add_argument('--restore', metavar='BACKUP', help='Restore the previous theme selection from this backup')
    args = parser.parse_args()
    try:
        if args.check:
            preflight()
            print(json.dumps({'ready': True, 'source': str(SOURCE), 'destination': str(DEST), 'selection': str(CONF)}, indent=2))
        elif os.geteuid() != 0:
            parser.exit(1, 'Administrator access is required: run this script with sudo or pkexec.\n')
        elif args.restore:
            restore(args.restore)
        else:
            install()
    except (OSError, ValueError, RuntimeError, configparser.Error) as error:
        parser.exit(1, f'{error}\n')
