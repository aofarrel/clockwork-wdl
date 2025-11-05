# clockwork-wdl
 A WDLization + Dockerization of some parts of the *Mycobacterium tuberculosis* toolkit [clockwork](https://github.com/iqbal-lab-org/clockwork), focusing on functions used by [this walkthrough](https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only). Supports (and sometimes requires) tarball inputs -- please make sure to read the inputs section.

> [!IMPORTANT]  
> If you are looking for a pipeline to decontaminate, call variants, and optionally put your samples on a phylogenetic tree, please see [myco](https://github.com/aofarrel/myco) instead of this repo. myco uses the tasks in this repo as its foundation, but includes several additional features such as integrated TBProfiler, covstats, and fastp. myco also includes several WDL-specific components to make running on the cloud much more simple.

## Available Docker images
  * [ashedpotatoes/iqbal-unofficial-clockwork-mirror](https://hub.docker.com/r/ashedpotatoes/iqbal-unofficial-clockwork-mirror) -- unofficial Docker Hub mirror of clockwork's official [the ghcr.io release](https://github.com/iqbal-lab-org/clockwork/pkgs/container/clockwork). Exists only because some WDL executors can fail when pulling ghcr.io containers. Completely unchanged from the official release and follows its tags.
  * [ashedpotatoes/clockwork-plus](https://hub.docker.com/r/ashedpotatoes/clockwork-plus/tags) -- clockwork Docker image plus reference genomes:
    * **v0.12.5.3-slim** -- H37Rv but no decontamination references. This allows you to run `clockwork map_reads` and `clockwork variant_call_one_sample`, and their associated WDL wrappers. Also contains [fastp](https://github.com/OpenGene/fastp) and [tree](https://linux.die.net/man/1/tree).
    * **v0.12.5.3-CRyPTIC** -- H37Rv and the decontamination reference you get by running [download_tb_reference_files.pl](https://github.com/iqbal-lab-org/clockwork/blob/master/scripts/download_tb_reference_files.pl) and `clockwork reference_prepare`. This allows you to run all clockwork commands, including `clockwork remove_contam`. Currently, this is built using v0.12.5 of clockwork.
    * **v0.12.5.3-CDC** --the slim image plus the decontamination reference from CDC's varpipe repository. Be aware that this decontamination reference, while perfectly functional, has unknown provinance (as in, we don't know what's actually in it) and seems to be slightly worse at removing NTM than the CRyPTIC reference. However, many LHJs prefer to use this reference as it is well-known.

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

### Skipping steps on walkthru.wdl
 To allow for quicker runs, several workflows have "bluepeter" options. Named after the TV show coining the term "here's one I made earlier," these are files you can insert when running a workflow more than once in order to avoid downloading the same set of files over and over again.
 
  All JSONs are Cromwell-formatted.
  * **walkthru-skip-nothing.json**: Skip nothing
  * **walkthru-skip-refdl.json**: Skip dl_TB_ref, which is the first step of wf-reprep-TB; use this to test index_decontamination_ref and index_H37Rv_reference.
  * **walkthru-skip-ref_prep.json**: Skip wf-ref_prep-TB (including dl_TB_ref); use this to test enaDataGet and (eventually) map_reads
  * **walkthru-skip-ref_prep-and-ena.json**: Skip wf-ref_prep-TB (including dl_TB_ref) and enaDataGet; use this to test map_reads

### Note to local Cromwell users
 My testing indicates that running the ref_prep workflow on a typical laptop setup will not be successful due to processes getting sigkilled thanks to lack of compute resources. You'll know you're having this issue because you will see "killed" and/or a return code of 137 in your Clockwork logs (you likely won't see this in Cromwell's terminal output). You may have some luck increasing Docker's resources or running more than once, but it's probably best to run these once in the cloud, download the results, and then use them as bluepeter inputs from then on (or just run the whole thing in the cloud).

