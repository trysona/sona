"""Radio « artistes inconnus », mix selon la météo, classements entre amis."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.providers.base import ArtistInfo, TrackInfo
from app.services import discover
from tests.test_extras import play
from tests.test_party import client, login  # noqa: F401


def tr(sid, artist):
    return TrackInfo("deezer", sid, f"Titre {sid}", artist, None, None, 180, None)


class DiscoverDeezer:
    async def get_related_artists(self, artist_id):
        return [ArtistInfo("deezer", "k", "Connu", None), ArtistInfo("deezer", "n1", "Neuf Un", None),
                ArtistInfo("deezer", "n2", "Neuf Deux", None)]

    async def get_artist_top_tracks(self, artist_id):
        name = {"n1": "Neuf Un", "n2": "Neuf Deux", "k": "Connu"}[artist_id]
        return [tr(f"{artist_id}-{i}", name) for i in range(5)]

    async def get_radio_tracks(self, radio_id):
        return [tr(f"r{radio_id}-{i}", "Radio") for i in range(10)]


def test_unknown_artists_radio_skips_known_artists(client):
    client.deps.deezer = DiscoverDeezer()
    me = login(client, "alice")
    now = datetime.now(timezone.utc).replace(microsecond=0)
    client.post("/plays", headers=me, json={"plays": [play("x", "Connu", now - timedelta(days=2))]})
    got = client.get("/discover/radio/deezer/seed", headers=me, params={"artist": "Graine"}).json()
    assert {t["artist"] for t in got} == {"Neuf Un", "Neuf Deux"}
    # Mélangés artiste par artiste, 3 titres chacun.
    assert [t["artist"] for t in got[:2]] == ["Neuf Un", "Neuf Deux"] and len(got) == 6
