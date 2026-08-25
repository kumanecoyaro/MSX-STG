import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine, step_frame

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

DASH_ACTIVE = sym["DASH_ACTIVE"]
DASH_DIR = sym["DASH_DIR"]
DASH_REMAINING = sym["DASH_REMAINING"]
DASH_DIST = sym["DASH_DIST"]
DASH_SPEED = sym["DASH_SPEED"]
DASH_SPRITE_Y_SHIFT = sym["DASH_SPRITE_Y_SHIFT"]
TANK_TOP_DRAW_Y = sym["TANK_TOP_DRAW_Y"]
TANK_X = sym["TANK_X"]
TANK_FACING = sym["TANK_FACING"]
TANK_DRAW_Y = sym["TANK_DRAW_Y"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
TANK_DX = sym["TANK_DX"]
JOY_DIR = sym["JOY_DIR"]
JOY_TRIGB = sym["JOY_TRIGB"]
PREV_TRIGB = sym["PREV_TRIGB"]
JUMP_ACTIVE = sym["JUMP_ACTIVE"]
SPRITE_ATTRS = sym["SPRITE_ATTRS"]
TANK_X_INIT = sym["TANK_X_INIT"]


def press_b(cpu, held_before=0):
    """Simulates a fresh B-button press this frame (PREV_TRIGB reflects
    last frame's own value, JOY_TRIGB is the new one)."""
    cpu.mem[PREV_TRIGB] = held_before
    cpu.mem[JOY_TRIGB] = 0xFF


def sprite_attrs(cpu):
    b = SPRITE_ATTRS
    return {
        "TL": (cpu.mem[b + 0], cpu.mem[b + 1]),
        "TR": (cpu.mem[b + 4], cpu.mem[b + 5]),
        "BL": (cpu.mem[b + 8], cpu.mem[b + 9]),
        "BR": (cpu.mem[b + 12], cpu.mem[b + 13]),
    }


# ---- UPDATE_DASH: trigger gating ("上下左右入力の下を入れたままジャン
# プのBボタンを押すと") ----
cpu = fresh_cpu()
cpu.mem[JOY_DIR] = 5   # pure down
cpu.mem[TANK_FACING] = 0   # facing right
press_b(cpu)
call_routine(cpu, "UPDATE_DASH")
check("UPDATE_DASH starts a dash on a fresh B press while DOWN is held",
      cpu.mem[DASH_ACTIVE] == 1)
check("UPDATE_DASH freezes DASH_DIR at the current TANK_FACING",
      cpu.mem[DASH_DIR] == 0)
check("UPDATE_DASH arms DASH_REMAINING at DASH_DIST(64)",
      cpu.mem[DASH_REMAINING] == DASH_DIST)

cpu = fresh_cpu()
cpu.mem[JOY_DIR] = 3   # right, not down
press_b(cpu)
call_routine(cpu, "UPDATE_DASH")
check("UPDATE_DASH does NOT start a dash without DOWN held (JOY_DIR!=5)",
      cpu.mem[DASH_ACTIVE] == 0)

# ---- round28: "斜め下でもダッシュできるように 現在は真下のみなんで" -
# widened to accept JOY_DIR 4(downright)/6(downleft) alongside the
# existing 5(pure down); the dash's own movement direction still comes
# from TANK_FACING, unchanged by which "down" variant triggered it ----
for down_dir, name in ((4, "downright"), (6, "downleft")):
    cpu = fresh_cpu()
    cpu.mem[JOY_DIR] = down_dir
    cpu.mem[TANK_FACING] = 1   # facing left
    press_b(cpu)
    call_routine(cpu, "UPDATE_DASH")
    check(f"UPDATE_DASH starts a dash on a fresh B press while a down-diagonal "
          f"(JOY_DIR={down_dir}, {name}) is held",
          cpu.mem[DASH_ACTIVE] == 1)
    check(f"UPDATE_DASH ({name}) still freezes DASH_DIR at TANK_FACING, not the "
          "diagonal input itself", cpu.mem[DASH_DIR] == 1)
    check(f"UPDATE_DASH ({name}) still arms DASH_REMAINING at DASH_DIST(64)",
          cpu.mem[DASH_REMAINING] == DASH_DIST)

# the 2 UP-diagonals must NOT trigger a dash - only the 3 down-ish
# directions (4/5/6) do
for up_dir in (2, 8):
    cpu = fresh_cpu()
    cpu.mem[JOY_DIR] = up_dir
    press_b(cpu)
    call_routine(cpu, "UPDATE_DASH")
    check(f"UPDATE_DASH does NOT start a dash on an up-diagonal (JOY_DIR={up_dir})",
          cpu.mem[DASH_ACTIVE] == 0)

cpu = fresh_cpu()
cpu.mem[JOY_DIR] = 5
cpu.mem[JUMP_ACTIVE] = 1   # already mid-jump
press_b(cpu)
call_routine(cpu, "UPDATE_DASH")
check("UPDATE_DASH does NOT start a dash while already mid-jump (JUMP_ACTIVE!=0)",
      cpu.mem[DASH_ACTIVE] == 0)

cpu = fresh_cpu()
cpu.mem[JOY_DIR] = 5
cpu.mem[PREV_TRIGB] = 0xFF
cpu.mem[JOY_TRIGB] = 0xFF   # already held (not a NEW press)
call_routine(cpu, "UPDATE_DASH")
check("UPDATE_DASH does NOT start a dash on an already-held B (no new press)",
      cpu.mem[DASH_ACTIVE] == 0)

cpu = fresh_cpu()
cpu.mem[JOY_DIR] = 5
cpu.mem[PREV_TRIGB] = 0
cpu.mem[JOY_TRIGB] = 0   # not pressed at all
call_routine(cpu, "UPDATE_DASH")
check("UPDATE_DASH does NOT start a dash while B isn't pressed", cpu.mem[DASH_ACTIVE] == 0)


# ---- UPDATE_DASH: mutual exclusion with jump - the SAME press must
# never ALSO start a jump ----
cpu = fresh_cpu()
cpu.mem[JOY_DIR] = 5
cpu.mem[TANK_FACING] = 0
press_b(cpu)
call_routine(cpu, "UPDATE_DASH")
call_routine(cpu, "UPDATE_JUMP")
check("UPDATE_JUMP does not ALSO start a jump the same frame a dash starts - 当然...と同時に"
      "ジャンプも, JUMP_ACTIVE stays 0", cpu.mem[JUMP_ACTIVE] == 0)


# ---- UPDATE_DASH: the actual 64px run, DASH_SPEED(3)px/frame, flat ----
cpu = fresh_cpu()
cpu.mem[TANK_X] = 100
cpu.mem[JOY_DIR] = 5
cpu.mem[TANK_FACING] = 0   # right
press_b(cpu)
call_routine(cpu, "UPDATE_DASH")   # arms the dash (no movement this call)
check("arming the dash does not move TANK_X on the same frame", cpu.mem[TANK_X] == 100)

x_trace = [cpu.mem[TANK_X]]
for _ in range(30):
    cpu.mem[PREV_TRIGB] = cpu.mem[JOY_TRIGB]   # simulate a normal, unchanging frame's own input
    call_routine(cpu, "UPDATE_DASH")
    x_trace.append(cpu.mem[TANK_X])
    if cpu.mem[DASH_ACTIVE] == 0:
        break
check("the dash moves the tank exactly DASH_DIST(64)px total, rightward - 今向いてる方向に"
      "倍速で64px移動", x_trace[-1] - x_trace[0] == DASH_DIST)
check("the dash finishes (DASH_ACTIVE=0) once the full 64px is covered",
      cpu.mem[DASH_ACTIVE] == 0)
steps = [x_trace[i + 1] - x_trace[i] for i in range(len(x_trace) - 1)]
check("each dash step moves by DASH_SPEED(3)px, except a possibly-shorter final step - "
      "a flat, literal double-speed run (normal movement averages 1.5px/frame)",
      all(s in (DASH_SPEED, DASH_DIST % DASH_SPEED) or s == DASH_SPEED for s in steps)
      and max(steps) == DASH_SPEED)

# leftward dash
cpu = fresh_cpu()
cpu.mem[TANK_X] = 150
cpu.mem[JOY_DIR] = 5
cpu.mem[TANK_FACING] = 1   # left
press_b(cpu)
call_routine(cpu, "UPDATE_DASH")
start_x = cpu.mem[TANK_X]
for _ in range(30):
    cpu.mem[PREV_TRIGB] = cpu.mem[JOY_TRIGB]
    call_routine(cpu, "UPDATE_DASH")
    if cpu.mem[DASH_ACTIVE] == 0:
        break
check("a leftward dash (TANK_FACING=1) moves exactly 64px to the left",
      start_x - cpu.mem[TANK_X] == DASH_DIST)


# ---- UPDATE_DASH: screen-edge clamps, matching ordinary movement's own
# bounds (not explicitly requested, but avoiding an obviously-bad
# off-screen dash is a sane default - flagged) ----
cpu = fresh_cpu()
cpu.mem[TANK_X] = 200   # close to the right edge
cpu.mem[JOY_DIR] = 5
cpu.mem[TANK_FACING] = 0
press_b(cpu)
call_routine(cpu, "UPDATE_DASH")
for _ in range(30):
    cpu.mem[PREV_TRIGB] = cpu.mem[JOY_TRIGB]
    call_routine(cpu, "UPDATE_DASH")
    if cpu.mem[DASH_ACTIVE] == 0:
        break
check("a rightward dash never pushes TANK_X past the same 224 clamp ordinary movement uses",
      cpu.mem[TANK_X] <= 224)

cpu = fresh_cpu()
cpu.mem[TANK_X] = 10   # close to the left edge
cpu.mem[JOY_DIR] = 5
cpu.mem[TANK_FACING] = 1
press_b(cpu)
call_routine(cpu, "UPDATE_DASH")
for _ in range(30):
    cpu.mem[PREV_TRIGB] = cpu.mem[JOY_TRIGB]
    call_routine(cpu, "UPDATE_DASH")
    if cpu.mem[DASH_ACTIVE] == 0:
        break
check("a leftward dash never underflows TANK_X past 0", cpu.mem[TANK_X] >= 0 and cpu.mem[TANK_X] < 256)


# ---- UPDATE_TANK_XY/UPDATE_JUMP are fully suppressed while dashing ----
cpu = fresh_cpu()
cpu.mem[DASH_ACTIVE] = 1
cpu.mem[TANK_DX] = 0
cpu.mem[JOY_DIR] = 3   # right - would normally set TANK_DX=1
call_routine(cpu, "UPDATE_TANK_XY")
check("UPDATE_TANK_XY is a no-op while DASH_ACTIVE (ordinary joystick input suppressed)",
      cpu.mem[TANK_DX] == 0)

cpu = fresh_cpu()
cpu.mem[DASH_ACTIVE] = 1
cpu.mem[JUMP_ACTIVE] = 0
press_b(cpu)
call_routine(cpu, "UPDATE_JUMP")
check("UPDATE_JUMP is a no-op while DASH_ACTIVE (can't jump mid-dash)",
      cpu.mem[JUMP_ACTIVE] == 0)


# ---- UPDATE_TANK_SPRITES: the visual TL/TR-only 5px shift - "自機スプ
# ライトの上部32x16のスプライトを下に5px下げるように" ----
# UPDATE_TANK_SPRITES itself recomputes TANK_DRAW_Y fresh from TANK_Y_CUR
# every call (poking TANK_DRAW_Y directly would just get overwritten) -
# drive it via TANK_Y_CUR instead and read back whatever real baseline
# it resolves to.
cpu = fresh_cpu()
cpu.mem[TANK_Y_CUR] = 100
cpu.mem[DASH_ACTIVE] = 0
call_routine(cpu, "UPDATE_TANK_SPRITES")
normal = sprite_attrs(cpu)
baseline = cpu.mem[TANK_DRAW_Y]
check("not dashing: TL/TR sit at plain TANK_DRAW_Y (no shift)",
      normal["TL"][0] == baseline and normal["TR"][0] == baseline)
check("not dashing: BL/BR sit at TANK_DRAW_Y+16, same as TL/TR's own baseline+16",
      normal["BL"][0] == baseline + 16 and normal["BR"][0] == baseline + 16)

cpu.mem[DASH_ACTIVE] = 1
call_routine(cpu, "UPDATE_TANK_SPRITES")
dashing = sprite_attrs(cpu)
check("dashing: TL/TR are pushed down by DASH_SPRITE_Y_SHIFT(5), to TANK_DRAW_Y+5",
      dashing["TL"][0] == baseline + DASH_SPRITE_Y_SHIFT
      and dashing["TR"][0] == baseline + DASH_SPRITE_Y_SHIFT)
check("dashing: BL/BR are left completely alone at TANK_DRAW_Y+16 - only the top half "
      "moves, matching '上部32x16のスプライトを下に5px下げる'",
      dashing["BL"][0] == baseline + 16 and dashing["BR"][0] == baseline + 16)

cpu.mem[DASH_ACTIVE] = 0
call_routine(cpu, "UPDATE_TANK_SPRITES")
after = sprite_attrs(cpu)
check("once DASH_ACTIVE clears, TL/TR revert to the plain (unshifted) TANK_DRAW_Y - "
      "ダッシュが終われば元の状態に", after["TL"][0] == baseline and after["TR"][0] == baseline)


# ---- real MAINLOOP: a full dash actually happens end-to-end ----
cpu = fresh_cpu()
cpu.sim_dir = 5          # holding DOWN the whole time
cpu.sim_trig_a = False
cpu.sim_trig_b = False
x0 = cpu.mem[TANK_X]
step_frame(cpu)          # let one ordinary frame pass first (no dash yet - B not pressed)
check("real MAINLOOP: holding DOWN alone (no B) never starts a dash",
      cpu.mem[DASH_ACTIVE] == 0)

cpu.sim_trig_b = True     # now also press B (down still held)
step_frame(cpu)
check("real MAINLOOP: DOWN+B genuinely starts a real dash (DASH_ACTIVE=1)",
      cpu.mem[DASH_ACTIVE] == 1)
saw_shift = cpu.mem[SPRITE_ATTRS + 0] == cpu.mem[TANK_DRAW_Y] + DASH_SPRITE_Y_SHIFT
frames = 0
while cpu.mem[DASH_ACTIVE] == 1 and frames < 60:
    step_frame(cpu)
    frames += 1
    if cpu.mem[SPRITE_ATTRS + 0] == cpu.mem[TANK_DRAW_Y] + DASH_SPRITE_Y_SHIFT:
        saw_shift = True
check("real MAINLOOP: the tank's own TL sprite is visibly shifted down during the dash",
      saw_shift)
check("real MAINLOOP: the dash actually finishes within a real, bounded number of frames",
      cpu.mem[DASH_ACTIVE] == 0 and frames < 60)
check("real MAINLOOP: the tank actually moved (a real 64px dash happened, not a no-op)",
      cpu.mem[TANK_X] != x0)
check("real MAINLOOP: once the dash ends, the TL sprite is back at the plain (unshifted) "
      "TANK_DRAW_Y - ダッシュが終われば元の状態に",
      cpu.mem[SPRITE_ATTRS + 0] == cpu.mem[TANK_DRAW_Y])

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
