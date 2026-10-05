"""Fixtures shared by the test modules: a fake sysfs builder and a fake clock."""

from pathlib import Path

DGPU = 0x7550
IGPU = 0x164E
SCLK = "0: 500Mhz\n1: 2400Mhz *\n2: 2900Mhz\n"


def make_card(root, card, device_id, hwmon, power_uw=100_000_000, temp_mc=55_000,
              sclk=SCLK, busy=42, with_temp=True, with_power=True):
    dev = Path(root) / "class" / "drm" / card / "device"
    (dev / "hwmon" / hwmon).mkdir(parents=True)
    (dev / "device").write_text(f"0x{device_id:04x}\n")
    (dev / "pp_dpm_sclk").write_text(sclk)
    (dev / "gpu_busy_percent").write_text(f"{busy}\n")
    if with_power:
        (dev / "hwmon" / hwmon / "power1_average").write_text(f"{power_uw}\n")
    if with_temp:
        (dev / "hwmon" / hwmon / "temp1_input").write_text(f"{temp_mc}\n")
    return dev


class FakeClock:
    def __init__(self):
        self.now = 1000.0
        self.sleeps = []

    WALL_OFFSET = 1_700_000_000.0

    def clock(self):
        return self.now

    def wall(self):
        return self.now + self.WALL_OFFSET

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds
