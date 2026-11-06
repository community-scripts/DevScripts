#!/usr/bin/env python3
"""Exercise device selection against synthetic sysfs and Proxmox configuration."""

import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ("moonlight-vm",)


class PassthroughTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.pci = self.root / "pci"
        self.usb = self.root / "usb"
        self.config = self.root / "config"
        self.bin = self.root / "sbin"
        self.units = self.root / "units"
        for path in (self.pci, self.usb, self.config, self.bin, self.units):
            path.mkdir()
        self.gpu()
        self.gpu("0000:01:00.1", "0x040300")
        self.usb_device()

    def gpu(self, address="0000:01:00.0", pci_class="0x030000", driver="vfio-pci", group="7"):
        device = self.pci / address
        device.mkdir(exist_ok=True)
        (device / "class").write_text(pci_class)
        (device / "boot_vga").write_text("0")
        (device / "vendor").write_text("0x1002")
        (device / "device").write_text("0x15dd")
        (device / "reset_method").write_text("flr bus")
        drivers = self.root / "drivers" / driver
        drivers.mkdir(parents=True, exist_ok=True)
        if (device / "driver").is_symlink():
            (device / "driver").unlink()
        (device / "driver").symlink_to(drivers)
        group_path = self.root / "groups" / group
        (group_path / "devices").mkdir(parents=True, exist_ok=True)
        (device / "iommu_group").symlink_to(group_path)
        (group_path / "devices" / address).symlink_to(device)
        return device

    def usb_device(self, port="1-2", usb_class="00", interface_class="03"):
        device = self.usb / port
        device.mkdir(exist_ok=True)
        for name, value in {"idVendor": "1234", "idProduct": "5678", "bDeviceClass": usb_class, "product": "Test controller"}.items():
            (device / name).write_text(value)
        interface = self.usb / f"{port}:1.0"
        interface.mkdir(exist_ok=True)
        (interface / "bInterfaceClass").write_text(interface_class)

    def run_case(self, slug, body="select_passthrough && attach_passthrough", **env):
        source = (ROOT / "vm" / f"{slug}.sh").read_text()
        functions = []
        for name in ("validate_gpu_passthrough", "validate_usb_passthrough", "select_passthrough", "attach_passthrough", "validate_raven_reset_guard", "install_raven_reset_guard"):
            match = re.search(rf"^function {name}\(\) \{{\n.*?^\}}", source, re.M | re.S)
            self.assertIsNotNone(match, name)
            functions.append(match.group())
        code = "\n".join(functions)
        code = code.replace("/sys/bus/pci/devices", str(self.pci))
        code = code.replace("/sys/bus/usb/devices", str(self.usb))
        code = code.replace("/etc/pve/qemu-server", str(self.config))
        code = code.replace("/usr/local/sbin", str(self.bin))
        code = code.replace("/etc/systemd/system", str(self.units))
        preamble = r'''
set -Eeuo pipefail
msg_error() { echo "ERROR: $*" >&2; }
msg_info() { :; }
msg_ok() { :; }
qm() { echo "qm $*" >>"$EVENTS"; }
systemctl() { echo "systemctl $*" >>"$EVENTS"; }
lspci() { echo "Synthetic GPU $*"; }
exit_script() { exit 130; }
vm_dialog() {
  echo "dialog $*" >&2
  case "$2" in
    "GPU PASSTHROUGH")
      [[ "${CANCEL:-}" != gpu ]] || return 1
      VM_DIALOG_RESULT="${PICK_GPU:-none}"
      ;;
    "USB PASSTHROUGH")
      [[ "${CANCEL:-}" != usb ]] || return 1
      VM_DIALOG_RESULT="${PICK_USB:-none}"
      ;;
    "CONFIRM DEVICE ASSIGNMENT") [[ "${CANCEL:-}" != confirm ]] || return 1 ;;
    *) return 2 ;;
  esac
}
'''
        events = self.root / "events"
        events.unlink(missing_ok=True)
        variables = {"PATH": os.environ["PATH"], "EVENTS": str(events), "NSAPP": slug, "VMID": "100", "VM_UNATTENDED": "1", "VM_PASSTHROUGH_CONFIRM": "yes", **env}
        result = subprocess.run(["bash", "-c", preamble + code + "\n" + body], env=variables, text=True, capture_output=True, timeout=10)
        if events.exists():
            result.stdout += events.read_text()
        return result

    def assert_rejected(self, **env):
        for slug in SCRIPTS:
            with self.subTest(slug=slug, env=env):
                result = self.run_case(slug, VM_GPU_PCI="0000:01:00.0", **env)
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("qm ", result.stdout)

    def test_no_automatic_assignment(self):
        for slug in SCRIPTS:
            result = self.run_case(slug)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("qm ", result.stdout)

    def test_only_selected_display_function_is_attached(self):
        for slug in SCRIPTS:
            result = self.run_case(slug, VM_GPU_PCI="01:00.0")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "qm set 100 --hostpci0 0000:01:00.0,pcie=1 --vga serial0")

    def test_unattended_requires_confirmation(self):
        self.assert_rejected(VM_PASSTHROUGH_CONFIRM="no")

    def test_missing_iommu(self):
        (self.pci / "0000:01:00.0" / "iommu_group").unlink()
        self.assert_rejected()

    def test_unrelated_iommu_device(self):
        self.gpu("0000:02:00.0", "0x010802")
        self.assert_rejected()

    def test_bridge_in_group_is_allowed_but_not_attached(self):
        self.gpu("0000:00:01.0", "0x060400", driver="pcieport")
        for slug in SCRIPTS:
            result = self.run_case(slug, VM_GPU_PCI="01:00.0")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("0000:00:01", result.stdout)

    def test_host_driver_is_not_unbound(self):
        device = self.pci / "0000:01:00.1" / "driver"
        device.unlink()
        device.symlink_to(self.root / "drivers" / "snd_hda_intel")
        self.assert_rejected()

    def test_boot_gpu_is_not_taken(self):
        (self.pci / "0000:01:00.0" / "boot_vga").write_text("1")
        self.assert_rejected()

    def test_prepared_boot_gpu_requires_explicit_override(self):
        (self.pci / "0000:01:00.0" / "boot_vga").write_text("1")
        result = self.run_case("moonlight-vm", VM_GPU_PCI="01:00.0", VM_ALLOW_BOOT_GPU="yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--hostpci0 0000:01:00.0,pcie=1 --vga serial0", result.stdout)

    def test_unrelated_slot_functions_in_other_groups_are_not_claimed(self):
        self.gpu("0000:01:00.2", "0x108000", driver="ccp", group="8")
        result = self.run_case("moonlight-vm", VM_GPU_PCI="01:00.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("01:00.2", result.stdout)

    def test_reset_guard_is_opt_in_and_hardware_scoped(self):
        body = "select_passthrough && install_raven_reset_guard"
        result = self.run_case("moonlight-vm", body=body, VM_GPU_PCI="01:00.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(self.units.iterdir()), [])
        (self.pci / "0000:01:00.0" / "device").write_text("0x9999")
        result = self.run_case("moonlight-vm", body=body, VM_GPU_PCI="01:00.0", VM_RAVEN_RESET_GUARD="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.units.iterdir()), [])
        self.assertNotIn("systemctl ", result.stdout)

    def test_reset_guard_rejects_no_gpu_and_invalid_options(self):
        for options in ({"VM_RAVEN_RESET_GUARD": "yes"}, {"VM_RAVEN_RESET_GUARD": "maybe"}, {"VM_ALLOW_BOOT_GPU": "maybe"}):
            result = self.run_case("moonlight-vm", **options)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("qm ", result.stdout)

    def test_reset_guard_runs_before_autostart_and_checks_device_identity(self):
        result = self.run_case("moonlight-vm", body="select_passthrough && install_raven_reset_guard", VM_GPU_PCI="01:00.0", VM_RAVEN_RESET_GUARD="yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        unit = self.units / "moonlight-raven-reset-100.service"
        self.assertIn("Before=pve-guests.service", unit.read_text())
        self.assertIn("After=systemd-udev-trigger.service", unit.read_text())
        script = self.bin / "moonlight-raven-reset-100"
        reset = self.pci / "0000:01:00.0" / "reset_method"
        run = subprocess.run(["sh", str(script)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(reset.read_text(), "\n")
        # Repeated boots remain harmless; a different device at the address is refused.
        run = subprocess.run(["sh", str(script)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        reset.write_text("flr bus")
        (self.pci / "0000:01:00.0" / "device").write_text("0x9999")
        run = subprocess.run(["sh", str(script)], capture_output=True, text=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(reset.read_text(), "flr bus")

    def test_existing_assignment_forms(self):
        for value in ("0000:01:00.0,pcie=1", "01:00,pcie=1", "host=01:00.1", "03:00.0;01:00.1,pcie=1", "mapping=render-gpu"):
            with self.subTest(value=value):
                (self.config / "101.conf").write_text(f"hostpci0: {value}\n")
                self.assert_rejected()

    def test_invalid_gpu_values(self):
        for slug in SCRIPTS:
            for address in ("../../etc/passwd", "01:00", "0000:01:00.1", "01:00.8", "01:00.0,pcie=1"):
                result = self.run_case(slug, VM_GPU_PCI=address)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("qm ", result.stdout)

    def test_gpu_ownership_is_checked_again_before_attachment(self):
        for slug in SCRIPTS:
            config = self.config / "102.conf"
            config.unlink(missing_ok=True)
            result = self.run_case(slug, body=f'select_passthrough && echo "hostpci0: 01:00" > "{config}" && attach_passthrough', VM_GPU_PCI="01:00.0")
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("qm ", result.stdout)

    def test_usb_physical_port_assignment(self):
        result = self.run_case("moonlight-vm", VM_USB_PORTS="1-2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "qm set 100 --usb0 host=1-2,usb3=1")

    def test_usb_invalid_or_duplicate(self):
        for value in ("1-2,1-2", "1-9", "usb1", "1-2,", ",1-2", "1-2,,1-3", "1-2,usb3=1"):
            result = self.run_case("moonlight-vm", VM_USB_PORTS=value)
            self.assertNotEqual(result.returncode, 0, value)
            self.assertNotIn("qm ", result.stdout)

    def test_usb_storage_network_and_hubs_are_rejected(self):
        for usb_class in ("08", "09", "02", "0a"):
            (self.usb / "1-2:1.0" / "bInterfaceClass").write_text(usb_class)
            result = self.run_case("moonlight-vm", VM_USB_PORTS="1-2")
            self.assertNotEqual(result.returncode, 0, usb_class)
            self.assertNotIn("qm ", result.stdout)

    def test_usb_existing_assignment(self):
        for value in ("host=1-2,usb3=1", "host=1-2", "host=1234:5678", "mapping=controller"):
            (self.config / "101.conf").write_text(f"usb0: {value}\n")
            result = self.run_case("moonlight-vm", VM_USB_PORTS="1-2")
            self.assertNotEqual(result.returncode, 0, value)
            self.assertNotIn("qm ", result.stdout)

    def test_usb_similar_port_is_not_a_conflict(self):
        (self.config / "101.conf").write_text("usb0: host=1-20,usb3=1\n")
        result = self.run_case("moonlight-vm", VM_USB_PORTS="1-2")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_usb_requires_unattended_confirmation(self):
        result = self.run_case("moonlight-vm", VM_USB_PORTS="1-2", VM_PASSTHROUGH_CONFIRM="no")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("qm ", result.stdout)

    def test_interactive_default_and_cancellation(self):
        for slug in SCRIPTS:
            result = self.run_case(slug, VM_UNATTENDED="0")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("qm ", result.stdout)
            self.assertIn("none Configure GPU later (no hardware acceleration promised) ON", result.stderr)
            for cancel in (("gpu", "confirm", "usb") if slug == "moonlight-vm" else ("gpu", "confirm")):
                result = self.run_case(slug, VM_UNATTENDED="0", CANCEL=cancel, PICK_GPU="01:00.0")
                self.assertEqual(result.returncode, 130, result.stderr)
                self.assertNotIn("qm ", result.stdout)


class FirstBootTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def render(self, slug):
        source = (ROOT / "vm" / f"{slug}.sh").read_text()
        match = re.search(r'cat >"\$(MOONLIGHT_SETUP_TMP)" <<FIRSTBOOT\n.*?\nFIRSTBOOT', source, re.S)
        self.assertIsNotNone(match)
        guest = self.root / f"{slug}-guest.sh"
        env = {"PATH": os.environ["PATH"], match.group(1): str(guest),
               "CLOUDINIT_USER": "streamuser", "VM_CLIENT_AUTOSTART": "yes",
               "VM_DESKTOP_AUTOLOGIN": "yes", "VM_RELEASE_ASSET": "Moonlight-6.2.0-x86_64.AppImage",
               "VM_RELEASE_VERSION": "6.2.0"}
        result = subprocess.run(["bash", "-eu", "-c", match.group()], env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return guest

    def test_guest_scripts_render_for_selected_user_and_parse(self):
        for slug in SCRIPTS:
            with self.subTest(slug=slug):
                guest = self.render(slug)
                self.assertIn('GUEST_USER="streamuser"', guest.read_text())
                result = subprocess.run(["bash", "-n", str(guest)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_guest_shellcheck(self):
        checker = os.environ.get("VM_TEST_SHELLCHECK") or shutil.which("shellcheck")
        if not checker:
            self.skipTest("ShellCheck is not installed")
        for slug in SCRIPTS:
            with self.subTest(slug=slug):
                result = subprocess.run([checker, "--severity=warning", str(self.render(slug))], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def heredoc(self, name):
        guest = self.render("moonlight-vm").read_text()
        match = re.search(rf"<<'{name}'\n(.*?)\n{name}$", guest, re.M | re.S)
        self.assertIsNotNone(match, name)
        return match.group(1)

    def test_xorg_starts_only_on_local_tty1(self):
        profile = self.heredoc("PROFILE_KIOSK")
        for tty, display, expected in (("/dev/tty1", "", True), ("/dev/ttyS0", "", False),
                                       ("/dev/pts/0", "", False), ("/dev/tty1", ":0", False)):
            with self.subTest(tty=tty, display=display):
                code = 'tty() { echo "$TEST_TTY"; }\n' + profile
                # An executable is needed because the real profile uses exec.
                command = self.root / "startx"
                command.write_text('#!/bin/sh\necho "STARTX $*"\n')
                command.chmod(0o755)
                env = {"PATH": f'{self.root}:{os.environ["PATH"]}', "DISPLAY": display, "TEST_TTY": tty}
                result = subprocess.run(["bash", "-c", code], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual("STARTX -- -nolisten tcp" in result.stdout, expected)

    def test_shell_configuration_is_preserved_and_not_appended_twice(self):
        guest = self.render("moonlight-vm").read_text()
        profile = re.search(r"^KIOSK_MARKER=.*?(?=^BASH_IT_SRC=)", guest, re.M | re.S).group()
        bashrc = re.search(r"^BASHIT_MARKER=.*?(?=^GETTY_DROPIN=)", guest, re.M | re.S).group()
        existing = {".bash_profile": "export EXISTING_PROFILE=yes\n", ".bashrc": "alias existing_alias=true\n"}
        for name, value in existing.items():
            (self.root / name).write_text(value)
        env = {"PATH": os.environ["PATH"], "USER_HOME": str(self.root), "GUEST_USER": "streamuser"}
        code = 'chown() { :; }\n' + profile + bashrc
        for _ in range(2):
            result = subprocess.run(["bash", "-eu", "-c", code], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        for name, value in existing.items():
            self.assertTrue((self.root / name).read_text().startswith(value))
            self.assertEqual((self.root / f"{name}.bak").read_text(), value)
        self.assertEqual((self.root / ".bash_profile").read_text().count("exec startx"), 1)
        self.assertEqual((self.root / ".bashrc").read_text().count('. "$BASH_IT/bash_it.sh"'), 1)
        self.assertIn("export BASH_IT_THEME=pure", (self.root / ".bashrc").read_text())

    def test_moonlight_is_relaunched_logged_and_fullscreened(self):
        snippet = self.heredoc("AUTOSTART_MOONLIGHT")
        commands = self.root / "commands"
        commands.mkdir()
        events = self.root / "events"
        for command, body in {
            "moonlight": 'echo launch >>"$EVENTS"; echo app-output; exit 1',
            "wmctrl": 'echo "wmctrl $*" >>"$EVENTS"',
            "sleep": 'echo "sleep $*" >>"$EVENTS"; /bin/sleep 0.05',
        }.items():
            path = commands / command
            path.write_text("#!/bin/sh\n" + body + "\n")
            path.chmod(0o755)
        snippet = snippet.replace("/usr/local/bin/moonlight", str(commands / "moonlight"))
        snippet = snippet.replace("$HOME", "$TEST_USER_HOME")
        env = {"PATH": f'{commands}:{os.environ["PATH"]}', "EVENTS": str(events), "TEST_USER_HOME": str(self.root)}
        process = subprocess.Popen(["sh", "-c", snippet + "\nwait"], env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                output = events.read_text() if events.exists() else ""
                if output.count("launch\n") >= 2 and "wmctrl -r Moonlight -b add,fullscreen" in output:
                    break
                time.sleep(0.02)
            self.assertGreaterEqual(output.count("launch\n"), 2, output)
            self.assertIn("sleep 3", output)
            self.assertIn("wmctrl -r Moonlight -b add,fullscreen", output)
            self.assertIn("app-output", (self.root / ".local/state/moonlight-kiosk.log").read_text())
        finally:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)

    def test_launcher_uses_gui_and_scopes_vaapi_override_to_amd(self):
        pci = self.root / "pci"
        pci.mkdir()
        app = self.root / "app"
        app.write_text('#!/usr/bin/env python3\nimport json,os,sys\nprint(json.dumps({"driver":os.getenv("LIBVA_DRIVER_NAME"),"scale":os.getenv("QT_SCALE_FACTOR"),"vulkan":os.getenv("PREFER_VULKAN"),"args":sys.argv[1:]}))\n')
        app.chmod(0o755)
        launcher = self.root / "launcher"
        launcher.write_text(self.heredoc("LAUNCHER").replace("/sys/bus/pci/devices", str(pci))
                            .replace("/opt/moonlight/Moonlight.AppImage", str(app)))
        config = self.root / "config"
        config.write_text("PREFER_VULKAN=1\nQT_SCALE_FACTOR=2.5\n")
        device = pci / "0000:01:00.0"
        device.mkdir()
        for driver, override, expected in (("i915", "", None), ("amdgpu", "", "radeonsi"), ("amdgpu", "custom", "custom")):
            with self.subTest(driver=driver, override=override):
                (device / "driver").unlink(missing_ok=True)
                target = self.root / "drivers" / driver
                target.mkdir(parents=True, exist_ok=True)
                (device / "driver").symlink_to(target)
                env = {"PATH": os.environ["PATH"], "MOONLIGHT_KIOSK_CONF": str(config)}
                if override:
                    env["LIBVA_DRIVER_NAME"] = override
                result = subprocess.run(["sh", str(launcher)], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                data = json.loads(result.stdout)
                self.assertEqual(data, {"driver": expected, "scale": "2.5", "vulkan": "1", "args": []})
        config.write_text("PREFER_VULKAN=0\nQT_SCALE_FACTOR=1.5\n")
        result = subprocess.run(["sh", str(launcher), "--help"], env=env, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        self.assertEqual((data["scale"], data["vulkan"], data["args"]), ("1.5", "0", ["--help"]))

    def test_display_prefers_available_4k60_and_survives_mode_failure(self):
        commands = self.root / "commands"
        commands.mkdir()
        for command, body in {
            "xset": 'echo "xset $*" >>"$EVENTS"',
            "xrandr": 'if [ "$1" = --query ]; then cat "$EDID"; else echo "xrandr $*" >>"$EVENTS"; exit 1; fi',
            "unclutter": 'echo "unclutter $*" >>"$EVENTS"',
        }.items():
            path = commands / command
            path.write_text("#!/bin/sh\n" + body + "\n")
            path.chmod(0o755)
        edid = self.root / "edid"
        events = self.root / "events"
        for modes, expected in (("   3840x2160 60.00*+ 59.94\n", True),
                                ("   1920x1080 60.00*+\n", False), ("   3840x2160 30.00\n", False)):
            with self.subTest(modes=modes):
                edid.write_text("DisplayPort-1 connected primary\n" + modes + "HDMI-1 disconnected\n")
                events.unlink(missing_ok=True)
                env = {"PATH": f'{commands}:{os.environ["PATH"]}', "EVENTS": str(events), "EDID": str(edid)}
                result = subprocess.run(["sh", "-c", self.heredoc("AUTOSTART")], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                output = events.read_text()
                self.assertEqual("xrandr --output DisplayPort-1 --mode 3840x2160 --rate 60" in output, expected)
                for action in ("xset s off", "xset s noblank", "xset -dpms", "unclutter --timeout 1 --start-hidden --fork"):
                    self.assertIn(action, output)

    def test_debian_components_are_added_per_stanza_without_duplicates(self):
        guest = self.render("moonlight-vm").read_text()
        block = re.search(r"for component in contrib non-free non-free-firmware; do\n.*?\ndone", guest, re.S).group()
        apt = self.root / "apt"
        (apt / "sources.list.d").mkdir(parents=True)
        sources = apt / "sources.list.d" / "debian.sources"
        sources.write_text("Types: deb\nComponents: main contrib\n\nTypes: deb\nComponents: main non-free-firmware\n")
        block = block.replace("/etc/apt", str(apt))
        for _ in range(2):
            subprocess.run(["bash", "-eu", "-c", block], check=True)
        for line in sources.read_text().splitlines():
            if line.startswith("Components:"):
                self.assertEqual(sorted(line.split()[1:]), sorted(("main", "contrib", "non-free", "non-free-firmware")))



if __name__ == "__main__":
    unittest.main(verbosity=2)
