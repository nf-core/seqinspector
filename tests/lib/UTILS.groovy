// Helper functions for pipeline tests

class UTILS {

    public static def getAssertions = { Map args ->
        // Mandatory, as we always need an outdir
        def outdir = args.outdir

        // Get scenario and extract all properties dynamically
        def scenario = args.scenario ?: [:]

        // Pass down workflow for std capture
        def workflow = args.workflow

        // These strings are not stable and should be ignored
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

        // If we have a snapshot options in scenario then we allow to capture either stderr, stdout or both
        // With options to include specific stings
        def workflow_std = []
        // Otherwise, we always capture stdout and stderr for any WARN message
        // Both have additional possibilities to ignore some strings
        def filter_args = [ignore: snapshot_ignore_list + (scenario.snapshot_ignore ?: [])]

        if (scenario.snapshot) {
            workflow_std = scenario.snapshot.split(',')
                .findAll { it in ['stderr', 'stdout'] }
                .collect { workflow."$it" }
                .flatten()

            if (scenario.snapshot_include) { filter_args.include = [scenario.snapshot_include] }
        } else {
            workflow_std = workflow.stderr + workflow.stdout
            filter_args.include = ["WARN"]
        }

        assertion.add(filterNextflowOutput(workflow_std, filter_args) ?: "No warnings")

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

            if (scenario.rundir_folder) {
                setup {
                    println ""
                    println ""
                    println "Downloading rundir"
                    def rundir_url = "https://github.com/nf-core/test-datasets/raw/seqinspector/testdata/NovaSeq6000/200624_A00834_0183_BHMTFYDRXX.tar.gz"
                    def download_rundir_command = ['bash', '-c', "curl -L --retry 5 ${rundir_url} | tar xzf - -C ${launchDir}"]
                    def download_rundir_process = download_rundir_command.execute()
                    download_rundir_process.waitFor()

                    if (download_rundir_process.exitValue() != 0) {
                        throw new RuntimeException("Error - failed to download rundir: ${download_rundir_process.err.text}")
                    } else {
                        println "Rundir downloaded"
                    }

                    println ""
                    println "Downloading samplesheet"
                    def samplesheet_url = "https://raw.githubusercontent.com/nf-core/test-datasets/seqinspector/testdata/NovaSeq6000/samplesheet.csv"
                    def download_samplesheet_command = ['bash', '-c', "curl -L --retry 5 ${samplesheet_url} > ${launchDir}/samplesheet.csv"]
                    def download_samplesheet_process = download_samplesheet_command.execute()
                    download_samplesheet_process.waitFor()

                    if (download_samplesheet_process.exitValue() != 0) {
                        throw new RuntimeException("Error - failed to download samplesheet: ${download_samplesheet_process.err.text}")
                    } else {
                        println "Samplesheet downloaded"
                    }

                    def sed_command = ['bash', '-c', "sed -i 's|https://github.com/nf-core/test-datasets/raw/seqinspector/testdata/NovaSeq6000/200624_A00834_0183_BHMTFYDRXX.tar.gz|$launchDir/200624_A00834_0183_BHMTFYDRXX|' ${launchDir}/samplesheet.csv"]
                    def sed_process = sed_command.execute()
                    sed_process.waitFor()
                }
            }

            when {
                params {
                    // Mandatory, as we always need an outdir
                    outdir = "${outputDir}"
                    // Apply scenario-specific params
                    scenario.params.each { key, value ->
                        if (scenario.rundir_folder) delegate.input = "${launchDir}/samplesheet.csv"
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
