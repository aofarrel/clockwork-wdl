version 1.0
# This is workflow that mimics 
# https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only
#
# You can skip clockwork_refprepWF by defining the following:
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__file_indxdH37Rvref_wrkfout"
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__FILE_DIRZIPPD_indxddeconref_wrkfout"
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__H37Rv_STRG_FILENAME_refprepd_taskout"
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__decontam_STRG_FILENAME_refprepd_taskout"
#
# You can skip enaDataGetTask.enaDataGet by defining the following as an array
# of arrays where each inner array corresponds with a sample in samples:
# * "ClockworkWalkthrough.bluepeter__fastqs"
#
# Note that miniwdl has a slightly different way of handling JSONs; the examples
# above are the Cromwell method.

#import "./wf-refprep-TB.wdl" as clockwork_refprepWF
#import "./tasks/mapreads.wdl" as clockwork_mapreadsTask
#import "../enaBrowserTools-wdl/tasks/enaDataGet.wdl" as enaDataGetTask
#import "./tasks/remove-contam.wdl" as clockwork_removecontamTask

import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/wf-refprep-TB.wdl" as clockwork_refprepWF
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/mapreads.wdl" as clockwork_mapreadsTask
import "https://raw.githubusercontent.com/aofarrel/enaBrowserTools-wdl/0.0.4/tasks/enaDataGet.wdl" as enaDataGetTask
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/remove-contam.wdl" as clockwork_removecontamTask
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/variant_call_one_sample.wdl" as clockwork_varcalloneTask

workflow ClockworkWalkthrough {
	input {
		# Used to identify sample names in map_reads, and if bluepeter__fastqs
		# is not defined, these are also downloaded by enaDataGet.
		Array[String] samples

		### This should only be defined if you're skipping enaDataGet;
		### please make sure to read the notes at the top of this WDL!
		Array[Array[File]]? bluepeter__fastqs
	}

	call clockwork_refprepWF.ClockworkRefPrepTB

	if(!defined(bluepeter__fastqs)) {
		scatter(sample in samples) {
			call enaDataGetTask.enaDataGet {
				input:
					sample = sample
			}
		}
	}

	# bluepeter__fastqs has type Array[Array[File]]?. WDL validators require
	# that this kind of scatter has type Array[Any], which Array[Array[File]]
	# satisfies, but Array[Array[File]]?  does not.
	# Therefore, we provide a bogus Array[Array[File]] to fall back on.
	Array[Array[File]] bogus = [["foo", "bar"], ["bizz", "buzz"]]
	Array[Array[File]] fastqs = select_first([bluepeter__fastqs, enaDataGet.fastqs, bogus])

	scatter(data in zip(samples, fastqs)) {
		call clockwork_mapreadsTask.map_reads as map_reads {
			input:
				sample_name = data.left,
				reads_files = data.right,
				unsorted_sam = true,
				DIRZIPPD_reference = ClockworkRefPrepTB.FILE_DIRZIPPD_indxddeconref_wrkfout,
				FILENAME_reference = ClockworkRefPrepTB.STRG_FILENAME_indxddeconref_wrkfout
		}
	}


	scatter(sam_file in map_reads.mapped_reads) {
		call clockwork_removecontamTask.remove_contam as remove_contamination {
			input:
				bam_in = sam_file,
				DIRZIPPD_decontam_ref = ClockworkRefPrepTB.FILE_DIRZIPPD_indxddeconref_wrkfout,
		}

		call clockwork_varcalloneTask.variant_call_one_sample {
			input:
				sample_name = sam_file,
				ref_dir = ClockworkRefPrepTB.file_indxdH37Rvref_wrkfout,
				reads_files = [remove_contamination.decontaminated_fastq_1, remove_contamination.decontaminated_fastq_2]


		}
	}
}
