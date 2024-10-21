/*
========================================================================================
    FUNCTIONS
========================================================================================
*/

// Function to get a valid profile from a ToolProfiles map
    /*
    String profileStr,
    Map<String, ToolProfile> toolProfilesMap
    <logger> log
    */

def getProfileFromToolProfiles(profileStr, toolProfilesMap, log) {

        if (!toolProfilesMap) {
            toolProfilesMap = SeqinspectorDataClasses.ToolProfiles
        }

        if (!toolProfilesMap.containsKey(profileStr.toUpperCase())) {
            def keys = toolProfilesMap.keySet().toLowerCase().join('\n  - ')
            log.error "Invalid profile specified: '${profileStr}'. Valid options are:\n  - ${keys}"
            nextflow.Nextflow.exit(1)
        }
        return toolProfilesMap[profileStr]
    }


// Function to combine two profiles
    /*
    String profileStr,
    Map<String, ToolProfile> toolProfilesMap
    <logger> log
    */

def combine_profiles(firstProfile, otherProfile, log) {

     // Create a new ToolProfile instance to store the combined results
    def combinedProfile = new SeqinspectorDataClasses.ToolProfile(
        enable: (firstProfile.enable + otherProfile.enable),
        disable: (firstProfile.disable + otherProfile.disable),
        tool_arguments: [:]
    )

    // remove possibly disabled tools
    combinedProfile.enable.removeAll(combinedProfile.disable)


    // Combine tool_arguments maps
    def allArgs = firstProfile.tool_arguments.keySet() + otherProfile.tool_arguments.keySet()
    allArgs.each { tool ->
        def firstArgs = firstProfile.tool_arguments[tool] ?: [:]
        def otherArgs = otherProfile.tool_arguments[tool] ?: [:]

        // Check for common arguments specified in both profiles for a tool
        def commonArgs = firstArgs.keySet().intersect(otherArgs.keySet())
        // if a common setting for a tool is detected, compare the values
        if (commonArgs) {
            def incompatibleArgs = false
            commonArgs.each { arg ->
                if(firstArgs[arg] != otherArgs[arg]) {
                log.error "Conflicting settings of argument '${arg}' for tool '${tool}'"
                incompatibleArgs = true
                }
            }
            if(incompatibleArgs) {
                nextflow.Nextflow.exit(1)
            }
        }
        combinedProfile.tool_arguments[tool] = firstArgs + otherArgs
    }

    return combinedProfile


}

