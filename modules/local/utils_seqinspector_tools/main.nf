
include { getEnumNames } from '../utils_seqinspector_validation/main.nf'

/*
========================================================================================
    FUNCTIONS
========================================================================================
*/

def getAllToolNames() {
        getEnumNames(SeqinspectorDataClasses.Tool)
    }
