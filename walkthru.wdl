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
# of arrays where each inner array corresponds with a sample in samples_to_dl:
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
import "https://raw.githubusercontent.com/aofarrel/enaBrowserTools-wdl/0.0.1/tasks/enaDataGet.wdl" as enaDataGetTask
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/remove-contam.wdl" as clockwork_removecontamTask

workflow ClockworkWalkthrough {
	input {
		# Samples to be downloaded by enaDataGet (technically unused if
		# you set bluepeter__fastqs).
		Array[String] samples_to_dl

		### This should only be defined if you're skipping enaDataGet;
		### please make sure to read the notes at the top of this WDL!
		Array[Array[File]]? bluepeter__fastqs
	}

	call clockwork_refprepWF.ClockworkRefPrepTB

	if (defined(bluepeter__fastqs)) {
		# Even though this task only runs if bluepeter__fastqs is defined, if we
		# scatter(data in zip(samples_to_dl, bluepeter__fastqs)) and
		# bluepeter__fastqs has type Array[Array[File]]?, WDL validators will fail
		# because this kind of scatter requires bluepeter__fastqs has type
		# Array[Any], which Array[Array[File]] satisfies, but Array[Array[File]]?
		# does not.
		# Therefore, we either have to make bluepeter__fastqs required, or we
		# have to pretend that we're scattering on a not-optional array. We went
		# with option two.
		Array[Array[File]] bogus = [["foo", "bar"], ["bizz", "buzz"]]
		Array[Array[File]] bluepeter__fastqs_req = select_first([bluepeter__fastqs, bogus])
		scatter(data in zip(samples_to_dl, bluepeter__fastqs_req)) {
			call clockwork_mapreadsTask.map_reads as map_reads_quick {
				input:
					sample_name = data.left,
					reads_files = data.right,
					unsorted_sam = true,
					optionB__ref_folder_zipped = ClockworkRefPrepTB.indexed_decontam_reference,
					optionB__ref_filename = ClockworkRefPrepTB.decontam_ref_filename
			}
		}
	}

	if(!defined(bluepeter__fastqs)) {
		scatter(sample in samples_to_dl) {
			call enaDataGetTask.enaDataGet {
				input:
					sample = sample
			}

			call clockwork_mapreadsTask.map_reads as map_reads_slow {
				input:
					reads_files = enaDataGet.fastqs,
					sample_name = enaDataGet.sample_out,
					unsorted_sam = true,
					optionB__ref_folder_zipped = ClockworkRefPrepTB.indexed_decontam_reference,
					optionB__ref_filename = ClockworkRefPrepTB.decontam_ref_filename
			}
		}
	}

	#Array[File] mapped_reads = select_first([map_reads_quick, map_reads_slow])
	#scatter(sam_file in mapped_reads) {
	#	call clockwork_removecontamTask
	#}
}