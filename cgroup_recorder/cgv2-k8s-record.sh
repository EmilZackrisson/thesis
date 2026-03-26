#!/usr/bin/env bash
#set -x
set -eo pipefail

INTERVAL="0.2"
TMPDIR="/tmp/cgv2-recorder"
PIDFILE="$TMPDIR/recorder.pid"

export KUBECONFIG="/home/ubuntu/.kube/config"

usage() {
    cat <<EOF
Usage:
  $0 start <output.tar> <namespace> <label-selector>
  $0 stop
EOF
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: must be run as root"
        exit 1
    fi
}

require_cmd() {
    command -v "$1" >/dev/null || {
        echo "ERROR: missing dependency: $1"
        exit 1
    }
}

discover_cgroups() {
    local namespace="$1"
    local selector="$2"

    CGROUP_LIST="$TMPDIR/cgroups.list"
    : >"$CGROUP_LIST"

    # Get pods by selector
    kubectl get pods -n "$namespace" -l "$selector" -o json |
    jq -r '
      .items[] |
      .metadata.name as $pod |
            ((.status.containerStatuses // []) + (.status.initContainerStatuses // []))[]? |
      select(.containerID != null) |
      "\($pod) \(.name) \(.containerID)"
    ' | while read -r pod container cid; do
        cid="${cid#cri-o://}"

        cg_full="$(crictl inspect "$cid" 2>/dev/null | jq -r '.info.runtimeSpec.linux.cgroupsPath')"
        [[ -z "$cg_full" || "$cg_full" == "null" ]] && continue

        pod_slice="${cg_full%%:*}"
        container_scope="crio-${cid}.scope"

        qos_slice=""
        if [[ "$pod_slice" == kubepods-besteffort-* ]]; then
            qos_slice="kubepods-besteffort.slice"
        elif [[ "$pod_slice" == kubepods-burstable-* ]]; then
            qos_slice="kubepods-burstable.slice"
        else
            continue
        fi

        full_path="/sys/fs/cgroup/kubepods.slice/${qos_slice}/${pod_slice}/${container_scope}"

        # FIXED: check for existence, not directory
        [[ -e "$full_path" ]] || continue

        echo "$pod $container $full_path" >>"$CGROUP_LIST"
    done

    # Get Istiod pod
    kubectl get pods -n istio-system -o json |
    jq -r '
      .items[] |
      .metadata.name as $pod |
            ((.status.containerStatuses // []) + (.status.initContainerStatuses // []))[]? |
      select(.containerID != null) |
      "\($pod) \(.name) \(.containerID)"
    ' | while read -r pod container cid; do
        cid="${cid#cri-o://}"

        cg_full="$(crictl inspect "$cid" 2>/dev/null | jq -r '.info.runtimeSpec.linux.cgroupsPath')"
        [[ -z "$cg_full" || "$cg_full" == "null" ]] && continue

        pod_slice="${cg_full%%:*}"
        container_scope="crio-${cid}.scope"

        qos_slice=""
        if [[ "$pod_slice" == kubepods-besteffort-* ]]; then
            qos_slice="kubepods-besteffort.slice"
        elif [[ "$pod_slice" == kubepods-burstable-* ]]; then
            qos_slice="kubepods-burstable.slice"
        else
            continue
        fi

        full_path="/sys/fs/cgroup/kubepods.slice/${qos_slice}/${pod_slice}/${container_scope}"

        # FIXED: check for existence, not directory
        [[ -e "$full_path" ]] || continue

        echo "$pod $container $full_path" >>"$CGROUP_LIST"
    done

    if [[ ! -s "$CGROUP_LIST" ]]; then
        echo "ERROR: no cgroups discovered for namespace=$namespace selector=$selector" >&2
        return 1
    fi
}

snapshot_once() {
    local base_dir="$1"
    [[ -z "$base_dir" ]] && base_dir="$TMPDIR"

    local outdir="$base_dir/$(date +%s%N)"
    mkdir -p "$outdir"

    # --- 1) Pod/container cgroups ---
    while read -r pod container cgroup; do
        [[ -d "$cgroup" ]] || continue

        safe_pod="${pod//\//_}"
        safe_container="${container//\//_}"

        local dst="$outdir/${safe_pod}_${safe_container}"
        mkdir -p "$dst"

        for f in cpu.stat cpu.pressure memory.current memory.stat memory.events io.stat pids.current; do
            [[ -f "$cgroup/$f" ]] || continue
            cat "$cgroup/$f" >"$dst/$f"
        done
    done <"$CGROUP_LIST"

    # --- 2) System (node-level) metrics ---
    local sys_dst="$outdir/system"
    mkdir -p "$sys_dst"

    # CPU usage
    if [[ -f /sys/fs/cgroup/cpu.stat ]]; then
        cat /sys/fs/cgroup/cpu.stat >"$sys_dst/cpu.stat"
    fi
    if [[ -f /sys/fs/cgroup/cpu.pressure ]]; then
        cat /sys/fs/cgroup/cpu.pressure >"$sys_dst/cpu.pressure"
    fi

    # Memory usage
    if [[ -f /sys/fs/cgroup/memory.current ]]; then
        cat /sys/fs/cgroup/memory.current >"$sys_dst/memory.current"
    fi
    if [[ -f /sys/fs/cgroup/memory.stat ]]; then
        cat /sys/fs/cgroup/memory.stat >"$sys_dst/memory.stat"
    fi
    if [[ -f /sys/fs/cgroup/memory.events ]]; then
        cat /sys/fs/cgroup/memory.events >"$sys_dst/memory.events"
    fi

    # I/O stats
    if [[ -f /sys/fs/cgroup/io.stat ]]; then
        cat /sys/fs/cgroup/io.stat >"$sys_dst/io.stat"
    fi

    # Number of PIDs
    if [[ -f /sys/fs/cgroup/pids.current ]]; then
        cat /sys/fs/cgroup/pids.current >"$sys_dst/pids.current"
    fi

    # basic /proc stats
    if [[ -f /proc/loadavg ]]; then
        cat /proc/loadavg >"$sys_dst/loadavg"
    fi
    if [[ -f /proc/meminfo ]]; then
        cat /proc/meminfo >"$sys_dst/meminfo"
    fi
    if [[ -f /proc/net/dev ]]; then
        cat /proc/net/dev >"$sys_dst/net_dev"
    fi

}

start() {
    echo "DEBUG: entered start()" >&2
    require_root
    require_cmd kubectl
    require_cmd jq
    require_cmd tar

    OUTPUT="$1"
    NAMESPACE="$2"
    SELECTOR="$3"

    if [[ -z "$OUTPUT" || -z "$NAMESPACE" || -z "$SELECTOR" ]]; then
        usage
        exit 1
    fi

    if [[ -f "$PIDFILE" ]]; then
        echo "ERROR: recorder already running"
        exit 1
    fi

    mkdir -p "$TMPDIR"

    CGROUP_LIST="$TMPDIR/cgroups.list"
    discover_cgroups "$NAMESPACE" "$SELECTOR" || exit 1

    echo "cgroup v2 recorder" > "$TMPDIR/meta.txt"
    echo "Started: $(date -Is)" >> "$TMPDIR/meta.txt"
    echo "Interval: $INTERVAL" >> "$TMPDIR/meta.txt"
    echo "Namespace: $NAMESPACE" >> "$TMPDIR/meta.txt"
    echo "Selector: $SELECTOR" >> "$TMPDIR/meta.txt"
    echo -e "\nEnvironment:" >> "$TMPDIR/meta.txt"
    printenv >> "$TMPDIR/meta.txt"

    mkdir -p $OUTPUT
    cp "$TMPDIR/meta.txt" "$OUTPUT/meta.txt"

    echo "DEBUG: starting recorder loop" >&2
    (
       set -e
       while true; do
        snapshot_once "$OUTPUT"
        sleep "$INTERVAL"
      done
    ) >>"$TMPDIR/recorder.log" 2>&1 &

    echo $! > "$PIDFILE"
    echo "Recording started"
    echo "  PID: $(cat "$PIDFILE")"
    echo "  Output: $OUTPUT"
}

stop() {
    if [[ ! -f "$PIDFILE" ]]; then
        echo "Recorder not running"
        exit 0
    fi

    PID="$(cat "$PIDFILE")"

    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        echo "Recorder stopped (PID $PID)"
    else
        echo "Recorder already stopped"
    fi

    rm -f "$PIDFILE"
}

case "$1" in
    start)
        shift
        start "$@"
        ;;
    stop)
        stop
        ;;
    *)
        usage
        exit 1
        ;;
esac