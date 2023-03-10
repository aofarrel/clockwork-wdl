# clockwork-wdl
 A partial WDLization of [clockwork](https://github.com/iqbal-lab-org/clockwork), focusing on functions used by [this walkthrough](https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only). Supports (and sometimes requires) tarball inputs -- please make sure to read the inputs section.

 To allow for quicker runs, several workflows have "bluepeter" options. Named after the TV show coining the term "here's one I made earlier," these are files you can insert when running a workflow more than once in order to avoid downloading the same set of files over and over again.

## Supported tasks and workflows
 **Tasks**
 * dl_TB_ref: downloads tuberculosis reference files using [download_tb_reference_files.pl](https://github.com/iqbal-lab-org/clockwork/blob/master/scripts/download_tb_reference_files.pl)
 * gvcf: implementation of `clockwork gvcf_from_minos_and_samtools`
 * map_reads: implementation of `clockwork map_reads`
 * ref_prep: limited implementation of `clockwork reference_prepare`, does not support databases
 * rm_contam: implementation of `clockwork remove_contam`
 * variant_call_one_sample: implementation of `clockwork variant_call_one_sample`

 **Workflows**
 * decontaminate_one_sample: decontaminates and combines a single sample's fastqs
 * gvcf_after_walkthru: converts the output of walkthru (see below) to a gvcf
 * ref_prep-generic: runs a generic ref_prep workflow
 * ref_prep-TB: runs a tuberculosis-specific ref_prep workflow [based on this](https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only#get-and-index-reference-genomes)
 * walkthru: goes from FASTQ input to minos' adjudicated VCF output

## Skipping steps on walkthru.wdl
All JSONs are Cromwell-formatted.
* **walkthru-skip-nothing.json**: Skip nothing
* **walkthru-skip-refdl.json**: Skip dl_TB_ref, which is the first step of wf-reprep-TB; use this to test index_decontamination_ref and index_H37Rv_reference.
* **walkthru-skip-ref_prep.json**: Skip wf-ref_prep-TB (including dl_TB_ref); use this to test enaDataGet and (eventually) map_reads
* **walkthru-skip-ref_prep-and-ena.json**: Skip wf-ref_prep-TB (including dl_TB_ref) and enaDataGet; use this to test map_reads

## Note to local Cromwell users
 My testing indicates that running the ref_prep workflow on a typical laptop setup will not be successful due to processes getting sigkilled thanks to lack of compute resources. You'll know you're having this issue because you will see "killed" and/or a return code of 137 in your Clockwork logs (you likely won't see this in Cromwell's terminal output). You may have some luck increasing Docker's resources or running more than once, but it's probably best to run these once in the cloud, download the results, and then use them as bluepeter inputs from then on (or just run the whole thing in the cloud).

## Why is the Docker image an "unofficial" mirror?
  https://github.com/broadinstitute/cromwell/issues/6827

  It's the exact same image as the official one. I pull [the ghcr.io release](https://github.com/iqbal-lab-org/clockwork/pkgs/container/clockwork) and then retag it for Docker Hub.

## To-do list:
[X] Investigate why Terra ran enaDataGet very quickly, no error, but cromwell failed to find any fastq.gz files  
[X] Finish the walkthru pipeline  
[X] Better cloud runtime attribute estimates  
[X] Merge bluepeter version of ref_prep with non-bluepeter version  
[X] Merge bluepeter version of walkthru with non-bluepeter version  
[] Check if any tasks can take in *just* a fasta reference, instead of a folder  
[] Have all tasks support taking in either a tarball ref folder or a ref_fasta where appropriate.   
    * Check if base stem of ref_fasta == basename of ref_fasta   
        * true: continue  
        * false: untar, assume filename is either user-defined optional ref_fasta_string or fall back to default ref.fa  
[] Finish miscellanous TODO stuff in code   
