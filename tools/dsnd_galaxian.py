"""dsnd_galaxian.py - Galaxian / Moon Cresta discrete sound (Galaxian.pdf p. 26-27, Moon Cresta.pdf p. 23) as a
dsnd_engine program, 48 kHz. Structure and values = the board model in verilator/galsnd/galsnd_model.h (MAME
galaxian_discrete, R40 at its schematic 2.2k), plus step 2 (2026-11-04) Moon Cresta from its schematic: C20 0.01 uF,
C21 22 uF, no R89 / R90, output C39 0.1 uF into R42 22k + 1k pot; the digital parts (pitch counter + 393, NOISE latch) stay in
rtl/boards/galaxian_snd/galaxian_sound.sv, which delivers per sample:
  byte 0: [3:0] LFO latch, [6:4] FS1-FS3, [7] HIT        byte 1: [0] FIRE, [2:1] VOL1 / VOL2, [3] NOISE
  bytes 2 / 3 / 4: 393 QA / QC / QD high count over the sample (32 fast ticks: 0 .. 32)
555s: per-sample RC steps with the threshold crossing placed inside the sample (linear), output = high fraction.
"""
import dsnd
from dsnd import Board, q

FS = dsnd.FS
TTL, V5, VU = 4.0, 5.0, 4.0 - 0.7
B0, B1, BQA, BQC, BQD = 0, 1, 2, 3, 4


def k(tau):
    return dsnd.rc_exp(tau)


def osc555(p, n, th, tr, kc, kd):
    """555 astable on a 5 V supply, thresholds th / tr (registers), charge / discharge steps kc / kd per sample.
    Registers n_v (cap), n_ff (1.0 = output high, charging); leaves n_d = output high fraction of this sample.
    A threshold that moved past the cap (CV change) gives a crossing fraction < 0, clamped: the flip happens at once."""
    v, ff, d, st, a, t = n + "_v", n + "_ff", n + "_d", n + "_st", n + "_a", "_t"
    p.op("LD", ff)
    p.op("CMPI", imm=q(0.5))
    s1 = p.skip_if(False)
    # charging toward 5 V
    p.op("LDI", imm=q(V5))
    p.op("SUB", v)
    p.op("MULI", imm=q(kc))
    p.op("ST", st)
    p.op("ADD", v)
    p.op("ST", t)
    p.op("CMP", th)
    s2 = p.skip_if(False)
    p.op("LD", st)                                    # crossed: a = (th - v) / step, then discharge for 1 - a
    p.op("MULI", imm=q(64.0))
    p.op("RCP")
    p.op("ST", a)
    p.op("LD", th)
    p.op("SUB", v)
    p.op("MUL", a)
    p.op("MULI", imm=q(64.0))
    p.op("MAXI", imm=0)
    p.op("MINI", imm=q(1.0))
    p.op("ST", d)
    p.op("LD", v)                                     # discharge starts at max(v, th): a CV drop leaves the cap
    p.op("CMP", th)
    p.op("LD", th)
    p.op("LDF", v)
    p.op("ST", st)
    p.op("LDI", imm=q(1.0))
    p.op("SUB", d)
    p.op("MULI", imm=q(kd))
    p.op("MUL", st)
    p.op("ST", a)
    p.op("LD", st)
    p.op("SUB", a)
    p.op("ST", v)
    p.op("LDI", imm=0)
    p.op("ST", ff)
    j1 = p.jump()
    p.land(s2)
    p.op("LD", t)
    p.op("ST", v)
    p.op("LDI", imm=q(1.0))
    p.op("ST", d)
    j2 = p.jump()
    p.land(s1)
    # discharging toward 0 V
    p.op("LD", v)
    p.op("MULI", imm=q(kd))
    p.op("ST", st)
    p.op("LD", v)
    p.op("SUB", st)
    p.op("ST", t)
    p.op("LD", tr)
    p.op("CMP", t)
    s3 = p.skip_if(False)
    p.op("LD", st)                                    # crossed: a = (v - tr) / step, then charge for 1 - a
    p.op("MULI", imm=q(64.0))
    p.op("RCP")
    p.op("ST", a)
    p.op("LD", v)
    p.op("SUB", tr)
    p.op("MUL", a)
    p.op("MULI", imm=q(64.0))
    p.op("MAXI", imm=0)
    p.op("MINI", imm=q(1.0))
    p.op("ST", a)
    p.op("LDI", imm=q(1.0))
    p.op("SUB", a)
    p.op("ST", d)
    p.op("LD", tr)                                    # charge starts at min(v, tr)
    p.op("CMP", v)
    p.op("LD", tr)
    p.op("LDF", v)
    p.op("ST", st)
    p.op("LD", d)
    p.op("MULI", imm=q(kc))
    p.op("ST", a)
    p.op("LDI", imm=q(V5))
    p.op("SUB", st)
    p.op("MUL", a)
    p.op("ADD", st)
    p.op("ST", v)
    p.op("LDI", imm=q(1.0))
    p.op("ST", ff)
    j3 = p.jump()
    p.land(s3)
    p.op("LD", t)
    p.op("ST", v)
    p.op("LDI", imm=0)
    p.op("ST", d)
    p.land(j1)
    p.land(j2)
    p.land(j3)


def board(mc):
    """Galaxian (mc = False) or Moon Cresta (mc = True) sound board"""
    p = Board("mooncrst" if mc else "galaxian")
    par = dsnd.par
    p.init("bg0_ff", 1.0)
    p.init("bg1_ff", 1.0)
    p.init("bg2_ff", 1.0)
    p.init("fi_ff", 1.0)

    # LFO: R18 / R17 / R16 / R15 DAC (+ 4.4 V / 15k Q1 bias, 330k) sets the 555 constant-current sawtooth slope
    g = 1 / 15e3 + 1 / 330e3 + 1 / 1e6 + 1 / 470e3 + 1 / 220e3 + 1 / 100e3
    p.op("LDI", imm=q(4.4 / 15e3 / g))
    p.op("ST", "lfo_dac")
    for b, r in enumerate((1e6, 470e3, 220e3, 100e3)):
        p.op("LDLM", 0, p.src(B0, 0), imm=(1 << b) | ((24 - b) << 8))
        p.op("MULI", imm=q(TTL / r / g))
        p.op("ADD", "lfo_dac")
        p.op("ST", "lfo_dac")
    p.op("ADDI", imm=q(0.7))
    p.op("ST", "lfo_lim")
    p.op("LDI", imm=q(5.0 - 0.7))
    p.op("SUB", "lfo_dac")
    p.op("MULI", imm=q(1.0 / (100e3 * 1e-6 * FS)))    # i = (5 - (vin + 0.7)) / R21 into C15
    p.op("ADD", "lfo_v")
    p.op("CMP", "lfo_lim")
    p.op("LDF", "lfo_lim")
    p.op("CMPI", imm=q(10.0 / 3))
    p.op("ST", "lfo_v")
    p.op("ADDI", imm=q(-5.0 / 3))
    p.op("STF", "lfo_v")
    p.op("LD", "lfo_v")                               # LM324 buffer (R31 / R32 47k, R33 10k) -> 555 CV
    p.op("MULI", imm=q(10e3 / par(47e3, 47e3, 10e3)))
    p.op("ADDI", imm=q(-5.0 * 10e3 / 47e3))
    p.op("MAXI", imm=0)
    p.op("MINI", imm=q(V5))
    p.op("ST", "cv")
    p.op("MULI", imm=q(0.5))
    p.op("ST", "cv2")

    # background tones: 555s 8R / 8S / 8T (R1 100k, R2 470k / 330k / 220k, 0.01 uF), reset = FS1-FS3
    p.op("LDI", imm=0)
    p.op("ST", "bg_in")
    for n, r2 in enumerate((470e3, 330e3, 220e3)):
        o = f"bg{n}"
        p.op("BIT", 0, p.src(B0, 4 + n))
        s = p.skip_if(True)
        p.op("LDI", imm=0)
        p.op("ST", o + "_v")
        p.op("LDI", imm=q(1.0))
        p.op("ST", o + "_ff")
        j = p.jump()
        p.land(s)
        osc555(p, o, "cv", "cv2", k((100e3 + r2) * 0.01e-6), k(r2 * 0.01e-6))
        p.op("LD", o + "_d")
        p.op("ADD", "bg_in")
        p.op("ST", "bg_in")
        p.land(j)
    # 3 x 10k into C20 (Galaxian 0.1 uF, Moon Cresta 0.01 uF); the 555 output high = 4.5 V
    p.op("LD", "bg_in")
    p.op("MULI", imm=q(4.5 / 3))
    p.op("RC", "bgmix", imm=q(k(par(10e3, 10e3, 10e3) * (0.01e-6 if mc else 0.1e-6))))

    # fire: !FIRE -> R47 2.2k / C28 47 uF -> R48 into the 7S CV, NOISE through R46 10k
    p.op("BIT", 0, p.src(B1, 0))
    p.op("LDI", imm=q(TTL))
    p.op("LDIF", imm=0)
    p.op("RC", "rc173", imm=q(k(2.2e3 * 47e-6)))
    p.op("MULI", imm=q(par(10e3, 2.2e3) / 2.2e3))
    p.op("ST", "cvf")
    p.op("BIT", 0, p.src(B1, 3))
    p.op("LDI", imm=0)
    p.op("LDIF", imm=q(TTL * par(10e3, 2.2e3) / 10e3))
    p.op("ADD", "cvf")
    p.op("ST", "cvf")
    p.op("MULI", imm=q(0.5))
    p.op("ST", "cvf2")
    p.op("LD", "cvf")                                 # 7S runs while its CV is above 0.25 V
    p.op("CMPI", imm=q(0.25))
    s = p.skip_if(True)
    p.op("LD", "fi_ff")
    p.op("ST", "fi_d")
    j = p.jump()
    p.land(s)
    osc555(p, "fi", "cvf", "cvf2", k(32e3 * 0.01e-6), k(22e3 * 0.01e-6))
    p.land(j)
    # C25 1 uF charged to FIRE - 0.7 V, drained through R41 100k while the 7S output is high
    p.op("BIT", 0, p.src(B1, 0))
    p.op("LDI", imm=0)
    p.op("LDIF", imm=q(VU))
    p.op("ST", "fi_u")
    p.op("CMP", "fi_cap")
    s = p.skip_if(False)
    p.op("LD", "fi_u")                                # charge: instant
    p.op("ST", "fi_cap")
    j = p.jump()
    p.land(s)
    p.op("LD", "fi_cap")
    p.op("SUB", "fi_u")
    p.op("MULI", imm=q(k(100e3 * 1e-6)))
    p.op("MUL", "fi_d")
    p.op("ADDI", imm=1)                               # rounded up: drains fully (no residual 7S buzz)
    p.op("ST", "_t")
    p.op("LD", "fi_cap")
    p.op("SUB", "_t")
    p.op("MAXI", imm=0)
    p.op("ST", "fi_cap")
    p.land(j)
    p.op("LD", "fi_cap")
    p.op("MUL", "fi_d")
    p.op("ST", "fr")
    # C26 0.01 uF into R43 (Galaxian: || R91 10k node; Moon Cresta: into the resistor node)
    p.op("RC", "fhp", imm=q(k((2.2e3 if mc else par(2.2e3, 10e3)) * 0.01e-6)))
    p.op("LD", "fr")
    p.op("SUB", "fhp")
    p.op("ST", "fire_o")

    # hit: HIT -> C21 (Galaxian 2.2 uF via R89 1k, Moon Cresta 22 uF direct), gated by NOISE (4066 7R) into the
    # R35 150k MFB band-pass; charge modelled instant on both
    p.op("BIT", 0, p.src(B0, 7))
    p.op("LDI", imm=0)
    p.op("LDIF", imm=q(VU))
    p.op("ST", "hit_u")
    p.op("BIT", 0, p.src(B1, 3))
    s = p.skip_if(True)
    p.op("LD", "hit_u")                               # NOISE low: switch open, cap only charges
    p.op("CMP", "hit_cap")
    p.op("LD", "hit_cap")
    p.op("LDF", "hit_u")
    p.op("ST", "hit_cap")
    p.op("LDI", imm=0)
    p.op("ST", "hit_h")
    j = p.jump()
    p.land(s)
    p.op("LD", "hit_u")
    p.op("CMP", "hit_cap")
    s2 = p.skip_if(True)
    p.op("LD", "hit_u")                               # discharging through R35 + R36
    p.op("RC", "hit_cap", imm=q(k((150e3 + 22e3) * (22e-6 if mc else 2.2e-6))))
    j2 = p.jump()
    p.land(s2)
    p.op("LD", "hit_u")
    p.op("ST", "hit_cap")
    p.land(j2)
    p.op("LD", "hit_cap")
    p.op("ST", "hit_h")
    p.land(j)
    rt = par(150e3, 22e3)
    vref, vpmax = 2.0, 5.0 - 1.5
    fc = 1.0 / (2 * 3.141592653589793 * (rt * 470e3 * 0.01e-6 * 0.01e-6) ** 0.5)
    dd = 0.02e-6 / (470e3 / rt * 0.01e-6 * 0.01e-6) ** 0.5
    gain = -470e3 / rt * 0.01e-6 / 0.02e-6
    import math
    wc = FS * 2.0 * math.tan(math.pi * fc / FS)
    tT = 2 * FS
    den = tT * tT + dd * wc * tT + wc * wc
    a1 = 2.0 * (-tT * tT + wc * wc) / den
    a2 = (tT * tT - dd * wc * tT + wc * wc) / den
    b0 = dd * wc * tT / den * gain
    p.op("LD", "hit_h")                               # input divider R35 / R36, biquad (MAME bilinear form)
    p.op("ADDI", imm=q(-vref))
    p.op("MULI", imm=q(rt / 150e3))
    p.op("ADDI", imm=q(-vref * (1.0 - rt / 150e3)))
    p.op("ST", "bx")
    p.op("MULI", imm=q(b0))
    p.op("MACI", "bx2", imm=q(-b0))
    p.op("MACI", "by1", imm=q(-a1))
    p.op("MACI", "by2", imm=q(-a2))
    p.op("ADDI", imm=q(vref))
    p.op("MAXI", imm=0)
    p.op("MINI", imm=q(vpmax))
    p.op("ST", "hit_o")
    p.op("LD", "by1")
    p.op("ST", "by2")
    p.op("LD", "hit_o")
    p.op("ADDI", imm=q(-vref))
    p.op("ST", "by1")
    p.op("LD", "bx1")
    p.op("ST", "bx2")
    p.op("LD", "bx")
    p.op("ST", "bx1")

    # pitch: 393 QA -> R51 33k, QC -> R50 22k + R49 10k (VOL1), QD -> R52 15k (VOL2); conductances in 1/kohm
    cnt = 1.0 / 32 * 256                              # LDL = count << 16 = count / 256 V; duty = count / 32
    p.op("LDL", 0, p.src(BQA, 0))
    p.op("MULI", imm=q(cnt * TTL / 33))
    p.op("ST", "num")
    p.op("BIT", 0, p.src(B1, 1))
    p.op("LDI", imm=q(1 / 22))
    p.op("LDIF", imm=q(1 / 22 + 1 / 10))
    p.op("ST", "_t")
    p.op("LDL", 0, p.src(BQC, 0))
    p.op("MULI", imm=q(cnt * TTL))
    p.op("MUL", "_t")
    p.op("ADD", "num")
    p.op("ST", "num")
    p.op("LDL", 0, p.src(BQD, 0))
    p.op("MULI", imm=q(cnt * TTL / 15))
    p.op("ST", "_t")
    p.op("BIT", 0, p.src(B1, 2))
    p.op("LDI", imm=0)
    p.op("LDF", "_t")
    p.op("ADD", "num")
    p.op("ST", "num")
    p.op("LD", "bgmix")                               # background through R34 (Galaxian 5.1k, Moon Cresta 15k)
    p.op("MULI", imm=q(1 / (15 if mc else 5.1)))
    p.op("ADD", "num")
    p.op("ST", "num")
    gfix = 1 / 33 + 1 / 22 + (1 / 15 + 2 / 2.2 if mc else 1 / 5.1)
    p.op("BIT", 0, p.src(B1, 1))
    p.op("LDI", imm=q(gfix))
    p.op("LDIF", imm=q(gfix + 1 / 10))
    p.op("ST", "_t")
    p.op("BIT", 0, p.src(B1, 2))
    p.op("LDI", imm=0)
    p.op("LDIF", imm=q(1 / 15))
    p.op("ADD", "_t")
    p.op("RCP")
    p.op("ST", "_t")
    if mc:
        # Moon Cresta: one resistor node, hit and fire through R40 / R43 2.2k into it
        p.op("LD", "hit_o")
        p.op("ADD", "fire_o")
        p.op("MULI", imm=q(1 / 2.2))
        p.op("ADD", "num")
        p.op("MUL", "_t")
    else:
        # Galaxian: pre-mix node, then R34 5.1k / R40 / R43 2.2k / R91 10k
        gf = 1 / 5.1 + 2 / 2.2 + 1 / 10
        p.op("LD", "num")
        p.op("MUL", "_t")
        p.op("MULI", imm=q(1 / 5.1 / gf))
        p.op("ST", "_t")
        p.op("LD", "hit_o")
        p.op("ADD", "fire_o")
        p.op("MULI", imm=q(1 / 2.2 / gf))
        p.op("ADD", "_t")
    p.op("ST", "mix")
    if mc:
        # C39 0.1 uF from the node (source ~1/_t kohm) into R42 22k + 1k volume pot; MB3712 not modelled
        p.op("RC", "amp", imm=q(k((22e3 + 1e3 + 1e3 / (1 / 33 + 1 / 22 + 1 / 15 + 2 / 2.2)) * 0.1e-6)))
    else:
        # C46 0.1 uF into R92 100k (LM377 bridge: flat, gain 101)
        p.op("RC", "amp", imm=q(k(100e3 * 0.1e-6)))
    p.op("LD", "mix")
    p.op("SUB", "amp")
    p.op("OUT")
    p.finish()
    return p


def galaxian():
    return board(False)


def mooncrst():
    return board(True)
