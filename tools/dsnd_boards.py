"""dsnd_boards.py - Galaxian discrete sound boards as dsnd_engine programs (rtl/rodimus/dsnd_engine, MRA index 5).

BOARDS maps a board name to a function returning a finished dsnd.Board; gen_mra.py picks the board per set and emits
the program through the master dsnd_program() hook. Assembler = master tools/dsnd.py.
Engine: TICK 1024 at 49.152 MHz (FS = 48 kHz), 410 budget units, OUT only (mono).
Sources: rtl/boards/galaxian_snd/galaxian_sound.sv (tools/dsnd_galaxian.py header).
"""
import sys
from pathlib import Path

sys.path.insert(0, "/Work/Projects/RodimusCoresMaster_MiSTer/tools")
import dsnd                                                 # noqa: E402

dsnd.set_fs(49152000 / 1024)                                # before any board module imports dsnd
sys.path.insert(0, str(Path(__file__).resolve().parent))
import dsnd_galaxian                                        # noqa: E402

BOARDS = {
    "galaxian": dsnd_galaxian.galaxian,     # Galaxian sound (Galaxian.pdf p. 27)
    "mooncrst": dsnd_galaxian.mooncrst,     # Moon Cresta mixer (MOONCRST_SOUND)
    "sbhoei": dsnd_galaxian.sbhoei,         # Space Battle sound (SB-002U, sbhoei_discrete)
}


_cache = {}


def program(board):
    """program bytes for a board, or None"""
    if board not in _cache:
        f = BOARDS.get(board)
        _cache[board] = f().binary() if f else None
    return _cache[board]


if __name__ == "__main__":
    for m, f in BOARDS.items():
        p = f()
        print(f"{m:10s} words {len(p.code):4d}  worst units {p.worst_path():3d}  registers {len(p.regs):3d}")
        if len(sys.argv) > 1:
            Path(sys.argv[1]).mkdir(parents=True, exist_ok=True)
            (Path(sys.argv[1]) / f"{m}.bin").write_bytes(p.binary())
