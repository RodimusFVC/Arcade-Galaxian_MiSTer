#!/usr/bin/env python3
"""Generate MRAs for the Galaxian core straight from MAME galaxian.cpp.

Region placement matches rtl/ram_rom/rom_loader.sv; images are copied as dumped.
DIP switches and the input map come from the set's MAME INPUT_PORTS.

Release layout: a parent set (MAME parent 0) goes to <releases>/<Title>.mra with the
trailing parentheses dropped; a clone goes to
<releases>/_alternatives/_<Parent Title>/<Full Title>.mra.

Usage:
    gen_mra.py <driver.cpp[,driver.cpp...]> <releases_dir> [set ...]      (no sets: every supported set)
"""
import copy
import re
import sys
from pathlib import Path

MAME_VERSION = "0289"
RBF = "Galaxian"
HISCORE_DAT = Path("/CybertronMD/Mame/plugins/hiscore/hiscore.dat")   # current file (user, 2026-09-27)
# hiscore.v header after START_WAIT: CHECK_WAIT 00FF, CHECK_HOLD 2, WRITE_HOLD 2, WRITE_REPEATCOUNT 1,
# WRITE_REPEATWAIT 1111, PAUSEPAD 0, CHANGEMASK 0
HISCORE_HEADER_TAIL = "00 FF 00 02 00 02 00 01 11 11 00 00"
# START_WAIT = last boot-time write to the hiscore.dat ranges, measured in MAME (write taps, 30 s, bytes rewritten
# every frame excluded), + 2 frames. Keyed by a reference set per distinct hiscore.dat layout.
# Measured on the CORE (Verilator write trace, verilator/hsmeasure/run.py): the last boot-time change to the table,
# ignoring attract-mode rewrites and live counters inside a range. MAME frames are too early: the core boots up to
# ~44 frames later, and a restore that lands mid-boot loops the RAM test (Galaxian, 2026-09-29).
HISCORE_INIT_FRAME = {"galaxian": 132, "starfght": 127, "exodus": 133, "warofbug": 3, "blkhole": 1, "orbitron": 0,
                      "azurian": 2, "mooncrst": 3, "mooncrsto": 3, "mooncrstg": 3, "mooncrgx": 3, "moonqsr": 3,
                      "moonal2": 127, "thepitm": 0, "ckongmc": 8, "porter": 3, "skybase": 36, "kong": 6,
                      "scorpionmc": 107, "bongo": 160, "jumpbug": 7, "levers": 2, "checkman": 0, "checkmanj": 0,
                      "dingo": 13, "zigzagb": 17, "fantastc": 1, "timefgtr": 2, "frogger": 1, "moonaln": 131}
# colour PROMs never dumped: stand-in from a related set, (zip, file, crc). Kong (Taito do Brasil) takes Crazy Kong's
# first palette PROM (user, 2026-09-29) - same byte layout; which colour group goes where is a guess
PROM_STANDIN = {"kong": ("ckong.zip", "ck6v.bin", "751c3325"),
                # Time Fighter (Taito do Brasil): Fantastic's PROM, same conversion board - a guess
                "timefgtr": ("fantastc.zip", "prom-74g138", "800f5718")}
# hiscore.dat entries that can't work here: atlantisb's range is live game state, omegab's C060 is unmapped
HISCORE_SKIP = {"atlantisb", "omegab"}
# layouts (by reference set) waiting for a core measurement: no hiscore entry for any set on them until then
HISCORE_PENDING = set()
CLK_HZ, FRAME_HZ = 49_152_000, 60.61

# region -> (base in ioctl index 0, size taken); "gfx1" is split by plane into gfx1_p0 / gfx1_p1
REGIONS = {
    "maincpu": (0x00000, 0x10000),
    "gfx1_p0": (0x10000, 0x02000),
    "gfx1_p1": (0x12000, 0x02000),
    "proms":   (0x14000, 0x00020),
    "audiocpu": (0x18000, 0x02000),
    "gfx2_p0": (0x11000, 0x01000),         # separate sprite ROM: upper half of each plane (code extension 8)
    "gfx2_p1": (0x13000, 0x01000),
}

IGNORED_REGIONS = {"plds", "unknown", "unk"}        # dumps MAME does not use

# (machine config, init) pairs the board implements -> (memory map, video flags, board flags, ROM top >> 8, code
# extension); see rtl/galaxian_board.sv
M_GAL, M_MC, M_SCORP, M_CKONG = 0, 1, 2, 3
V_SCRAMBLE_SHELLS, V_GBR = 0x01, 0x02
B_NMI0, B_RAM2K, B_NOSTARS, B_DECRYPT, B_DECRYPT_OP, B_BANK2, B_MCSND = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40
M_JUMPBUG = 4
X_MC, X_MQ, X_PISCES, X_UPPER, X_BATMAN2, X_MSHUTTLE, X_JUMPBUG = 1, 2, 3, 4, 5, 6, 7
# board flags 2 (optional 6th field)
B2_NOWDOG, B2_NODISC, B2_AYIO, B2_IN2DSW, B2_PDIV8, B2_STARS232 = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
# board flags 3 (optional 7th field): Check Man sound board
S_BOARD, S_JAPAN, S_CMD_OUT, S_DECRYPT, S_PROT_CM, S_PROT_DINGO = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
# video flags 2 (8th field), board flags 4 (9th field)
V2_SPR2, V2_SHELLS_C0, V2_NOSHELLS, V2_PAGE = 0x01, 0x02, 0x04, 0x08
B4_OBJ1K, B4_ROMSWAP, B4_UNSCRAMBLE, B4_AY2, B4_ZZAY, B4_AY3M = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
X_SPRITE_ROM = 8
M_FROGGER = 5
# video flags 3 (10th field), board flags 5 (11th field)
V3_FROGGER = 0x0F                                               # nibble swap, colour rotate, blue river, gfx D0/D1
B5_KONAMI, B5_TWO_AY, B5_SND_SWAP01 = 0x01, 0x02, 0x04
MC = B_NMI0 | B_MCSND                                           # mooncrst_map: NMI enable at B000, MOONCRST_SOUND
SUPPORTED = {
    ("galaxian", "init_galaxian"):  (M_GAL, 0, 0, 0, 0),
    ("galaxian", "init_nolock"):    (M_GAL, 0, 0, 0, 0),        # coin lockout not connected
    ("galaxian", "init_azurian"):   (M_GAL, V_SCRAMBLE_SHELLS, 0, 0, 0),
    ("galaxian", "init_mooncrgx"):  (M_GAL, 0, 0, 0, X_MC),     # lamps / coin lockout replaced by the gfx bank
    ("mooncrst", "init_mooncrst"):  (M_MC, 0, MC | B_DECRYPT, 0, X_MC),
    ("mooncrst", "init_mooncrsu"):  (M_MC, 0, MC, 0, X_MC),
    ("mooncrst", "init_galaxian"):  (M_MC, 0, MC, 0, 0),
    ("eagle", "init_mooncrsu"):     (M_MC, V_GBR, MC, 0, X_MC),
    ("moonqsr", "init_moonqsr"):    (M_MC, 0, MC | B_DECRYPT_OP, 0, X_MQ),
    ("thepitm", "init_mooncrsu"):   (M_MC, 0, B_MCSND | B_NOSTARS, 0x48, X_MC),    # NMI enable moved to B001
    ("porter", "init_pisces"):      (M_MC, 0, MC | B_RAM2K | B_BANK2, 0x50, X_PISCES),
    ("skybase", "init_pisces"):     (M_MC, 0, MC | B_RAM2K | B_BANK2, 0x60, X_PISCES),
    ("kong", "init_kong"):          (M_MC, 0, MC | B_RAM2K, 0x80, X_UPPER),
    ("scorpnmc", "init_batman2"):   (M_SCORP, 0, B_MCSND, 0, X_BATMAN2),
    ("ckongmc", "init_ckongs"):     (M_CKONG, V_SCRAMBLE_SHELLS, B_MCSND | B_NOSTARS, 0x60, X_MSHUTTLE),
    # AY-3-8910 boards
    ("jumpbug", "init_jumpbug"):    (M_JUMPBUG, V_SCRAMBLE_SHELLS, 0, 0, X_JUMPBUG, B2_NOWDOG | B2_NODISC | B2_STARS232),
    ("bongo", "init_kong"):         (M_MC, 0, 0, 0x60, X_UPPER, B2_NODISC | B2_AYIO),         # NMI enable at B001
    ("bongog", "init_kong"):        (M_MC, 0, B_MCSND, 0x60, X_UPPER, B2_IN2DSW | B2_PDIV8),
    # Check Man sound board (Z80 + AY)
    ("checkman", "init_checkman"):  (M_MC, 0, B_MCSND, 0, X_MC, 0, S_BOARD | S_CMD_OUT | S_DECRYPT),   # NMI enable B001
    ("checkmaj", "init_checkmaj"):  (M_GAL, 0, 0, 0, 0, B2_NODISC, S_BOARD | S_JAPAN | S_PROT_CM),
    ("checkmaj", "init_dingo"):     (M_GAL, 0, 0, 0, 0, B2_NODISC, S_BOARD | S_JAPAN | S_PROT_DINGO),
    # second sprite generator
    ("zigzag", "init_zigzag"):      (M_GAL, 0, B_RAM2K, 0, X_SPRITE_ROM, B2_NODISC, 0, V2_SPR2 | V2_NOSHELLS,
                                     B4_ROMSWAP | B4_ZZAY | B4_AY3M),
    ("fantastc", "init_fantastc"):  (M_MC, 0, B_NMI0 | B_RAM2K, 0x80, X_UPPER, B2_NODISC, 0, V2_SPR2 | V2_SHELLS_C0,
                                     B4_OBJ1K | B4_UNSCRAMBLE | B4_AY2 | B4_AY3M),
    ("timefgtr", "init_timefgtr"):  (M_MC, 0, B_NMI0 | B_RAM2K, 0x80, X_UPPER, B2_NODISC, 0,
                                     V2_SPR2 | V2_SHELLS_C0 | V2_PAGE, B4_OBJ1K | B4_AY2 | B4_AY3M),
    # Konami sound board
    ("frogger", "init_frogger"):    (M_FROGGER, 0, 0, 0, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_FROGGER,
                                     B5_KONAMI | B5_SND_SWAP01),
}

F_4WAY, F_IMPULSE, F_VERT, F_ROT90 = 0x01, 0x04, 0x10, 0x80

# port order on the board: DIP bytes 0-3 and input map bytes 16-47
PORTS = [("IN0",), ("IN1",), ("IN2",), ("IN3", "FAKE", "DSW")]   # first name present wins
LINE_BASE = 40      # control ids 40-47 = DIP byte 3 bits: a port bit that reads a line of the FAKE port

# control ids (Arcade-Galaxian.sv)
CTL = {("JOYSTICK_UP", 1): 1, ("JOYSTICK_DOWN", 1): 2, ("JOYSTICK_LEFT", 1): 3, ("JOYSTICK_RIGHT", 1): 4,
       ("BUTTON1", 1): 5, ("BUTTON2", 1): 6, ("BUTTON3", 1): 7, ("BUTTON4", 1): 8,
       ("JOYSTICK_UP", 2): 9, ("JOYSTICK_DOWN", 2): 10, ("JOYSTICK_LEFT", 2): 11, ("JOYSTICK_RIGHT", 2): 12,
       ("BUTTON1", 2): 13, ("BUTTON2", 2): 14, ("BUTTON3", 2): 15, ("BUTTON4", 2): 16,
       ("BUTTON5", 1): 32, ("BUTTON6", 1): 33, ("BUTTON5", 2): 34, ("BUTTON6", 2): 35,
       ("COIN1", 0): 17, ("COIN2", 0): 18, ("START1", 0): 19, ("START2", 0): 20,
       ("TILT", 0): 21, ("BILL1", 0): 18, ("SERVICE1", 0): 22, ("SERVICE2", 0): 22, ("SERVICE", 0): 22, ("COIN3", 0): 23}
TRACKBALL = {}
IGNORED_TYPES = {"UNUSED", "UNKNOWN"}

SERIES_BY_PARENT = {}
REGION_WORDS = [("US", "US"), ("Japan", "Japan"), ("Spanish", "Spain"), ("Italian", "Italy"), ("French", "France"),
                ("Brazil", "Brazil"), ("Argentina", "Argentina"), ("Greek", "Greece"), ("Hungarian", "Hungary")]

# ---------------------------------------------------------------- parsing

GAME_RE = re.compile(r'^GAME\(\s*([\w?]+),\s*(\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*(ROT\d+),\s*"([^"]*)",\s*"([^"]*)",\s*([^)]*)\)', re.M)
LOAD_RE = re.compile(r'ROM_LOAD\(\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(?:BAD_DUMP\s+)?CRC\(([0-9a-fA-F]+)\)')
CONT_RE = re.compile(r'ROM_CONTINUE\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
NIB_RE = re.compile(r'ROM_LOAD_NIB_(LOW|HIGH)\s*\(\s*"([^"]+)",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*CRC\(([0-9a-fA-F]+)\)')
RELOAD_RE = re.compile(r'ROM_RELOAD\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
FILL_RE = re.compile(r'ROM_FILL\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
COPY_RE = re.compile(r'ROM_COPY\(\s*"([^"]+)",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
REGION_RE = re.compile(r'ROM_REGION\(\s*(0x[0-9a-fA-F]+),\s*"([^"]+)"')
MACRO_RE = re.compile(r'\b(PORT_\w+|INPUT_PORTS_\w+)\b(\s*\(((?:[^()"]|"[^"]*"|\([^()]*\))*)\))?')


def parse_games(src):
    games = {}
    for m in GAME_RE.finditer(src):
        year, name, parent, machine, inputs, init, rot, manuf, desc, flags = m.groups()
        games[name] = dict(year=year, name=name, parent=None if parent == "0" else parent,
                           machine=machine, inputs=inputs, init=init, rot=rot, manuf=manuf, desc=desc,
                           working="MACHINE_NOT_WORKING" not in flags)
    return games


def parse_roms(src, setname):
    m = re.search(r'ROM_START\(\s*%s\s*\)(.*?)ROM_END' % re.escape(setname), src, re.S)
    if not m:
        raise SystemExit(f"ROM_START({setname}) not found")
    segs, region, rsize, last = [], None, 0, None
    for line in m.group(1).splitlines():
        line = line.split("//")[0]
        if "NO_DUMP" in line:
            continue                                   # never dumped; MAME runs without it
        if (r := REGION_RE.search(line)):
            region, rsize, last = r.group(2), int(r.group(1), 16), None
        elif (l := LOAD_RE.search(line)):
            name, off, length, crc = l.group(1), int(l.group(2), 16), int(l.group(3), 16), l.group(4).lower()
            last = dict(name=name, crc=crc, src=0, dst=off, len=length, flen=length, region=region, rsize=rsize)
            segs.append(last)
        elif (c := CONT_RE.search(line)):
            off, length = int(c.group(1), 16), int(c.group(2), 16)
            nxt = dict(last, src=last["src"] + last["len"], dst=off, len=length)
            segs.append(nxt)
            last = nxt
        elif (n := NIB_RE.search(line)):
            # ROM_LOAD_NIB_LOW / _HIGH: two 4-bit PROMs sharing one byte; each gets its own slot, merged in the core
            half, name, off, length, crc = n.group(1), n.group(2), int(n.group(3), 16), int(n.group(4), 16), n.group(5).lower()
            last = dict(name=name, crc=crc, src=0, dst=off, len=length, flen=length,
                        region=f"{region}_n{'lo' if half == 'LOW' else 'hi'}", rsize=length)
            segs.append(last)
        elif (r := RELOAD_RE.search(line)):
            # ROM_RELOAD: the previous file loaded again at another offset
            base = next(s for s in reversed(segs) if s["name"] == last["name"] and s["src"] == 0)
            last = dict(base, dst=int(r.group(1), 16), len=int(r.group(2), 16))
            segs.append(last)
        elif (f := FILL_RE.search(line)):
            off, length, val = int(f.group(1), 16), int(f.group(2), 16), int(f.group(3), 16)
            segs.append(dict(name=None, crc=None, fill=val, src=0, dst=off, len=length, region=region, rsize=rsize))
            last = None
        elif (c := COPY_RE.search(line)):
            # ROM_COPY re-reads bytes already loaded into a region: slice the file loads that cover the source range
            sreg, sofs, dofs, length = c.group(1), int(c.group(2), 16), int(c.group(3), 16), int(c.group(4), 16)
            covered = 0
            for s in [s for s in segs if s["region"] == sreg]:
                lo, hi = max(s["dst"], sofs), min(s["dst"] + s["len"], sofs + length)
                if lo < hi:
                    segs.append(dict(s, src=s["src"] + lo - s["dst"], dst=dofs + lo - sofs, len=hi - lo,
                                     region=region, rsize=rsize))
                    covered += hi - lo
            if covered != length:
                raise SystemExit(f"{setname}: ROM_COPY source not fully loaded: {line.strip()}")
            last = None
        elif "ROM_" in line and any(k in line for k in ("ROM_LOAD", "ROM_COPY", "ROM_FILL", "ROM_RELOAD")):
            raise SystemExit(f"{setname}: unhandled ROM statement: {line.strip()}")
    return segs


def def_str(s):
    s = s.strip()
    m = re.fullmatch(r'DEF_STR\(\s*(\w+)\s*\)', s)
    if not m:
        return s.strip('"')
    w = m.group(1)
    c = re.fullmatch(r'(\d+)C_(\d+)C', w)
    if c:
        return f"{c.group(1)}C/{c.group(2)}C"
    return w.replace("_", " ")


def idle_level(arg, mask):
    """Released level from an IP_ACTIVE_LOW / IP_ACTIVE_HIGH keyword or a numeric default."""
    if arg == "IP_ACTIVE_LOW":
        return mask
    if arg == "IP_ACTIVE_HIGH":
        return 0
    return int(arg, 0) & mask


def split_args(a):
    out, depth, cur, q = [], 0, "", False
    for ch in a:
        if ch == '"':
            q = not q
        if not q and ch == "(":
            depth += 1
        elif not q and ch == ")":
            depth -= 1
        if ch == "," and depth == 0 and not q:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def parse_inputs(src):
    """INPUT_PORTS name -> {tag: [field]}; field = dict(mask, kind, default, type, player, name, settings, fourway)."""
    blocks = {m.group(1): m.group(2) for m in re.finditer(
        r'INPUT_PORTS_START\(\s*(\w+)\s*\)(.*?)INPUT_PORTS_END', src, re.S)}
    cache = {}

    def build(name):
        if name in cache:
            return copy.deepcopy(cache[name])
        ports, cur, fld = {}, None, None
        body = "\n".join(l.split("//")[0] for l in blocks[name].splitlines())
        for m in MACRO_RE.finditer(body):
            mac, args = m.group(1), split_args(m.group(3) or "")
            if mac == "PORT_INCLUDE":
                ports.update(build(args[0]))
            elif mac in ("PORT_START", "PORT_MODIFY"):
                cur = args[0].strip('"')
                if mac == "PORT_START":
                    ports[cur] = []
                fld = None
            elif mac in ("PORT_BIT", "PORT_DIPNAME", "PORT_CONFNAME", "PORT_SERVICE", "PORT_SERVICE_NO_TOGGLE",
                         "PORT_DIPUNUSED", "PORT_DIPUNUSED_DIPLOC", "PORT_DIPUNKNOWN", "PORT_DIPUNKNOWN_DIPLOC"):
                mask = int(args[0], 0)
                ports[cur] = [f for f in ports[cur] if not (f["mask"] & mask)]
                if mac == "PORT_BIT":
                    low = args[1] == "IP_ACTIVE_LOW"
                    t = args[2].replace("IPT_", "")
                    if t in TRACKBALL:
                        low = False
                    fld = dict(mask=mask, kind="unused" if t in IGNORED_TYPES else "input",
                               default=mask if low else 0, type=t, player=1, name=None, settings=[], fourway=False)
                elif mac in ("PORT_DIPNAME", "PORT_CONFNAME"):
                    fld = dict(mask=mask, kind="dip", default=int(args[1], 0), name=def_str(args[2]), settings=[])
                elif mac == "PORT_SERVICE":
                    off = idle_level(args[1], mask)
                    on = off ^ mask
                    fld = dict(mask=mask, kind="dip", default=off, name="Service Mode", settings=[(off, "Off"), (on, "On")])
                elif mac == "PORT_SERVICE_NO_TOGGLE":
                    fld = dict(mask=mask, kind="input", default=idle_level(args[1], mask), type="SERVICE", player=0,
                               name=None, settings=[], fourway=False)
                else:
                    d = {"IP_ACTIVE_LOW": mask, "IP_ACTIVE_HIGH": 0}.get(args[1])
                    fld = dict(mask=mask, kind="unused", default=int(args[1], 0) if d is None else d)
                ports[cur].append(fld)
            elif mac in ("PORT_DIPSETTING", "PORT_CONFSETTING"):
                fld["settings"].append((int(args[0], 0), def_str(args[1])))
            elif mac == "PORT_PLAYER":
                fld["player"] = int(args[0])
            elif mac == "PORT_COCKTAIL":
                fld["player"] = 2
            elif mac == "PORT_4WAY":
                fld["fourway"] = True
            elif mac == "PORT_2WAY":
                fld["twoway"] = True
            elif mac == "PORT_REVERSE":
                fld["reverse"] = True
            elif mac == "PORT_NAME":
                fld["name"] = args[0].strip('"')
            elif mac == "PORT_READ_LINE_MEMBER":
                lm = re.fullmatch(r'FUNC\(\w+::azurian_port_r<(\d)>\)', args[0])
                if not lm:
                    raise SystemExit(f"INPUT_PORTS({name}): unhandled read line {args[0]}")
                fld["line"] = int(lm.group(1))
            elif mac == "PORT_IMPULSE":
                fld["impulse"] = True
            elif mac in ("PORT_DIPLOCATION", "PORT_CODE", "PORT_TOGGLE", "PORT_8WAY", "PORT_CONDITION",
                         "PORT_SENSITIVITY", "PORT_KEYDELTA", "PORT_CUSTOM_MEMBER"):
                pass
            else:
                raise SystemExit(f"INPUT_PORTS({name}): unhandled {mac}")
        cache[name] = ports
        return copy.deepcopy(ports)

    return build


def split_planes(segs):
    """gfx1 / gfx2 = two bitplanes, RGN_FRAC(0,2) and RGN_FRAC(1,2): each half goes to its own plane store."""
    out = []
    for s in segs:
        if s["region"] not in ("gfx1", "gfx2"):
            out.append(s)
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


def place(segs, setname):
    out = []
    for s in split_planes(segs):
        if s["region"] in IGNORED_REGIONS:
            continue
        if s["region"] not in REGIONS:
            raise SystemExit(f"{setname}: unmapped region {s['region']}")
        base, size = REGIONS[s["region"]]
        if s["dst"] >= size:
            continue                                   # e.g. the namco timing PROM
        if s["dst"] + s["len"] > size:
            raise SystemExit(f"{setname}: {s['name']} overruns {s['region']}")
        a, e = base + s["dst"], base + s["dst"] + s["len"]
        kept = []
        for o in out:                                  # later loads, copies and fills overwrite earlier bytes
            oe = o["addr"] + o["len"]
            if oe <= a or o["addr"] >= e:
                kept.append(o)
                continue
            if o["addr"] < a:
                kept.append(dict(o, len=a - o["addr"]))
            if oe > e:
                kept.append(dict(o, addr=e, src=o["src"] + e - o["addr"], len=oe - e))
        out = kept + [dict(s, addr=a)]
    out.sort(key=lambda s: s["addr"])
    for a, b in zip(out, out[1:]):
        assert a["addr"] + a["len"] <= b["addr"], f"{setname}: overlap {a['name']} / {b['name']}"
    return out


def whole_file(seg, segs):
    """True when this segment is the file's only load (no ROM_CONTINUE pieces)."""
    return (sum(1 for s in segs if s["name"] == seg["name"] and s["crc"] == seg["crc"]) == 1 and seg["src"] == 0
            and seg["len"] == seg["flen"])

# ---------------------------------------------------------------- inputs -> MRA

def input_config(g, ports):
    """-> (idle bytes, dip list, input map, 4-way, P1 button names, trackball reverse flags, coin impulse)."""
    idle, dips, imap, fourway, buttons, tb_rev, impulse = [], [], [0] * 32, False, {}, 0, False
    global twoway
    twoway = True
    for p, names in enumerate(PORTS):
        tag = next((n for n in names if n in ports), names[0])
        fields = ports.get(tag)
        if fields is None:
            idle.append(0xFF)
            continue
        level = 0xFF
        for f in fields:
            level = (level & ~f["mask"]) | (f["default"] & f["mask"])
            if f["kind"] == "dip":
                lo = (f["mask"] & -f["mask"]).bit_length() - 1
                hi = f["mask"].bit_length() - 1
                if f["mask"] != ((1 << (hi + 1)) - (1 << lo)):
                    raise SystemExit(f'{g["name"]}: non-contiguous DIP {f["name"]} mask {f["mask"]:#x}')
                vals = [v >> lo for v, _ in f["settings"]]
                ids = ",".join(n.replace(",", ";") for _, n in f["settings"])
                bits = f"{p * 8 + lo}" if lo == hi else f"{p * 8 + lo},{p * 8 + hi}"
                seq = vals == list(range(len(vals))) and len(vals) == 1 << (hi - lo + 1)
                dips.append((f["name"], bits, ids, None if seq else ",".join(str(v) for v in vals)))
            elif f["kind"] == "input":
                t, pl = f["type"], f["player"]
                if t == "CUSTOM" and "line" in f:
                    imap[p * 8 + f["mask"].bit_length() - 1] = LINE_BASE + f["line"]
                    level &= ~f["mask"]
                    continue
                if t == "CUSTOM":
                    continue                           # no handler: a fixed level, already in the idle byte
                if t in TRACKBALL:
                    if f["mask"] != 0x0F:
                        raise SystemExit(f'{g["name"]}: trackball mask {f["mask"]:#x} in {tag}')
                    for b in range(4):
                        imap[p * 8 + b] = TRACKBALL[t] + b
                    tb_rev |= (1 if t == "TRACKBALL_X" else 2) if f.get("reverse") else 0
                    continue
                key = (t, pl if t.startswith(("JOYSTICK", "BUTTON")) else 0)
                if key not in CTL:
                    raise SystemExit(f'{g["name"]}: unmapped input {t} player {pl} in {tag}')
                if f["mask"] & (f["mask"] - 1):
                    raise SystemExit(f'{g["name"]}: multi-bit input {t} in {tag}')
                imap[p * 8 + f["mask"].bit_length() - 1] = CTL[key]
                impulse |= t.startswith("COIN") and f.get("impulse", False)
                fourway |= f["fourway"]
                if t.startswith("JOYSTICK") and pl == 1:
                    twoway = twoway and f.get("twoway", False)
                if t.startswith("BUTTON") and pl == 1:
                    buttons[int(t[6:])] = f["name"] or ("Fire" if t == "BUTTON1" else f"Button {t[6:]}")
        idle.append(level & 0xFF)
    return idle, dips, imap, fourway, buttons, tb_rev, impulse


def parse_hiscores(path):
    """hiscore.dat -> {set: [entry lines]}; sets listed together share the entry lines below them."""
    out, names, body = {}, [], False
    for line in path.read_text(encoding="latin-1").splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            names, body = ([], False) if not line else (names, body)
            continue
        if line.endswith(":"):
            if body:
                names, body = [], False
            names.append(line[:-1])
        elif line.startswith("@"):
            for n in names:
                out.setdefault(n, []).append(line)
            body = True
    return out


HISCORES = parse_hiscores(HISCORE_DAT) if HISCORE_DAT.exists() else {}


def hiscore_xml(g):
    lines = HISCORES.get(g["name"])
    pending = {tuple(HISCORES[n]) for n in HISCORE_PENDING if n in HISCORES}
    if not lines or g["name"] in HISCORE_SKIP or tuple(lines) in pending:
        return ""
    ents = []
    for line in lines:
        f = line.split(",")
        if f[0] != "@:maincpu" or f[1] != "program":
            raise SystemExit(f'{g["name"]}: unsupported hiscore.dat line {line}')
        ents.append((int(f[2], 16), int(f[3], 16), int(f[4], 16), int(f[5], 16)))
    rows = "\n".join(f"            {a >> 24 & 0xFF:02X} {a >> 16 & 0xFF:02X} {a >> 8 & 0xFF:02X} {a & 0xFF:02X} "
                      f"{n >> 8:02X} {n & 0xFF:02X} {s:02X} {e:02X}" for a, n, s, e in ents)
    total = sum(n for _, n, _, _ in ents)
    ref = next((k for k in HISCORE_INIT_FRAME if HISCORES.get(k) == lines), None)
    if ref is None:
        raise SystemExit(f'{g["name"]}: no measured table-init frame for this hiscore layout')
    wait = round((HISCORE_INIT_FRAME[ref] + 2) / FRAME_HZ * CLK_HZ)
    header = " ".join(f"{b:02X}" for b in wait.to_bytes(4, "big")) + " " + HISCORE_HEADER_TAIL
    return f"""
    <!-- Index 3: hiscore config (MAME hiscore.dat), index 4: saved scores -->
    <rom index="3" md5="none">
        <part>
            {header}
{rows}
        </part>
    </rom>
    <rom index="4"></rom>
    <nvram index="4" size="{total}"></nvram>
"""


def mra(g, games, segs, build_inputs):
    variant, vflags, bflags, rom_top, ext, *rest = SUPPORTED[(g["machine"], g["init"])]
    bflags2 = rest[0] if rest else 0
    bflags3, vflags2, bflags4, vflags3, bflags5 = (list(rest[1:]) + [0] * 5)[:5]
    idle, dips, imap, fourway, buttons, tb_rev, impulse = input_config(g, build_inputs(g["inputs"]))
    flags = (F_4WAY if fourway else 0) | (F_IMPULSE if impulse else 0) | \
            (F_VERT if g["rot"] in ("ROT90", "ROT270") else 0) | \
            (F_ROT90 if g["rot"] == "ROT90" else 0)
    nbtn = max(buttons) if buttons else 0
    names = ",".join([buttons.get(i, "Not Used") for i in range(1, 5)] + ["Coin", "Start 1P", "Start 2P", "Pause"] +
                     [buttons.get(i, "Not Used") for i in (5, 6)])
    parent = g["parent"] or g["name"]
    zipname = f'{g["name"]}.zip' + (f'|{g["parent"]}.zip' if g["parent"] else "") + \
              (f'|{PROM_STANDIN[g["name"]][0]}' if g["name"] in PROM_STANDIN else "")
    rotation = {"ROT0": "horizontal", "ROT270": "vertical (ccw)", "ROT90": "vertical (cw)"}[g["rot"]]
    bootleg = "yes" if "bootleg" in g["manuf"].lower() or "hack" in g["desc"].lower() else "no"
    top = games.get(parent, g)                         # parent may live in another driver (suprglob: epos)
    series, category = SERIES_BY_PARENT.get(parent, (title_case(clean_title(top["desc"])), "Shooter"))
    region = next((r for w, r in REGION_WORDS if w in g["desc"]), "World")

    lines = []
    pos = 0
    for s in segs:
        if s["addr"] > pos:
            lines.append(f'        <part repeat="0x{s["addr"] - pos:X}">00</part>')
        if s.get("fill") is not None:
            lines.append(f'        <part repeat="0x{s["len"]:X}">{s["fill"]:02X}</part>')
        elif whole_file(s, segs):
            lines.append(f'        <part crc="{s["crc"]}" name="{s["name"]}"/>')
        else:
            lines.append(f'        <part crc="{s["crc"]}" name="{s["name"]}" offset="0x{s["src"]:X}" length="0x{s["len"]:X}"/>')
        pos = s["addr"] + s["len"]

    dip_lines = "\n".join(f'        <dip name="{n}" bits="{b}" ids="{i}"' + (f' values="{v}"' if v else "") + "/>"
                          for n, b, i, v in dips)
    cfg = [variant, flags, vflags, bflags, rom_top, ext, bflags2, bflags3, vflags2, bflags4, vflags3, bflags5] + \
          [0] * 4 + imap
    cfg_rows = "\n".join("            " + " ".join(f"{b:02X}" for b in cfg[i:i + 16]) for i in range(0, len(cfg), 16))
    return f"""<misterromdescription>
    <name>{display_name(g)}</name>
    <region>{region}</region>
    <homebrew>no</homebrew>
    <bootleg>{bootleg}</bootleg>
    <version></version>
    <alternative></alternative>
    <platform></platform>
    <series>{series}</series>
    <year>{g["year"]}</year>
    <manufacturer>{g["manuf"]}</manufacturer>
    <category>{category}</category>

    <setname>{g["name"]}</setname>
    <parent>{parent}</parent>
    <mameversion>{MAME_VERSION}</mameversion>
    <rbf>{RBF}</rbf>
    <about></about>

    <resolution>15kHz</resolution>
    <rotation>{rotation}</rotation>
    <flip>yes</flip>

    <players>2 (alternating)</players>
    <joystick>{"2-way horizontal" if twoway else "4-way" if fourway else "8-way"}</joystick>
    <special_controls></special_controls>
    <num_buttons>{nbtn}</num_buttons>
    <buttons names="{names}" default="A,Y,B,X,Select,Start,R,L"/>

    <switches default="{",".join(f"{b:02X}" for b in idle)}">
{dip_lines}
    </switches>

    <!-- Index 0: CPU 0x00000, gfx planes 0x10000 / 0x12000 (sprite ROM in the upper halves), colour PROM 0x14000, sound CPU 0x18000 -->
    <rom index="0" md5="none" zip="{zipname}">
{chr(10).join(lines)}
    </rom>

    <!-- Index 1: memory map, flags, video flags, board flags, ROM top, code extension, board flags 2 and 3, video flags 2, board flags 4, input map (see Arcade-Galaxian.sv) -->
    <rom index="1">
        <part>
{cfg_rows}
        </part>
    </rom>
{hiscore_xml(g)}
    <remark>{remark(g)}</remark>
    <mratimestamp>20260928000000</mratimestamp>
</misterromdescription>
"""


def title_case(text):
    """Capitalise every word, small words included; acronyms (US, II, PCB) stay as written."""
    out = []
    for word in re.split(r"(\s+|[()/,-])", text):
        if word and word[0].isalpha():
            word = word[0].upper() + word[1:]
        out.append(word)
    return "".join(out)


def clean_title(desc):
    """Parent title: the description without its trailing parenthesised qualifiers."""
    return re.sub(r"(\s*\([^()]*\))+$", "", desc).strip()


def display_name(g):
    return title_case(clean_title(g["desc"]) if g["parent"] is None else g["desc"])


def remark(g):
    """'Title (Maker)', without repeating a maker the title already names."""
    m = re.fullmatch(r'bootleg \((.+)\)', g["manuf"])
    maker = f"{m.group(1)} bootleg" if m else g["manuf"]
    desc = title_case(g["desc"])
    return desc if maker.lower() in g["desc"].lower() else f"{desc} ({title_case(maker)})"


def safe(name):
    return re.sub(r'\s*/\s*', " - ", re.sub(r'[\\:*?"<>|]', "-", name))


MAME_SRC = Path("/Work/Build/mame/src/mame")
_foreign = {}


def foreign_parent(name):
    """A parent set that lives in another MAME driver (dockman, thepit, ckong, scorpion)."""
    if name not in _foreign:
        _foreign[name] = None
        for f in MAME_SRC.rglob("*.cpp"):
            text = f.read_text(errors="ignore")
            if name in text and (m := parse_games(text).get(name)):
                _foreign[name] = m
                break
    return _foreign[name]


def out_path(root, g, games):
    if g["parent"] is None:
        return root / f"{safe(display_name(g))}.mra"
    top = games.get(g["parent"]) or foreign_parent(g["parent"])
    parent_title = display_name(top) if top else title_case(clean_title(g["desc"]))
    return root / "_alternatives" / f"_{safe(parent_title)}" / f"{safe(display_name(g))}.mra"


def main():
    src = "\n".join(Path(f).read_text() for f in sys.argv[1].split(","))
    out_dir = Path(sys.argv[2])
    games = parse_games(src)
    build_inputs = parse_inputs(src)
    names = sys.argv[3:] or [n for n, g in games.items() if (g["machine"], g["init"]) in SUPPORTED and g["working"]]
    for name in names:
        g = games[name]
        if (g["machine"], g["init"]) not in SUPPORTED:
            raise SystemExit(f'{name}: board {g["machine"]} / {g["init"]} not implemented')
        raw = parse_roms(src, name)
        if name in PROM_STANDIN:
            _, fn, crc = PROM_STANDIN[name]
            raw.append(dict(name=fn, crc=crc, src=0, dst=0, len=0x20, flen=0x20, region="proms", rsize=0x20))
        segs = place(raw, name)
        path = out_path(out_dir, g, games)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(mra(g, games, segs, build_inputs))
        print(f'{name:12s} {path.relative_to(out_dir)}')


if __name__ == "__main__":
    main()
