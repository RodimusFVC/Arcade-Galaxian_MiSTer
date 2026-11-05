"""dsnd_galaxian.py - Galaxian / Moon Cresta discrete sound (Galaxian.pdf p. 26-27, Moon Cresta.pdf p. 23) as a
dsnd_engine program, 48 kHz. Structure and values = the board model in verilator/galsnd/galsnd_model.h (MAME
galaxian_discrete, R40 at its schematic 2.2k). Moon Cresta keeps the Galaxian C20 / C21 / output values: its
schematic values (C20 0.01 uF, C21 22 uF, C39 into R42 22k) were tried and rejected by ear on hardware; the digital parts (pitch counter + 393, NOISE latch) stay in
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


def fire(p, b_fire, b_noise, fhp_tau):
    """Galaxian fire circuit (7S 555 on a CV swept by !FIRE through R47 / C28 / R48 plus NOISE through R46, C25 drained
    through R41 while the 555 output is high), sources (byte, bit) b_fire / b_noise. Leaves fire_o (high-passed)."""
    par = dsnd.par
    # fire: !FIRE -> R47 2.2k / C28 47 uF -> R48 into the 7S CV, NOISE through R46 10k
    p.op("BIT", 0, p.src(*b_fire))
    p.op("LDI", imm=q(TTL))
    p.op("LDIF", imm=0)
    p.op("RC", "rc173", imm=q(k(2.2e3 * 47e-6)))
    p.op("MULI", imm=q(par(10e3, 2.2e3) / 2.2e3))
    p.op("ST", "cvf")
    p.op("BIT", 0, p.src(*b_noise))
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
    p.op("BIT", 0, p.src(*b_fire))
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
    # output coupling cap into the mix (high-pass, time constant fhp_tau)
    p.op("RC", "fhp", imm=q(k(fhp_tau)))
    p.op("LD", "fr")
    p.op("SUB", "fhp")
    p.op("ST", "fire_o")



def noise_bp(p, pre, b_en, b_noise, r1, cdis, vref, r2=22e3, rf=470e3, c1=0.01e-6, c2=0.01e-6):
    """Galaxian HIT channel: EN -> diode -> cap cdis (charge instant), switched by NOISE (4066) into an LM324 MFB
    band-pass (input R1 / R2 to vref, feedback rf, c1 / c2), bilinear biquad (MAME form). Registers pre_*; leaves
    pre_o = op-amp output (V, clamped 0 .. 3.5)."""
    par = dsnd.par
    p.op("BIT", 0, p.src(*b_en))
    p.op("LDI", imm=0)
    p.op("LDIF", imm=q(VU))
    p.op("ST", pre + "_u")
    p.op("BIT", 0, p.src(*b_noise))
    s = p.skip_if(True)
    p.op("LD", pre + "_u")                               # NOISE low: switch open, cap only charges
    p.op("CMP", pre + "_cap")
    p.op("LD", pre + "_cap")
    p.op("LDF", pre + "_u")
    p.op("ST", pre + "_cap")
    p.op("LDI", imm=0)
    p.op("ST", pre + "_h")
    j = p.jump()
    p.land(s)
    p.op("LD", pre + "_u")
    p.op("CMP", pre + "_cap")
    s2 = p.skip_if(True)
    p.op("LD", pre + "_u")                               # discharging through R35 + R36
    p.op("RC", pre + "_cap", imm=q(k((r1 + r2) * cdis)))
    j2 = p.jump()
    p.land(s2)
    p.op("LD", pre + "_u")
    p.op("ST", pre + "_cap")
    p.land(j2)
    p.op("LD", pre + "_cap")
    p.op("ST", pre + "_h")
    p.land(j)
    rt = par(r1, r2)
    vpmax = 5.0 - 1.5
    fc = 1.0 / (2 * 3.141592653589793 * (rt * rf * c1 * c2) ** 0.5)
    dd = (c1 + c2) / (rf / rt * c1 * c2) ** 0.5
    gain = -rf / rt * c1 / (c1 + c2)
    import math
    wc = FS * 2.0 * math.tan(math.pi * fc / FS)
    tT = 2 * FS
    den = tT * tT + dd * wc * tT + wc * wc
    a1 = 2.0 * (-tT * tT + wc * wc) / den
    a2 = (tT * tT - dd * wc * tT + wc * wc) / den
    b0 = dd * wc * tT / den * gain
    p.op("LD", pre + "_h")                               # input divider R35 / R36, biquad (MAME bilinear form)
    p.op("ADDI", imm=q(-vref))
    p.op("MULI", imm=q(rt / r1))
    p.op("ADDI", imm=q(-vref * (1.0 - rt / r1)))
    p.op("ST", pre + "_bx")
    p.op("MULI", imm=q(b0))
    p.op("MACI", pre + "_bx2", imm=q(-b0))
    p.op("MACI", pre + "_by1", imm=q(-a1))
    p.op("MACI", pre + "_by2", imm=q(-a2))
    p.op("ADDI", imm=q(vref))
    p.op("MAXI", imm=0)
    p.op("MINI", imm=q(vpmax))
    p.op("ST", pre + "_o")
    p.op("LD", pre + "_by1")
    p.op("ST", pre + "_by2")
    p.op("LD", pre + "_o")
    p.op("ADDI", imm=q(-vref))
    p.op("ST", pre + "_by1")
    p.op("LD", pre + "_bx1")
    p.op("ST", pre + "_bx2")
    p.op("LD", pre + "_bx")
    p.op("ST", pre + "_bx1")



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
    # 3 x 10k into C20 (0.1 uF); the 555 output high = 4.5 V
    p.op("LD", "bg_in")
    p.op("MULI", imm=q(4.5 / 3))
    p.op("RC", "bgmix", imm=q(k(par(10e3, 10e3, 10e3) * 0.1e-6)))

    fire(p, (B1, 0), (B1, 3), (2.2e3 if mc else par(2.2e3, 10e3)) * 0.01e-6)   # C26 into R43 (|| R91 on Galaxian)

    # hit: HIT -> C21 2.2 uF, gated by NOISE (4066 7R) into the R35 150k MFB band-pass
    noise_bp(p, "hit", (B0, 7), (B1, 3), 150e3, 2.2e-6, 2.0)

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
    p.op("RC", "amp", imm=q(k(100e3 * 0.1e-6)))       # C46 output coupling
    p.op("LD", "mix")
    p.op("SUB", "amp")
    p.op("OUT")
    p.finish()
    return p


def sbhoei():
    """Space Battle (Hoei / Sun SB-002U) discrete sound, step 1 = exact port of the pre-dsnd RTL (MAME sbhoei_discrete):
    three Galaxian-HIT noise band-passes, the Galaxian fire circuit, the pitch DAC, one resistor mix node. Sources from
    rtl/boards/sbhoei_snd/galaxian_sbsound.sv:
      byte 0: [0] noise 3 enable (A803), [1] noise 1 enable (A000), [2] noise 2 enable (A001), [3] NOISE 2V latch,
              [4] NOISE 64H latch, [5] NOISE 4V latch, [6] FIRE (A805)      byte 1: [1:0] VOL1 / VOL2 (A806 / A807)
      bytes 2 / 3 / 4: 393 QA / QC / QD high count over the sample (0 .. 32)"""
    p = Board("sbhoei")
    par = dsnd.par
    p.init("fi_ff", 1.0)
    vref = 5.0 * 33e3 / (22e3 + 33e3)                    # R76 / R77 band-pass bias
    # noise 3 (R62 150k, C22 2.2 uF, NOISE 2V), noise 1 (R68 100k, C26 1 uF, 64H), noise 2 (R64 100k, C19 1 uF, 4V)
    noise_bp(p, "n3", (B0, 0), (B0, 3), 150e3, 2.2e-6, vref)
    noise_bp(p, "n1", (B0, 1), (B0, 4), 100e3, 1.0e-6, vref)
    noise_bp(p, "n2", (B0, 2), (B0, 5), 100e3, 1.0e-6, vref)
    # each band-pass into the mix through 0.1 uF + 2.2k (|| R91 10k): high-pass, summed
    khp = q(k(par(2.2e3, 10e3) * 0.1e-6))
    p.op("LD", "n3_o")
    p.op("RC", "n3_hp", imm=khp)
    p.op("LD", "n3_o")
    p.op("SUB", "n3_hp")
    p.op("ST", "hs")
    for c in ("n1", "n2"):
        p.op("LD", c + "_o")
        p.op("RC", c + "_hp", imm=khp)
        p.op("LD", c + "_o")
        p.op("SUB", c + "_hp")
        p.op("ADD", "hs")
        p.op("ST", "hs")
    # fire: the Galaxian circuit, CV noise = the 2V latch; into the mix through 0.1 uF + 4.7k (|| R91)
    fire(p, (B0, 6), (B0, 3), par(4.7e3, 10e3) * 0.1e-6)
    # pitch: QA -> 120k, QC -> 82k (+ 39k on VOL1), QD -> 62k on VOL2; conductances in 1/kohm
    cnt = 1.0 / 32 * 256
    p.op("LDL", 0, p.src(BQA, 0))
    p.op("MULI", imm=q(cnt * TTL / 120))
    p.op("ST", "num")
    p.op("BIT", 0, p.src(B1, 0))
    p.op("LDI", imm=q(1 / 82))
    p.op("LDIF", imm=q(1 / 82 + 1 / 39))
    p.op("ST", "_t")
    p.op("LDL", 0, p.src(BQC, 0))
    p.op("MULI", imm=q(cnt * TTL))
    p.op("MUL", "_t")
    p.op("ADD", "num")
    p.op("ST", "num")
    p.op("LDL", 0, p.src(BQD, 0))
    p.op("MULI", imm=q(cnt * TTL / 62))
    p.op("ST", "_t")
    p.op("BIT", 0, p.src(B1, 1))
    p.op("LDI", imm=0)
    p.op("LDF", "_t")
    p.op("ADD", "num")
    p.op("ST", "num")
    p.op("LD", "hs")
    p.op("MULI", imm=q(1 / 2.2))
    p.op("ADD", "num")
    p.op("ST", "num")
    p.op("LD", "fire_o")
    p.op("MULI", imm=q(1 / 4.7))
    p.op("ADD", "num")
    p.op("ST", "num")
    gfix = 1 / 120 + 1 / 82 + 3 / 2.2 + 1 / 4.7 + 1 / 10
    p.op("BIT", 0, p.src(B1, 0))
    p.op("LDI", imm=q(gfix))
    p.op("LDIF", imm=q(gfix + 1 / 39))
    p.op("ST", "_t")
    p.op("BIT", 0, p.src(B1, 1))
    p.op("LDI", imm=0)
    p.op("LDIF", imm=q(1 / 62))
    p.op("ADD", "_t")
    p.op("RCP")
    p.op("MUL", "num")
    p.op("ST", "mix")
    p.op("RC", "amp", imm=q(k(100e3 * 0.1e-6)))       # C46 output coupling (MAME 100k)
    p.op("LD", "mix")
    p.op("SUB", "amp")
    p.op("OUT")
    p.finish()
    return p


def galaxian():
    return board(False)


def mooncrst():
    return board(True)
