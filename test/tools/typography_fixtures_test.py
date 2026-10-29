"""Publication CSS aliases must never rewrite the embedded upstream font."""
import importlib.util
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
import zipfile

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    'typography_fixtures', REPO / 'tools/make_typography_fixtures.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class TypographyFixturesTest(unittest.TestCase):
    def test_aliases_keep_original_font_and_license_bytes(self):
        with zipfile.ZipFile(REPO / 'test/fixtures/reflowable.epub') as source:
            originals = {name: source.read(name) for name in source.namelist()}
        original_font = originals['EPUB/book.ttf']
        original_license = originals['EPUB/FONT-LICENSE.txt']
        files = fixtures.publication_files()
        self.assertEqual(files.keys(), originals.keys())
        self.assertEqual(files['EPUB/book.ttf'], original_font)
        self.assertEqual(files['EPUB/FONT-LICENSE.txt'], original_license)
        self.assertEqual([name for name in files if name.endswith('.ttf')],
                         ['EPUB/book.ttf'])
        for name, data in files.items():
            if name.endswith(('.xhtml', '.opf')):
                ET.fromstring(data)
            chapter = name.endswith('.xhtml') and '/ch' in name
            if name != 'EPUB/package.opf' and not chapter:
                self.assertEqual(data, originals[name], name)
        # Generation changes only publication-owned documents and metadata.
        with zipfile.ZipFile(REPO / 'test/fixtures/reflowable.epub') as source:
            self.assertEqual(source.read('EPUB/book.ttf'), original_font)


if __name__ == '__main__':
    unittest.main()
