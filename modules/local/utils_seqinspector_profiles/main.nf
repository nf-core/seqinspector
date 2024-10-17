
/*
========================================================================================
    CLASSES
========================================================================================
*/


/*
========================================================================================
    FUNCTIONS
========================================================================================
*/


    // Method to perform AND operation: Perform AND common entries and set the rest to false (interpret absence as false)
    public ToolProfile andOperation(ToolProfile other) {
        ToolProfile result = new ToolProfile()
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

    // Method to perform UnionOR operation: Retain entries that exists in either of the ToolProfile instances, OR for common entries
    public ToolProfile orOperation(ToolProfile other) {
        ToolProfile result = new ToolProfile()
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

        // Method to perform exclusiveOR (XOR) operation: Retain entries that exists in either of the ToolProfile instances, but not both
    public ToolProfile xorOperation(ToolProfile other) {
        ToolProfile result = new ToolProfile()
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

    // Method to perform inclusiveAND operation: Retain entries that exists in either of the ToolProfile instances, AND conjunction for common entries
    public ToolProfile iAndOperation(ToolProfile other) {
        ToolProfile result = new ToolProfile()
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
