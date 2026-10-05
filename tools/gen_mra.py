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
                      "dingo": 13, "zigzagb": 17, "fantastc": 1, "timefgtr": 2, "frogger": 1, "moonaln": 131,
                      "amidars": 162, "theend": 4, "theendss": 0, "atlantis": 0, "scobra": 162, "suprheli": 162,
                      "armorcar": 50, "tazmania": 47, "spdcoin": 38,
                      "turtles": 3, "amidar": 162, "frogg": 1, "froggers": 1, "froggrs": 1, "frogf": 1, "quaak": 1,
                      "froggeram": 1, "froggert": 1, "turpins": 3,
                      # core-measured 2026-09-30 (hsmeasure, 400 frames): last boot-time table change; live counters
                      # (hustler 8003, pacmanblv 426C, ghostmun/komemokos/pacmanblci 60-frame timer) excluded; scramb2/3 =
                      # end of the boot RAM test
                      "batman2": 2, "bigkonggx": 310, "billiard": 1, "calipso": 45, "cavelon": 54, "devilfsh":
                      0, "froggerv": 1, "froggervd": 1, "ghostmun": 2, "hotshock": 3, "hustler": 1,
                      "hustlerb": 1, "hustlerd": 1, "komemokos": 2, "ladybugg": 2, "losttomb": 49, "mariner":
                      6, "mars": 20, "mimonkey": 66, "mimonscr": 63, "minefld": 43, "mrkougar": 25, "newsin7":
                      2, "pacmanbl": 6, "pacmanbla": 6, "pacmanblb": 1, "pacmanblc": 2, "pacmanblci": 2,
                      "pacmanblv": 2, "phoenxp2": 2, "pisces": 0, "rescue": 43, "scramb2": 248, "scramb3":
                      248, "scramblb": 161, "scrambleo": 172, "scrambler": 162, "stratgyx": 161, "streakng":
                      2, "superbon": 1, "tazmani2": 47, "tazmani3": 47, "tazmaniet": 47, "tazzmang": 32,
                      "tazzmang2": 32, "triplep": 99}
# colour PROMs never dumped: stand-in from a related set, (zip, file, crc). Kong (Taito do Brasil) takes Crazy Kong's
# first palette PROM (user, 2026-09-29) - same byte layout; which colour group goes where is a guess
PROM_STANDIN = {"kong": ("ckong.zip", "ck6v.bin", "751c3325"),
                # Time Fighter (Taito do Brasil): Fantastic's PROM, same conversion board - a guess
                "timefgtr": ("fantastc.zip", "prom-74g138", "800f5718")}
# hiscore.dat entries that can't work here: atlantisb's range is live game state, omegab's C060 is unmapped
HISCORE_SKIP = {"atlantisb", "omegab"}
# sets waiting for a core measurement: no hiscore entry until then (safe: the top gates an unconfigured hiscore)
HISCORE_PENDING = {"hunchbkg", "hunchbgb"}                  # no ROMs to measure with yet
CLK_HZ, FRAME_HZ = 49_152_000, 60.61

# region -> (base in ioctl index 0, size taken); "gfx1" is split by plane into gfx1_p0 / gfx1_p1
REGIONS = {
    "maincpu": (0x00000, 0x10000),
    "gfx1_p0": (0x10000, 0x02000),
    "gfx1_p1": (0x12000, 0x02000),
    "proms":   (0x14000, 0x00040),         # 64 bytes on Driving Force
    "audiocpu": (0x18000, 0x04000),
    "user1":   (0x14100, 0x00040),         # background PROM (Strategy X; Mariner uses the first 0x40 of 0x100)
    "user2":   (0x14140, 0x00020),
    "gfx1_p2": (0x16000, 0x01000),         # third bitplane (V4_BPP3)         # Mariner char bank / star column PROM
    "gfx2_p0": (0x11000, 0x01000),         # separate sprite ROM: upper half of each plane (code extension 8)
    "gfx2_p1": (0x13000, 0x01000),
    "cclimber_audio:samples": (0x1C000, 0x02000),                 # Moon Shuttle sample ROM
    "digitalker": (0x20000, 0x03000),                             # Scorpion speech ROM (Digitalker)
    "gfx1_p0h": (0x24000, 0x02000),                               # upper 8K of 16K planes (Rack + Roll)
    "gfx1_p1h": (0x26000, 0x02000),
    "i8039": (0x1E000, 0x00800),                                  # Space Battle speech CPU
    "sbhoei_sound_rom": (0x1F000, 0x01000),                       # Space Battle speech data
}

TRUNCATE = {"user1"}                    # PROMs whose tail the hardware never addresses
IGNORED_REGIONS = {"plds", "pld", "unknown", "unk", "unused_proms",   # dumps MAME does not use
                   "tempgfx",                                  # ROM_COPY source only
                   "other_proms",                              # decoding PROMs (Superbike)
                   "proms2", "extra_prom", "epoxy_block_prom"} # unknown PROMs (ckongcv / ckongis, guttangts3, bmxstunts)

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
V3_SCR_BG, V3_SCR_STARS, V3_THEEND_SHELLS = 0x10, 0x20, 0x40
B5_KONAMI, B5_TWO_AY, B5_SND_SWAP01, B5_PROT, B5_WD7800 = 0x01, 0x02, 0x04, 0x08, 0x10
B5_FR_TIMER, B5_TIMER9000, B5_TURPINNV = 0x20, 0x40, 0x80
M_FROGF, M_FROGGERAM, M_TURPINS = 9, 10, 11
V3_FROG_COL = 0x06                                              # Frogger colour rotate + blue river, no nibble swap
M_STERN2 = 12
# video flags 4 (12th field), board flags 6 (13th field): Stern boards (scobra.cpp)
V4_RESCUE_BG, V4_MINEFLD_BG, V4_STARS_LEFT, V4_STRAT_BG, V4_GFX_RESCUE, V4_GFX_MINEFLD = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
B6_TAZ3, B6_RESCUEB, B6_TAZET, B6_STRAT_RGB, B6_TAZ2_BG, B6_HUSTLER, B6_BILLIARD = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40
# board flags 7 (14th field)
B7_NO_FILTER, B7_HB_SOUND, B7_ROM12K, B7_MARINER, B7_NEWSIN7, B7_FLIPSWAP = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
B6_SCRAMBLER = 0x80
B7_S2650, B7_SBK_LATCH = 0x40, 0x80                             # S2650 plug-in board (hunchbkg), Superbike latch
M_GS, M_SB2, M_TZB = 18, 19, 20                                 # galaxold.cpp bootleg maps
# board flags 9 / video flags 5 (config bytes 48 / 49, after the input map)
B9_SCOBRAE, B9_SUPERBON, B9_ROMC000, B9_DFSHG, B9_INT, B9_REV256 = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
V5_LOSTTOMB, V5_ANTEATER, V5_ANT_BG, V5_CALIPSO = 0x01, 0x02, 0x04, 0x08
SCOB = (7, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0)                  # M_SCOBRA (scobra_map) + sound board
V4_MARINER, V4_BPP3 = 0x40, 0x80
# 3-bitplane gfx1 (MAME newsin7 layouts): plane offsets MSB 0x2000, 0x0000, LSB 0x1000 -> stores p0 / p1 / p2
BPP3_PLANES = ((0x2000, "gfx1_p0"), (0x0000, "gfx1_p1"), (0x1000, "gfx1_p2"))
M_HUSTLERB, M_HUSTLERB6 = 13, 14
HUS = B5_KONAMI | B5_SND_SWAP01                                 # Frogger-style 1-AY sound board, D0/D1-swapped ROM
M_SCRAMBLE, M_SCOBRA, M_TURTLES = 6, 7, 8
V3_TURTLES_BG = 0x80
SCR = (V3_SCR_BG | V3_SCR_STARS, B5_KONAMI | B5_TWO_AY)                  # Scramble background + 2-AY sound board
# board flags 8 (15th field): scramble.cpp boards
M_MARS, M_HOTSHOCK, M_TRIPLEP = 15, 16, 17
V_PACKED = 0x04                                                 # Mr. Kougar packed gfx (ROM loaded into both planes)
B8_ADDRSWAP, B8_KOUGAR_NMI, B8_PC00, B8_NOMUTE, B8_HSPATCH, B8_CAVELON, B8_AYIO01, B8_TPPROT = \
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80
KOUGAR = B8_KOUGAR_NMI | B8_PC00 | B8_NOMUTE                    # mrkougar_map + mrkougar_sh_irqtrigger_w
SCRS = (V3_SCR_STARS, B5_KONAMI | B5_TWO_AY)                    # scrambold video (no background latch) + 2-AY board
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
    ("pisces", "init_pisces"):      (M_GAL, 0, B_BANK2, 0, X_PISCES),
    ("pisces", "init_batman2"):     (M_GAL, 0, B_BANK2, 0, X_BATMAN2),
    ("pacmanbl", "init_pacmanbl"):  (M_GAL, 0, 0, 0, X_SPRITE_ROM),   # coin lockout replaced by a no-op latch
    ("pacmanbl", "init_galaxian"):  (M_GAL, 0, 0, 0, X_SPRITE_ROM),
    ("pacmanbl", "init_ghostmun"):  (M_GAL, 0, 0, 0, X_SPRITE_ROM),
    ("galartic", "init_galaxian"):  (M_GAL, 0, 0, 0, 0),              # coin lockout not connected
    ("astroamb", "init_scramble"):  (18, V_SCRAMBLE_SHELLS, 0, 0, 0, 0, 0, 0, 0, V3_SCR_BG | V3_SCR_STARS),   # M_GS map
    ("mandinka", "init_scramble"):  (21, V_SCRAMBLE_SHELLS, 0, 0x40, 0, B2_NODISC, 0, 0, 0, SCR[0], SCR[1]),   # M_MANDINKA
    ("scramble", "init_mandingaeg"): (M_SCRAMBLE, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, SCR[0], SCR[1] | B5_PROT,
                                      0, 0, 0, 0, 0x40),                                     # watchdog also at 6800
    ("scramble", "init_mandinga"):  (M_SCRAMBLE, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, SCR[0], SCR[1] | B5_PROT,
                                     0, 0, 0, 0, 0x40),
    ("ckongg", "init_ckongs"):      (22, V_SCRAMBLE_SHELLS, B_NOSTARS, 0x60, X_MSHUTTLE),   # M_CKONGG; C804 stars link cut
    ("bigkonggx", "init_bigkonggx"): (22, V_SCRAMBLE_SHELLS, B_NOSTARS, 0x40, X_MSHUTTLE, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                      B9_REV256 | 0x80),                                     # + ROM D400-E3FF
    ("ckongg", "init_ckonggx"):     (22, V_SCRAMBLE_SHELLS, B_NOSTARS, 0x60, X_MSHUTTLE, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                     0, 0x10),                                               # 256-byte block remap
    ("ckongs", "init_ckongs"):      (23, V_SCRAMBLE_SHELLS, 0, 0x60, X_MSHUTTLE, B2_NODISC, 0, 0, 0, V3_SCR_STARS, SCR[1]),
    # board flags 10 (17th field): 0x01 Victory decode, 0x02 RAM 8000-87FF, 0x04 Crazy Mazey decode
    ("victoryc", "init_victoryc"):  (M_GAL, 0, B_NOSTARS, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01 | 0x02),
    ("victoryc", "init_galaxian"):  (M_GAL, 0, B_NOSTARS, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x02),
    ("galaxian", "init_crazym"):    (M_GAL, 0, 0, 0, X_UPPER, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x04),
    ("jumpbugbrf", "init_jumpbugbc"): (M_JUMPBUG, V_SCRAMBLE_SHELLS, 0, 0, X_JUMPBUG, B2_NOWDOG | B2_NODISC | B2_STARS232,
                                       0, 0, 0, 0, 0, 0, 0, 0, 0, B9_REV256),
    ("amigo2", "init_turtles"):     (24, 0, 0, 0x40, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_TURTLES_BG, B5_KONAMI | B5_TWO_AY),
    # Mighty Monkey: code extension 9 (latches 0 / 2 = gfx banks, 4 = background, ROM C000-FFFF); 0x08 = program XOR
    ("mimonkey", "init_mimonkey"):  (M_SCOBRA, V_SCRAMBLE_SHELLS, 0, 0x40, 9, B2_NODISC, 0, 0, 0, V3_SCR_BG, SCR[1],
                                     0, 0, 0, 0, 0, 0, 0x08),
    ("mimonkey", "init_mimonkeyb"): (M_SCOBRA, V_SCRAMBLE_SHELLS, 0, 0x40, 9, B2_NODISC, 0, 0, 0, V3_SCR_BG, SCR[1]),
    ("mimonscr", "init_mimonkeyb"): (M_SCRAMBLE, V_SCRAMBLE_SHELLS, 0, 0x40, 9, B2_NODISC, 0, 0, 0, V3_SCR_BG, SCR[1]),
    ("jumpbugbrf", "init_jumpbug"): (M_JUMPBUG, V_SCRAMBLE_SHELLS, 0, 0, X_JUMPBUG, B2_NOWDOG | B2_NODISC | B2_STARS232),
    ("mandingarf", "init_galaxian"):  (M_GAL, 0, B_RAM2K, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, B9_ROMC000),
    ("devilfshg", "init_devilfshg"):  (M_GAL, 0, 0, 0, X_SPRITE_ROM, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, B9_INT | B9_DFSHG),
    ("devilfshg", "init_galaxian"):   (M_GAL, 0, 0, 0, X_SPRITE_ROM, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, B9_INT),
    ("scobra", "init_scobrae"):       (*SCOB, *SCR, 0, 0, 0, 0, B9_SCOBRAE),
    ("scobra", "init_superbon"):      (*SCOB, *SCR, 0, 0, 0, 0, B9_SUPERBON),
    ("scobra", "init_losttomb"):      (*SCOB, *SCR, 0, 0, 0, 0, 0, V5_LOSTTOMB),
    ("scobra", "init_calipso"):       (*SCOB, *SCR, 0, 0, 0, 0, 0, V5_CALIPSO),
    ("anteater", "init_anteater"):    (*SCOB, V3_SCR_STARS, SCR[1], 0, 0, 0, 0, 0, V5_ANTEATER | V5_ANT_BG),
    ("anteateruk", "init_anteateruk"): (25, V_SCRAMBLE_SHELLS, 0, 0xC0, 0, B2_NODISC, 0, 0, 0, V3_SCR_STARS, SCR[1],
                                        0, 0, 0, 0, 0, V5_ANT_BG),                           # M_ANTEATERUK
    ("anteaterg", "init_anteateruk"):  (26, V_SCRAMBLE_SHELLS, 0, 0xC0, 0, B2_NODISC, 0, 0, 0, V3_SCR_STARS, SCR[1],
                                        0, 0, 0, 0, 0, V5_ANT_BG),                           # M_ANTEATERG
    ("anteatergg", "init_galaxian"):   (M_GAL, 0, B_RAM2K, 0, 0),
    # board flags 10: 0x20 Lady Bug opcodes 0000-0FFF from 4000, 0x40 Frogger (MC) sound latch / IRQ, 0x80 AY 512 kHz
    ("ladybugg2", "init_ladybugg2"):   (M_GAL, 0, B_BANK2, 0, X_BATMAN2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, B9_REV256, 0, 0x20),
    ("froggermc", "init_froggermc"):   (M_MC, 0, B_NMI0 | B_RAM2K | B_NOSTARS, 0, 0, B2_NODISC, 0, V2_NOSHELLS, 0,
                                        V3_FROG_COL, B5_KONAMI | B5_SND_SWAP01, 0, 0, 0, 0, 0, 0, 0x40),
    ("spactrai", "init_nolock"):       (27, 0, 0, 0x50, 0),                                  # M_SPACTRAI
    # board flags 11 (19th field): 0x01 ROM 2000-27FF banked by the 6000 latch
    ("guttangt", "init_guttangt"):     (M_GAL, 0, B_RAM2K | B_NOSTARS, 0, X_UPPER, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01),
    ("guttangts3", "init_guttangts3"): (M_GAL, 0, B_RAM2K | B_NOSTARS, 0, X_UPPER, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, B9_REV256, 0, 0, 0x02),
    ("bagmanmc", "init_bagmanmc"):     (M_CKONG, 0, B_MCSND, 0x60, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, B9_INT),   # bank B002
    # Moon Shuttle: code extension 11, INT, AY 512 kHz, board flags 11 0x08 (+ 0x10 Japan opcode table)
    ("mshuttle", "init_mshuttle"):     (M_MC, 0, 0, 0x80, 11, B2_NODISC, 0, 0, 0, 0, 0, 0, 0, 0, 0, B9_INT, 0x10, 0x80, 0x08),
    ("mshuttle", "init_mshuttlj"):     (M_MC, 0, 0, 0x80, 11, B2_NODISC, 0, 0, 0, 0, 0, 0, 0, 0, 0, B9_INT, 0x10, 0x80, 0x18),
    # King & Balloon: speech CPU board, stars cut (B004 unmapped), NMI enable at B001
    ("kingball", "init_galaxian"):     (M_MC, 0, B_MCSND | B_NOSTARS, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x20),
    # Scorpion: the End map + ROM 5800-67FF, parity protection, third AY (Digitalker not fitted yet)
    ("scorpion", "init_scorpion"):     (M_SCRAMBLE, V_SCRAMBLE_SHELLS, 0, 0, X_BATMAN2, B2_NODISC, 0, 0, 0, SCR[0], SCR[1],
                                        0, 0, 0, 0, 0, 0, 0, 0x40),
    # BMX Stunts: 6502 board (board flags 11 0x80), SN76489A, sprite extension 12, INT from VBLANK, no stars
    ("bmxstunts", "init_bmxstunts"):   (M_GAL, 0, B_NOSTARS, 0, 12, B2_NODISC, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x80),
    # Space Battle (Hoei): speech board + sbhoei_map I/O (board flags 12 0x01), code extension 13, RGB -> RBG (0x20);
    # no watchdog (MAME's is 20 frames against the board's 8)
    ("sbhoei", "init_sbhoei"):         (M_MC, 0, B_NMI0 | B_RAM2K | B_MCSND, 0x80, 13, B2_NOWDOG, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                        0x20, 0, 0, 0x01),
    ("moonwar", "init_scobra"):        (*SCOB, *SCR, 0, 0, 0, 0, 0, 0, 0, 0x04),            # dials on IN0 (board)
    ("ozon1", "init_galaxian"):        (M_SCRAMBLE, 0, 0, 0x30, 0, B2_NOWDOG | B2_NODISC, 0, 0, 0, 0, 0, 0, 0, 0,
                                        B8_AYIO01, 0, 0, 0x80),                              # AY on I/O 00 / 01
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
    ("scramble", "init_scramble"):  (M_SCRAMBLE, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, SCR[0], SCR[1] | B5_PROT),
    ("scobra", "init_scobra"):      (M_SCOBRA, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, SCR[0], SCR[1]),
    ("theend", "init_theend"):      (M_SCRAMBLE, 0, 0, 0, 0, B2_NODISC, 0, 0, 0, V3_THEEND_SHELLS,
                                     B5_KONAMI | B5_TWO_AY | B5_PROT),
    ("theend", "init_atlantis"):    (M_SCRAMBLE, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, SCR[0],
                                     SCR[1] | B5_PROT | B5_WD7800),
    ("turtles", "init_turtles"):    (M_TURTLES, 0, 0, 0x80, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_TURTLES_BG,
                                     B5_KONAMI | B5_TWO_AY),
    # Frogger / Turtles bootlegs and conversions
    ("frogg", "init_frogg"):        (M_GAL, 0, B_RAM2K | B_NOSTARS, 0, 0, 0, 0, 0, 0, V3_FROG_COL, 0),
    ("froggers", "init_froggers"):  (M_SCRAMBLE, 0, B_NOSTARS, 0, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_FROG_COL,
                                     B5_KONAMI | B5_SND_SWAP01),
    ("froggers", "init_froggrs"):   (M_SCRAMBLE, 0, B_NOSTARS, 0, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_FROG_COL | 0x08,
                                     B5_KONAMI | B5_SND_SWAP01),
    ("frogf", "init_froggers"):     (M_FROGF, 0, B_NOSTARS, 0, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_FROG_COL,
                                     B5_KONAMI | B5_SND_SWAP01),
    ("froggervd", "init_quaak"):    (M_SCRAMBLE, 0, B_NOSTARS, 0, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_FROG_COL,
                                     B5_KONAMI | B5_WD7800),
    ("quaak", "init_quaak"):        (M_SCOBRA, 0, B_NOSTARS, 0x80, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_FROG_COL,
                                     B5_KONAMI | B5_TWO_AY | B5_FR_TIMER),
    ("froggeram", "init_quaak"):    (M_FROGGERAM, 0, B_NOSTARS, 0, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_FROG_COL,
                                     B5_KONAMI | B5_TWO_AY | B5_FR_TIMER),
    ("turtles", "init_quaak"):      (M_TURTLES, 0, 0, 0x80, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_FROG_COL,
                                     B5_KONAMI | B5_TWO_AY),
    ("turpinnv", "init_turtles"):   (M_SCRAMBLE, 0, B_NOSTARS, 0, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_TURTLES_BG,
                                     B5_KONAMI | B5_TWO_AY | B5_TURPINNV),
    ("turpins", "init_turtles"):    (M_TURPINS, 0, 0, 0x80, 0, B2_NODISC, 0, V2_NOSHELLS, 0, V3_TURTLES_BG,
                                     B5_KONAMI | B5_TWO_AY | B5_TIMER9000),
    # scobra.cpp (Stern): type 1 = the Super Cobra map; keys carry the driver (config names repeat across drivers)
    ("scobra.cpp", "rescue", "init_rescue"):   (M_SCOBRA, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, V3_SCR_STARS,
                                                B5_KONAMI | B5_TWO_AY, V4_RESCUE_BG | V4_STARS_LEFT | V4_GFX_RESCUE),
    ("scobra.cpp", "rescueb", "init_rescue"):  (M_SCOBRA, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, V3_SCR_STARS,
                                                B5_KONAMI | B5_TWO_AY, V4_RESCUE_BG | V4_STARS_LEFT | V4_GFX_RESCUE,
                                                B6_RESCUEB),
    ("scobra.cpp", "minefld", "init_minefld"): (M_SCOBRA, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, V3_SCR_STARS,
                                                B5_KONAMI | B5_TWO_AY,
                                                V4_RESCUE_BG | V4_MINEFLD_BG | V4_STARS_LEFT | V4_GFX_MINEFLD),
    ("scobra.cpp", "stratgyx", "init_stratgyx"): (M_STERN2, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, 0,
                                                  B5_KONAMI | B5_TWO_AY, V4_STRAT_BG, B6_STRAT_RGB),
    ("scobra.cpp", "type2", "init_tazmani2"):  (M_STERN2, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, SCR[0],
                                                B5_KONAMI | B5_TWO_AY, 0, B6_TAZ2_BG),
    ("scobra.cpp", "tazmani3", "empty_init"):  (M_STERN2, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, SCR[0],
                                                B5_KONAMI | B5_TWO_AY, 0, B6_TAZ3),
    ("scobra.cpp", "tazmani3", "init_tazmaniet"): (M_STERN2, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, SCR[0],
                                                   B5_KONAMI | B5_TWO_AY, 0, B6_TAZ3 | B6_TAZET | B6_TAZ2_BG),
    # Hustler (Konami): the Frog (Falcon) map; 1 AY without RC filters
    ("scobra.cpp", "hustler", "init_hustler"):  (M_FROGF, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, 0, HUS, 0,
                                                 B6_HUSTLER, B7_NO_FILTER),
    ("scobra.cpp", "hustler", "init_billiard"): (M_FROGF, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, 0, HUS, 0,
                                                 B6_BILLIARD, B7_NO_FILTER),
    ("scobra.cpp", "hustler", "init_hustlerd"): (M_FROGF, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, 0, HUS, 0,
                                                 0, B7_NO_FILTER),
    ("scobra.cpp", "hustlerb", "empty_init"):   (M_HUSTLERB, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, 0,
                                                 B5_KONAMI, 0, 0, B7_NO_FILTER | B7_HB_SOUND),
    ("scobra.cpp", "hustlerb4", "empty_init"):  (M_HUSTLERB, V_SCRAMBLE_SHELLS, 0, 0x80, 0, B2_NODISC, 0, 0, 0, 0,
                                                 B5_KONAMI, 0, 0, B7_NO_FILTER),
    ("scobra.cpp", "hustlerb6", "empty_init"):  (M_HUSTLERB6, V_SCRAMBLE_SHELLS, 0, 0x40, 0, B2_NODISC | B2_NOWDOG, 0, 0,
                                                 0, 0, B5_KONAMI, 0, 0, B7_NO_FILTER),
    # scramble.cpp (Konami-style boards)
    ("scramble.cpp", "mars", "init_mars"):         (M_MARS, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, *SCRS, 0, 0, B7_ROM12K,
                                                    B8_ADDRSWAP),
    ("scramble.cpp", "mars", "empty_init"):        (M_MARS, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, *SCRS, 0, 0, B7_ROM12K),
    ("scramble.cpp", "devilfsh", "init_devilfsh"): (M_MARS, V_SCRAMBLE_SHELLS, 0, 0, X_UPPER, B2_NODISC, 0, 0, 0, *SCRS,
                                                    0, 0, B7_ROM12K, B8_ADDRSWAP),
    ("scramble.cpp", "mrkougar", "init_mrkougar"): (M_MARS, V_SCRAMBLE_SHELLS | V_PACKED, 0, 0, 0, B2_NODISC, 0, 0, 0,
                                                    *SCRS, 0, 0, B7_ROM12K, B8_ADDRSWAP | KOUGAR),
    ("scramble.cpp", "mrkougb", "empty_init"):     (M_MARS, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, *SCRS, 0, 0, B7_ROM12K,
                                                    KOUGAR),
    ("scramble.cpp", "mrkougb", "init_mrkougar"):  (M_MARS, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, *SCRS, 0, 0, B7_ROM12K,
                                                    B8_ADDRSWAP | KOUGAR),
    ("scramble.cpp", "cavelon", "init_cavelon"):   (M_SCRAMBLE, V_SCRAMBLE_SHELLS, 0, 0, X_MSHUTTLE, B2_NODISC, 0, 0, 0,
                                                    *SCRS, 0, 0, B7_ROM12K, B8_CAVELON),
    # S2650 on a Scramble board (board flags 12: 0x02 map, 0x04 3.072 MHz / 0x08 0.768 MHz, 0x10 port 00 protection)
    ("scramble.cpp", "hunchbks", "init_scramble_ppi"): (M_SCRAMBLE, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, *SCRS,
                                                        0, 0, B7_S2650, 0, 0, 0, 0, 0, 0x02 | 0x04 | 0x10),
    ("scramble.cpp", "hncholms", "init_scramble_ppi"): (M_SCRAMBLE, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, *SCRS,
                                                        0, 0, B7_S2650, 0, 0, 0, 0, 0, 0x02 | 0x08 | 0x10),
    ("scramble.cpp", "hotshock", "init_hotshock"): (M_HOTSHOCK, 0, 0, 0, X_PISCES, B2_NODISC, 0, 0, 0, 0,
                                                    B5_KONAMI | B5_TWO_AY, 0, 0, B7_ROM12K, B8_HSPATCH),
    # Triple Punch: no sound board, one AY on the main CPU's I/O
    ("scramble.cpp", "triplep", "init_scramble_ppi"): (M_TRIPLEP, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0,
                                                      V3_SCR_STARS, 0, 0, 0, 0, B8_AYIO01 | B8_TPPROT),
    ("scramble.cpp", "mariner", "init_mariner"):  (M_TRIPLEP, V_SCRAMBLE_SHELLS, 0, 0, 0, B2_NODISC, 0, 0, 0, 0, 0,
                                                   V4_MARINER, 0, B7_MARINER, B8_AYIO01 | B8_TPPROT),
    ("scramble.cpp", "newsin7", "init_mars"):     (M_MARS, V_SCRAMBLE_SHELLS, 0, 0, X_UPPER, B2_NODISC, 0, 0, 0, *SCRS,
                                                   V4_BPP3, 0, B7_ROM12K | B7_NEWSIN7, B8_ADDRSWAP),
    ("scramble.cpp", "newsin7", "init_newsin7a"): (M_MARS, V_SCRAMBLE_SHELLS, 0, 0, X_UPPER, B2_NODISC, 0, 0, 0, *SCRS,
                                                   V4_BPP3, 0, B7_ROM12K | B7_NEWSIN7, B8_ADDRSWAP),
    # galaxold.cpp bootlegs
    ("galaxold.cpp", "scramblb", "empty_init"):   (M_GS, V_SCRAMBLE_SHELLS, 0, 0, 0, 0, 0, 0, 0, V3_SCR_BG | V3_SCR_STARS),
    ("galaxold.cpp", "scramb2", "empty_init"):    (M_SB2, V_SCRAMBLE_SHELLS, 0, 0, 0, 0, 0, 0, 0, V3_SCR_STARS),
    ("galaxold.cpp", "scramb3", "empty_init"):    (M_SB2, V_SCRAMBLE_SHELLS, 0, 0, 0, 0, 0, 0, 0, V3_SCR_STARS),
    ("galaxold.cpp", "scrambler", "empty_init"):  (M_GAL, V_SCRAMBLE_SHELLS, B_NMI0, 0, 0, 0, 0, 0, 0,
                                                   V3_SCR_BG | V3_SCR_STARS, 0, 0, B6_SCRAMBLER),
    ("galaxold.cpp", "scrambleo", "empty_init"):  (M_GAL, V_SCRAMBLE_SHELLS, 0, 0, 0, 0, 0, 0, 0,
                                                   V3_SCR_BG | V3_SCR_STARS, 0, 0, B6_SCRAMBLER),
    ("galaxold.cpp", "tazzmang", "empty_init"):   (M_TZB, 0, 0, 0x60, 0),
    ("galaxold.cpp", "videotron", "empty_init"):  (M_MC, 0, B_RAM2K, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, B7_FLIPSWAP),
    ("galaxold.cpp", "devilfshv", "empty_init"):  (M_GAL, 0, B_RAM2K, 0, X_SPRITE_ROM, 0, 0, 0, 0, 0, 0, 0, 0, B7_FLIPSWAP),
    ("galaxold.cpp", "hunchbkg", "empty_init"):   (M_GAL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, B7_S2650),
    # Driving Force: S2650 3.072 MHz (board flags 12 0x04), drivfrcg_program (0x20), port 00 protection (0x40), tile and
    # sprite codes from colour bits 5-4 (code extension 11), colour bit 3 from bit 6 + 64-entry palette (video flags 5 0x40)
    ("galaxold.cpp", "drivfrcg", "empty_init"):   (M_GAL, 0, B_NOSTARS, 0, 11, B2_NOWDOG, 0, 0, 0, 0, 0, 0, 0, B7_S2650,
                                                   0, 0, 0x40, 0, 0, 0x20 | 0x40 | 0x04),
    ("galaxold.cpp", "superbikg", "init_superbikg"): (M_GAL, 0, B_NOSTARS, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                      B7_S2650 | B7_SBK_LATCH),
}
# program ROM beyond 0x10000 moved into a free part of the 64K store: set -> (source, length, destination)
ROM_MOVE = {"cavelon": (0x10000, 0x2000, 0x4000)}              # bank 1 of 0000-1FFF (see B8_CAVELON)
# 4K gfx planes read with 8K codes (Moon Shuttle sprite banks): the unconnected top address line mirrors the ROM
GFX_MIRROR = {"cavelon"}

F_4WAY, F_IMPULSE, F_TWIN, F_VERT, F_ROT90 = 0x01, 0x04, 0x08, 0x10, 0x80

# port order on the board: DIP bytes 0-3 and input map bytes 16-47
PORTS = [("IN0",), ("IN1",), ("IN2", "DSW0", "DSW1"), ("IN3", "FAKE", "DSW", "DSW1"), ("IN4", "COINAGE")]   # each tag used once   # first name present wins; IN4 = DIPs only
LINE_BASE = 40      # control ids 40-47 = DIP byte 3 bits: a port bit that reads a line of the FAKE port
LINE4_BASE = 48     # control ids 48-55 = DIP byte 4 bits (fake IN4, read through other ports: Strategy X coinage)

# control ids (Arcade-Galaxian.sv)
CTL = {("JOYSTICK_UP", 1): 1, ("JOYSTICK_DOWN", 1): 2, ("JOYSTICK_LEFT", 1): 3, ("JOYSTICK_RIGHT", 1): 4,
       ("BUTTON1", 1): 5, ("BUTTON2", 1): 6, ("BUTTON3", 1): 7, ("BUTTON4", 1): 8,
       ("JOYSTICK_UP", 2): 9, ("JOYSTICK_DOWN", 2): 10, ("JOYSTICK_LEFT", 2): 11, ("JOYSTICK_RIGHT", 2): 12,
       ("BUTTON1", 2): 13, ("BUTTON2", 2): 14, ("BUTTON3", 2): 15, ("BUTTON4", 2): 16,
       ("BUTTON5", 1): 32, ("BUTTON6", 1): 33, ("BUTTON5", 2): 34, ("BUTTON6", 2): 35,
       ("COIN1", 0): 17, ("COIN2", 0): 18, ("START1", 0): 19, ("START2", 0): 20,
       ("TILT", 0): 21, ("BILL1", 0): 18, ("SERVICE1", 0): 22, ("SERVICE2", 0): 22, ("SERVICE", 0): 22, ("COIN3", 0): 23,
       # twin sticks (Rescue, Minefield): left stick = joystick, right stick = buttons 1-4 (fire up / down / left / right)
       ("JOYSTICKLEFT_UP", 1): 1, ("JOYSTICKLEFT_DOWN", 1): 2, ("JOYSTICKLEFT_LEFT", 1): 3, ("JOYSTICKLEFT_RIGHT", 1): 4,
       ("JOYSTICKRIGHT_UP", 1): 5, ("JOYSTICKRIGHT_DOWN", 1): 6, ("JOYSTICKRIGHT_LEFT", 1): 7, ("JOYSTICKRIGHT_RIGHT", 1): 8,
       ("JOYSTICKLEFT_UP", 2): 9, ("JOYSTICKLEFT_DOWN", 2): 10, ("JOYSTICKLEFT_LEFT", 2): 11, ("JOYSTICKLEFT_RIGHT", 2): 12,
       ("JOYSTICKRIGHT_UP", 2): 13, ("JOYSTICKRIGHT_DOWN", 2): 14, ("JOYSTICKRIGHT_LEFT", 2): 15, ("JOYSTICKRIGHT_RIGHT", 2): 16}
TWIN_FIRE = {"JOYSTICKRIGHT_UP": (1, "Fire Up"), "JOYSTICKRIGHT_DOWN": (2, "Fire Down"),
             "JOYSTICKRIGHT_LEFT": (3, "Fire Left"), "JOYSTICKRIGHT_RIGHT": (4, "Fire Right")}
TRACKBALL = {}
IGNORED_TYPES = {"UNUSED", "UNKNOWN"}

SERIES_BY_PARENT = {}
REGION_WORDS = [("US", "US"), ("Japan", "Japan"), ("Spanish", "Spain"), ("Italian", "Italy"), ("French", "France"),
                ("Brazil", "Brazil"), ("Argentina", "Argentina"), ("Greek", "Greece"), ("Hungarian", "Hungary")]

# ---------------------------------------------------------------- parsing

GAME_RE = re.compile(r'^GAME\(\s*([\w?]+),\s*(\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*(ROT\d+),\s*"([^"]*)",\s*"([^"]*)",\s*([^)]*)\)', re.M)
# ROM_LOAD16_WORD_SWAP (BMX Stunts): loaded as dumped, the board swaps the byte pair on reads (A0 inverted)
LOAD_RE = re.compile(r'ROM_LOAD(?:16_WORD_SWAP)?\(\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(?:BAD_DUMP\s+)?CRC\(([0-9a-fA-F]+)\)')
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
                sc = re.fullmatch(r'FUNC\(\w+::(?:stratgyx|ckongs)_coinage_r<0x0?([0-9a-fA-F]+)>\)', args[0])
                if sc:
                    fld["line4"] = int(sc.group(1), 16).bit_length() - 1
                    continue
                if args[0] == "FUNC(kingball_state::muxbit_r)":
                    fld["line"] = 1                     # the Speech DIP; the board swaps in service by the B003 latch
                    continue
                if args[0] == "FUNC(kingball_state::noise_r)":
                    fld["board"] = True                 # the board's noise bit
                    continue
                if re.fullmatch(r'FUNC\(\w+::theend_protection_alt_r<\d>\)', args[0]):
                    fld["board"] = True                 # driven by the board's protection PAL model
                    continue
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


def split_planes(segs, packed=False, bpp3=False):
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
        rg = s["region"]
        half = s["rsize"] // 2
        lo, hi = s["dst"], s["dst"] + s["len"]
        if lo < half:
            out.append(dict(s, region=f"{rg}_p0", len=min(hi, half) - lo))
        if hi > half:
            start = max(lo, half)
            out.append(dict(s, region=f"{rg}_p1", src=s["src"] + start - lo, dst=start - half, len=hi - start))
    return out


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


def place(segs, setname, packed=False, bpp3=False):
    out = []
    for s in split_high(split_planes(segs, packed, bpp3)):
        if s["region"] in IGNORED_REGIONS:
            continue
        if s["region"] not in REGIONS:
            raise SystemExit(f"{setname}: unmapped region {s['region']}")
        base, size = REGIONS[s["region"]]
        if s["dst"] >= size:
            continue                                   # e.g. the namco timing PROM
        if s["dst"] + s["len"] > size and s["region"] in TRUNCATE:
            s = dict(s, len=size - s["dst"])
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
    spill, spill_idle = [], 0                          # non-contiguous DIPs moved to DIP byte 4 (read back as lines)
    global twoway
    twoway = True
    used = set()
    for p, names in enumerate(PORTS):
        tag = next((n for n in names if n in ports and n not in used), names[0])
        used.add(tag)
        fields = ports.get(tag)
        if fields is None:
            if p < 4:                                  # IN4 only exists as a fifth DIP byte when the game has it
                idle.append(0xFF)
            continue
        level = 0xFF
        ndips = len(dips)
        for f in fields:
            level = (level & ~f["mask"]) | (f["default"] & f["mask"])
            if f["kind"] == "dip":
                lo = (f["mask"] & -f["mask"]).bit_length() - 1
                hi = f["mask"].bit_length() - 1
                if f["mask"] != ((1 << (hi + 1)) - (1 << lo)) and p >= 4:
                    continue                           # fake port read by a custom handler: not selectable (ckongg)
                if f["mask"] != ((1 << (hi + 1)) - (1 << lo)):
                    # MRA DIP bits are a range: pack the bits into DIP byte 4 and route each back as a line
                    bl = [b for b in range(8) if f["mask"] >> b & 1]
                    pos = sum(len(x[1]) for x in spill)
                    for i, b in enumerate(bl):
                        imap[p * 8 + b] = LINE4_BASE + pos + i
                        spill_idle |= (f["default"] >> b & 1) << (pos + i)
                    level &= ~f["mask"]
                    spill.append((f, bl))
                    continue
                vals = [v >> lo for v, _ in f["settings"]]
                ids = ",".join(n.replace(",", ";") for _, n in f["settings"])
                bits = f"{p * 8 + lo}" if lo == hi else f"{p * 8 + lo},{p * 8 + hi}"
                seq = vals == list(range(len(vals))) and len(vals) == 1 << (hi - lo + 1)
                dips.append((f["name"], bits, ids, None if seq else ",".join(str(v) for v in vals)))
            elif f["kind"] == "input":
                t, pl = f["type"], f["player"]
                if p >= 4 and not (t == "CUSTOM" or t in IGNORED_TYPES):
                    raise SystemExit(f'{g["name"]}: input {t} on port {tag}: only DIPs are supported past IN3')
                if t == "CUSTOM" and "line4" in f:
                    imap[p * 8 + f["mask"].bit_length() - 1] = LINE4_BASE + f["line4"]
                    level &= ~f["mask"]
                    continue
                if t == "CUSTOM" and f.get("board"):
                    continue                           # the board overrides this bit
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
                if t in TWIN_FIRE and pl == 1:
                    buttons[TWIN_FIRE[t][0]] = TWIN_FIRE[t][1]
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
        if p >= 4 and len(dips) == ndips:
            continue                                   # fake port with nothing selectable: no fifth DIP byte
        idle.append(level & 0xFF)
    if spill:
        if len(idle) > 4:
            raise SystemExit(f'{g["name"]}: non-contiguous DIP and a fifth DIP byte')
        pos = 0
        for f, bl in spill:
            vals = [sum((v >> b & 1) << i for i, b in enumerate(bl)) for v, _ in f["settings"]]
            ids = ",".join(n.replace(",", ";") for _, n in f["settings"])
            bits = f"{32 + pos}" if len(bl) == 1 else f"{32 + pos},{32 + pos + len(bl) - 1}"
            seq = vals == list(range(len(vals))) and len(vals) == 1 << len(bl)
            dips.append((f["name"], bits, ids, None if seq else ",".join(str(v) for v in vals)))
            pos += len(bl)
        idle.append(spill_idle)
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
        elif line.startswith("@delay"):
            continue                                   # MAME's own restore delay; ours is measured on the core
        elif line.startswith("@"):
            for n in names:
                out.setdefault(n, []).append(line)
            body = True
    return out


HISCORES = parse_hiscores(HISCORE_DAT) if HISCORE_DAT.exists() else {}
HISCORE_UNMEASURED = []


def hiscore_xml(g):
    lines = HISCORES.get(g["name"])
    if not lines or g["name"] in HISCORE_SKIP or g["name"] in HISCORE_PENDING:
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
    # the set's own measurement, then its parent's, then any set with the same layout (same layout != same boot)
    ref = next((k for k in (g["name"], g["parent"]) if k in HISCORE_INIT_FRAME and HISCORES.get(k) == lines),
               next((k for k in HISCORE_INIT_FRAME if HISCORES.get(k) == lines), None))
    if ref is None:
        HISCORE_UNMEASURED.append(g["name"])       # measured in one pass later; no hiscore entry until then
        return ""
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


# Parked 2026-09-30: Rack + Roll / Hex Pool / Bulls Eye Darts - the column-bank loop (self-modifying code in RAM at 7C42)
# writes only port 3F in sim (MAME: 3F..20); not released until fixed
SUPPORTED_PARKED = {
    # Rack + Roll board (board flags 13: 0x01 map / INT / banks, 0x02 SN at I/O 1D, 0x04 SN on the data port, 0x08 / 0x10
    # data port protection, 0x20 Bulls Eye Darts gfx patch); S2650 3.072 MHz, code extension 15 (column tile banks)
    ("galaxold.cpp", "racknrol", "empty_init"):   (M_GAL, 0, B_NOSTARS, 0, 15, B2_NOWDOG | B2_NODISC, 0, V2_NOSHELLS, 0, 0,
                                                   0, 0, 0, B7_S2650, 0, 0, 0, 0, 0, 0x04, 0x01 | 0x02),
    ("galaxold.cpp", "hexpoola", "empty_init"):   (M_GAL, 0, B_NOSTARS, 0, 15, B2_NOWDOG | B2_NODISC, 0, V2_NOSHELLS, 0, 0,
                                                   0, 0, 0, B7_S2650, 0, 0, 0, 0, 0, 0x04, 0x01 | 0x04 | 0x08),
    ("galaxold.cpp", "bullsdrtg", "init_bullsdrtg"): (M_GAL, 0, B_NOSTARS, 0, 15, B2_NOWDOG | B2_NODISC, 0, V2_NOSHELLS, 0,
                                                      0, 0, 0, 0, B7_S2650, 0, 0, 0, 0, 0, 0x04, 0x01 | 0x04 | 0x10 | 0x20),
}

def board_cfg(g):
    """SUPPORTED entry for a set: (driver, config, init) keys for the other drivers, (config, init) for galaxian.cpp
    (config names such as mooncrst / scobra / galaxian mean different boards in galaxold / scobra / scramble.cpp)."""
    return SUPPORTED.get((g["drv"], g["machine"], g["init"])) or \
        (SUPPORTED.get((g["machine"], g["init"])) if g["drv"] == "galaxian.cpp" else None)


def mra(g, games, segs, build_inputs):
    variant, vflags, bflags, rom_top, ext, *rest = board_cfg(g)
    bflags2 = rest[0] if rest else 0
    bflags3, vflags2, bflags4, vflags3, bflags5, vflags4, bflags6, bflags7, bflags8, bflags9, vflags5, bflags10, \
        bflags11, bflags12, bflags13 = (list(rest[1:]) + [0] * 15)[:15]
    ports = build_inputs(g["inputs"])
    idle, dips, imap, fourway, buttons, tb_rev, impulse = input_config(g, ports)
    twin = any(f.get("type", "").startswith("JOYSTICKRIGHT") for fl in ports.values() for f in fl)
    flags = (F_4WAY if fourway else 0) | (F_IMPULSE if impulse else 0) | (F_TWIN if twin else 0) | \
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
    cfg = [variant, flags, vflags, bflags, rom_top, ext, bflags2, bflags3, vflags2, bflags4, vflags3, bflags5,
           vflags4, bflags6, bflags7, bflags8] + imap + [bflags9, vflags5, bflags10] + ([bflags11, bflags12, bflags13] if bflags13 else [bflags11, bflags12] if bflags12 else
                                                          [bflags11] if bflags11 else [])
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
    <special_controls>{"twin joysticks (right stick = fire directions)" if twin else ""}</special_controls>
    <num_buttons>{nbtn}</num_buttons>
    <buttons names="{names}" default="A,B,X,Y,Select,Start,R,L"/>

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


# MRA file names Main_MiSTer would mis-title: its names.txt lookup is a plain substring search for "<file name>:",
# so a bare "Scramble" matches another core's line and is listed as that game (user, 2026-09-29)
FILE_NAME_OVERRIDE = {"scramble": "Scramble (Konami)"}


def out_path(root, g, games):
    if g["name"] in FILE_NAME_OVERRIDE:
        return root / f"{FILE_NAME_OVERRIDE[g['name']]}.mra"
    if g["parent"] is None:
        return root / f"{safe(display_name(g))}.mra"
    top = games.get(g["parent"]) or foreign_parent(g["parent"])
    parent_title = display_name(top) if top else title_case(clean_title(g["desc"]))
    return root / "_alternatives" / f"_{safe(parent_title)}" / f"{safe(display_name(g))}.mra"


def main():
    """Each driver is parsed on its own: INPUT_PORTS / config names repeat across the galaxian drivers."""
    out_dir = Path(sys.argv[2])
    wanted = set(sys.argv[3:])
    drivers = [Path(f) for f in sys.argv[1].split(",")]
    all_games = {}
    for d in drivers:
        for n, g in parse_games(d.read_text()).items():
            all_games.setdefault(n, dict(g, drv=d.name))
    for d in drivers:
        src = d.read_text()
        games = {n: dict(g, drv=d.name) for n, g in parse_games(src).items()}
        build_inputs = parse_inputs(src)
        names = [n for n in games if n in wanted] if wanted else \
                [n for n, g in games.items() if board_cfg(g) and g["working"]]
        for name in names:
            try:
                main_one(name, games, all_games, src, build_inputs, out_dir)
            except SystemExit as e:                    # one set's unsupported feature must not stop the others
                if wanted:
                    raise
                print(f"SKIPPED {name}: {e}")
    if HISCORE_UNMEASURED:
        print("hiscore layout not measured yet (no entry written):", " ".join(HISCORE_UNMEASURED))
    missing = wanted - set(all_games)
    if missing:
        raise SystemExit(f"unknown sets: {sorted(missing)}")


def rom_segments(g, src):
    """ioctl index 0 layout for a set (shared with verilator/build_rom.py)."""
    name = g["name"]
    raw = parse_roms(src, name)
    if name in PROM_STANDIN:
        _, fn, crc = PROM_STANDIN[name]
        raw.append(dict(name=fn, crc=crc, src=0, dst=0, len=0x20, flen=0x20, region="proms", rsize=0x20))
    if name in ROM_MOVE:
        mv_src, n, mv_dst = ROM_MOVE[name]
        for s in raw:
            if s["region"] == "maincpu" and mv_src <= s["dst"] < mv_src + n:
                s["dst"] += mv_dst - mv_src
    cfg = board_cfg(g)
    if (list(cfg[5:]) + [0] * 9)[8] & B7_S2650:
        for s in raw:                                  # S2650 ROM pages 0000 / 2000 / 4000 / 6000 (4K) -> 0000-3FFF
            if s["region"] == "maincpu":
                assert not s["dst"] & 0x1000 and (s["dst"] & 0xFFF) + s["len"] <= 0x1000, f"{name}: S2650 page"
                s["dst"] = (s["dst"] >> 13 << 12) | (s["dst"] & 0xFFF)
    segs = place(raw, name, bool(cfg[1] & V_PACKED), bool((list(cfg[5:]) + [0] * 8)[6] & V4_BPP3))
    if name in GFX_MIRROR:
        for base in (REGIONS["gfx1_p0"][0], REGIONS["gfx1_p1"][0]):
            half = [s for s in segs if base <= s["addr"] < base + 0x1000]
            assert half and all(s["addr"] + s["len"] <= base + 0x1000 for s in half), f"{name}: gfx mirror"
            segs += [dict(s, addr=s["addr"] + 0x1000) for s in half]
        segs.sort(key=lambda s: s["addr"])
    return segs


def main_one(name, games, all_games, src, build_inputs, out_dir):
    g = games[name]
    if not board_cfg(g):
        raise SystemExit(f'{name}: board {g["drv"]} {g["machine"]} / {g["init"]} not implemented')
    if True:
        segs = rom_segments(g, src)
        path = out_path(out_dir, g, all_games)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(mra(g, all_games, segs, build_inputs))
        print(f'{name:12s} {path.relative_to(out_dir)}')


if __name__ == "__main__":
    main()
