#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/OrcaSlicer/OrcaSlicer

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing OrcaSlicer dependencies"
$STD apt install -y ca-certificates file libasound2t64 libdbus-1-3 libfontconfig1 \
  libfreetype6 libglib2.0-0 libgl1 libgtk-3-0 libopengl0 libsm6 \
  libwebkit2gtk-4.1-0 libx11-6 libx11-xcb1 libxcb-render0 libxcb1 \
  libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxtst6 xauth xz-utils xvfb
msg_ok "Installed OrcaSlicer dependencies"

msg_info "Downloading OrcaSlicer"
fetch_and_deploy_gh_release "orcaslicer" "OrcaSlicer/OrcaSlicer" "singlefile" "latest" "/opt/orcaslicer" "OrcaSlicer_Linux_AppImage_Ubuntu2404_V*.AppImage"
mkdir -p /opt/orcaslicer_data /var/lib/orcaslicer/jobs /var/lib/orcaslicer/.config
chmod 700 /opt/orcaslicer_data /var/lib/orcaslicer
msg_ok "Downloaded OrcaSlicer"

msg_info "Extracting OrcaSlicer"
cd /opt/orcaslicer
./orcaslicer --appimage-extract >/dev/null
mv squashfs-root rootfs
msg_ok "Extracted OrcaSlicer"

PYTHON_VERSION="3.13" setup_uv
msg_info "Installing OrcaSlicer MCP dependencies"
$STD uv venv --python 3.13 /opt/orcaslicer/.venv
$STD uv pip install --python /opt/orcaslicer/.venv/bin/python "mcp>=1.20,<2"
msg_ok "Installed OrcaSlicer MCP dependencies"

msg_info "Installing Bambu Lab X1 Carbon profiles"
cat <<'PYCODE' >/opt/orcaslicer/build_profiles.py
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

VERSION = sys.argv[1].lstrip("v")
BASE = f"https://raw.githubusercontent.com/OrcaSlicer/OrcaSlicer/v{VERSION}/resources/profiles/BBL"
ROOT = Path("/opt/orcaslicer/profiles")
ROOT.mkdir(parents=True, exist_ok=True)

def fetch(folder, name):
    path = ROOT / folder / (name + ".json")
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    url = BASE + "/" + folder + "/" + urllib.parse.quote(name + ".json", safe="")
    request = urllib.request.Request(url, headers={"User-Agent": "OrcaSlicer-MCP"})
    with urllib.request.urlopen(request, timeout=45) as response:
        path.write_bytes(response.read())
    json.loads(path.read_text())
    return path

def merge(target, source):
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge(target[key], value)
        else:
            target[key] = value
    return target

def resolve(folder, name, seen=None):
    seen = seen or set()
    if name in seen:
        raise RuntimeError("Profile inheritance cycle: " + name)
    seen.add(name)
    child = json.loads(fetch(folder, name).read_text())
    result = {}
    parent = child.get("inherits")
    if parent:
        result = resolve(folder, parent, seen)
    merge(result, {key: value for key, value in child.items()
                   if key not in ("inherits", "from", "include", "setting_id", "renamed_from")})
    for included in child.get("include", []):
        template = json.loads(fetch(folder, included).read_text())
        merge(result, {key: value for key, value in template.items()
                       if key not in ("type", "name", "inherits", "from", "include",
                                      "setting_id", "instantiation")})
    result["type"] = child.get("type", result.get("type"))
    result["name"] = child.get("name", name)
    result["from"] = "User"
    result["instantiation"] = "true"
    return result

profiles = {
    "machine": ("machine", "Bambu Lab X1 Carbon 0.4 nozzle"),
    "process": ("process", "0.20mm Standard @BBL X1C"),
    "process-draft": ("process", "0.24mm Draft @BBL X1C"),
    "process-016": ("process", "0.16mm Optimal @BBL X1C"),
    "filament": ("filament", "Bambu PETG Basic @BBL X1C"),
}
for target, (folder, name) in profiles.items():
    output = ROOT / (target + ".json")
    output.write_text(json.dumps(resolve(folder, name), indent=2) + "\n")
    print(f"Installed {target}: {name}")
PYCODE
$STD /opt/orcaslicer/.venv/bin/python /opt/orcaslicer/build_profiles.py "$(cat ~/.orcaslicer)"
msg_ok "Installed Bambu Lab X1 Carbon profiles"

msg_info "Configuring Nextcloud WebDAV"
cat <<EOF >/opt/orcaslicer_data/.env
NC_URL=${var_nextcloud_url:-}
NC_USER=${var_nextcloud_user:-}
NC_PASS=${var_nextcloud_password:-}
NC_INPUT_DIR=${var_nextcloud_input_dir:-STL}
NC_OUTPUT_DIR=${var_nextcloud_output_dir:-3MF_PRET_A_IMPRIMER}
EOF
chmod 600 /opt/orcaslicer_data/.env
unset var_nextcloud_password
msg_ok "Configured Nextcloud WebDAV"

msg_info "Installing OrcaSlicer MCP service"
cat <<'PYCODE' >/opt/orcaslicer/server.py
from __future__ import annotations

import base64
import json
import os
import re
import shutil
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path, PurePosixPath

from mcp.server.fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import JSONResponse

APP_VERSION = Path("/root/.orcaslicer").read_text().strip() if Path("/root/.orcaslicer").exists() else "unknown"
PROFILE_DIR = Path("/opt/orcaslicer/profiles")
WORK = Path("/var/lib/orcaslicer/jobs")
ORCA = "/opt/orcaslicer/rootfs/AppRun"
DATA_DIR = "/opt/orcaslicer_data"
MAX_STL_BYTES = 100 * 1024 * 1024

mcp = FastMCP(
    "OrcaSlicer MCP",
    instructions=(
        "Prepare Bambu Lab X1 Carbon STL files on demand. Inspect geometry, "
        "orient and slice with OrcaSlicer, then upload a verified .gcode.3mf to "
        "Nextcloud. No folder watcher, printer control or print submission."
    ),
    host=os.environ.get("MCP_HOST", "0.0.0.0"),
    port=int(os.environ.get("MCP_PORT", "8765")),
    streamable_http_path="/mcp",
    stateless_http=True,
    json_response=True,
)

def config():
    values = {
        "user": os.environ.get("NC_USER", ""),
        "password": os.environ.get("NC_PASS", ""),
        "url": os.environ.get("NC_URL", "").rstrip("/"),
        "input": os.environ.get("NC_INPUT_DIR", "STL").strip("/"),
        "output": os.environ.get("NC_OUTPUT_DIR", "3MF_PRET_A_IMPRIMER").strip("/"),
    }
    if not values["user"] or not values["password"] or not values["url"]:
        raise RuntimeError(
            "Nextcloud is not configured. Set NC_URL, NC_USER and NC_PASS in "
            "/opt/orcaslicer_data/.env, then restart orcaslicer-mcp."
        )
    if not values["url"].startswith(("https://", "http://")):
        raise ValueError("NC_URL must be an HTTP(S) WebDAV URL.")
    return values

def safe_relative(value: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError("A relative STL path is required.")
    path = PurePosixPath(value.replace("\\", "/"))
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise ValueError("The path must stay inside the configured Nextcloud STL folder.")
    if path.suffix.lower() != ".stl":
        raise ValueError("Only STL input files are accepted.")
    return str(path)

def webdav(method: str, relative: str, body: bytes | None = None, depth: str | None = None):
    cfg = config()
    encoded = "/".join(urllib.parse.quote(part, safe="") for part in relative.strip("/").split("/") if part)
    url = cfg["url"] + ("/" + encoded if encoded else "/")
    token = base64.b64encode(f'{cfg["user"]}:{cfg["password"]}'.encode()).decode()
    headers = {"Authorization": "Basic " + token, "User-Agent": "OrcaSlicer-MCP"}
    if depth:
        headers["Depth"] = depth
    if method == "PROPFIND":
        headers["Content-Type"] = "application/xml; charset=utf-8"
    if method == "PUT":
        headers["Content-Type"] = "application/octet-stream"
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read(2048).decode("utf-8", "replace")
        raise RuntimeError(f"Nextcloud WebDAV returned HTTP {exc.code}: {detail[:400]}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Nextcloud WebDAV connection failed: {exc.reason}") from exc

def list_folder(relative: str):
    request_body = b"""<?xml version="1.0" encoding="UTF-8"?>
    <d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>"""
    status, payload = webdav("PROPFIND", relative, request_body, "1")
    if status != 207:
        raise RuntimeError(f"Unexpected WebDAV response: HTTP {status}")
    root = ET.fromstring(payload)
    ns = {"d": "DAV:"}
    result = []
    for response in root.findall("d:response", ns):
        prop = response.find(".//d:prop", ns)
        if prop is None:
            continue
        resource_type = prop.find("d:resourcetype", ns)
        is_dir = resource_type is not None and resource_type.find("d:collection", ns) is not None
        href = response.findtext("d:href", default="", namespaces=ns)
        name = urllib.parse.unquote(href.rstrip("/").rsplit("/", 1)[-1])
        if name:
            result.append({
                "name": name,
                "type": "directory" if is_dir else "file",
                "size_bytes": int(prop.findtext("d:getcontentlength", default="0", namespaces=ns) or 0),
                "modified": prop.findtext("d:getlastmodified", default="", namespaces=ns),
            })
    return result

def download_stl(relative_path: str):
    cfg = config()
    relative = safe_relative(relative_path)
    _, payload = webdav("GET", cfg["input"] + "/" + relative)
    if not payload or len(payload) > MAX_STL_BYTES:
        raise ValueError("STL is empty or exceeds the 100 MiB limit.")
    job = WORK / uuid.uuid4().hex
    job.mkdir(mode=0o700, parents=True, exist_ok=False)
    local = job / Path(relative).name
    local.write_bytes(payload)
    return local

def run_orca(arguments: list[str], timeout: int = 900):
    command = [
        "/usr/bin/xvfb-run", "-a", ORCA,
        "--datadir", DATA_DIR,
        "--logfile", "/var/lib/orcaslicer/orca-cli.log",
    ] + arguments
    result = subprocess.run(
        command, cwd="/var/lib/orcaslicer", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=timeout, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"OrcaSlicer failed (exit {result.returncode}): {result.stdout[-2500:]}")
    return result.stdout[-6000:]

def slice_report(path: Path):
    report = {
        "file": path.name,
        "size_bytes": path.stat().st_size,
        "orcaslicer_version": APP_VERSION,
        "contains_gcode": False,
    }
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        gcode = [name for name in names if name.lower().endswith(".gcode")]
        if not gcode:
            raise RuntimeError("The exported 3MF does not contain G-code; refusing upload.")
        report["contains_gcode"] = True
        report["gcode_entry"] = gcode[0]
        if "Metadata/slice_info.config" in names:
            metadata = archive.read("Metadata/slice_info.config").decode("utf-8", "replace")
            for key, output in (
                ("prediction", "estimated_time_seconds"),
                ("weight", "filament_weight_g"),
                ("support_used", "supports_used"),
            ):
                match = re.search(r'<metadata key="' + re.escape(key) + r'" value="([^"]*)"', metadata)
                if match:
                    report[output] = match.group(1)
            report["warnings"] = re.findall(r'<warning msg="([^"]+)"[^>]*/>', metadata)
    return report

@mcp.custom_route("/health", methods=["GET"], include_in_schema=False)
async def health(request: Request):
    return JSONResponse({
        "status": "ok",
        "service": "OrcaSlicer MCP",
        "orcaslicer_version": APP_VERSION,
        "nextcloud_configured": bool(os.environ.get("NC_URL") and os.environ.get("NC_USER") and os.environ.get("NC_PASS")),
        "input_mode": "on-demand",
        "printer_control": False,
    })

@mcp.tool()
def list_stl_files() -> dict:
    """List STL files in the configured Nextcloud input folder."""
    cfg = config()
    return {"folder": cfg["input"], "files": list_folder(cfg["input"])}

@mcp.tool()
def inspect_stl(relative_path: str) -> dict:
    """Download a Nextcloud STL temporarily and inspect dimensions, triangles and faces."""
    local = download_stl(relative_path)
    try:
        output = run_orca(["--inspect-mesh", str(local)], timeout=180)
        start = output.find("{")
        if start < 0:
            raise RuntimeError(f"OrcaSlicer did not return geometry JSON: {output[-2000:]}")
        return {"source": relative_path, "geometry": json.loads(output[start:])}
    finally:
        shutil.rmtree(local.parent, ignore_errors=True)

@mcp.tool()
def slice_stl(
    relative_path: str,
    quality: str = "standard",
    strength: str = "standard",
    supports: str = "auto",
    support_on_build_plate_only: bool = True,
    orientation: str = "auto",
) -> dict:
    """Slice an STL for a Bambu Lab X1 Carbon and upload a verified .gcode.3mf to Nextcloud."""
    cfg = config()
    if quality not in {"draft", "standard", "fine"}:
        raise ValueError("quality must be draft, standard or fine.")
    if strength not in {"light", "standard", "strong"}:
        raise ValueError("strength must be light, standard or strong.")
    if supports not in {"auto", "on", "off"}:
        raise ValueError("supports must be auto, on or off.")
    if orientation not in {"auto", "keep"}:
        raise ValueError("orientation must be auto or keep.")

    local = download_stl(relative_path)
    try:
        process_name = {"draft": "process-draft.json", "standard": "process.json", "fine": "process-016.json"}[quality]
        arguments = [
            "--curr-bed-type", "Textured PEI Plate",
            "--load-settings", str(PROFILE_DIR / "machine.json") + ";" + str(PROFILE_DIR / process_name),
            "--load-filaments", str(PROFILE_DIR / "filament.json"),
        ]
        if orientation == "auto":
            arguments += ["--orient", "1"]
        arguments += ["--arrange", "1"]
        if strength == "light":
            arguments += ["--wall_loops=2", "--sparse_infill_density=10%"]
        elif strength == "standard":
            arguments += ["--wall_loops=3", "--sparse_infill_density=20%", "--sparse_infill_pattern=gyroid"]
        else:
            arguments += ["--wall_loops=4", "--sparse_infill_density=35%", "--sparse_infill_pattern=gyroid"]
        arguments += [f"--support_enable={0 if supports == 'off' else 1}"]
        arguments += [f"--support_on_build_plate_only={1 if support_on_build_plate_only else 0}"]
        output = local.parent / (local.stem + ".gcode.3mf")
        log_tail = run_orca(
            arguments + ["--slice", "0", "--strict", "--export-3mf", str(output), str(local)],
            timeout=1800,
        )
        report = slice_report(output)
        output_name = f"{local.stem}-{time.strftime('%Y%m%d-%H%M%S', time.gmtime())}.gcode.3mf"
        status, _ = webdav("PUT", cfg["output"] + "/" + output_name, output.read_bytes())
        if status not in (200, 201, 204):
            raise RuntimeError(f"Nextcloud upload failed: HTTP {status}")
        report.update({
            "source": relative_path,
            "output_path": cfg["output"] + "/" + output_name,
            "machine_profile": "Bambu Lab X1 Carbon 0.4 nozzle",
            "filament_profile": "Bambu PETG Basic @BBL X1C",
            "build_plate": "Textured PEI Plate",
            "quality": quality,
            "strength": strength,
            "supports": supports,
            "orientation": orientation,
            "cli_log_tail": log_tail[-1200:],
            "printed": False,
        })
        return report
    finally:
        shutil.rmtree(local.parent, ignore_errors=True)

if __name__ == "__main__":
    WORK.mkdir(parents=True, exist_ok=True)
    mcp.run(transport="streamable-http")
PYCODE
cat <<'EOF' >/etc/systemd/system/orcaslicer-mcp.service
[Unit]
Description=OrcaSlicer MCP service for Bambu Lab X1 Carbon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/orcaslicer
Environment=HOME=/var/lib/orcaslicer
Environment=XDG_CONFIG_HOME=/var/lib/orcaslicer/.config
EnvironmentFile=/opt/orcaslicer_data/.env
ExecStart=/usr/bin/xvfb-run -a /opt/orcaslicer/.venv/bin/python /opt/orcaslicer/server.py
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/var/lib/orcaslicer /opt/orcaslicer_data
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now orcaslicer-mcp
msg_ok "Installed OrcaSlicer MCP service"

motd_ssh
customize
cleanup_lxc
