import groovy.json.JsonGenerator
import groovy.json.JsonGenerator.Converter

nextflow.enable.dsl=2

// comes from nf-test to store json files
params.nf_test_output  = ""

// include dependencies


// include test workflow
include { QC_BAM } from '/Users/beatrizsavinhas/development/seqinspector/subworkflows/local/qc_bam/main.nf'

// define custom rules for JSON that will be generated.
def jsonOutput =
    new JsonGenerator.Options()
        .addConverter(Path) { value -> value.toAbsolutePath().toString() } // Custom converter for Path. Only filename
        .build()

def jsonWorkflowOutput = new JsonGenerator.Options().excludeNulls().build()

workflow {

    // run dependencies
    

    // workflow mapping
    def input = []
    
                input[0]  = channel.of(
                    [
                        [id:'earlycasualcaiman', sample:'earlycasualcaiman', single_end:false, num_lanes:1, read_group: "'@RG\\tID:earlycasualcaiman\\tPL:illumina\\tSM:earlycasualcaiman'", lane:1, sex:1, phenotype:1, paternal:0, maternal:0, case_id:'justhusky'],
                        [file(params.pipelines_testdata_base_path + '/testdata/earlycasualcaiman_sorted_md.bam', checkIfExists: true)],
                        [file(params.pipelines_testdata_base_path + '/testdata/earlycasualcaiman_sorted_md.bam.bai', checkIfExists: true)]
                    ]
                )
                input[1]  = channel.fromPath(params.pipelines_testdata_base_path + '/reference/target.bed', checkIfExists: true).collect()
                input[2]  = channel.fromPath(params.pipelines_testdata_base_path + '/reference/target.bed', checkIfExists: true).collect()
                input[3]  = channel.of([id:'genome'], file(params.pipelines_testdata_base_path + '/reference/reference.fasta', checkIfExists: true)).collect()
                input[4]  = channel.of([id:'genome'], file(params.pipelines_testdata_base_path + '/reference/reference.fasta.fai', checkIfExists: true)).collect()
                input[5]  = channel.of([id:'genome'], file(params.pipelines_testdata_base_path + '/reference/reference.dict', checkIfExists: true)).collect()
                
    //----

    //run workflow
    QC_BAM(*input)
    
    if (QC_BAM.output){

        // consumes all named output channels and stores items in a json file
        for (def name in QC_BAM.out.getNames()) {
            serializeChannel(name, QC_BAM.out.getProperty(name), jsonOutput)
        }	  
    
        // consumes all unnamed output channels and stores items in a json file
        def array = QC_BAM.out as Object[]
        for (def i = 0; i < array.length ; i++) {
            serializeChannel(i, array[i], jsonOutput)
        }    	

    }
}


def serializeChannel(name, channel, jsonOutput) {
    def _name = name
    def list = [ ]
    channel.subscribe(
        onNext: {
            list.add(it)
        },
        onComplete: {
              def map = new HashMap()
              map[_name] = list
              def filename = "${params.nf_test_output}/output_${_name}.json"
              new File(filename).text = jsonOutput.toJson(map)		  		
        } 
    )
}


workflow.onComplete {

    def result = [
        success: workflow.success,
        exitStatus: workflow.exitStatus,
        errorMessage: workflow.errorMessage,
        errorReport: workflow.errorReport
    ]
    new File("${params.nf_test_output}/workflow.json").text = jsonWorkflowOutput.toJson(result)
    
}
