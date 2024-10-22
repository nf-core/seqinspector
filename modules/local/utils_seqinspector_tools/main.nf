
include { getEnumNames } from '../utils_seqinspector_validation/main.nf'

new GroovyShell().evaluate(new File("$projectDir/lib/SeqinspectorDataClasses.groovy"))

/*
========================================================================================
    FUNCTIONS
========================================================================================
*/

def getAllToolNames() {
        getEnumNames(SeqinspectorDataClasses.Tool)
    }
