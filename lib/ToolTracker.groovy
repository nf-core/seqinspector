/* Example usage of the ToolTracker class to define and intersect selections of tools

def profile1 = new ToolTracker()
profile1['tool1'] = true
profile1['tool2'] = false
profile1['tool3'] = false

def profile2 = new ToolTracker()
profile2['tool1'] = false
profile2['tool2'] = true

def andResult = profile1.andOperation(profile2)
def orResult = profile1.orOperation(profile2)

println "AND Result: ${andResult.tool_selection}"
println "OR Result: ${orResult.tool_selection}"

*/

// ToolTracker class to define and intersect selections of tools

class ToolTracker {
    Map<String, Boolean> tool_selection = [:]

    // Override getAt method for concise access
    Boolean getAt(String tool) {
        return tool_selection[tool]
    }

    // Override putAt method for concise assignment
    void putAt(String tool, Boolean setting) {
        tool_selection[tool] = setting
    }

    // There is actually no use for non-union methods, since that would eliminate entries from the maps.


        // Method to perform AND operation: Perform AND common entries and set the rest to false (interpret absence as false)
    public ToolTracker andOperation(ToolTracker other) {
        ToolTracker result = new ToolTracker()
        Set<String> allTools = this.tool_selection.keySet() + other.tool_selection.keySet()

        allTools.each { tool ->
            if (this.tool_selection.containsKey(tool) && other.tool_selection.containsKey(tool)) {
                result[tool] = this[tool] && other[tool]
            } else if (this.tool_selection.containsKey(tool) && !other.tool_selection.containsKey(tool)) {
                result[tool] = false
            } else if (!this.tool_selection.containsKey(tool) && other.tool_selection.containsKey(tool)) {
                result[tool] = false
            }
        }
        return result
    }

    // Method to perform UnionOR operation: Retain entries that exists in either of the ToolTracker instances, OR for common entries
    public ToolTracker orOperation(ToolTracker other) {
        ToolTracker result = new ToolTracker()
        Set<String> allTools = this.tool_selection.keySet() + other.tool_selection.keySet()

        allTools.each { tool ->
            if (this.tool_selection.containsKey(tool) && other.tool_selection.containsKey(tool)) {
                result[tool] = this[tool] || other[tool]
            } else if (this.tool_selection.containsKey(tool) && !other.tool_selection.containsKey(tool)) {
                result[tool] = this[tool]
            } else if (!this.tool_selection.containsKey(tool) && other.tool_selection.containsKey(tool)) {
                result[tool] = other[tool]
            }
        }
        return result
    }

        // Method to perform exclusiveOR (XOR) operation: Retain entries that exists in either of the ToolTracker instances, but not both
    public ToolTracker xorOperation(ToolTracker other) {
        ToolTracker result = new ToolTracker()
        Set<String> allTools = this.tool_selection.keySet() + other.tool_selection.keySet()

        allTools.each { tool ->
            if (this.tool_selection.containsKey(tool) && !other.tool_selection.containsKey(tool)) {
                result[tool] = this[tool]
            } else if (!this.tool_selection.containsKey(tool) && other.tool_selection.containsKey(tool)) {
                result[tool] = other[tool]
            } else {
                result[tool] = false
            }
        }
        return result
    }

    // Method to perform inclusiveAND operation: Retain entries that exists in either of the ToolTracker instances, AND conjunction for common entries
    public ToolTracker iAndOperation(ToolTracker other) {
        ToolTracker result = new ToolTracker()
        Set<String> allTools = this.tool_selection.keySet() + other.tool_selection.keySet()

        allTools.each { tool ->
            if (this.tool_selection.containsKey(tool) && other.tool_selection.containsKey(tool)) {
                result[tool] = this[tool] && other[tool]
            } else if (this.tool_selection.containsKey(tool) && !other.tool_selection.containsKey(tool)) {
                result[tool] = this[tool]
            } else if (!this.tool_selection.containsKey(tool) && other.tool_selection.containsKey(tool)) {
                result[tool] = other[tool]
            }
        }
        return result
    }

}

