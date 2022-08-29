version 1.0
# This is workflow that mimics 
# https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only
#
# You can skip clockwork_refprepWF by defining the following:
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__indexed_H37Rv_reference"
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__indexed_decontam_reference"
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__H37Rv_ref_filename"
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__decontam_ref_filename"
#
# You can skip enaDataGetTask.enaDataGet by defining the following as an array
# of arrays where each inner array corresponds with a sample in samples:
# * "ClockworkWalkthrough.bluepeter__fastqs"
#
# Note that miniwdl has a slightly different way of handling JSONs; the examples
# above are the Cromwell method.

import "./wf-refprep-TB.wdl" as clockwork_refprepWF
import "./tasks/mapreads.wdl" as clockwork_mapreadsTask
import "../enaBrowserTools-wdl/tasks/enaDataGet.wdl" as enaDataGetTask
import "./tasks/remove-contam.wdl" as clockwork_removecontamTask

#import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/wf-refprep-TB.wdl" as clockwork_refprepWF
#import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/mapreads.wdl" as clockwork_mapreadsTask
#import "https://raw.githubusercontent.com/aofarrel/enaBrowserTools-wdl/0.0.3/tasks/enaDataGet.wdl" as enaDataGetTask
#import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/remove-contam.wdl" as clockwork_removecontamTask

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
				DIRZIPPD_reference = ClockworkRefPrepTB.indexed_decontam_reference,
				FILENAME_reference = ClockworkRefPrepTB.indexed_decontam_ref_filename
		}
	}


#	Array[File] mapped_reads = select_first([map_reads_quick, map_reads_slow])
#	scatter(sam_file in mapped_reads) {
#		call clockwork_removecontamTask
#			input:
#				metadata_tsv = ClockworkRefPrepTB.
#				bam_in = sam_file,
#				counts_out,
#				reads_out_1,
#				reads_out_2,
#				dirnozip_tsv
#	}
}
