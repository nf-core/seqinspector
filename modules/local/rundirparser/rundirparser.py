# rundirparser.py
import sys
import yaml


def parse_rundir(rundir):
    # Dummy implementation, replace with actual logic

    yml_contents = """# plot_type: 'table'
# section_name: 'rundir stats'
# description: 'dummy rundir stats'
# pconfig:
#     namespace: 'Cust Data'
# headers:
#     col1:
#         title: '#Seqs'
#         description: 'Number of sequences'
#         format: '{:,.0f}'
#     col2:
#         title: 'Total bp'
#         description: 'Total size of the dataset'
#     col3:
#         title: 'Avg'
#         description: 'Average sequence length'
#     col4:
#         title: 'N50'
#         description: '50% of the sequences are longer than this size'
#     col5:
#         title: 'N75'
#         description: '75% of the sequences are longer than this size'
#     col6:
#         title: 'N90'
#         description: '90% of the sequences are longer than this size'
#     col7:
#         title: 'Min'
#         description: 'Length of the shortest sequence'
#     col8:
#         title: 'Max'
#         description: 'Length of the longest sequence'
#     col9:
#         title: 'auN'
#         description: 'Area under the Nx curve'
#     col10:
#         title: 'GC'
#         description: 'Relative GC content (excluding Ns)'
"""
    tsv_contents = f"""Sample	col1	col2	col3	col4	col5	col6	col7	col8	col9	col10
{rundir}	10	147806	14780.6000000	22507	16573	15322	22801.9181765	344	33340	NaN
"""

    contents = yml_contents + tsv_contents

    with open(f"{rundir}_mqc.txt", "w") as f:
        f.write(contents)


def main():
    rundir = sys.argv[1]
    parse_rundir(rundir)


if __name__ == "__main__":
    main()
