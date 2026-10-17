#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/ggml-org/llama.cpp

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_model_repo="${var_model_repo:-ggml-org/gemma-4-E2B-it-GGUF:Q4_0}"
var_port="${var_port:-8080}"
var_ctx_size="${var_ctx_size:-4096}"
var_offload_layers="${var_offload_layers:-}"
var_api_key="${var_api_key:-}"

# The Linux prebuilts upstream publishes (see .github/workflows/release.yml):
#   cpu       ubuntu-{x64,arm64}
#   vulkan    ubuntu-vulkan-{x64,arm64}       any GPU vendor (AMD through RADV)
#   cuda      ubuntu-cuda-{12.x,13.x}-x64, ubuntu-cuda-13.x-arm64, plus a cudart tarball
#   rocm      ubuntu-rocm-<ver>-x64           needs the matching ROCm (TheRock) runtime
#   sycl      ubuntu-sycl-{fp16,fp32}-x64     Intel GPUs, needs oneAPI + Level Zero
#   openvino  ubuntu-openvino-<ver>-x64       Intel CPU/GPU, OpenVINO runtime is bundled
var_backend="${var_backend:-auto}"

if [[ "$var_backend" == "auto" ]]; then
  if [[ -e /dev/kfd || -e /dev/nvidia0 || -d /dev/dri ]]; then
    var_backend="vulkan"
  else
    var_backend="cpu"
  fi
fi
[[ "$var_backend" == "sycl" ]] && var_backend="sycl-fp16"

LLAMA_ARCH="$(arch_resolve x64 arm64)"
case "$var_backend" in
rocm | sycl-fp16 | sycl-fp32 | openvino)
  if [[ "$LLAMA_ARCH" != "x64" ]]; then
    msg_error "llama.cpp publishes the ${var_backend} build for x64 only"
    exit 1
  fi
  ;;
cpu | vulkan | cuda) ;;
*)
  msg_error "Unknown var_backend '${var_backend}' (expected auto, cpu, vulkan, cuda, rocm, sycl-fp16, sycl-fp32 or openvino)"
  exit 1
  ;;
esac

msg_info "Installing Dependencies"
LLAMA_DEPS=(libgomp1)
case "$var_backend" in
vulkan) LLAMA_DEPS+=(libvulkan1 mesa-vulkan-drivers vulkan-tools) ;;
openvino) LLAMA_DEPS+=(libtbb12 ocl-icd-libopencl1) ;;
sycl-*) LLAMA_DEPS+=(ocl-icd-libopencl1) ;;
esac
$STD apt install -y "${LLAMA_DEPS[@]}"
msg_ok "Installed Dependencies"

setup_hwaccel

# SYCL and OpenVINO reach an Intel GPU through Level Zero. release.yml builds
# SYCL against the loader from oneapi-src/level-zero, so use the same package.
if [[ "$var_backend" == sycl-* || "$var_backend" == "openvino" ]]; then
  fetch_and_deploy_gh_release "level-zero" "oneapi-src/level-zero" "binary" "latest" "" "libze1_*u24.04_amd64.deb"
  if [[ -d /dev/dri ]]; then
    fetch_and_deploy_gh_release "intel-level-zero-gpu" "intel/compute-runtime" "binary" "latest" "" "libze-intel-gpu1_*_amd64.deb" || true
  fi
fi

# The SYCL tarball ships only llama.cpp itself; the DPC++/oneMKL/oneDNN/TBB
# libraries it links against come from oneAPI. release.yml builds with the full
# toolkit, but running needs only the runtime libraries.
if [[ "$var_backend" == sycl-* ]]; then
  setup_deb822_repo \
    "oneapi" \
    "https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB" \
    "https://apt.repos.intel.com/oneapi" \
    "all" \
    "main"
  msg_info "Installing Intel oneAPI Runtime"
  $STD apt install -y intel-oneapi-runtime-libs
  # The runtime packages unpack under /opt/intel/oneapi without telling the
  # dynamic linker, so register every directory that holds one of them.
  find /opt/intel/oneapi -type f \( -name 'libsycl.so*' -o -name 'libur_loader.so*' -o -name 'libmkl_core.so*' \
    -o -name 'libdnnl.so*' -o -name 'libtbb.so*' -o -name 'libsvml.so' -o -name 'libiomp5.so' -o -name 'libumf.so*' \) \
    -printf '%h\n' 2>/dev/null | sort -u >/etc/ld.so.conf.d/oneapi-llama-cpp.conf
  ldconfig
  msg_ok "Installed Intel oneAPI Runtime"
fi

LLAMA_CUDART_ASSET=""
case "$var_backend" in
vulkan) LLAMA_ASSET="llama-*-bin-ubuntu-vulkan-${LLAMA_ARCH}.tar.gz" ;;
cuda)
  # CUDA 13 needs a 580+ host driver; anything older gets the CUDA 12 build,
  # which upstream publishes for x64 only.
  NVIDIA_DRIVER_MAJOR="$(grep -oP '\d{3,}(?=\.\d+)' /proc/driver/nvidia/version 2>/dev/null | head -1)"
  if [[ "$LLAMA_ARCH" == "x64" && -n "$NVIDIA_DRIVER_MAJOR" && "$NVIDIA_DRIVER_MAJOR" -lt 580 ]]; then
    var_backend="cuda-12"
  else
    var_backend="cuda-13"
  fi
  [[ -z "$NVIDIA_DRIVER_MAJOR" ]] && msg_warn "No NVIDIA host driver visible - installing the CUDA 13 build, which needs driver 580 or newer"
  LLAMA_ASSET="llama-*-bin-ubuntu-cuda-${var_backend#cuda-}.*-${LLAMA_ARCH}.tar.gz"
  LLAMA_CUDART_ASSET="cudart-${LLAMA_ASSET}"
  ;;
rocm) LLAMA_ASSET="llama-*-bin-ubuntu-rocm-*-x64.tar.gz" ;;
sycl-fp16 | sycl-fp32) LLAMA_ASSET="llama-*-bin-ubuntu-${var_backend}-x64.tar.gz" ;;
openvino) LLAMA_ASSET="llama-*-bin-ubuntu-openvino-*x64.tar.gz" ;;
*) LLAMA_ASSET="llama-*-bin-ubuntu-${LLAMA_ARCH}.tar.gz" ;;
esac

# Only the bNNNN builds carry binaries, and upstream marks them prerelease. A
# stable vX.Y.Z release ships just nightly-tag.txt, naming the build it was cut
# from, so without GH_INCLUDE_PRERELEASE=1 that build is the one deployed.
mkdir -p /opt/llama-cpp_data/models
if [[ "${GH_INCLUDE_PRERELEASE:-0}" == "1" ]]; then
  fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "latest" "/opt/llama-cpp" "$LLAMA_ASSET" "b"
  LLAMA_RELEASE="$(cat ~/.llama-cpp)"
else
  USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "llama-cpp-stable" "ggml-org/llama.cpp" "singlefile" "latest" "/opt/llama-cpp_data" "nightly-tag.txt"
  LLAMA_RELEASE="$(</opt/llama-cpp_data/nightly-tag.txt)"
  fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "$LLAMA_RELEASE" "/opt/llama-cpp" "$LLAMA_ASSET"
fi
if [[ -n "$LLAMA_CUDART_ASSET" ]]; then
  fetch_and_deploy_gh_release "llama-cpp-cudart" "ggml-org/llama.cpp" "prebuild" "$LLAMA_RELEASE" "/opt/llama-cpp" "$LLAMA_CUDART_ASSET"
fi
LLAMA_LIBPATH="/opt/llama-cpp"

# The ROCm build carries no ROCm libraries. release.yml builds it against AMD's
# TheRock wheels, so install the same ROCm release of those as the runtime.
if [[ "$var_backend" == "rocm" ]]; then
  ROCM_VERSION="$(jq -r --arg t "$LLAMA_RELEASE" 'if type == "array" then .[] else . end | select(.tag_name == $t) | .assets[].name' "$TOOLS_GH_REL_JSON" 2>/dev/null | grep -oP 'bin-ubuntu-rocm-\K[0-9.]+(?=-x64)' | head -1)"
  if [[ -z "$ROCM_VERSION" ]]; then
    msg_error "Could not read the ROCm release the llama.cpp ${LLAMA_RELEASE} build targets"
    exit 1
  fi
  PYTHON_VERSION="3.12" setup_uv
  msg_info "Installing ROCm ${ROCM_VERSION} Runtime"
  $STD uv venv --python 3.12 /opt/llama-cpp_data/rocm
  $STD uv pip install --python /opt/llama-cpp_data/rocm --index-url https://stable.repo.amd.com/rocm/whl-next/ "rocm[libraries]==${ROCM_VERSION}.*"
  echo "$ROCM_VERSION" >/opt/llama-cpp_data/rocm/.version
  LLAMA_LIBPATH="${LLAMA_LIBPATH}:$(/opt/llama-cpp_data/rocm/bin/rocm-sdk path --root)/lib"
  msg_ok "Installed ROCm ${ROCM_VERSION} Runtime"
fi

msg_info "Configuring llama.cpp"
chmod +x /opt/llama-cpp/llama-*
echo "$var_backend" >/opt/llama-cpp_data/.backend
echo "${GH_INCLUDE_PRERELEASE:-0}" >/opt/llama-cpp_data/.prerelease
if [[ -z "$var_offload_layers" ]]; then
  [[ "$var_backend" == "cpu" ]] && var_offload_layers=0 || var_offload_layers=999
fi
cat <<EOF >/opt/llama-cpp.env
LLAMA_ARG_HOST=0.0.0.0
LLAMA_ARG_PORT=${var_port}

# Model to serve. Either point at a local GGUF file:
#LLAMA_ARG_MODEL=/opt/llama-cpp_data/models/your-model.gguf
# ...or let llama-server pull one from Hugging Face on first start:
LLAMA_ARG_HF_REPO=${var_model_repo}
# Model switching: comment out LLAMA_ARG_HF_REPO (and LLAMA_ARG_MODEL) to serve
# every model in this folder and pick one per request from the web UI or API:
LLAMA_ARG_MODELS_DIR=/opt/llama-cpp_data/models

LLAMA_CACHE=/opt/llama-cpp_data/models
LLAMA_ARG_CTX_SIZE=${var_ctx_size}
LLAMA_ARG_N_GPU_LAYERS=${var_offload_layers}
EOF
case "$var_backend" in
sycl-*)
  cat <<EOF >>/opt/llama-cpp.env

# SYCL: the persistent kernel cache speeds up restarts but can stop models
# from loading on some Intel GPUs, so it is off by default
#SYCL_CACHE_PERSISTENT=1
#SYCL_CACHE_DIR=/opt/llama-cpp_data/sycl-cache
#ONEAPI_DEVICE_SELECTOR=level_zero:0
EOF
  ;;
openvino)
  OV_DEVICE="CPU"
  compgen -G "/dev/dri/renderD*" >/dev/null && OV_DEVICE="GPU"
  cat <<EOF >>/opt/llama-cpp.env

# OpenVINO device: CPU, GPU (GPU.0, GPU.1, ...) or NPU
GGML_OPENVINO_DEVICE=${OV_DEVICE}
GGML_OPENVINO_CACHE_DIR=/opt/llama-cpp_data/openvino-cache
EOF
  ;;
esac
# An empty LLAMA_ARG_API_KEY makes llama-server demand an empty bearer token.
if [[ -n "$var_api_key" ]]; then
  echo "LLAMA_ARG_API_KEY=${var_api_key}" >>/opt/llama-cpp.env
else
  echo "#LLAMA_ARG_API_KEY=" >>/opt/llama-cpp.env
fi
chmod 600 /opt/llama-cpp.env
msg_ok "Configured llama.cpp (${var_backend} build)"

if [[ "$var_backend" != "cpu" ]]; then
  if LD_LIBRARY_PATH="$LLAMA_LIBPATH" ldd /opt/llama-cpp/llama-server /opt/llama-cpp/libggml-*.so 2>/dev/null | grep -q "not found"; then
    msg_warn "The ${var_backend} build is missing shared libraries in this container - it will fall back to the CPU"
  elif [[ "$var_backend" == "vulkan" ]] && ! vulkaninfo --summary >/dev/null 2>&1; then
    msg_warn "Vulkan build installed but no Vulkan device is visible - check GPU passthrough and the driver libraries in the container"
  elif [[ "$var_backend" == cuda-* ]] && ! ldconfig -p | grep -q 'libcuda[.]so'; then
    msg_warn "CUDA build installed but the NVIDIA driver library (libcuda) is missing - check GPU passthrough"
  elif [[ "$var_backend" == sycl-* || "$var_backend" == "rocm" ]] && [[ ! -d /dev/dri && ! -e /dev/kfd ]]; then
    msg_warn "${var_backend} build installed but no GPU is passed through - it will fall back to the CPU"
  fi
fi

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/llama-cpp.service
[Unit]
Description=llama.cpp Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/llama-cpp
EnvironmentFile=/opt/llama-cpp.env
Environment=LD_LIBRARY_PATH=${LLAMA_LIBPATH}
ExecStart=/opt/llama-cpp/llama-server
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now llama-cpp
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
