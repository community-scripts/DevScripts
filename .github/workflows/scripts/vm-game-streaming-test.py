#!/usr/bin/env python3
"""Exercise device selection against synthetic sysfs and Proxmox configuration."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ("sunshine-vm", "moonlight-vm")


class PassthroughTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.pci = self.root / "pci"
        self.usb = self.root / "usb"
        self.config = self.root / "config"
        for path in (self.pci, self.usb, self.config):
            path.mkdir()
        self.gpu()
        self.gpu("0000:01:00.1", "0x040300")
        self.usb_device()

    def gpu(self, address="0000:01:00.0", pci_class="0x030000", driver="vfio-pci", group="7"):
        device = self.pci / address
        device.mkdir(exist_ok=True)
        (device / "class").write_text(pci_class)
        (device / "boot_vga").write_text("0")
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
        for name in ("validate_gpu_passthrough", "validate_usb_passthrough", "select_passthrough", "attach_passthrough"):
            match = re.search(rf"^function {name}\(\) \{{\n.*?^\}}", source, re.M | re.S)
            self.assertIsNotNone(match, name)
            functions.append(match.group())
        code = "\n".join(functions)
        code = code.replace("/sys/bus/pci/devices", str(self.pci))
        code = code.replace("/sys/bus/usb/devices", str(self.usb))
        code = code.replace("/etc/pve/qemu-server", str(self.config))
        preamble = r'''
set -Eeuo pipefail
msg_error() { echo "ERROR: $*" >&2; }
qm() { echo "qm $*" >>"$EVENTS"; }
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

    def test_gpu_slot_contains_gpu_and_audio(self):
        for slug in SCRIPTS:
            result = self.run_case(slug, VM_GPU_PCI="01:00.0")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "qm set 100 --hostpci0 0000:01:00,pcie=1 --vga none")

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
        match = re.search(r'cat >"\$(SUNSHINE_FIRSTBOOT_TMP|MOONLIGHT_SETUP_TMP)" <<FIRSTBOOT\n.*?\nFIRSTBOOT', source, re.S)
        self.assertIsNotNone(match)
        guest = self.root / f"{slug}-guest.sh"
        env = {"PATH": os.environ["PATH"], match.group(1): str(guest),
               "CLOUDINIT_USER": "streamuser", "INSTALL_STEAM": "yes", "INSTALL_DOLPHIN": "yes",
               "INSTALL_PEGASUS": "yes", "DESKTOP_AUTOLOGIN": "yes", "VM_CLIENT_AUTOSTART": "yes",
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

    def test_pegasus_preserves_existing_sunshine_apps(self):
        guest = self.render("sunshine-vm").read_text()
        query = re.search(r"jq '(if any\(.apps\[\].*?)'", guest).group(1)
        original = {"env": {"PATH": "kept"}, "apps": [{"name": "Desktop", "cmd": ""}, {"name": "Custom game", "cmd": "keep-me"}]}
        first = subprocess.run(["jq", query], input=json.dumps(original), capture_output=True, text=True, check=True).stdout
        second = subprocess.run(["jq", query], input=first, capture_output=True, text=True, check=True).stdout
        data = json.loads(second)
        self.assertEqual(data["env"], original["env"])
        self.assertEqual(data["apps"][:2], original["apps"])
        self.assertEqual(sum(app["name"] == "Pegasus" for app in data["apps"]), 1)
        self.assertIn("QT_QPA_PLATFORM=xcb", data["apps"][-1]["cmd"])

    def test_debian_components_are_added_per_stanza_without_duplicates(self):
        guest = self.render("sunshine-vm").read_text()
        block = re.search(r"for component in contrib non-free non-free-firmware; do\n.*?\ndone", guest, re.S).group()
        apt = self.root / "apt"
        (apt / "sources.list.d").mkdir(parents=True)
        sources = apt / "sources.list.d" / "debian.sources"
        sources.write_text("Types: deb\nComponents: main contrib\n\nTypes: deb\nComponents: main non-free-firmware\n")
        block = block.replace("/etc/apt", str(apt))
        for _ in range(2):
            subprocess.run(["bash", "-eu", "-c", block], check=True)
        fields = [line.split()[1:] for line in sources.read_text().splitlines() if line.startswith("Components:")]
        for components in fields:
            self.assertEqual(set(components), {"main", "contrib", "non-free", "non-free-firmware"})
            self.assertEqual(len(components), 4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
