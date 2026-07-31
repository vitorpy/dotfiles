from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import random
import sys
import tempfile
import unittest
from pathlib import Path

DEFAULT_SOURCE = (
    Path(__file__).resolve().parents[1]
    / "private_dot_local/bin/executable_arts-wallpaper"
)
SOURCE = Path(os.environ.get("ARTS_WALLPAPER_SOURCE", DEFAULT_SOURCE))
LOADER = importlib.machinery.SourceFileLoader("arts_wallpaper", str(SOURCE))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
arts = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = arts
LOADER.exec_module(arts)


class FakeHTTP:
    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []

    def get_json(self, url, params=None):
        self.requests.append((url, params))
        if not self.responses:
            raise AssertionError(f"unexpected request: {url}")
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def download(self, url, destination):
        self.requests.append((url, "download"))
        destination.write_bytes(b"P6\n2 2\n255\n" + bytes([255, 0, 0]) * 4)
        return "image/x-portable-pixmap"


class ProviderTests(unittest.TestCase):
    def test_google_normalizes_record(self):
        http = FakeHTTP(
            [
                [
                    {
                        "title": "The Work",
                        "creator": "The Artist",
                        "attribution": "Example Museum",
                        "image": "https://example.test/image",
                        "link": "asset/the-work/abc123",
                    }
                ]
            ]
        )
        candidate = arts.GoogleProvider(http, random.Random(1)).select({})
        self.assertEqual(candidate.artwork.provider, "google")
        self.assertEqual(candidate.artwork.record_id, "abc123")
        self.assertEqual(
            candidate.artwork.image_url, "https://example.test/image=s2560-rw"
        )
        self.assertEqual(
            candidate.artwork.source_url,
            "https://artsandculture.google.com/asset/the-work/abc123",
        )

    def test_cleveland_requires_cc0_flat_art_and_prefers_print_image(self):
        record = {
            "id": 99,
            "accession_number": "1940.1",
            "title": "River",
            "creation_date": "1940",
            "share_license_status": "CC0",
            "type": "Print",
            "creators": [{"description": "Printmaker (American, 1900–1980)"}],
            "images": {
                "web": {"url": "https://example.test/web.jpg"},
                "print": {"url": "https://example.test/print.jpg"},
            },
            "url": "https://www.clevelandart.org/art/1940.1",
        }
        overview = {"info": {"total": 10}, "data": [record]}
        candidate = arts.ClevelandProvider(
            FakeHTTP([overview, {"data": [record]}]), random.Random(3)
        ).select({})
        self.assertEqual(candidate.artwork.record_id, "1940.1")
        self.assertEqual(candidate.artwork.image_url, "https://example.test/print.jpg")
        self.assertEqual(candidate.artwork.rights, "CC0 1.0")

    def test_masp_normalizes_flat_art_and_advances_page_cursor(self):
        response = {
            "result": {
                "items": [
                    {
                        "slug": "three-dimensional-work",
                        "title": "Three-dimensional work",
                        "designation": "Escultura",
                        "image": [{"path": "/uploads/temp/sculpture.jpg"}],
                    },
                    {
                        "slug": "obra-exemplo",
                        "author": "Artista Exemplo",
                        "title": " Obra exemplo ",
                        "date_work": " 1944 ",
                        "technique": "Óleo sobre tela",
                        "designation": "Pintura",
                        "photo_credits": "Fotógrafa Exemplo",
                        "image": [
                            {
                                "filename": "WEB_EXAMPLE_MASP_00001_01",
                                "path": "/uploads/temp/WEB_EXAMPLE_MASP_00001_01.jpg",
                            }
                        ],
                    },
                ],
                "next_page_url": ("https://masp.org.br/pt/acervo/previous/2023?page=2"),
            }
        }
        http = FakeHTTP([response])
        candidate = arts.MaspProvider(http, random.Random(1)).select({})
        self.assertEqual(candidate.artwork.provider, "masp")
        self.assertEqual(candidate.artwork.record_id, "obra-exemplo")
        self.assertEqual(candidate.artwork.title, "Obra exemplo")
        self.assertEqual(candidate.artwork.creator, "Artista Exemplo")
        self.assertEqual(candidate.artwork.date, "1944")
        self.assertEqual(
            candidate.artwork.source_url,
            "https://masp.org.br/acervo/obra/obra-exemplo",
        )
        self.assertEqual(
            candidate.artwork.image_url,
            "https://assets.masp.org.br/uploads/temp/WEB_EXAMPLE_MASP_00001_01.jpg",
        )
        self.assertIn("Fotógrafa Exemplo", candidate.artwork.attribution)
        self.assertEqual(
            candidate.state_update["masp"]["next"],
            "https://masp.org.br/pt/acervo/previous/2023?page=2",
        )

    def test_masp_uses_saved_cursor_and_skips_page_without_flat_art(self):
        saved = "https://masp.org.br/pt/acervo/previous/2022?page=3"
        next_page = "https://masp.org.br/pt/acervo/previous/2022?page=4"
        no_flat_art = {
            "result": {
                "items": [
                    {
                        "slug": "sculpture",
                        "title": "Sculpture",
                        "designation": "Escultura",
                        "image": [{"path": "/uploads/temp/sculpture.jpg"}],
                    }
                ],
                "next_page_url": next_page,
            }
        }
        drawing = {
            "result": {
                "items": [
                    {
                        "slug": "drawing",
                        "title": "Drawing",
                        "author": "Artist",
                        "designation": "Desenho",
                        "image": [{"path": "/uploads/temp/drawing.jpg"}],
                    }
                ],
                "next_page_url": None,
            }
        }
        http = FakeHTTP([no_flat_art, drawing])
        candidate = arts.MaspProvider(http, random.Random(2)).select(
            {"masp": {"next": saved}}
        )
        self.assertEqual(http.requests[0], (saved, None))
        self.assertEqual(http.requests[1], (next_page, None))
        self.assertEqual(candidate.artwork.record_id, "drawing")

    def test_masp_rejects_untrusted_urls(self):
        self.assertIsNone(
            arts.MaspProvider._image_url("https://example.test/uploads/image.jpg")
        )
        self.assertIsNone(
            arts.MaspProvider._valid_page_url(
                "https://example.test/pt/acervo/previous/2023?page=2"
            )
        )

    def test_rijksmuseum_resolves_linked_art_and_advances_type_cursor(self):
        page = {
            "orderedItems": [{"id": "https://id.rijksmuseum.nl/200100001"}],
            "next": {
                "id": (
                    "https://data.rijksmuseum.nl/search/collection?"
                    "imageAvailable=true&type=painting&pageToken=next"
                )
            },
        }
        object_record = {
            "_label": "SK-A-1",
            "identified_by": [
                {
                    "type": "Identifier",
                    "content": "SK-A-1",
                    "classified_as": [{"id": "https://id.rijksmuseum.nl/22015218"}],
                },
                {
                    "type": "Name",
                    "content": "Former Canal Title",
                    "classified_as": [{"id": "https://id.rijksmuseum.nl/22015528"}],
                    "language": [{"id": "http://vocab.getty.edu/aat/300388277"}],
                },
                {
                    "type": "Name",
                    "content": "Canal in Winter",
                    "classified_as": [{"id": "http://vocab.getty.edu/aat/300417207"}],
                    "language": [{"id": "http://vocab.getty.edu/aat/300388277"}],
                },
            ],
            "shows": [{"id": "https://id.rijksmuseum.nl/202100001"}],
            "produced_by": {
                "part": [
                    {
                        "carried_out_by": [
                            {
                                "notation": [
                                    {"@language": "nl", "@value": "Voorbeeldschilder"},
                                    {"@language": "en", "@value": "Example Painter"},
                                ]
                            }
                        ]
                    }
                ],
                "timespan": {"identified_by": [{"type": "Name", "content": "c. 1700"}]},
            },
        }
        visual_record = {
            "digitally_shown_by": [{"id": "https://id.rijksmuseum.nl/500100001"}]
        }
        digital_record = {
            "access_point": [
                {"id": "https://iiif.micr.io/ABCDE/full/max/0/default.jpg"}
            ]
        }
        provider = arts.RijksmuseumProvider(
            FakeHTTP([page, object_record, visual_record, digital_record]),
            random.Random(4),
        )
        provider.artwork_types = ("painting",)
        candidate = provider.select({})
        self.assertEqual(candidate.artwork.record_id, "SK-A-1")
        self.assertEqual(candidate.artwork.title, "Canal in Winter")
        self.assertEqual(candidate.artwork.creator, "Example Painter")
        self.assertEqual(candidate.artwork.date, "c. 1700")
        self.assertEqual(
            candidate.artwork.image_url,
            "https://iiif.micr.io/ABCDE/full/2560,/0/default.webp",
        )
        self.assertIn("next", candidate.state_update["rijksmuseum"]["painting"])


class CoreTests(unittest.TestCase):
    def test_flat_art_filter(self):
        self.assertTrue(arts.is_flat_art("Photographic print"))
        self.assertTrue(arts.is_flat_art([{"title": "Drawing"}]))
        self.assertFalse(arts.is_flat_art("Sculpture"))

    def test_merge_state_preserves_other_rijksmuseum_cursors(self):
        original = {
            "version": 1,
            "rijksmuseum": {"painting": {"next": "old"}},
        }
        merged = arts.merge_state(
            original,
            {"rijksmuseum": {"print": {"next": "new"}}},
        )
        self.assertEqual(merged["rijksmuseum"]["painting"]["next"], "old")
        self.assertEqual(merged["rijksmuseum"]["print"]["next"], "new")
        self.assertNotIn("print", original["rijksmuseum"])

    def test_masp_wallpaper_resolution_floor(self):
        self.assertTrue(arts.masp_image_is_large_enough(3327, 3495))
        self.assertTrue(arts.masp_image_is_large_enough(5194, 2617))
        self.assertFalse(arts.masp_image_is_large_enough(2559, 2000))
        self.assertFalse(arts.masp_image_is_large_enough(4000, 1439))

    def test_first_success_falls_back(self):
        attempted = []

        def attempt(name):
            attempted.append(name)
            if name == "google":
                raise arts.ProviderError("offline")
            return name

        self.assertEqual(
            arts.first_success(["google", "cleveland"], attempt), "cleveland"
        )
        self.assertEqual(attempted, ["google", "cleveland"])

    def test_all_provider_failure_is_bounded(self):
        with self.assertRaises(arts.AllProvidersError) as raised:
            arts.first_success(
                ["google", "cleveland"],
                lambda name: (_ for _ in ()).throw(arts.ProviderError(f"{name} down")),
            )
        self.assertEqual(set(raised.exception.errors), {"google", "cleveland"})

    def test_forced_provider_does_not_add_fallbacks(self):
        self.assertEqual(
            arts.provider_order("cleveland", random.Random(1)),
            ["cleveland"],
        )
        automatic = arts.provider_order("auto", random.Random(1))
        self.assertEqual(set(automatic), set(arts.PROVIDER_NAMES))

    def test_process_and_publish_webp_with_metadata_and_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.ppm"
            source.write_bytes(b"P6\n2 2\n255\n" + bytes([0, 128, 255]) * 4)
            processed = root / "processed.webp"
            width, height = arts.process_image(source, processed)
            self.assertEqual((width, height), (2, 2))
            arts.publish(
                root,
                processed,
                {"provider": "test", "width": width, "height": height},
                {"version": 1},
            )
            self.assertTrue((root / "current.webp").is_file())
            self.assertEqual(
                json.loads((root / "current.json").read_text()),
                {"height": 2, "provider": "test", "width": 2},
            )
            self.assertEqual(
                json.loads((root / "state.json").read_text()), {"version": 1}
            )

    def test_invalid_image_leaves_published_files_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            current = root / "current.webp"
            metadata = root / "current.json"
            current.write_bytes(b"old-image")
            metadata.write_text('{"provider":"old"}\n')
            invalid = root / "invalid"
            invalid.write_bytes(b"not an image")
            before_image = current.read_bytes()
            before_metadata = metadata.read_bytes()
            with self.assertRaises(arts.WallpaperError):
                arts.process_image(invalid, root / "new.webp")
            self.assertEqual(current.read_bytes(), before_image)
            self.assertEqual(metadata.read_bytes(), before_metadata)

    def test_invalid_state_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            state_path.write_text("not json")
            self.assertEqual(arts.load_state(state_path), {"version": 1})


if __name__ == "__main__":
    unittest.main()
