#!/usr/bin/env bash

set -euo pipefail

EXPID="${1:-}"
PROTOCOL="${2:-HTTP}"

re='^[0-9]+$'
if ! [[ $EXPID =~ $re ]] ; then
   echo "error: Invalid EXPID" >&2; exit 1
fi


rename_cap_files() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        echo "Directory not found: $dir" >&2
        return 2
    fi

    shopt -s nullglob
    for path in "$dir"/*; do
        [[ -f "$path" ]] || continue
        base="$(basename "$path")"

        if [[ "$base" != *grizzly* ]]; then
            rm -v -- "$path"
            continue
        fi

        if [[ "$base" =~ -([0-9]+)-grizzly\.cap$ ]]; then
            seq="${BASH_REMATCH[1]}-trace"
            target="$dir/$seq.cap"
            if [[ -e "$target" ]]; then
                echo "Skipping $base -> $seq.cap : target exists"
            else
                mv -v -- "$path" "$target"
            fi
        else
            echo "Skipping (pattern mismatch): $base"
        fi
    done
    shopt -u nullglob
}

REMOTE_TRACE_PATH="/mnt/LONTAS/traces/$EXPID"

ssh NodeB chown -R ubuntu:ubuntu ${REMOTE_TRACE_PATH}
ssh NodeB chmod -R 777 ${REMOTE_TRACE_PATH}

rsync -avz "NodeB:${REMOTE_TRACE_PATH}/" "$EXPID"

# Rename trace files to their RUN_ID
rename_cap_files "$EXPID"

# Convert traces to protocol specific CSVs
if [[ "$PROTOCOL" == "UDP" ]]; then
    
    for file in "$EXPID"/*; do
        [[ -f "$file" ]] || continue
        [[ "$file" == *.csv ]] && continue

        oneway -p 2 -s 42 -c 1500 \
            --ip.proto=UDP \
            --tp.port=30002 \
            -C "$file"
    done

elif [[ "$PROTOCOL" == "HTTP" ]]; then

    for file in "$EXPID"/*; do
        [[ -f "$file" ]] || continue
        [[ "$file" == *.csv ]] && continue

        new_name="${file%.cap}.csv"

        python3 /home/emizac/http-service-delay-dpmi/http_delay_analyzer.py \
            $file \
            -o $new_name \
            -p 30001
    done


elif [[ "$PROTOCOL" == "TCP" ]]; then

    for file in "$EXPID"/*; do
        [[ -f "$file" ]] || continue
        [[ "$file" == *.csv ]] && continue

        new_name="${file%.cap}.csv"

        python3 /home/emizac/http-service-delay-dpmi/tcp_delay_analyzer.py \
            $file \
            -o $new_name \
            -p 30003
    done

else
    echo "Invalid protocol"
    echo "Usage: $0 TRACE_DIR [TCP|UDP|HTTP]"
    exit 1
fi

# Move each converted RUNID trace pair into EXPID/RUNID.
shopt -s nullglob
for cap_file in "$EXPID"/*.cap; do
    cap_name="$(basename "$cap_file")"

    if [[ "$cap_name" =~ ^([0-9]+)\.cap$ ]]; then
        runid="${BASH_REMATCH[1]}"
        csv_file="$EXPID/$runid.csv"
    elif [[ "$cap_name" =~ ^([0-9]+)-trace\.cap$ ]]; then
        runid="${BASH_REMATCH[1]}"
        csv_file="$EXPID/$runid-trace.csv"
    else
        continue
    fi

    run_dir="$EXPID/$runid"
    mkdir -p "$run_dir"

    mv -f "$cap_file" "$run_dir/$runid-trace.cap"

    if [[ -f "$csv_file" ]]; then
        mv -f "$csv_file" "$run_dir/$runid-trace.csv"
    else
        echo "Warning: missing CSV for RUNID=$runid ($csv_file)"
    fi
done
shopt -u nullglob

# Copy cgroup recordings
REMOTE_CG_PATH="/mnt/LONTAS/ExpControl/k8test/cgroup-recordings"
INFO_FILE="$EXPID/info.txt"

mkdir -p "$EXPID"

# Write a human-readable experiment summary.
cat > "$INFO_FILE" <<EOF
Experiment Summary
==================

Experiment ID: $EXPID
Naming format: dataplane_used-protocol-POLICY_DIRECTION-ISTIO_INSTALLED-ISTIO_POLICY--EXPID-RUNID-KEYID-export
EOF

mapfile -t CGROUP_DIRS < <(
    ssh NodeB "find '$REMOTE_CG_PATH' -mindepth 1 -maxdepth 1 -type d -name '*--${EXPID}-*-*-export' -printf '%f\\n'"
)

shared_written=0

if [[ ${#CGROUP_DIRS[@]} -eq 0 ]]; then
    echo "No cgroup recording directories found for EXPID=$EXPID"
    exit 0
fi

for dir_name in "${CGROUP_DIRS[@]}"; do
    [[ "$dir_name" == *"--"*"-export" ]] || {
        echo "Skipping (unexpected format): $dir_name"
        continue
    }

    left_part="${dir_name%%--*}"
    right_part="${dir_name#*--}"
    right_part="${right_part%-export}"

    if [[ ! "$left_part" =~ ^(.+)-([^-]+)-([^-]+)-([^-]+)-([^-]+)$ ]]; then
        echo "Skipping (cannot parse left side): $dir_name"
        continue
    fi

    dataplane_used="${BASH_REMATCH[1]}"
    protocol_name="${BASH_REMATCH[2]}"
    policy_direction="${BASH_REMATCH[3]}"
    istio_installed="${BASH_REMATCH[4]}"
    istio_policy="${BASH_REMATCH[5]}"

    IFS='-' read -r parsed_expid runid keyid extra <<< "$right_part"
    if [[ -n "${extra:-}" || -z "${parsed_expid:-}" || -z "${runid:-}" || -z "${keyid:-}" ]]; then
        echo "Skipping (cannot parse right side): $dir_name"
        continue
    fi

    if [[ "$parsed_expid" != "$EXPID" ]]; then
        echo "Skipping (EXPID mismatch): $dir_name"
        continue
    fi

    if [[ $shared_written -eq 0 ]]; then
        cat >> "$INFO_FILE" <<EOF
Experiment Variables
--------------------
Dataplane Used : $dataplane_used
Protocol       : $protocol_name
Policy Dir     : $policy_direction
Istio Installed: $istio_installed
Istio Policy   : $istio_policy
Key ID         : $keyid

Runs
----
EOF
        shared_written=1
    fi

    local_parent="$EXPID/$runid/cg"
    mkdir -p "$local_parent"

    # Copy only inner contents of the remote cgroup directory into cg/.
    rsync -avz "NodeB:$REMOTE_CG_PATH/$dir_name/" "$local_parent/"

    # Keep system/ as-is, but flatten pod dirs by moving their child dirs into cg/.
    shopt -s nullglob
    for candidate in "$local_parent"/*; do
        [[ -d "$candidate" ]] || continue

        candidate_name="$(basename "$candidate")"
        [[ "$candidate_name" == "system" ]] && continue

        child_dirs=("$candidate"/*/)
        [[ ${#child_dirs[@]} -eq 0 ]] && continue

        for child in "${child_dirs[@]}"; do
            child_name="$(basename "${child%/}")"
            if [[ -e "$local_parent/$child_name" ]]; then
                echo "Skipping move (target exists): $local_parent/$child_name"
                continue
            fi
            mv "$child" "$local_parent/"
        done

        rmdir "$candidate" 2>/dev/null || true
    done
    shopt -u nullglob

    cat >> "$INFO_FILE" <<EOF
Run ID: $runid
  Remote Dir   : $dir_name
  Local CG Path: $local_parent
  Trace CAP    : $EXPID/$runid/$runid-trace.cap
  Trace CSV    : $EXPID/$runid/$runid-trace.csv

EOF
done

echo "Cgroup recordings downloaded. Info written to: $INFO_FILE"

