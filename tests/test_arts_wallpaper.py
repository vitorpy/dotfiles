from __future__ import annotations

import importlib.machinery
import importlib.util
import io
import json
import os
import random
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

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


def sample_current_metadata(**overrides):
    metadata = {
        "provider": "masp",
        "provider_name": "Museu de Arte de São Paulo Assis Chateaubriand (MASP)",
        "record_id": "vestes",
        "title": "Vestes",
        "creator": "Gal Oppido",
        "date": "1989",
        "attribution": "MASP; photograph: Eduardo Ortega",
        "rights": "Personal, non-distributed use",
        "rights_url": "https://masp.org.br/acervo/intercambio",
        "source_url": "https://masp.org.br/acervo/obra/vestes",
        "image_url": "https://assets.masp.org.br/uploads/temp/vestes.jpg",
        "downloaded": "2026-08-10T10:49:30+02:00",
        "width": 2560,
        "height": 3328,
    }
    metadata.update(overrides)
    return metadata


def sample_mnw_detail(**overrides):
    detail = {
        "id": 449940,
        "title": "Szopka krakowska",
        "authors": [
            {"name": "Makowski, Tadeusz (1882-1932)"},
            {"name": "Makowski, Tadeusz (1882-1932)"},
            {"name": "Artysta pomocniczy"},
        ],
        "createDates": [{"name": "ok. 1906"}],
        "types": [
            {
                "id": 116727,
                "name": "obraz",
                "hierarchyName": "rodzaje wg techniki / malarstwo / obraz",
            }
        ],
        "techniques": [{"name": "olej"}],
        "copyrights": [
            {
                "id": 500,
                "name": "DOMENA PUBLICZNA",
                "link": "https://pl.wikipedia.org/wiki/Domena_publiczna",
                "restricted": False,
            }
        ],
        "image": {
            "filePath": "45/61/4561a2b9eae1fc4e5ef0459a6e9a5084",
            "extension": "jpg",
        },
    }
    detail.update(overrides)
    return detail


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

    def test_mnw_normalizes_filtered_public_domain_record(self):
        page = {
            "data": {
                "items": [{"id": 449940}],
                "paginatorDetails": {"totalPagesCount": 1},
            }
        }
        http = FakeHTTP([page, {"data": sample_mnw_detail()}])

        candidate = arts.MnwProvider(http, random.Random(1)).select({})

        self.assertEqual(candidate.state_update, {})
        self.assertEqual(candidate.artwork.provider, "mnw")
        self.assertEqual(
            candidate.artwork.provider_name,
            "Muzeum Narodowe w Warszawie (MNW)",
        )
        self.assertEqual(candidate.artwork.record_id, "449940")
        self.assertEqual(candidate.artwork.title, "Szopka krakowska")
        self.assertEqual(
            candidate.artwork.creator,
            "Makowski, Tadeusz (1882-1932); Artysta pomocniczy",
        )
        self.assertEqual(candidate.artwork.date, "ok. 1906")
        self.assertEqual(candidate.artwork.rights, "DOMENA PUBLICZNA")
        self.assertEqual(
            candidate.artwork.rights_url,
            "https://pl.wikipedia.org/wiki/Domena_publiczna",
        )
        self.assertEqual(
            candidate.artwork.source_url,
            "https://cyfrowe.mnw.art.pl/pl/katalog/449940",
        )
        self.assertEqual(
            candidate.artwork.image_url,
            "https://cyfrowe-cdn.mnw.art.pl/upload/multimedia/"
            "45/61/4561a2b9eae1fc4e5ef0459a6e9a5084.jpg",
        )
        self.assertEqual(
            http.requests[0],
            (
                "https://cyfrowe-api.mnw.art.pl/api/search/Object/page/1",
                [
                    ("maxPerPage", 80),
                    ("filter[types][]", 116727),
                    ("filter[types][]", 116729),
                    ("filter[types][]", 116786),
                    ("filter[types][]", 116704),
                    ("filter[copyrights][]", 500),
                    ("filter[formFeature][]", 3),
                ],
            ),
        )

    def test_mnw_selects_a_random_filtered_page(self):
        overview = {
            "data": {
                "items": [{"id": 1}],
                "paginatorDetails": {"totalPagesCount": 3},
            }
        }
        selected_page = {
            "data": {
                "items": [{"id": 449940}],
                "paginatorDetails": {"totalPagesCount": 3},
            }
        }
        rng = mock.Mock()
        rng.randrange.return_value = 3
        http = FakeHTTP([overview, selected_page, {"data": sample_mnw_detail()}])

        candidate = arts.MnwProvider(http, rng).select({})

        self.assertEqual(candidate.artwork.record_id, "449940")
        self.assertEqual(
            http.requests[1][0],
            "https://cyfrowe-api.mnw.art.pl/api/search/Object/page/3",
        )
        rng.randrange.assert_called_once_with(1, 4)
        rng.shuffle.assert_called_once()

    def test_mnw_rejects_nonflat_protected_and_untrusted_records(self):
        public_domain = sample_mnw_detail()["copyrights"][0]
        fixtures = {
            "missing rights": {"copyrights": []},
            "unknown rights": {"copyrights": [{**public_domain, "name": "NIEZNANE"}]},
            "restricted": {"copyrights": [{**public_domain, "restricted": True}]},
            "mixed rights": {
                "copyrights": [public_domain, {**public_domain, "id": 501}]
            },
            "sculpture": {
                "types": [{"id": 42, "name": "rzeźba"}],
                "techniques": [{"name": "odlewanie"}],
            },
            "traversal image": {
                "image": {"filePath": "../../private/image", "extension": "jpg"}
            },
            "absolute image": {
                "image": {
                    "filePath": "https://example.test/image",
                    "extension": "jpg",
                }
            },
        }
        for label, overrides in fixtures.items():
            with self.subTest(label=label):
                self.assertIsNone(
                    arts.MnwProvider._candidate(
                        sample_mnw_detail(**overrides),
                        449940,
                    )
                )

    def test_mnw_detail_checks_are_bounded(self):
        page = {
            "data": {
                "items": [{"id": record_id} for record_id in range(1, 26)],
                "paginatorDetails": {"totalPagesCount": 1},
            }
        }
        invalid_details = [
            {
                "data": sample_mnw_detail(
                    id=record_id,
                    copyrights=[],
                )
            }
            for record_id in range(1, 21)
        ]
        http = FakeHTTP([page, *invalid_details])

        with self.assertRaisesRegex(
            arts.ProviderError,
            "after 20 detail checks",
        ):
            arts.MnwProvider(http, random.Random(1)).select({})

        self.assertEqual(len(http.requests), 21)

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
        self.assertIn("mnw", automatic)

    def test_process_and_publish_wallpaper_and_greeter_derivative(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.ppm"
            source.write_bytes(b"P6\n2 2\n255\n" + bytes([0, 128, 255]) * 4)
            processed = root / "processed.webp"
            greeter = root / "greeter.png"
            width, height = arts.process_image(source, processed)
            self.assertEqual((width, height), (2, 2))
            self.assertEqual(
                arts.render_greeter_image(processed, greeter),
                (2, 2),
            )
            arts.publish(
                root,
                processed,
                greeter,
                {"provider": "test", "width": width, "height": height},
                {"version": 1},
            )
            self.assertTrue((root / "current.webp").is_file())
            self.assertEqual(
                (root / "current.png").read_bytes()[:8],
                b"\x89PNG\r\n\x1a\n",
            )
            self.assertEqual(
                json.loads((root / "current.json").read_text()),
                {"height": 2, "provider": "test", "width": 2},
            )
            self.assertEqual(
                json.loads((root / "state.json").read_text()), {"version": 1}
            )
            for name in (
                "current.webp",
                "current.png",
                "current.json",
                "state.json",
            ):
                self.assertEqual((root / name).stat().st_mode & 0o777, 0o640)

    def test_render_greeter_command_atomically_publishes_png(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.ppm"
            source.write_bytes(b"P6\n2 2\n255\n" + bytes([255, 64, 0]) * 4)
            arts.process_image(source, root / "current.webp")

            result, stdout, stderr = CliTests().run_main(root, ["render-greeter"])

            self.assertEqual(result, 0)
            self.assertEqual(stderr, "")
            self.assertIn("Rendered SDDM greeter image: 2x2", stdout)
            self.assertEqual(
                (root / "current.png").read_bytes()[:8],
                b"\x89PNG\r\n\x1a\n",
            )
            self.assertEqual((root / "current.png").stat().st_mode & 0o777, 0o640)

    def test_failed_greeter_render_preserves_existing_png(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "current.webp").write_bytes(b"not an image")
            current_png = root / "current.png"
            current_png.write_bytes(b"old-greeter-image")

            result, stdout, stderr = CliTests().run_main(root, ["render-greeter"])

            self.assertEqual(result, 1)
            self.assertEqual(stdout, "")
            self.assertIn("SDDM greeter image render failed", stderr)
            self.assertEqual(current_png.read_bytes(), b"old-greeter-image")

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


class CliTests(unittest.TestCase):
    def run_main(self, data_dir, argv):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.dict(
                os.environ,
                {"ARTS_WALLPAPER_DATA_DIR": str(data_dir)},
            ),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = arts.main(argv)
        return result, stdout.getvalue(), stderr.getvalue()

    def test_default_data_dir_matches_shared_publisher_path(self):
        with mock.patch.dict(os.environ, {"ARTS_WALLPAPER_DATA_DIR": ""}):
            self.assertEqual(
                arts.default_data_dir(),
                Path("/var/lib/arts-wallpaper"),
            )

    def test_bare_command_shows_human_current_info(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "current.json").write_text(
                json.dumps(sample_current_metadata()),
                encoding="utf-8",
            )

            result, stdout, stderr = self.run_main(root, [])

            self.assertEqual(result, 0)
            self.assertEqual(stderr, "")
            self.assertIn("Title: Vestes\n", stdout)
            self.assertIn("Artist: Gal Oppido\n", stdout)
            self.assertIn("Date: 1989\n", stdout)
            self.assertIn("Dimensions: 2560x3328\n", stdout)
            self.assertIn(f"Wallpaper: {root / 'current.webp'}\n", stdout)

    def test_human_output_omits_empty_optional_fields(self):
        metadata = sample_current_metadata(
            creator=None,
            date="",
            rights=None,
            rights_url=None,
        )
        output = arts.format_current_metadata(metadata, Path("/tmp/current.webp"))
        self.assertNotIn("Artist:", output)
        self.assertNotIn("Date:", output)
        self.assertNotIn("Rights:", output)
        self.assertNotIn("Rights URL:", output)

    def test_json_outputs_complete_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = sample_current_metadata(creator="Artista Exemplo")
            (root / "current.json").write_text(
                json.dumps(metadata),
                encoding="utf-8",
            )

            result, stdout, stderr = self.run_main(root, ["--json"])

            self.assertEqual(result, 0)
            self.assertEqual(stderr, "")
            self.assertEqual(json.loads(stdout), metadata)

    def test_missing_metadata_does_not_create_data_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "missing"

            result, stdout, stderr = self.run_main(root, [])

            self.assertEqual(result, 1)
            self.assertEqual(stdout, "")
            self.assertIn("no current wallpaper metadata found", stderr)
            self.assertFalse(root.exists())

    def test_malformed_and_incomplete_metadata_fail(self):
        fixtures = (
            ("not json", "could not read current wallpaper metadata"),
            (json.dumps(sample_current_metadata(title="")), "'title'"),
        )
        for content, expected in fixtures:
            with self.subTest(
                expected=expected
            ), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "current.json").write_text(content, encoding="utf-8")

                result, stdout, stderr = self.run_main(root, [])

                self.assertEqual(result, 1)
                self.assertEqual(stdout, "")
                self.assertIn(expected, stderr)

    def test_rotation_requires_explicit_command(self):
        parser = arts.build_parser()
        args = parser.parse_args(
            [
                "rotate",
                "--provider",
                "mnw",
                "--dry-run",
                "--no-restart",
            ]
        )
        self.assertEqual(args.command, "rotate")
        self.assertEqual(args.provider, "mnw")
        self.assertTrue(args.dry_run)
        self.assertTrue(args.no_restart)

        stderr = io.StringIO()
        with redirect_stderr(stderr), self.assertRaises(SystemExit) as raised:
            parser.parse_args(["--provider", "mnw"])
        self.assertEqual(raised.exception.code, 2)
        self.assertIn("error:", stderr.getvalue())
        self.assertIn("rotate", stderr.getvalue())

    def test_rotate_command_routes_to_rotation_workflow(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with mock.patch.object(arts, "rotate_wallpaper", return_value=0) as rotate:
                result, stdout, stderr = self.run_main(
                    root,
                    ["rotate", "--provider", "cleveland"],
                )

            self.assertEqual(result, 0)
            self.assertEqual(stdout, "")
            self.assertEqual(stderr, "")
            rotate.assert_called_once()
            args, data_dir = rotate.call_args.args
            self.assertEqual(args.provider, "cleveland")
            self.assertEqual(data_dir, root)

    def test_render_greeter_command_routes_to_render_workflow(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with mock.patch.object(
                arts,
                "render_greeter_wallpaper",
                return_value=0,
            ) as render:
                result, stdout, stderr = self.run_main(root, ["render-greeter"])

            self.assertEqual(result, 0)
            self.assertEqual(stdout, "")
            self.assertEqual(stderr, "")
            render.assert_called_once_with(root)

    def test_json_cannot_be_combined_with_rotate(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr), self.assertRaises(SystemExit) as raised:
            arts.main(["--json", "rotate"])
        self.assertEqual(raised.exception.code, 2)
        self.assertIn("--json cannot be used with rotate", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
