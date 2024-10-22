
new GroovyShell().evaluate(new File("$projectDir/lib/SeqinspectorDataClasses.groovy"))

/*
========================================================================================
    FUNCTIONS
========================================================================================
*/


// Function to convert a string to an enum variant (enums give you a way of saying a value is one of a possible set of values)
    /*
    String s
    Enum e
    */


def getEnumFromString(s, e) {
    try {
        return e.valueOf(s.toUpperCase())
    } catch(java.lang.IllegalArgumentException err) {
        return null
    }
}

// Function to return all possible names of an enum
    /*
    Enum e
    */

def getEnumNames(e) {
    e
        .values()
        *.name()
        *.toLowerCase()
}



// Function to convert a comma-seperated string of tools to a list of Tool enums
    /*
    String tool_str
    */

def validateToolList(tool_str, log) {
        if (!tool_str) {
            return []
        }
        return tool_str
            .tokenize(',')
            .collect { token ->
                try {
                    return SeqinspectorDataClasses.Tool.valueOf(token.toUpperCase())
                } catch(java.lang.IllegalArgumentException e) {
                    def all_tools = getEnumNames(SeqinspectorDataClasses.Tool).join('\n  - ')
                    log.error "Recieved invalid tool specification: '${token}'. Valid options are:\n  - ${all_tools}"
                    nextflow.Nextflow.exit(1)
                }
            }
            .unique()
    }

    // Function to check if the include and exclude lists have any common elements
    /*
    List<Enum> include_list
    List<Enum> exclude_list
    */

def checkIncludeExcludeList(include_list, exclude_list, log) {
        def common_tools = include_list + exclude_list
            .countBy { it }
            .findAll { k, v -> v > 1 }
            .keySet()

        if (common_tools) {
            def common_tools_str = common_tools.values().join('\n  - ')
            def message_base = 'The following tools were found in the include and the exclude lists!'
            log.error "${message_base}:\n  - ${common_tools_str}"
            nextflow.Nextflow.exit(1)
        }
}


// Function to validate the run mode by comparing it to the enumerated values of a constant
    /*
    String run_mode
    */

def validateRunMode(run_mode, log) {
    def run_mode_enum = getEnumFromString(run_mode, SeqinspectorDataClasses.RunMode)
    if (!run_mode_enum) {
        def run_modes_str = getEnumNames(SeqinspectorDataClasses.RunMode).join('\n  - ')
        log.error "Invalid run mode selected: '${run_mode}'. Valid options are:\n  - ${run_modes_str}"
        nextflow.Nextflow.exit(1)
    }
    return run_mode_enum
}
