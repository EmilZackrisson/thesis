
from typing import Optional
import os
from pathlib import Path


def parse_net_dev(file_path: str) -> dict[str, dict[str,int]]:
    lines = open(file_path, "r").readlines()

    columnLine = lines[1]
    _, receiveCols , transmitCols = columnLine.split("|")
    receiveCols = ["recv_" + col for col in receiveCols.split()]
    transmitCols = ["trans_" + col for col in transmitCols.split()]

    cols = receiveCols + transmitCols

    faces = {}
    for line in lines[2:]:
        if line.find(":") < 0: continue
        face, data = line.split(":")
        faceData = {key: int(value) for key, value in zip(cols, data.split())}
        faces[face.strip()] = faceData

    return faces

def stat_file_to_dict(stat_file_path: str) -> dict[str, int]:
    stat: dict[str, int] = {}
    with open(stat_file_path, "r") as f:
        for line in f:
            line_split = line.split(' ')
            stat[line_split[0]] = int(line_split[1])
    return stat

def current_file_to_int(current_file_path: str) -> Optional[int]:
    try:
        with open(current_file_path, "r") as f:
            return int(f.readline())
    except (OSError, ValueError) as e:
        print(e)

def parse_pressure_file(file_path: str) -> dict[str, dict[str, float | int]]:
    pressure: dict[str, dict[str, float | int]] = {}
    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            tokens = line.split()
            pressure_type = tokens[0]
            metrics: dict[str, float | int] = {}
            for token in tokens[1:]:
                key, value = token.split("=", 1)
                if key == "total":
                    metrics[key] = int(value)
                else:
                    metrics[key] = float(value)
            pressure[pressure_type] = metrics

    return pressure

def parse_io_stat_file(file_path: str) -> dict[str, dict[str, int]]:
    io_stat: dict[str, dict[str, int]] = {}
    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            tokens = line.split()
            device = tokens[0]
            metrics: dict[str, int] = {}
            for token in tokens[1:]:
                key, value = token.split("=", 1)
                metrics[key] = int(value)
            io_stat[device] = metrics

    return io_stat

def parse_loadavg_file(file_path: str) -> dict[str, float | int]:
    with open(file_path, "r") as f:
        parts = f.readline().split()

    running_tasks, total_tasks = parts[3].split("/")
    return {
        "load1": float(parts[0]),
        "load5": float(parts[1]),
        "load15": float(parts[2]),
        "running_tasks": int(running_tasks),
        "total_tasks": int(total_tasks),
        "last_pid": int(parts[4]),
    }

def parse_meminfo_file(file_path: str) -> dict[str, int]:
    meminfo: dict[str, int] = {}
    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            key, rest = line.split(":", 1)
            value_tokens = rest.split()
            if not value_tokens:
                continue

            meminfo[key] = int(value_tokens[0])

    return meminfo

def parse_container_dir(container_dir: Path) -> dict[str, int | dict]:
    ret_dict: dict[str, int | dict] = {}

    file_parsers = {
        "cpu.pressure": parse_pressure_file,
        "cpu.stat": stat_file_to_dict,
        "io.stat": parse_io_stat_file,
        "memory.current": current_file_to_int,
        "memory.events": stat_file_to_dict,
        "memory.stat": stat_file_to_dict,
        "pids.current": current_file_to_int,
    }

    for file_name, parser in file_parsers.items():
        file_path = os.path.join(container_dir, file_name)
        if os.path.exists(file_path):
            ret_dict[file_name] = parser(file_path)

    return ret_dict

def parse_system_dir(system_dir: Path) -> dict[str, int | dict]:
    ret_dict: dict[str, int | dict] = {}

    file_parsers = {
        "cpu.pressure": parse_pressure_file,
        "cpu.stat": stat_file_to_dict,
        "io.stat": parse_io_stat_file,
        "loadavg": parse_loadavg_file,
        "meminfo": parse_meminfo_file,
        "memory.stat": stat_file_to_dict,
        "net_dev": parse_net_dev,
    }

    for file_name, parser in file_parsers.items():
        file_path = os.path.join(system_dir, file_name)
        if os.path.exists(file_path):
            ret_dict[file_name] = parser(file_path)

    return ret_dict