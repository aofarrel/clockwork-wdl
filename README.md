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

## Skipping steps on walkthru.wdl
All are Cromwell-formatted.
* **walkthru-skip-nothing.json**: Skip nothing
* **walkthru-skip-refdl.json**: Skip dl-TB-ref, which is the first step of wf-reprep-TB; use this to test index_decontamination_ref and index_H37Rv_reference.
* **walkthru-skip-refprep.json**: Skip wf-refprep-TB (including dl-TB-ref); use this to test enaDataGet and (eventually) map_reads
* **walkthru-skip-refprep-and-ena.json**: Skip wf-refprep-TB (including dl-TB-ref) and enaDataGet; use this to test map_reads

## Note to local Cromwell users
 My testing indicates that running the refprep workflow on a typical laptop setup will not be successful due to processes getting sigkilled thanks to lack of compute resources. You'll know you're having this issue because you will see "killed" and/or a return code of 137 in your Clockwork logs (you likely won't see this in Cromwell's terminal output). You may have some luck increasing Docker's resources or running more than once, but it's probably best to run these once in the cloud, download the results, and then use them as bluepeter inputs from then on (or just run the whole thing in the cloud).

## Variable weirdness
The original pipeline assumes that you can pass entire directories around. WDL 1.0 does allow for this, and Cromwell has (to my knowledge) no timeline on supporting WDL 1.1, so we have to get a little creative. When dealing with an input variable that is often passed in from a directory, the following naming schema is used (inconsistently, because everything is still in development):

Public:    
* STRG_FILENAME_varname: String - "cromwell_inputs/remove_contam_metadata.tsv"  
* STRG_DIRNOZIP_varname: String - "cromwell_inputs/Ref.remove_contam"  
* FILE_DIRZIPPD_varname: File   - "cromwell_inputs/Ref.remove_contam.zip"  
* FILE_LONESOME_varname: File   - "cromwell_inputs/remove_contam_metadata.tsv"

Private:  
* strg_fullpath_varname: String - "cromwell_inputs/Ref.remove_contam/remove_contam_metadata.tsv"
* strg_basestem_varname: String - "Ref.remove_contam"
* strg_intermed_varname: String - Intermediate variable used to calculate arg_varname. Not always present.  
* strg_argument_varname: String - Argument for a command line call in a task's command section.

Suffixes:
* \_TASKIN: Variable is a task-level input
* \_taskout: Variable is a task-level output
* \_wrkfinn: Variable is a workflow-level input
* \_wrkfout: Variable is a workflow-level output

Generally speaking:

`arg_varname = if(defined(fullpath_varname)) then "~{fullpath_varname}" else "~{dirnozip_varname}/~{filename_varname}"`

...with the assumption that `~{dirzippd_varname}` gets unzipped before arg_varname is used in the command section.

## To-do list:
[X] Investigate why Terra ran enaDataGet very quickly, no error, but cromwell failed to find any fastq.gz files  
[] Use the newly-coined naming schema consistently and/or simplify variable nonsense  
[] Finish the walkthru pipeline  
[] Better cloud runtime attribute estimates  
[X] Merge bluepeter version of refprep with non-bluepeter version  
[X] Merge bluepeter version of walkthru with non-bluepeter version  
[] Finish miscellanous TODO stuff in code  
