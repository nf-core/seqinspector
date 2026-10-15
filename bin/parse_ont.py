#!/usr/bin/env python3

# Licence: MIT

import json
import sys
from datetime import datetime
from pathlib import Path

import yaml


def read_report(directory):
    reports = sorted(directory.glob("report_*.json"))
    if not reports:
        raise Exception(
            "Could not find ONT MinKNOW report_*.json. "
            "Please provide the MinKNOW run report or skip module."
        )
    with open(reports[0]) as f:
        return json.load(f)


def get(d, *keys):
    # MinKNOW report layout varies between versions, so return None for any missing key
    for key in keys:
        if not isinstance(d, dict) or key not in d:
            return None
        d = d[key]
    return d


def parse_time(timestamp):
    # MinKNOW timestamps have nanosecond precision, which datetime can not parse
    date, _, _ = timestamp.rstrip("Z").partition(".")
    return datetime.fromisoformat(date)


def main_acquisition(report):
    # A run has several short acquisitions (e.g. calibration) before the sequencing one,
    # pick the acquisition with the most reads
    acquisitions = report.get("acquisitions", [])
    return max(
        acquisitions,
        key=lambda a: int(get(a, "acquisition_run_info", "yield_summary", "read_count") or 0),
        default={},
    )


def arg_value(run_info, name):
    # Protocol args are a flat list, e.g. ["--read_filtering", "min_qscore=8"]
    for arg in run_info.get("args", []):
        if arg.startswith(name + "="):
            return arg.split("=", 1)[1]
    return None


def construct_data(report):
    run_info = report.get("protocol_run_info", {})
    acquisition = main_acquisition(report)
    yield_summary = get(acquisition, "acquisition_run_info", "yield_summary") or {}
    # MinKNOW < 6 stores software versions at the top level and uses Guppy as basecaller
    versions = run_info.get("software_versions") or report.get("software_versions") or {}

    info = {
        "Run ID": get(run_info, "run_id"),
        "Instrument type": get(report, "host", "product_name") or get(run_info, "device", "device_type"),
        "Control software": "MinKNOW",
        "Control software version": get(versions, "minknow", "full"),
        "Flowcell type": get(run_info, "flow_cell", "product_code")
        or get(run_info, "flow_cell", "user_specified_product_code"),
        "Flowcell ID": get(run_info, "flow_cell", "flow_cell_id")
        or get(run_info, "flow_cell", "user_specified_flow_cell_id"),
        "Sequencing kit": get(run_info, "user_info", "kit_info", "sequencing_kit")
        or get(run_info, "meta_info", "tags", "kit", "string_value"),
        "Basecaller version": versions.get("basecaller_connected_version") or versions.get("guppy_connected_version"),
        "Basecalling model": get(acquisition, "basecaller_config", "model_names", "simplex_model")
        or get(acquisition, "acquisition_run_info", "config_summary", "basecalling_config_filename"),
        "Min Q-score": get(acquisition, "basecaller_config", "read_filtering", "min_qscore")
        or arg_value(run_info, "min_qscore"),
    }

    start_time = get(run_info, "start_time")
    end_time = get(run_info, "end_time")
    if start_time:
        info["Start time"] = parse_time(start_time).strftime("%Y-%m-%d %H:%M")
    if start_time and end_time:
        hours = (parse_time(end_time) - parse_time(start_time)).total_seconds() / 3600
        info["Run time"] = f"{hours:.1f} h"

    # read_count is counted before read splitting, so use pass + fail as the total
    pass_reads = int(yield_summary.get("basecalled_pass_read_count", 0))
    fail_reads = int(yield_summary.get("basecalled_fail_read_count", 0))
    pass_bases = int(yield_summary.get("basecalled_pass_bases", 0))
    if pass_reads + fail_reads:
        info["Basecalled reads"] = f"{pass_reads + fail_reads:,}"
        info["Pass reads"] = f"{pass_reads:,} ({100 * pass_reads / (pass_reads + fail_reads):.1f}%)"
        info["Pass bases"] = f"{pass_bases / 1e9:.2f} Gb"

    return {key: {"Value": str(value)} for key, value in info.items() if value is not None}


def construct_multiqc_yaml(directory):

    report = read_report(directory)

    data = construct_data(report)

    metadata = {
        "id": "mqc_seq_metadata",
        "section_name": "Sequencing instrument metadata",
        "description": "Sequencing metadata gathered from the run directory",
        "plot_type": "table",
        "pconfig": {
            "id": "mqc_seq_metadata",
            "title": "Run directory Metadata",
            "col1_header": "Metadata",
        },
        "data": data,
    }

    return metadata


if __name__ == "__main__":
    rundir_path = Path(sys.argv[1])
    output_file = "ont_mqc.yml"

    multiqc_yaml = construct_multiqc_yaml(rundir_path)

    with open(output_file, "w") as f:
        yaml.dump(multiqc_yaml, f, sort_keys=False)
