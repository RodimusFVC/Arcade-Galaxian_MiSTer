#!/usr/bin/env python3
"""Generate MRAs for the Galaxian core straight from MAME's galaxian / galaxold / scramble / scobra / dambustr /
galaxian_rockclim drivers. Engine: RodimusCoresMaster_MiSTer/tools/mra_lib.py (release layout, ioctl index map, game-ID
block, opt-in features); tables in tools/galaxian_tables.py.

Usage:
    gen_mra.py <releases_dir> [set ...]      (no sets: every supported, working set)
    gen_mra.py --check                       every GAME() in DRIVERS accounted for, every ROM_START parsed

Game-ID block (index 1): the fleet layout. Ports 0-3 = the board's IN0-IN3, port 4 = DIP-only fake port (IN4 /
COINAGE: Rock Climber IN4, 4 Fun in 1 game DIPs, non-contiguous DIPs packed by the engine), DIP byte n = port n.
Control ids 56-63 = lines of DIP byte 3, 24-31 = lines of DIP byte 4 (ports reading a fake DIP port's bit).
Byte 3 (flags2): [0] optional mouse, [1] ROT180. Bytes 64-83: the board config (SUPPORTED value after the variant).
verilator/build_rom.py builds its images from Core().setup().
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, "/Work/Projects/RodimusCoresMaster_MiSTer/tools")
sys.path.insert(0, str(Path(__file__).resolve().parent))
import mra_lib                                          # noqa: E402
from galaxian_tables import *                           # noqa: E402,F401,F403


def fin_dips(ports, table):
    """4 Fun in 1: per-game FAKE DIP ports packed into the IN3 / IN4 DIP bytes (FIN_DIPS)."""
    def move(v, src, dst):                              # bits of src (low first) -> bits of dst
        sb = [i for i in range(8) if src >> i & 1]
        db = [i for i in range(8) if dst >> i & 1]
        return sum(1 << d for s_, d in zip(sb, db) if v >> s_ & 1)
    out = {k: v for k, v in ports.items() if k not in table}
    for tag, moves in table.items():
        for m, byte, nm in moves:
            f = next(f for f in ports[tag] if f["kind"] == "dip" and f["mask"] == m)
            out.setdefault(f"IN{byte}", []).append(dict(f, mask=nm, default=move(f["default"], m, nm),
                                                        settings=[(move(v, m, nm), n) for v, n in f["settings"]]))
    return out


class Core(mra_lib.Core):
    RBF = RBF
    MAME_VERSION = MAME_VERSION
    MRA_TIMESTAMP = "20260928000000"
    DRIVERS = ["galaxian.cpp", "galaxold.cpp", "scramble.cpp", "scobra.cpp", "dambustr.cpp", "galaxian_rockclim.cpp"]
    PER_DRIVER = True
    # drivers that only hold parent sets of our clones (dockman, thepit, ckong, scorpion ...)
    PARENT_DRIVERS = ["bagman.cpp", "cclimber.cpp", "centiped.cpp", "cvs.cpp", "ladybug.cpp", "pacman.cpp", "phoenix.cpp",
                      "rallyx.cpp", "roundup.cpp"]
    # Main_MiSTer's names.txt lookup is a substring search for "<file name>:": a bare "Scramble" matches another core's
    # line (user, 2026-09-29); "Victory" clashes with Exidy's Victory.mra in _RodimusCores/_Arcade/ (2026-10-22)
    FILE_NAME = {"scramble": "Scramble (Konami)", "victoryc": "Victory (Comsoft)"}
    SAFE_QMARK = "-"                                    # 'Swarm (Bootleg-).mra'
    PATCHED = {"froggerp": dict(parent="frogger", name="Frogger (Patched)", manuf="philmurr", year="2023", zip="hbfrogger.zip",
                                parts={"frogger.27": ("froggerp/frogger.27p", "b05c6d06"),
                                       "frsm3.7": ("froggerp/frsm3.7p", "098a8093")})}
    ARTWORK = False                                     # no artwork module in this core yet
    DEFAULT_CATEGORY = "Shooter"
    SERIES_BY_PARENT = SERIES_BY_PARENT

    CLK_HZ, FRAME_HZ = CLK_HZ, FRAME_HZ
    HISCORE_INIT_FRAME = HISCORE_INIT_FRAME
    HISCORE_SKIP = HISCORE_SKIP
    HISCORE_IGNORE_DELAY = True                         # START_WAIT is measured on the core, not MAME's @delay
    HISCORE_OWN_FIRST = True

    REGIONS = REGIONS
    IGNORED_REGIONS = IGNORED_REGIONS
    REGION_OVERRIDE = REGION_OVERRIDE
    # user1 PROM tails the hardware never addresses (Mariner / Strategy X background PROM)
    REGION_TRUNCATE = {(k[-2], "user1") for k in SUPPORTED if k[-2] not in REGION_OVERRIDE}
    STANDIN = STANDIN
    ROM_MOVE = ROM_MOVE
    WORD_SWAP_AS_DUMPED = True                          # BMX Stunts: the board swaps the byte pair (A0 inverted)
    SUPPORTED = SUPPORTED

    PORTS = [("IN0",), ("IN1",), ("IN2", "DSW0", "DSW1"), ("IN3", "FAKE", "DSW", "DSW1"), ("IN4", "COINAGE"), ("",)]
    UNIQUE_PORT_TAGS = True
    MAX_DIP_PORTS = 5
    DIP_BYTE_PER_PORT = True
    DIP_LINE_IDS = {3: 56, 4: 24}
    DIP_SPILL_PORT = 4
    CUSTOM_LINES = {r"azurian_port_r<(\d)>": (3, lambda m: int(m.group(1))),
                    r"muxbit_r": (3, 1),                # King & Balloon Speech DIP; the board swaps in service (B003)
                    r"(?:stratgyx|ckongs)_coinage_r<0x0?([0-9a-fA-F]+)>": (4, lambda m: int(m.group(1), 16).bit_length() - 1)}
    CTL = {**mra_lib.Core.CTL, ("BILL1", 0): 18}
    TRACKBALL = {}
    IGNORED_TYPES = IGNORED_TYPES
    SKIP = SKIP

    @staticmethod
    def cfg(variant, n=21):
        return (list(variant) + [0] * n)[:n]

    def pre_place(self, segs, g, variant):
        """S2650 ROM pages 0000 / 2000 / 4000 / 6000 (4K) -> 0000-3FFF; gfx1 / gfx2 bitplanes to their plane stores."""
        cfg, name = self.cfg(variant), g["name"]
        if cfg[13] & B7_S2650:
            for s in segs:
                if s["region"] == "maincpu":
                    if s["dst"] & 0x1000 or (s["dst"] & 0xFFF) + s["len"] > 0x1000:
                        raise SystemExit(f"{name}: S2650 page")
                    s["dst"] = (s["dst"] >> 13 << 12) | (s["dst"] & 0xFFF)
        return self.split_high(self.split_planes(segs, bool(cfg[1] & V_PACKED), bool(cfg[11] & V4_BPP3), name))

    @staticmethod
    def split_planes(segs, packed, bpp3, setname):
        """gfx1 / gfx2 = two bitplanes, RGN_FRAC(0,2) and RGN_FRAC(1,2): each half goes to its own plane store.
        Packed gfx (both planes in each byte, V_PACKED): the whole region goes to both stores."""
        out = []
        for s in segs:
            if s["region"] not in ("gfx1", "gfx2"):
                out.append(s)
                continue
            if packed:
                out += [dict(s, region=f'{s["region"]}_p0'), dict(s, region=f'{s["region"]}_p1')]
                continue
            if bpp3:
                for base, rg in BPP3_PLANES:
                    lo, hi = max(s["dst"], base), min(s["dst"] + s["len"], base + 0x1000)
                    if lo < hi:
                        out.append(dict(s, region=rg, src=s["src"] + lo - s["dst"], dst=lo - base, len=hi - lo))
                continue
            if s["region"] == "gfx1" and setname in GFX_QUARTERS:
                for q in range(4):
                    lo, hi = max(s["dst"], q * 0x2000), min(s["dst"] + s["len"], (q + 1) * 0x2000)
                    if lo < hi:
                        out.append(dict(s, region=f"gfx1_p{q & 1}" + ("h" if q & 2 else ""), src=s["src"] + lo - s["dst"],
                                        dst=lo - q * 0x2000, len=hi - lo))
                continue
            rg = s["region"]
            half = s["rsize"] // 2
            lo, hi = s["dst"], s["dst"] + s["len"]
            if lo < half:
                out.append(dict(s, region=f"{rg}_p0", len=min(hi, half) - lo))
            if hi > half:
                start = max(lo, half)
                out.append(dict(s, region=f"{rg}_p1", src=s["src"] + start - lo, dst=start - half, len=hi - start))
        return out

    @staticmethod
    def split_high(segs):
        """16K bitplanes: the upper 8K of each plane goes to its own load window."""
        out = []
        for s in segs:
            if s["region"] in ("gfx1_p0", "gfx1_p1") and s["dst"] + s["len"] > 0x2000:
                lo, hi = s["dst"], s["dst"] + s["len"]
                if lo < 0x2000:
                    out.append(dict(s, len=0x2000 - lo))
                start = max(lo, 0x2000)
                out.append(dict(s, region=s["region"] + "h", src=s["src"] + start - lo, dst=start - 0x2000, len=hi - start))
            else:
                out.append(s)
        return out

    def index0(self, segs, g, variant):
        """4K gfx planes read with 8K codes (GFX_MIRROR): the upper 4K mirrors the lower; bytes 64+ = board config."""
        if g["name"] in GFX_MIRROR:
            for base in (REGIONS["gfx1_p0"][0], REGIONS["gfx1_p1"][0]):
                half = [s for s in segs if base <= s["addr"] < base + 0x1000]
                if not half or any(s["addr"] + s["len"] > base + 0x1000 for s in half):
                    raise SystemExit(f'{g["name"]}: gfx mirror')
                segs = segs + [dict(s, addr=s["addr"] + 0x1000) for s in half]
            segs.sort(key=lambda s: s["addr"])
        return segs, self.cfg(variant)[1:]

    def dsnd_program(self, g):
        """Galaxian / Moon Cresta discrete sound on the dsnd_engine (index 5), as the dispatcher mixes it: none with
        B2_NODISC or on Space Battle (bflags12[0], own sound board)."""
        cfg = self.cfg(self.variant(g))
        if cfg[5] & B2_NODISC or cfg[19] & 0x01:
            return None
        import dsnd_boards
        return dsnd_boards.program("mooncrst" if cfg[2] & B_MCSND else "galaxian")

    def flags2(self, g):
        return (0x01 if g["name"] in MOUSE_SETS else 0) | (0x02 if g["rot"] == "ROT180" else 0)

    def port_fixup(self, g, ports):
        """PORT_CONDITION alternatives of one DIP value become one setting ("A / B"); 4 Fun in 1 DIP packing; a
        non-contiguous DIP on the DIP-only fake port (IN4 / COINAGE) is read by handlers the board does not model
        (Crazy Kong ckongg_coinage_r): it stays at its default, not selectable."""
        for fields in ports.values():
            for f in fields:
                if f["kind"] == "dip":
                    merged = {}
                    for v, n in f["settings"]:
                        merged[v] = f"{merged[v]} / {n}" if v in merged else n
                    f["settings"] = list(merged.items())
        if g["inputs"] in FIN_DIPS:
            ports = fin_dips(ports, FIN_DIPS[g["inputs"]])
        tag = next((n for n in self.PORTS[4] if n in ports), None)
        for f in ports.get(tag, []):
            hi, lo = f["mask"].bit_length() - 1, (f["mask"] & -f["mask"]).bit_length() - 1
            if f["kind"] == "dip" and f["mask"] != (1 << (hi + 1)) - (1 << lo):
                f["kind"] = "unused"
        return ports

    def hiscore_addr(self, g, a):
        """S2650 sets: hiscore.dat holds S2650 addresses; their RAM (1C00-1FFF and its mirrors) is replayed at 4000
        (galaxian_board.sv s26_zaddr)."""
        if self.cfg(self.variant(g))[13] & B7_S2650:
            if a & 0x1C00 != 0x1C00:
                raise SystemExit(f'{g["name"]}: hiscore address {a:04X} outside S2650 RAM')
            return 0x4000 | (a & 0x3FF)
        return a


# module-level API for verilator/scripts (runset.py, cmp.py) and verilator/hsmeasure/run.py
PROM_STANDIN = {k: v[:3] for k, v in STANDIN.items()}
_core = None


def core():
    global _core
    if _core is None:
        _core = Core()
    return _core


def parse_games(src):
    return core().parse_games(src)


def hs_addr(g, a):
    return core().hiscore_addr(core().games()[g["name"]], a)


def __getattr__(name):
    if name == "HISCORES":
        return core().hiscores
    raise AttributeError(name)


if __name__ == "__main__":
    Core().main(sys.argv)
