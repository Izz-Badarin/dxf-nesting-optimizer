"""MaxRects bin packing at bounding-box level.

Classic maximal-rectangle algorithm: keep every maximal free rectangle,
place each item at the bottom-left corner of the best-scoring free rectangle
that fits, then split all overlapping free rectangles into remainders.

The nesting engine passes *collision bounding boxes* (part bbox grown by
half the part spacing), so adjacent items keep exactly the required gap.
"""

from __future__ import annotations

_EPS = 1e-6

#: a free rectangle is (x, y, w, h) in usable-sheet coordinates
Rect = tuple[float, float, float, float]

RULES = ("best-area", "short-side")


class MaxRectsBin:
    """One bin (sheet) of the MaxRects algorithm."""

    def __init__(self, width: float, height: float) -> None:
        self.width = width
        self.height = height
        self.free: list[Rect] = [(0.0, 0.0, width, height)]

    def best_score(self, w: float, h: float, rule: str) -> tuple[float, float, float] | None:
        """Best (score, x, y) for placing a w x h item, or None if it fits nowhere."""
        best: tuple[float, float, float] | None = None
        for fx, fy, fw, fh in self.free:
            if w > fw + _EPS or h > fh + _EPS:
                continue
            score = min(fw - w, fh - h) if rule == "short-side" else fw * fh - w * h
            if (
                best is None
                or score < best[0] - _EPS
                or (abs(score - best[0]) <= _EPS and (fy, fx) < (best[2], best[1]))
            ):
                best = (score, fx, fy)
        return best

    def place(self, x: float, y: float, w: float, h: float) -> None:
        """Occupy the w x h item at (x, y) and recompute free rectangles."""
        placed = (x, y, x + w, y + h)
        new_free: list[Rect] = []
        for rect in self.free:
            new_free.extend(_split(rect, placed))
        self.free = _prune(new_free)

    def insert(self, w: float, h: float, rule: str) -> tuple[float, float] | None:
        """Score, place and return the item position, or None if it does not fit."""
        best = self.best_score(w, h, rule)
        if best is None:
            return None
        _, x, y = best
        self.place(x, y, w, h)
        return (x, y)


def _split(rect: Rect, placed: tuple[float, float, float, float]) -> list[Rect]:
    fx, fy, fw, fh = rect
    px0, py0, px1, py1 = placed
    if px0 >= fx + fw - _EPS or px1 <= fx + _EPS or py0 >= fy + fh - _EPS or py1 <= fy + _EPS:
        return [rect]  # no overlap
    out: list[Rect] = []
    if px0 > fx + _EPS:
        out.append((fx, fy, px0 - fx, fh))
    if px1 < fx + fw - _EPS:
        out.append((px1, fy, fx + fw - px1, fh))
    if py0 > fy + _EPS:
        out.append((fx, fy, fw, py0 - fy))
    if py1 < fy + fh - _EPS:
        out.append((fx, py1, fw, fy + fh - py1))
    return out


def _contains(outer: Rect, inner: Rect) -> bool:
    ox, oy, ow, oh = outer
    ix, iy, iw, ih = inner
    return (
        ix >= ox - _EPS
        and iy >= oy - _EPS
        and ix + iw <= ox + ow + _EPS
        and iy + ih <= oy + oh + _EPS
    )


def _prune(rects: list[Rect]) -> list[Rect]:
    """Drop rectangles fully contained in another (deterministic order)."""
    keep: list[Rect] = []
    for i, rect in enumerate(rects):
        contained = False
        for j, other in enumerate(rects):
            if i == j:
                continue
            if _contains(other, rect) and (not _contains(rect, other) or j < i):
                contained = True
                break
        if not contained:
            keep.append(rect)
    return keep
