"""Galaxian core MRA tables for tools/gen_mra.py: board config (SUPPORTED), ROM region layout, hiscore START_WAIT
frames. A SUPPORTED value = (variant, video flags, board flags, ROM top, code extension, board flags 2, board flags 3,
video flags 2, board flags 4, video flags 3, board flags 5, video flags 4, board flags 6, board flags 7, board flags 8,
board flags 9, video flags 5, board flags 10 .. 13), missing trailing items 0; everything after the variant is sent as
game-ID bytes 64-83 in that order. Bit meanings: rtl/boards/galaxian/galaxian_board.sv.
"""
MAME_VERSION = "0289"
RBF = "Galaxian"
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
                      "tazzmang2": 32, "triplep": 99,
                      # core-measured 2026-10-10 (hsmeasure, 400 frames; kingball 1200): last boot-time table write.
                      # S2650 sets traced at their replayed RAM address (hs_addr); Driving Force f65 / King & Balloon
                      # f405 are clears before the real init
                      "ad2083": 161, "anteaterg": 1, "anteatergg": 1, "anteateruk": 1, "bagmanmc": 5, "bagmanm2": 5,
                      "drivfrcg": 201, "drivfrcb": 201, "drivfrcsg": 201, "drivfrct": 137, "guttangt": 116,
                      "guttangts3": 116, "hunchbkg": 263, "hunchbgb": 263, "hunchbks": 263, "hunchbks2": 263,
                      "kingball": 419, "moonwar": 50, "moonwara": 50, "mshuttle": 137, "mshuttle2": 137,
                      "mshuttlea": 137, "mshuttlej": 137, "mshuttlej2": 137, "ozon1": 4, "rockclim": 283,
                      "sbhoei": 14, "sbhoeia": 14,
                      # core-measured 2026-10-16 (hsmeasure, obj17, 400 frames): Rack + Roll board, clear then fill
                      "racknrol": 28, "hexpool": 24, "hexpoola": 50, "bullsdrtg": 24,
                      # hncholms (0.768 MHz S2650): f65 clear, f203 table (MAME f64 / f202), measured after the port 00 fix
                      "hncholms": 203}
# colour PROMs never dumped: stand-in from a related set, (zip, file, crc, region, length). Kong (Taito do Brasil) takes
# Crazy Kong's first palette PROM (user, 2026-09-29) - same byte layout; which colour group goes where is a guess
STANDIN = {"kong": ("ckong.zip", "ck6v.bin", "751c3325", "proms", 0x20),
           # Time Fighter (Taito do Brasil): Fantastic's PROM, same conversion board - a guess
           "timefgtr": ("fantastc.zip", "prom-74g138", "800f5718", "proms", 0x20)}
# BAD_DUMP tile / sprite ROMs: Bagman set 1 takes set 2's (the bootleg gfx MAME says work; user, 2026-11-05)
REGION_FROM = {"bagmanmc": {"gfx1": "bagmanm2"}}
# hiscore.dat entries that can't work here: atlantisb's range is live game state, omegab's C060 is unmapped
HISCORE_SKIP = {"atlantisb", "omegab"}
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
    "tmsprom": (0x28000, 0x02000),                                # A.D. 2083 speech ROMs (TMS5110)
    "5110ctrl": (0x2A000, 0x00020),                               # A.D. 2083 speech sequencer PROM
    "i8039": (0x1E000, 0x00800),                                  # Space Battle speech CPU
    "sbhoei_sound_rom": (0x1F000, 0x01000),                       # Space Battle speech data
    "bg_gfx": (0x2C000, 0x02000),                                 # Rock Climber background tiles (lc13 / lc14)
    "bg_proms": (0x14020, 0x00020),                               # Rock Climber background PROM: colour PROM entries 20-3F
}

IGNORED_REGIONS = {"plds", "pld", "unknown", "unk", "unused_proms",   # dumps MAME does not use
                   "tempgfx",                                  # ROM_COPY source only
                   "other_proms",                              # decoding PROMs (Superbike)
                   "proms2", "extra_prom", "epoxy_block_prom", # unknown PROMs (ckongcv / ckongis, guttangts3, bmxstunts)
                   "unk_prom",                                 # Dambusters timing PROM
                   "extraproms"}                               # aracnisa PROM board (not read by MAME)
# region placement where MAME's region name means something else: Dambusters program (address-swapped, read path)
REGION_OVERRIDE = {"dambustr": {"user1": (0, 0x08000, 0x04000)}}

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
M_HAREM, X_HAREM, M_DAMBUSTR = 28, 14, 29
M_ROCKCLIM = 30
V_PACKED, V_SPRHI, V_AD2083 = 0x04, 0x08, 0x10                                  # Mr. Kougar packed gfx (ROM loaded into both planes);
                                                                # sprites from the upper 8K of 16K planes (4 Fun in 1);
                                                                # A.D. 2083 sprite code (colour bits 5-4 above it, no X flip)
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
    # Sidam explorer board (board flags 12 0x80): Hot Shocker map + 6800 latches, mirrored I/O, no stars; sound Z80 + AY-3-8912
    # at 1.5 MHz, IRQ set by 9000 / cleared by the latch read, timer on AY #2 port A (Take Off: one AY, timer at I/O 20)
    ("explorer", "init_explorer"):  (M_HOTSHOCK, V_SCRAMBLE_SHELLS, B_NOSTARS, 0, 0, B2_NODISC, 0, 0, 0, 0,
                                     B5_KONAMI | B5_TWO_AY, 0, 0, 0, 0, 0, 0, 0, 0, 0x80),
    ("takeoff", "init_explorer"):   (M_HOTSHOCK, V_SCRAMBLE_SHELLS, B_NOSTARS, 0, 0, B2_NODISC, 0, 0, 0, 0,
                                     B5_KONAMI, 0, 0, B7_NO_FILTER, 0, 0, 0, 0, 0, 0x80),
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
    ("checkmanj", "init_checkmanj"): (M_GAL, 0, 0, 0, 0, B2_NODISC, S_BOARD | S_JAPAN | S_PROT_CM),
    ("checkmanj", "init_dingo"):     (M_GAL, 0, 0, 0, 0, B2_NODISC, S_BOARD | S_JAPAN | S_PROT_DINGO),
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
    # Harem: own map (28), run-time ROM decryption, column tile banks + Bagman sprite bank (code extension 14),
    # Scorpion sound board (third AY + Digitalker, INTR at 6000)
    # 4 Fun in 1: Galaxian board, 8000 game bank (ROM, gfx bank, DIP set), menu ROM C000, program XOR (board flags 13 0x40)
    ("galaxold.cpp", "_4in1", "init_4in1"):        (M_GAL, V_SPRHI, 0, 0, X_PISCES, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                    0, 0, 0x40),
    # Dambusters: own map (29), split background with priority, character bank, PROM R/G/B swap (board), program and
    # gfx unscrambled on the read path; Galaxian discrete sound
    ("dambustr.cpp", "dambustr", "init_dambustr"): (M_DAMBUSTR, V_SCRAMBLE_SHELLS, 0, 0, 0),
    # Rock Climber: own map (30) = Moon Cresta + scrolling background (RAM 4000, scroll 4800, ROM 6000, IN3 5800, IN4 8800),
    # sprite banks 0 / 1 swapped; melody chip (Epson 7910C) NO_DUMP and silent in MAME too
    ("galaxian_rockclim.cpp", "rockclim", "init_rockclim"): (M_ROCKCLIM, 0, MC, 0, X_MC),
    ("scramble.cpp", "harem", "init_harem"):       (M_HAREM, V_SCRAMBLE_SHELLS, 0, 0, X_HAREM, B2_NODISC, 0, 0, 0, *SCRS,
                                                    0, 0, B7_ROM12K),
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
    # A.D. 2083: Hot Shocker map + ROM A000-DFFF / RAM E800 / RGB background / program XOR (board flags 13 0x80), tile and
    # sprite codes from colour bits 5-4 (code extension 11 + V_AD2083), TMS5110 speech on the sound board
    ("scramble.cpp", "ad2083", "init_ad2083"):     (M_HOTSHOCK, V_SCRAMBLE_SHELLS | V_AD2083, 0, 0, 11, B2_NODISC, 0, 0, 0,
                                                    V3_TURTLES_BG, B5_KONAMI | B5_TWO_AY, 0, 0, B7_ROM12K, 0, 0, 0, 0, 0, 0,
                                                    0x80),
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
    # galaxold mooncrst machine (Video Pool): the Moon Cresta map, sound and gfx bank, 2K RAM at 8000
    ("galaxold.cpp", "mooncrst", "empty_init"):   (M_MC, 0, MC | B_RAM2K, 0, X_MC),
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
# program ROM beyond 0x10000 moved into a free part of the 64K store: set -> (region, source, length, destination)
ROM_MOVE = {"cavelon": [("maincpu", 0x10000, 0x2000, 0x4000)],  # bank 1 of 0000-1FFF (see B8_CAVELON)
            # 4 Fun in 1 games 10000-1FFFF packed around the menu at C000 (rtl/galaxian_board.sv fin_a)
            "4in1": [("maincpu", 0x10000, 0x4000, 0x0000), ("maincpu", 0x14000, 0x4000, 0x4000),
                     ("maincpu", 0x18000, 0x3000, 0x8000), ("maincpu", 0x1C000, 0x1000, 0xB000),
                     ("maincpu", 0x1D000, 0x2000, 0xE000)]}
# 4K gfx planes read with 8K codes (Moon Shuttle sprite banks): the unconnected top address line mirrors the ROM
GFX_MIRROR = {"cavelon"}
# gfx1 = chars plane 0 / 1, then sprites plane 0 / 1 (8K each; sprites read from the upper 8K, V_SPRHI)
GFX_QUARTERS = {"4in1"}

MOUSE_SETS = {"warofbug", "warofbugg", "warofbugu"}   # optional mouse / trackball (Game Options), user 2026-09-29
IGNORED_TYPES = {"UNUSED", "UNKNOWN", "OTHER"}   # OTHER: operator-only buttons (Dambusters Initials Reset)

SERIES_BY_PARENT = {"rockclim": ("Rock Climber", "Platform - Climb"), "racknrol": ("Rack + Roll", "Sports - Pool"),
                    "bullsdrt": ("Bulls Eye Darts", "Sports - Darts")}

# 4 Fun in 1: the four per-game FAKE DIP ports, selected by the game bank, packed into DIP bytes 3 (IN3) / 4 (IN4) as
# rtl/boards/galaxian/galaxian_board.sv fin_dip unpacks them: port -> [(MAME mask, DIP byte, packed mask)]
FIN_DIPS = {"4in1": {"FAKE1": [(0x03, 3, 0x03), (0xC0, 3, 0x0C)], "FAKE3": [(0x03, 3, 0x30), (0xC0, 3, 0xC0)],
                     "FAKE4": [(0x01, 4, 0x01), (0xC0, 4, 0x06)],
                     "FAKE2": [(0x08, 4, 0x08), (0x10, 4, 0x10), (0x20, 4, 0x20), (0xC0, 4, 0xC0)]}}

# Rack + Roll / Hex Pool / Bulls Eye Darts (needs the sgs2650 sIO write-cycle fix: the bank loop runs from RAM)
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
SUPPORTED.update(SUPPORTED_PARKED)

# sets deliberately not built (gen_mra.py --check): the reason
NW = "MAME MACHINE_NOT_WORKING; board not implemented"
SKIP = {"highroll": NW, "warofbugg": NW, "tenspot": NW, "porterb": NW, "dingoe": NW, "ncentury": NW, "scrammr": NW,
        "scramblebun": NW, "jungsub": NW, "dkingjrv": NW, "spcwarp": NW, "conquer": NW, "rescuefe": NW,
        "gmgalax": "multi-game board (Ghostmuncher / Galaxian switch, banked gfx + 64-pen palette) not implemented",
        "fourplay": "multi-game board (4 games, banked ROM / gfx) not implemented",
        "videight": "multi-game board (8 games, banked ROM / gfx, 256-pen palette) not implemented",
        "amidarc": "thepitm map + 2K RAM with the Turtles background (init_turtles): combination not implemented",
        "aracnisb": "scorpnmc map with init_ladybugg2 decode: combination not implemented",
        "namenayo": "namenayo map / gfx layout / 64-pen palette not implemented",
        "dkongjrm": "32 sprites per line (Galaxian sprite engine: 8); MAME colours wrong",
        "dkongjrmc": "64 sprites per line (Galaxian sprite engine: 8); MAME colours wrong",
        "dingov": "deferred: Nuova Videotron dkingjrv board not implemented",
        "junglekv": "deferred: Nuova Videotron dkingjrv board not implemented",
        "darkplnt": "Stern Dark Planet: dial + own palette / video not implemented",
        "minefldfe": "minefldfe map (Logicshop bootleg) not implemented",
        "mimonkeyug": "U.Games bootleg board (own map, MAME NO_SOUND) not implemented"}
