// Class to hold ultility functions, inspired by nf-core/oncoanalyser

class Ultilities {

    public static getEnumFromString(String s, Enum e) {
        try {
            return e.valueOf(s.toUpperCase())
        } catch(java.lang.IllegalArgumentException err) {
            return null
        }
    }

    public static getEnumNames(Enum e) {
        e
            .values()
            *.name()
            *.toLowerCase()
    }


    public static getAllToolNames() {
        Ultilities.getEnumNames(Constants.Tool)
    }

    // Function to get a valid profile from a ToolProfiles map

    public static getProfileFromToolProfiles(String profile, Map<String, ToolTracker> toolProfiles, log) {

        if (!toolProfiles) {
            toolProfiles = Constants.ToolProfiles
        }

        if (!toolProfiles.containsKey(profile.toUpperCase())) {
            def keys = toolProfiles.keySet().toLowerCase().join('\n  - ')
            log.error "Invalid profile specified: '${profile}'. Valid options are:\n  - ${keys}"
            nextflow.Nextflow.exit(1)
        }
        return map[key]
    }

    // Function to convert a comma-seperated string of tools to a list of Tool enums

    public static getToolList(String tool_str, log) {
        if (!tool_str) {
            return []
        }
        return tool_str
            .tokenize(',')
            .collect { token ->
                try {
                    return Constants.Tool.valueOf(token.toUpperCase())
                } catch(java.lang.IllegalArgumentException e) {
                    def all_tools = Ultilities.getAllToolNames().join('\n  - ')
                    log.error "Recieved invalid tool specification: '${token}'. Valid options are:\n  - ${all_tools}"
                    nextflow.Nextflow.exit(1)
                }
            }
            .unique()
    }

    // Function to check if the include and exclude lists have any common elements

    public static checkIncludeExcludeList(List<Enum> include_list, List<Enum> exclude_list, log) {
        def common_tools = [*include_list, *exclude_list]
            .countBy { it }
            .findAll { k, v -> v > 1 }
            .keySet()

        if (common_tools) {
            def common_tools_str = common_tools.values().join('\n  - ')
            def message_base = 'The following tools were found in the include and the exclude lists!'
            log.error "${message_base}:\n  - ${processes_shared_str}"
            nextflow.Nextflow.exit(1)
        }
    }

    // Create a ToolTracker from the include and exclude lists

    public static buildToolTracker(List<Enum> include_tools, List<Enum> exclude_tools) {
        def tool_tracker = new ToolTracker()
        include_tools
            .each { tool ->
                tool_tracker[tool.name()] = true
            }
        exclude_tools
            .each { tool ->
                tool_tracker[tool.name()] = false
            }
        return tool_tracker
    }

    public parseAndApplyBooleanOperation(String profileString, Map<String, ToolTracker> toolProfiles, log) {
        def tokens = profileString.tokenize(' ')

        // A valid string must always consist of an odd number of tokens, e.g. "default" or "default AND minimal"
        if (tokens.size() % 2 == 0) {
            log.error("Invalid profile operation specified: $profileString")
            nextflow.Nextflow.exit(1)
        }

        def result = Ultilities.getProfileFromToolProfiles([tokens[0],toolProfiles,log)

        // Sequentially apply the operations in a left to right manner

        for (int i = 1; i < tokens.size(); i += 2) {
            def operation = tokens[i].toUpperCase()
            def nextProfile =  Ultilities.getProfileFromToolProfiles([tokens[i + 1],toolProfiles,log)

            // New Nextflow syntax no longer supports Java-style switch statements

            if (operation == "AND") {
                result = result.andOperation(nextProfile)
            } else if (operation == "OR") {
                result = result.orOperation(nextProfile)
            } else if (operation == "IAND") {
                result = result.iAndOperationOperation(nextProfile)
            } else if (operation == "XOR") {
                result = result.xorOperation(nextProfile)
            } else {
                log.error("Unsupported operation: $operation")
                nextflow.Nextflow.exit(1)
            }
        }

        return result
    }

    // Function to convert the run mode string to a RunMode enum (check for validity)

    public static getRunMode(String run_mode, log) {
        def run_mode_enum = Ultilities.getEnumFromString(run_mode, Constants.RunMode)
        if (!run_mode_enum) {
            def run_modes_str = Ultilities.getEnumNames(Constants.RunMode).join('\n  - ')
            log.error "Invalid run mode selected: '${run_mode}'. Valid options are:\n  - ${run_modes_str}"
            Nextflow.exit(1)
        }
        return run_mode_enum
    }

}
