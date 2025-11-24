#!/usr/bin/env python3

import os
import yaml
import sys
from datetime import datetime
from pathlib import Path
import xmltodict


def read_run_parameters(directory):
    alt_1 = directory / "runParameters.xml"
    alt_2 = directory / "RunParameters.xml"
    if alt_1.exists():
        with open(alt_1) as f:
            return xmltodict.parse(f.read())
    elif alt_2.exists():
        with open(alt_2) as f:
            return xmltodict.parse(f.read())
    else:
        raise Exception("Could not find Illumina [Rr]unParameters.xml. "
                        "Please provide RunParameters.xml or skip module.")


def find(d, tag):
    if isinstance(d, dict):
        if tag in d:
            yield d[tag]
        for k, v in d.items():
            if isinstance(v, dict):
                yield from find(v, tag)
            if isinstance(v, list):
                for i in v:
                    yield from find(i, tag)


def construct_data(run_parameters):
    run_parameters_tags = {
        "RunId": "Run ID",
        "RunID": "Run ID",
        "InstrumentType": "Instrument type",
        "ApplicationName": "Control software",
        "Application": "Control software",
        "ApplicationVersion": "Control software version",
        "SystemSuiteVersion": "Control software version",
        "Flowcell": "Flowcell type",
        "FlowCellMode": "Flowcell type",
        "ReagentKitVersion": "Reagent kit version",
        "RTAVersion": "RTA Version",
        "RtaVersion": "RTA Version",
    }
    data = {}
    for k, v in run_parameters_tags.items():
        for key, value in run_parameters_tags.items():
            info = list(find(run_parameters, key))
            if info:
                data[value] = {"Value": info[0]}
        return data


def construct_multiqc_yaml(directory):

    directory_name = directory.name
    run_parameters = read_run_parameters(directory)

    data = construct_data(run_parameters)

    metadata = {
        "id": "mqc_seq_metadata",
        "section_name": "Sequencing instrument metadata",
        "description": "Sequencing metadata gathered from the run directory",
        "plot_type": "table",
        "pconfig": {
            "id": 'mqc_seq_metadata',
            "title": 'Run directory Metadata',
            "col1_header": "Metadata",
            },
        "data": data,

    }

    return metadata


if __name__ == "__main__":
    rundir_path = Path(sys.argv[1])
    output_file = "illumina_mqc.yml"

    multiqc_yaml = construct_multiqc_yaml(rundir_path)

    with open(output_file, "w") as f:
        yaml.dump(multiqc_yaml, f)
