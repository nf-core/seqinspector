// Helper functions for pipeline tests

class UTILS {

    public static def getAssertions = { Map args ->
        // Mandatory, as we always need an outdir
        def outdir = args.outdir

        // Get scenario and extract all properties dynamically
        def scenario = args.scenario ?: [:]

        // Pass down workflow for std capture
        def workflow = args.workflow

        def snapshot_ignore_list = [
            "Creating env using",
            "Downloading plugin",
            "Pulling Singularity image",
            "Staging foreign file",
            "unable to stage foreign file"
        ]

        // stable_name: All files + folders in ${outdir}/ with a stable name
        def stable_name = getAllFilesFromDir(outdir, relative: true, includeDir: true, ignore: ['pipeline_info/*.{html,json,txt}'])
        // stable_content: All files in ${outdir}/ with stable content
        def stable_content = getAllFilesFromDir(outdir, ignoreFile: 'tests/.nftignore', ignore: [scenario.ignoreFiles ])
        // bam_files: All bam files
        def bam_files = getAllFilesFromDir(outdir, include: ['**/*.bam'], ignore: [scenario.ignoreFiles ])
        // cram_files: All cram files
        def fasta_base = 'https://raw.githubusercontent.com/nf-core/test-datasets/modules/data/'

        def assertion = []

        if (!scenario.failure) {
            assertion.add(workflow.trace.succeeded().size())
            assertion.add(removeFromYamlMap("${outdir}/pipeline_info/nf_core_seqinspector_software_mqc_versions.yml", "Workflow"))
        }

        // At least always pipeline_info/ is created and stable
        assertion.add(stable_name)

        if (!scenario.stub) {
            assertion.add(stable_content.isEmpty() ? 'No stable content' : stable_content)
            assertion.add(bam_files.isEmpty() ? 'No BAM files' : bam_files.collect { file -> file.getName() + ":md5," + bam(file.toString()).readsMD5 })
        }

        // Always capture stdout and stderr for any WARN message
        assertion.add(filterNextflowOutput(workflow.stderr + workflow.stdout, include: ["WARN"], ignore: snapshot_ignore_list + (scenario.snapshot_ignoreWarning ?: [])) ?: "No warnings")

        // Capture std for snapshot
        // Allow to capture either stderr, stdout or both
        // Additional possibilities to include and/or ignore some string
        if (scenario.snapshot) {
            def workflow_std = []

            scenario.snapshot.split(',').each { std ->
                if (std in ['stderr', 'stdout']) { workflow_std.add(workflow."$std") }
            }

            if (scenario.snapshot_include) {
                assertion.add(filterNextflowOutput(workflow_std.flatten(), ignore: snapshot_ignore_list + (scenario.snapshot_ignore ?: []), include:[scenario.snapshot_include]))
            } else {
                assertion.add(filterNextflowOutput(workflow_std.flatten(), ignore: snapshot_ignore_list + (scenario.snapshot_ignore ?: [])))
            }
        }

        return assertion
    }

    public static def getTest = { scenario ->
        // This function returns a closure that will be used to run the test and the assertion
        // It will create tags or options based on the scenario

        return {
            // If the test is for a gpu, we add the gpu tag
            // Otherwise, we add the cpu tag
            // If the tests has no conda incompatibilities
            // then we append "_conda" to the cpu/gpu tag
            // If the test is for a stub, we add options -stub
            // And we append "_stub" to the cpu/gpu tag

            // All options should be:
            // gpu (this is the default for gpu)
            // cpu (this is the default for tests without conda)
            // gpu_conda (this should never happen)
            // cpu_conda (this is the default for tests with conda compatibility)
            // gpu_stub
            // cpu_stub
            // gpu_conda_stub (this should never happen)
            // cpu_conda_stub

            tag "pipeline"
            tag "pipeline_seqinspector"

            if (scenario.stub) {
                options "-stub"
            }

            options "-output-dir $outputDir"

            if (scenario.gpu) {
                tag "gpu${!scenario.no_conda ? '_conda' : ''}${scenario.stub ? '_stub' : ''}"
            }

            if (!scenario.gpu) {
                tag "cpu${!scenario.no_conda ? '_conda' : ''}${scenario.stub ? '_stub' : ''}"
            }

            // If a tag is provided, add it to the test
            if (scenario.tag) {
                tag scenario.tag
            }

            when {
                params {
                    // Mandatory, as we always need an outdir
                    outdir = "${outputDir}"
                    // Apply scenario-specific params
                    scenario.params.each { key, value ->
                        delegate."$key" = value
                    }
                }
            }

            then {
                // Assert failure/success, and fails early so we don't pollute console with massive diffs
                if (scenario.failure) {
                    assert workflow.failed
                } else {
                    assert workflow.success
                }
                assertAll(
                    { assert snapshot(
                        // All assertions based on the scenario
                        *UTILS.getAssertions(
                            outdir: params.outdir,
                            scenario: scenario,
                            workflow: workflow
                        )
                    ).match() }
                )
            }
            cleanup {
                if (System.getenv('NFT_CLEANUP')) {
                    println ""
                    println "CLEANUP"
                    println "Set NFT_CLEANUP to false to disable."
                    println "The following folders will be deleted:"
                    println "- ${workDir}"

                    new File("${workDir}").deleteDir()
                }
            }
        }
    }
}
