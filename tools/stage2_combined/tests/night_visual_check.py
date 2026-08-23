import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_check as rc
from banked_helpers import get_out, fresh_cpu, step_frame

out, sym, text = get_out()
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False

for f in range(2100):
    step_frame(cpu)

print("NIGHT_ROW =", cpu.mem[sym["NIGHT_ROW"]], "GAME_TICK =",
      cpu.mem[sym["GAME_TICK"]] | (cpu.mem[sym["GAME_TICK"]+1] << 8))
rc.render_full(cpu.vram, "night_check.ppm")
print("rendered")
