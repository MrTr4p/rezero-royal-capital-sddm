#!/usr/bin/env python3
"""Exercise installation/rollback using temporary directories; no sudo needed."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer', Path(__file__).with_name('install.py'))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.source = root / 'source'
        self.source.mkdir()
        (self.source / 'Main.qml').write_text('new theme')
        self.dest = root / 'themes/rezero-royal-capital'
        self.conf = root / 'etc/99-rezero-royal-capital.conf'
        self.conf.parent.mkdir(parents=True)
        self.other = self.conf.parent / '90-sister-location.conf'
        self.other.write_text('[Theme]\nCurrent=sister-location\n')
        self.backups = root / 'backups'
        for name, value in [('SOURCE', self.source), ('DEST', self.dest), ('CONF', self.conf), ('BACKUPS', self.backups)]:
            p = patch.object(installer, name, value)
            p.start()
            self.addCleanup(p.stop)
        p = patch.object(installer, 'preflight')
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

    def test_first_install_and_restore_preserve_other_configuration(self):
        result = self.install()
        self.assertEqual((self.dest / 'Main.qml').read_text(), 'new theme')
        self.assertEqual(self.conf.read_text(), installer.SELECTION)
        rollback = self.restore(result['backup'])
        self.assertFalse(self.dest.exists())
        self.assertFalse(self.conf.exists())
        self.assertTrue(Path(rollback['retained_theme']).is_dir())
        self.assertEqual(self.other.read_text(), '[Theme]\nCurrent=sister-location\n')

    def test_replacement_restores_original_theme_and_selection(self):
        self.dest.mkdir(parents=True)
        (self.dest / 'Main.qml').write_text('old theme')
        self.conf.write_text('[Theme]\nCurrent=previous\n')
        result = self.install()
        self.assertEqual((Path(result['backup']) / 'theme/Main.qml').read_text(), 'old theme')
        self.restore(result['backup'])
        self.assertEqual((self.dest / 'Main.qml').read_text(), 'old theme')
        self.assertEqual(self.conf.read_text(), '[Theme]\nCurrent=previous\n')

    def test_failed_selection_write_rolls_back(self):
        self.dest.mkdir(parents=True)
        (self.dest / 'Main.qml').write_text('old theme')
        self.conf.write_text('old selection')
        with patch.object(installer, 'atomic_text', side_effect=OSError('write failed')):
            with self.assertRaises(OSError):
                installer.install()
        self.assertEqual((self.dest / 'Main.qml').read_text(), 'old theme')
        self.assertEqual(self.conf.read_text(), 'old selection')
        self.assertFalse(list(self.dest.parent.glob('.rezero-royal-capital-*')))


if __name__ == '__main__':
    unittest.main()
