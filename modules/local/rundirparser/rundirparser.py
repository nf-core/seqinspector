# rundirparser.py
import sys
import yaml


def parse_rundir(rundir):
    # Dummy implementation, replace with actual logic
    return_dict = {
        "rundir": rundir,
        "samples": [
            {"sample_id": "SAMPLE_1", "metric_1": 10, "metric_2": 20},
            {"sample_id": "SAMPLE_2", "metric_1": 15, "metric_2": 25},
            {"sample_id": "SAMPLE_3", "metric_1": 20, "metric_2": 30},
        ],
    }
    return return_dict


def main():
    rundir = sys.argv[1]
    metadata = parse_rundir(rundir)
    with open(f"{rundir}_mqc.yml", "w") as outfile:
        yaml.dump(metadata, outfile, default_flow_style=False)


if __name__ == "__main__":
    main()
