// enum for the supported run modes

public static enum RunMode {
        FASTQ,
        RUNFOLDER,
    }

// enum for the available tools

public static enum Tool {
        FASTQSCREEN,
        FASTQC,
        MULTIQC,
    }

// ToolProfile class to define and intersect selections of tools and handle extra arguments and settings

public class ToolProfile {
    Set<Tool> enable
    Set<Tool> disable
    Map<Tool, Map<String,String>> tool_arguments = [:]
}



