// enum for the supported run modes

static enum RunMode {
        FASTQ,
        RUNFOLDER,
    }

// enum for the available Tools

static enum Tool {
        FASTQSCREEN,
        FASTQC,
        // MULTIQC, // Turning MultiQC off kind of defeats the purpose of the pipeline
    }

// ToolProfile class to define and intersect selections of tools

class ToolProfile {
    Set<Tool> enable
    Set<Tool> disable
    Map<Tool, Map<String,String>> tool_arguments = [:]
}



