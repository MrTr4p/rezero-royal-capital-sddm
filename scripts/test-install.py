#!/usr/bin/env python3
"""Exercise installation/rollback using temporary directories; no sudo needed."""
import contextlib
import configparser
import importlib.util
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer', Path(__file__).with_name('install.py'))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
PACKAGED_THEME = installer.SOURCE


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.source = root / 'source'
        (self.source / 'assets').mkdir(parents=True)
        (self.source / 'Main.qml').write_text('new theme')
        (self.source / 'metadata.desktop').write_text('[SddmGreeterTheme]\nQtVersion=6\n')
        (self.source / 'theme.conf').write_text('[General]\nBackground=assets/royal-capital.png\n')
        (self.source / 'assets/royal-capital.png').write_bytes(b'fixture artwork')
        self.dest = root / 'themes/rezero-royal-capital'
        self.conf = root / 'etc/sddm.conf.d/99-rezero-royal-capital.conf'
        self.legacy = root / 'etc/sddm.conf'
        self.conf.parent.mkdir(parents=True)
        self.other = self.conf.parent / '90-sister-location.conf'
        self.other.write_text('[Theme]\nCurrent=sister-location\n')
        self.backups = root / 'backups'
        for name, value in [('SOURCE', self.source), ('DEST', self.dest), ('CONF', self.conf),
                            ('LEGACY_CONF', self.legacy), ('BACKUPS', self.backups)]:
            p = patch.object(installer, name, value)
            p.start()
            self.addCleanup(p.stop)
        # Only the external executable lookup is simulated. All preflight,
        # copy/hash verification, configuration writes and rollback run for real.
        p = patch.object(installer.shutil, 'which', return_value='/test/bin/sddm-greeter-qt6')
        p.start()
        self.addCleanup(p.stop)

    def install(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            installer.install()
        return json.loads(output.getvalue())

    def restore(self, backup):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            installer.restore(backup)
        return json.loads(output.getvalue())

    def existing_installation(self):
        self.dest.mkdir(parents=True)
        (self.dest / 'Main.qml').write_text('old theme')
        self.conf.write_text('[Theme]\nCurrent=previous\n')

    def assert_original_installation(self):
        self.assertEqual((self.dest / 'Main.qml').read_text(), 'old theme')
        self.assertEqual(self.conf.read_text(), '[Theme]\nCurrent=previous\n')
        self.assertFalse(list(self.dest.parent.glob('.rezero-royal-capital-*')))

    def assert_no_installation(self):
        self.assertFalse(self.dest.exists())
        self.assertFalse(self.conf.exists())
        self.assertFalse(self.backups.exists())

    def snapshot(self):
        root = Path(self.temporary.name)
        return {str(p.relative_to(root)): (stat.S_IMODE(p.stat().st_mode), p.read_bytes() if p.is_file() else None)
                for p in root.rglob('*')}

    def test_first_install_and_restore_preserve_other_configuration(self):
        self.legacy.write_text('[General]\nDisplayServer=wayland\n')
        result = self.install()
        self.assertEqual((self.dest / 'Main.qml').read_text(), 'new theme')
        config = configparser.RawConfigParser()
        config.read(self.conf)
        self.assertEqual(config['Theme']['Current'], installer.NAME)
        self.assertEqual(config['Theme']['ThemeDir'], str(self.dest.parent))
        self.assertFalse(result['service_restarted'])
        backup = Path(result['backup'])
        self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o700)
        self.assertEqual((backup / 'sddm.conf-reference').read_bytes(), self.legacy.read_bytes())
        self.assertEqual((backup / 'sddm.conf.d-reference' / self.other.name).read_bytes(), self.other.read_bytes())
        rollback = self.restore(result['backup'])
        self.assertFalse(self.dest.exists())
        self.assertFalse(self.conf.exists())
        self.assertTrue(Path(rollback['retained_theme']).is_dir())
        self.assertEqual(self.other.read_text(), '[Theme]\nCurrent=sister-location\n')
        self.assertEqual(self.legacy.read_text(), '[General]\nDisplayServer=wayland\n')
        self.assertFalse(rollback['service_restarted'])

    def test_replacement_restores_original_theme_and_selection(self):
        self.existing_installation()
        result = self.install()
        self.assertEqual((Path(result['backup']) / 'theme/Main.qml').read_text(), 'old theme')
        self.restore(result['backup'])
        self.assert_original_installation()

    def test_complete_packaged_theme_is_copied_and_readable(self):
        with patch.object(installer, 'SOURCE', PACKAGED_THEME):
            result = self.install()
        originals = {p.relative_to(PACKAGED_THEME) for p in PACKAGED_THEME.rglob('*') if p.is_file()}
        copies = {p.relative_to(self.dest) for p in self.dest.rglob('*') if p.is_file()}
        self.assertEqual(originals, copies)
        for relative in originals:
            with self.subTest(file=str(relative)):
                self.assertEqual(installer.digest(PACKAGED_THEME / relative), installer.digest(self.dest / relative))
                self.assertEqual(stat.S_IMODE((self.dest / relative).stat().st_mode), 0o644)
        for directory in [self.dest, *[p for p in self.dest.rglob('*') if p.is_dir()]]:
            self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o755)
        config = configparser.RawConfigParser()
        config.read(self.dest / 'theme.conf')
        self.assertEqual(config['General']['Background'], 'assets/royal-capital.png')
        self.assertTrue((self.dest / config['General']['Background']).is_file())
        self.restore(result['backup'])
        self.assertFalse(self.dest.exists())

    def test_preflight_is_read_only(self):
        self.existing_installation()
        before = self.snapshot()
        installer.preflight()
        self.assertEqual(self.snapshot(), before)

    def test_missing_artwork_refuses_before_writes(self):
        (self.source / 'assets/royal-capital.png').unlink()
        with self.assertRaisesRegex(RuntimeError, 'Missing theme file'):
            installer.install()
        self.assert_no_installation()

    def test_missing_qt6_greeter_refuses_before_writes(self):
        with patch.object(installer.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'Qt 6 SDDM'):
                installer.install()
        self.assert_no_installation()

    def test_source_symlink_refuses_before_writes(self):
        (self.source / 'linked.qml').symlink_to(self.source / 'Main.qml')
        with self.assertRaisesRegex(RuntimeError, 'symlinks'):
            installer.install()
        self.assert_no_installation()

    def test_target_symlink_refuses_without_changing_linked_files(self):
        self.conf.symlink_to(self.other)
        before = self.other.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'symlink'):
            installer.install()
        self.assertEqual(self.other.read_bytes(), before)
        self.assertTrue(self.conf.is_symlink())
        self.assertFalse(self.dest.exists())

    def test_conflicting_later_configuration_refuses_before_writes(self):
        later = self.conf.parent / 'zz-custom.conf'
        for path in (later, self.legacy):
            for key, value in (('Current', 'other-theme'), ('ThemeDir', '/somewhere/else'),
                               ('Current', ''), ('ThemeDir', '')):
                with self.subTest(path=path.name, key=key):
                    path.write_text(f'[Theme]\n{key}={value}\n')
                    with self.assertRaisesRegex(RuntimeError, 'overrides'):
                        installer.install()
                    self.assert_no_installation()
                    path.unlink()

    def test_matching_later_configuration_is_accepted(self):
        self.legacy.write_text(f'[Theme]\nCurrent={installer.NAME}\nThemeDir={self.dest.parent}/\n')
        installer.preflight()
        self.assert_no_installation()

    def test_malformed_configuration_refuses_before_writes(self):
        self.legacy.write_text('not an ini file')
        with self.assertRaises(configparser.Error):
            installer.install()
        self.assert_no_installation()

    def test_failed_selection_write_rolls_back(self):
        self.existing_installation()
        with patch.object(installer, 'atomic_text', side_effect=OSError('write failed')):
            with self.assertRaises(OSError):
                installer.install()
        self.assert_original_installation()

    def test_failed_first_install_leaves_no_theme_or_selection(self):
        with patch.object(installer, 'atomic_text', side_effect=OSError('write failed')):
            with self.assertRaises(OSError):
                installer.install()
        self.assertFalse(self.dest.exists())
        self.assertFalse(self.conf.exists())
        self.assertFalse(list(self.dest.parent.glob('.rezero-royal-capital-*')))

    def test_failed_manifest_write_rolls_back_written_selection(self):
        self.existing_installation()
        original = installer.atomic_text

        def fail_manifest(path, text):
            if path.name == 'manifest.json':
                raise OSError('manifest write failed')
            original(path, text)

        with patch.object(installer, 'atomic_text', side_effect=fail_manifest):
            with self.assertRaises(OSError):
                installer.install()
        self.assert_original_installation()

    def test_corrupted_copy_leaves_previous_installation_intact(self):
        self.existing_installation()
        original = installer.digest

        def corrupt_digest(path):
            return original(path) if path.is_relative_to(self.source) else 'corrupted'

        with patch.object(installer, 'digest', side_effect=corrupt_digest):
            with self.assertRaisesRegex(RuntimeError, 'Copy verification failed'):
                installer.install()
        self.assert_original_installation()

    def test_atomic_write_failure_preserves_existing_file_and_cleans_temporary(self):
        self.conf.write_text('old selection')
        before = self.snapshot()
        with patch.object(installer.os, 'replace', side_effect=OSError('replace failed')):
            with self.assertRaises(OSError):
                installer.atomic_text(self.conf, 'new selection')
        self.assertEqual(self.snapshot(), before)

    def test_failed_restore_selection_write_keeps_current_installation(self):
        self.existing_installation()
        result = self.install()
        selection = self.conf.read_bytes()
        with patch.object(installer, 'atomic_text', side_effect=OSError('write failed')):
            with self.assertRaises(OSError):
                self.restore(result['backup'])
        self.assertEqual((self.dest / 'Main.qml').read_text(), 'new theme')
        self.assertEqual(self.conf.read_bytes(), selection)
        self.assertFalse(list(self.dest.parent.glob('.rezero-royal-capital-*')))
        self.restore(result['backup'])
        self.assert_original_installation()

    def test_failed_restore_copy_leaves_current_installation_intact(self):
        self.existing_installation()
        result = self.install()
        selection = self.conf.read_bytes()
        with patch.object(installer.shutil, 'copytree', side_effect=OSError('copy failed')):
            with self.assertRaises(OSError):
                self.restore(result['backup'])
        self.assertEqual((self.dest / 'Main.qml').read_text(), 'new theme')
        self.assertEqual(self.conf.read_bytes(), selection)
        self.assertFalse(list(self.dest.parent.glob('.rezero-royal-capital-*')))

    def test_invalid_or_missing_backup_refuses_before_changes(self):
        self.existing_installation()
        result = self.install()
        backup = Path(result['backup'])
        with self.assertRaisesRegex(RuntimeError, 'directly inside'):
            self.restore(backup.parent.parent)
        (backup / 'selection.conf').unlink()
        before = self.snapshot()
        with self.assertRaisesRegex(RuntimeError, 'selection backup is missing'):
            self.restore(backup)
        self.assertEqual(self.snapshot(), before)

    def test_restore_rejects_symlink_target(self):
        result = self.install()
        self.conf.unlink()
        self.conf.symlink_to(self.other)
        with self.assertRaisesRegex(RuntimeError, 'symlink'):
            self.restore(result['backup'])
        self.assertEqual((self.dest / 'Main.qml').read_text(), 'new theme')
        self.assertEqual(self.other.read_text(), '[Theme]\nCurrent=sister-location\n')


if __name__ == '__main__':
    unittest.main()
