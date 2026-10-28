"""Static checks for config/sofle.keymap: layer shape, references, reachability.

Layer resolution mirrors ZMK: the highest active layer wins, `&trans` falls
through to the next lower active layer, combos match on the highest active layer.
"""
import itertools
import re
from pathlib import Path

import pytest

KEYMAP = Path(__file__).resolve().parent.parent / "config" / "sofle.keymap"
KEYS = 60
DEFAULT, LOWER, RAISE, LOCK, MACRO, GAME = range(6)
EXPECTED_LAYERS = ["default", "lower", "raise", "lock", "macro", "game"]


def _text():
    s = KEYMAP.read_text()
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def _bindings(raw):
    out = []
    for tok in raw.split():
        if tok.startswith("&"):
            out.append([tok])
        else:
            out[-1].append(tok)
    return [" ".join(b) for b in out]


def _layers():
    section = _text().split("keymap {", 1)[1]
    return {
        m.group(1): _bindings(m.group(2))
        for m in re.finditer(r"(\w+)_layer\s*\{\s*bindings\s*=\s*<(.*?)>;", section, re.S)
    }


def _combos():
    section = _text().split("combos {", 1)[1].split("keymap {", 1)[0]
    combos = {}
    for m in re.finditer(r"(\w+)\s*\{([^{}]*)\}", section):
        body = m.group(2)
        pos = re.search(r"key-positions\s*=\s*<([^>]*)>", body)
        bnd = re.search(r"bindings\s*=\s*<(.*?)>;", body, re.S)
        lay = re.search(r"layers\s*=\s*<([^>]*)>", body)
        if pos and bnd:
            combos[m.group(1)] = {
                "positions": [int(x) for x in pos.group(1).split()],
                "binding": " ".join(bnd.group(1).split()),
                "layers": [int(x) for x in lay.group(1).split()] if lay else None,
            }
    return combos


LAYERS = _layers()
ORDERED = [LAYERS[n] for n in EXPECTED_LAYERS]
COMBOS = _combos()


def resolve(active, pos):
    """Binding for `pos` given the set of active layers (highest wins, &trans falls through)."""
    for layer in sorted(active, reverse=True):
        b = ORDERED[layer][pos]
        if b != "&trans":
            return b
    return "&trans"


def targets(binding, behavior):
    m = re.fullmatch(rf"&{behavior} (\d+)", binding)
    return int(m.group(1)) if m else None


def reachable_states():
    """Toggled-layer sets reachable from {DEFAULT} by pressing single keys / combos, with MO layers held."""
    start = frozenset({DEFAULT})
    seen, todo = {start}, [start]
    while todo:
        toggled = todo.pop()
        mo_layers = {
            t for pos in range(KEYS)
            if (t := targets(resolve(toggled, pos), "mo")) is not None
        }
        for held in [()] + [(m,) for m in mo_layers]:
            active = set(toggled) | set(held)
            top = max(active)
            toggles = {
                targets(resolve(active, pos), "tog") for pos in range(KEYS)
            }
            toggles |= {
                targets(c["binding"], "tog") for c in COMBOS.values()
                if c["layers"] is None or top in c["layers"]
            }
            for t in toggles - {None}:
                nxt = frozenset(toggled ^ {t})
                if nxt not in seen:
                    seen.add(nxt)
                    todo.append(nxt)
    return seen


def test_layer_names_and_order():
    assert list(LAYERS) == EXPECTED_LAYERS


@pytest.mark.parametrize("name", EXPECTED_LAYERS)
def test_every_layer_has_60_bindings(name):
    assert len(LAYERS[name]) == KEYS


def test_layer_references_exist():
    refs = []
    for name, binds in LAYERS.items():
        for pos, b in enumerate(binds):
            for beh in ("mo", "tog", "to"):
                if (t := targets(b, beh)) is not None:
                    refs.append((f"{name}[{pos}]", t))
    for cname, c in COMBOS.items():
        if (t := targets(c["binding"], "tog")) is not None:
            refs.append((f"combo {cname}", t))
        refs += [(f"combo {cname} layers", l) for l in c["layers"] or []]
    assert refs
    bad = [(w, t) for w, t in refs if not 0 <= t < len(EXPECTED_LAYERS)]
    assert not bad, bad


def test_combo_positions_in_range():
    for name, c in COMBOS.items():
        assert all(0 <= p < KEYS for p in c["positions"]), name


def test_default_layer_has_no_transparent_keys():
    assert "&trans" not in LAYERS["default"]


def test_every_toggle_layer_can_be_turned_off():
    """Whatever toggled layers we can get into, we can get back to plain default."""
    states = reachable_states()
    assert frozenset({DEFAULT}) in states
    stuck = [sorted(s) for s in states if len(s) > 1 and not _can_return(s, states)]
    assert not stuck, f"cannot return to default from {stuck}"


def _can_return(state, states):
    seen, todo = {state}, [state]
    while todo:
        cur = todo.pop()
        if cur == frozenset({DEFAULT}):
            return True
        for nxt in _neighbors(cur, states):
            if nxt not in seen:
                seen.add(nxt)
                todo.append(nxt)
    return False


def _neighbors(toggled, states):
    mo_layers = {
        t for pos in range(KEYS)
        if (t := targets(resolve(toggled, pos), "mo")) is not None
    }
    out = set()
    for held in [()] + [(m,) for m in mo_layers]:
        active = set(toggled) | set(held)
        top = max(active)
        ts = {targets(resolve(active, pos), "tog") for pos in range(KEYS)}
        ts |= {
            targets(c["binding"], "tog") for c in COMBOS.values()
            if c["layers"] is None or top in c["layers"]
        }
        out |= {frozenset(toggled ^ {t}) for t in ts - {None}}
    return out


# ---- game layer ----------------------------------------------------------

def test_game_layer_can_be_entered_from_default():
    assert frozenset({DEFAULT, GAME}) in reachable_states()


def test_raise_g_enters_game_layer():
    assert resolve({DEFAULT, RAISE}, 29) == f"&tog {GAME}"


def test_game_layer_exit_does_not_rely_on_raise_g():
    """Layer 5 is above Raise (2): holding MO2 on the game layer still yields plain G."""
    assert resolve({DEFAULT, GAME, RAISE}, 29) == "&kp G"
    exits = [n for n, c in COMBOS.items() if GAME in (c["layers"] or []) and c["binding"] == f"&tog {GAME}"]
    assert exits, "need a combo with layers containing 5 that toggles layer 5 off"


def test_game_layer_keeps_mo_keys_for_exit():
    assert LAYERS["game"][53] == "&mo 1" and LAYERS["game"][56] == "&mo 2"


def test_game_layer_inverted_t_arrows():
    g = LAYERS["game"]
    assert (g[32], g[45], g[46], g[47]) == ("&kp UP_ARROW", "&kp LEFT", "&kp DOWN", "&kp RIGHT")


def test_game_layer_left_ctrl_bottom_left():
    assert LAYERS["game"][36] == "&kp LCTRL"


def test_game_layer_has_no_timing_behaviors():
    """No hold-tap / tap-dance / morph bindings: they add input latency."""
    custom = [b for b in LAYERS["game"] if not re.match(r"&(kp|mo|trans|none) ", b + " ")]
    assert not custom, custom


def test_game_layer_has_no_transparent_keys():
    assert "&trans" not in LAYERS["game"]


# ---- other layers --------------------------------------------------------

def test_lock_layer_disables_everything():
    assert set(LAYERS["lock"]) == {"&none"}


def test_lock_can_be_exited_by_combo():
    assert any(LOCK in (c["layers"] or []) and c["binding"].startswith("&lock_toggle_hold") for c in COMBOS.values())
