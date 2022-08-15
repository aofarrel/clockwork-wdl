# clockwork-wdl
 An in-progress WDLization of [clockwork](https://github.com/iqbal-lab-org/clockwork), focusing on functions used by [this walkthrough](https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only).

 To allow for quicker runs, several workflows have "bluepeter" options. Named after the TV show coining the term "here's one I made earlier," these are files you can insert when running a workflow more than once in order to avoid downloading the same set of files over and over again.

 **Tasks**
 * dl-TB-ref: downloads tuberculosis reference files using [download_tb_reference_files.pl](https://github.com/iqbal-lab-org/clockwork/blob/master/scripts/download_tb_reference_files.pl)
 * mapreads: implementation of `clockwork map_reads`
 * refprep: limited implementation of `clockwork reference_prepare`, does not support databases
 * remove-contam: implementation of `clockwork remove_contam`

 **Workflows**
 * wf-refprep-generic: runs a generic refprep workflow
 * wf-refprep-TB: runs a tuberculosis-specific refprep workflow [based on this](https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only#get-and-index-reference-genomes)
 * walkthru: WIP, not complete, but will eventually go from FASTQ input to minos' adjudicated VCF output

## Note to local Cromwell users
 My testing indicates that running the refprep workflow on a typical laptop setup will not be successful due to processes getting sigkilled thanks to lack of compute resources. You'll know you're having this issue because you will see "killed" and/or a return code of 137 in your Clockwork logs (you likely won't see this in Cromwell's terminal output). You may have some luck increasing Docker's resources or running more than once, but it's probably best to run these once in the cloud, download the results, and then use them as bluepeter inputs from then on (or just run the whole thing in the cloud).

 The walkthru workflow [![works on my machine badge](https://cdn.jsdelivr.net/gh/nikku/works-on-my-machine@v0.2.0/badge.svg)](https://github.com/nikku/works-on-my-machine) with a runtime of about 45 minutes when skipping refprep.


## To-do list:
[] Finish the walkthru pipeline
[] Better cloud runtime attribute estimates
[] Merge bluepeter version of refprep with non-bluepeter version
[] Merge bluepeter version of walkthru with non-bluepeter version
[] Finish miscellanous TODO stuff in code