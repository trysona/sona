"""Découverte : « Si tu aimes ce titre », une radio faite uniquement
d'artistes que tu n'as jamais écoutés."""

from __future__ import annotations

import asyncio

from app.services import lookup
from app.providers.base import TrackInfo

# ── Radio « artistes inconnus » ─────────────────────────────────────────────


async def unknown_artists_radio(deps, user_id: int, source: str, artist_id: str, artist_name: str = "",
                                per_artist: int = 3, max_artists: int = 10) -> list[TrackInfo]:
    """Les artistes proches de celui du titre, sauf ceux déjà écoutés : leurs
    titres phares, mélangés artiste par artiste."""
    related = await lookup.get_related_artists(deps, source, artist_id)
    plays = await deps.repo.plays_between(user_id, None, None)
    known = {p.artist.casefold() for p in plays} | {artist_name.casefold()}
    fresh = [a for a in related if a.name.casefold() not in known][:max_artists]
    if not fresh:
        return []

    async def top(artist):
        try:
            return (await lookup.get_artist_top_tracks(deps, artist.source, artist.source_id))[:per_artist]
        except Exception:  # noqa: BLE001 — un artiste en panne n'arrête pas la radio
            return []

    batches = await asyncio.gather(*(top(a) for a in fresh))
    out: list[TrackInfo] = []
    for i in range(per_artist):
        for batch in batches:
            if i < len(batch):
                out.append(batch[i])
    return out
