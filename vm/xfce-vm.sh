set -euo pipefail

connection="${VM_CONNECTION:-qemu:///system}"
pool="${VM_POOL:-default}"
network="${VM_NETWORK:-default}"
initial_memory_mib="${VM_INITIAL_MEMORY_MIB:-6144}"
maximum_memory_mib="${VM_MAX_MEMORY_MIB:-12288}"
vcpus="${VM_VCPUS:-4}"
image_result="${VM_IMAGE_RESULT:-$PWD/result}"

base_image=""
base_volume=""
selected_vm=""
managed_vms=()

usage() {
  cat <<'EOF'
Usage:
  xfce-vm
  xfce-vm create NAME [DISK_SIZE]
  xfce-vm rebuild NAME
  xfce-vm delete NAME
  xfce-vm list

Run without arguments for the interactive menu. DISK_SIZE defaults to 64G.
The legacy form `xfce-vm NAME [DISK_SIZE]` also creates a VM.
EOF
}

virsh_system() {
  virsh --connect "$connection" "$@"
}

validate_name() {
  local name=$1

  if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "VM name must contain only letters, numbers, dots, underscores, or hyphens." >&2
    return 1
  fi
}

validate_size() {
  local size=${1^^}

  if [[ ! "$size" =~ ^[1-9][0-9]*([KMGTPE]I?B?)?$ ]]; then
    echo "Disk size must be a positive number with an optional unit, such as 64G." >&2
    return 1
  fi
}

resolve_base_image() {
  local store_output store_hash
  local image_candidates=()

  shopt -s nullglob
  image_candidates=("$image_result"/*.qcow2)
  shopt -u nullglob

  if (( ${#image_candidates[@]} != 1 )); then
    echo "Expected exactly one qcow2 image under $image_result; run:" >&2
    echo "  nix build --accept-flake-config path:./vm#xfce-vm-image" >&2
    return 1
  fi

  base_image=$(readlink -f -- "${image_candidates[0]}")
  store_output=$(basename -- "$(dirname -- "$base_image")")
  store_hash=${store_output%%-*}

  if [[ ! "$store_hash" =~ ^[0-9a-df-np-sv-z]{32}$ ]]; then
    echo "Could not derive a Nix store hash from $base_image" >&2
    return 1
  fi

  base_volume="xfce-base-${store_hash}.qcow2"
}

ensure_base_volume() {
  local base_capacity

  resolve_base_image

  if virsh_system vol-info --pool "$pool" "$base_volume" >/dev/null 2>&1; then
    return
  fi

  echo "Importing immutable base image as $base_volume ..."
  base_capacity=$(qemu-img info --output=json "$base_image" | jq -r '."virtual-size"')
  virsh_system vol-create-as \
    "$pool" "$base_volume" "$base_capacity" \
    --allocation 0 \
    --format qcow2 >/dev/null

  if ! virsh_system vol-upload \
    --pool "$pool" \
    --sparse \
    "$base_volume" "$base_image"; then
    virsh_system vol-delete --pool "$pool" "$base_volume" >/dev/null 2>&1 || true
    return 1
  fi
}

ensure_network() {
  virsh_system net-autostart "$network" >/dev/null
  if ! virsh_system net-info "$network" | grep '^Active:.*yes$' >/dev/null; then
    virsh_system net-start "$network" >/dev/null
  fi
}

create_overlay() {
  local name=$1
  local disk_size=$2

  virsh_system vol-create-as \
    "$pool" "${name}.qcow2" "$disk_size" \
    --format qcow2 \
    --backing-vol "$base_volume" \
    --backing-vol-format qcow2 >/dev/null
}

create_vm() {
  local name=$1
  local disk_size=${2:-64G}
  local vm_volume="${name}.qcow2"

  validate_name "$name"
  validate_size "$disk_size"
  disk_size=${disk_size^^}

  if virsh_system dominfo "$name" >/dev/null 2>&1; then
    echo "A libvirt domain named $name already exists." >&2
    return 1
  fi

  if virsh_system vol-info --pool "$pool" "$vm_volume" >/dev/null 2>&1; then
    echo "A storage volume named $vm_volume already exists in pool $pool." >&2
    return 1
  fi

  ensure_base_volume
  ensure_network

  echo "Creating $disk_size overlay $vm_volume ..."
  create_overlay "$name" "$disk_size"

  echo "Defining and starting $name ..."
  if ! virt-install \
    --connect "$connection" \
    --name "$name" \
    --memory "memory=${maximum_memory_mib},currentMemory=${initial_memory_mib}" \
    --vcpus "$vcpus" \
    --cpu host-passthrough \
    --machine q35 \
    --osinfo nixos-unstable \
    --import \
    --boot uefi \
    --disk "vol=${pool}/${vm_volume},bus=virtio,cache=none,discard=unmap" \
    --network "network=${network},model=virtio" \
    --graphics spice \
    --video virtio \
    --channel spicevmc,target_type=virtio,name=com.redhat.spice.0 \
    --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
    --controller usb,model=qemu-xhci \
    --redirdev usb,type=spicevmc \
    --redirdev usb,type=spicevmc \
    --sound ich9 \
    --audio id=1,type=spice \
    --memballoon model=virtio,stats.period=5 \
    --rng /dev/urandom \
    --noautoconsole; then
    virsh_system vol-delete --pool "$pool" "$vm_volume" >/dev/null 2>&1 || true
    return 1
  fi

  echo
  echo "$name is running. Open it in virt-manager using $connection."
}

is_managed_vm() {
  local name=$1
  local source

  if ! virsh_system dominfo "$name" >/dev/null 2>&1; then
    return 1
  fi

  if ! virsh_system vol-info --pool "$pool" "${name}.qcow2" >/dev/null 2>&1; then
    return 1
  fi

  source=$(virsh_system domblklist "$name" --details | awk '$2 == "disk" { print $4; exit }')
  [[ -n "$source" && "$(basename -- "$source")" == "${name}.qcow2" ]]
}

refresh_managed_vms() {
  local name
  local all_vms=()

  managed_vms=()
  mapfile -t all_vms < <(virsh_system list --all --name)
  for name in "${all_vms[@]}"; do
    if [[ -n "$name" ]] && is_managed_vm "$name"; then
      managed_vms+=("$name")
    fi
  done
}

vm_state() {
  virsh_system domstate "$1" | awk '{$1=$1; print}'
}

list_vms() {
  local name state capacity

  refresh_managed_vms
  if (( ${#managed_vms[@]} == 0 )); then
    echo "No managed VMs were found in libvirt pool $pool."
    return
  fi

  printf '%-24s %-14s %s\n' "NAME" "STATE" "DISK CAPACITY"
  for name in "${managed_vms[@]}"; do
    state=$(vm_state "$name")
    capacity=$(virsh_system vol-info --pool "$pool" "${name}.qcow2" |
      awk -F: '$1 == "Capacity" { sub(/^[[:space:]]+/, "", $2); print $2 }')
    printf '%-24s %-14s %s\n' "$name" "$state" "$capacity"
  done
}

select_vm() {
  local choice index name state

  refresh_managed_vms
  if (( ${#managed_vms[@]} == 0 )); then
    echo "No managed VMs were found in libvirt pool $pool."
    return 1
  fi

  echo "Available VMs:"
  for index in "${!managed_vms[@]}"; do
    name=${managed_vms[$index]}
    state=$(vm_state "$name")
    printf '  %d) %s (%s)\n' "$((index + 1))" "$name" "$state"
  done

  while true; do
    read -r -p "Select a VM by number, or q to cancel: " choice
    if [[ ${choice,,} == "q" ]]; then
      return 1
    fi
    if [[ "$choice" =~ ^[1-9][0-9]*$ ]] &&
      (( choice <= ${#managed_vms[@]} )); then
      selected_vm=${managed_vms[$((choice - 1))]}
      return
    fi
    echo "Enter a number from 1 to ${#managed_vms[@]}."
  done
}

confirm() {
  local prompt=$1
  local reply

  read -r -p "$prompt [y/N] " reply
  [[ ${reply,,} == "y" || ${reply,,} == "yes" ]]
}

stop_vm() {
  local name=$1
  local state attempt

  state=$(vm_state "$name")
  if [[ "$state" == "shut off" ]]; then
    return
  fi

  echo "Requesting shutdown for $name ..."
  virsh_system shutdown "$name" >/dev/null 2>&1 || true
  for ((attempt = 0; attempt < 30; attempt++)); do
    if [[ "$(vm_state "$name")" == "shut off" ]]; then
      return
    fi
    sleep 1
  done

  echo "The guest did not stop after 30 seconds; forcing it off."
  virsh_system destroy "$name" >/dev/null
}

rebuild_vm() {
  local name=$1
  local capacity

  validate_name "$name"
  if ! is_managed_vm "$name"; then
    echo "$name is not a VM managed by this tool in pool $pool." >&2
    return 1
  fi

  capacity=$(virsh_system vol-info --pool "$pool" "${name}.qcow2" --bytes |
    awk '$1 == "Capacity:" { print $2 }')
  if [[ ! "$capacity" =~ ^[1-9][0-9]*$ ]]; then
    echo "Could not determine the capacity of ${name}.qcow2." >&2
    return 1
  fi

  echo "Rebuilding replaces $name's writable disk with a fresh overlay."
  echo "All files and changes made inside that VM will be permanently erased."
  if ! confirm "Rebuild $name from the current base image?"; then
    echo "Rebuild cancelled."
    return
  fi

  # Import the new base before touching the existing guest disk.
  ensure_base_volume
  stop_vm "$name"

  echo "Replacing ${name}.qcow2 ..."
  virsh_system vol-delete --pool "$pool" "${name}.qcow2" >/dev/null
  create_overlay "$name" "$capacity"
  ensure_network
  virsh_system start "$name" >/dev/null

  echo "$name was rebuilt from $base_volume and is running."
}

delete_vm() {
  local name=$1
  local xml
  local undefine_args=("$name" --managed-save)

  validate_name "$name"
  if ! is_managed_vm "$name"; then
    echo "$name is not a VM managed by this tool in pool $pool." >&2
    return 1
  fi

  echo "Deleting removes the libvirt definition and ${name}.qcow2."
  echo "This permanently erases all files and changes inside the VM."
  if ! confirm "Delete $name?"; then
    echo "Delete cancelled."
    return
  fi

  stop_vm "$name"
  xml=$(virsh_system dumpxml "$name")
  if grep '<nvram' <<<"$xml" >/dev/null; then
    undefine_args+=(--nvram)
  fi

  if ! virsh_system undefine "${undefine_args[@]}" >/dev/null; then
    echo "Could not undefine $name; its disk was retained." >&2
    return 1
  fi
  virsh_system vol-delete --pool "$pool" "${name}.qcow2" >/dev/null

  echo "$name and its writable disk were deleted."
}

interactive_create() {
  local name disk_size

  while true; do
    read -r -p "VM name: " name
    if validate_name "$name"; then
      break
    fi
  done

  read -r -p "Disk size [64G]: " disk_size
  create_vm "$name" "${disk_size:-64G}"
}

interactive_menu() {
  local action

  if [[ ! -t 0 ]]; then
    echo "The interactive menu requires a terminal." >&2
    usage >&2
    return 2
  fi

  echo "XFCE VM manager"
  echo "  1) Create a new VM"
  echo "  2) Rebuild a VM from the current base image"
  echo "  3) Delete a VM"
  echo "  4) List VMs"
  echo "  5) Quit"

  while true; do
    read -r -p "Choose an action: " action
    case "$action" in
      1)
        interactive_create
        return
        ;;
      2)
        if select_vm; then
          rebuild_vm "$selected_vm"
        fi
        return
        ;;
      3)
        if select_vm; then
          delete_vm "$selected_vm"
        fi
        return
        ;;
      4)
        list_vms
        return
        ;;
      5 | q | Q)
        return
        ;;
      *)
        echo "Choose a number from 1 to 5."
        ;;
    esac
  done
}

command=${1:-}
case "$command" in
  "")
    interactive_menu
    ;;
  -h | --help | help)
    usage
    ;;
  create)
    if (( $# < 2 || $# > 3 )); then
      usage >&2
      exit 2
    fi
    create_vm "$2" "${3:-64G}"
    ;;
  rebuild)
    if (( $# != 2 )); then
      usage >&2
      exit 2
    fi
    rebuild_vm "$2"
    ;;
  delete)
    if (( $# != 2 )); then
      usage >&2
      exit 2
    fi
    delete_vm "$2"
    ;;
  list)
    if (( $# != 1 )); then
      usage >&2
      exit 2
    fi
    list_vms
    ;;
  -* )
    usage >&2
    exit 2
    ;;
  *)
    if (( $# > 2 )); then
      usage >&2
      exit 2
    fi
    create_vm "$1" "${2:-64G}"
    ;;
esac
