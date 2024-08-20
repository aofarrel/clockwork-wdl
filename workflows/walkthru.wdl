version 1.0
# This is workflow that mimics 
# https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only
#
# It is highly recommended to instead use the "myco" pipeline instead of this
# one. myco builds upon this "walthru" workflow's base to provide much more
# flexibility, including in-depth QC, sample filtering, guardrails to prevent
# runaway cloud costs, integrated TBProfiler, and more goodies. myco's output
# can also be directly fed into "Tree Nine" to build a phylogenetic tree.
# Get myco here: github.com/aofarrel/myco
# Get Tree Nine here: github.com/aofarrel/tree_nine
#
# If you do indeed want to use this proof-of-concept workflow, here's some tips:
#
# You can skip clockwork_ref_prepWF by defining the following:
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__tar_indexed_H37Rv_ref"
# * "ClockworkWalkthrough.ClockworkRefPrepTB.bluepeter__tar_indexd_dcontm_ref"
#
# You can skip ena.enaDataGet by defining the following as an array
# of arrays where each inner array corresponds with a sample in samples:
# * "ClockworkWalkthrough.bluepeter__fastqs"
#
# Note that miniwdl has a slightly different way of handling JSONs; the examples
# above are the Cromwell method.

import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/2.13.0/workflows/refprep-TB.wdl" as clockwork_ref_prepWF
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/2.13.0/tasks/map_reads.wdl" as clockwork_map_readsTask
import "https://raw.githubusercontent.com/aofarrel/enaBrowserTools-wdl/0.0.4/tasks/enaDataGet.wdl" as ena
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/2.13.0/tasks/rm_contam.wdl" as clockwork_removecontamTask
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/2.13.0/tasks/variant_call_one_sample.wdl" as clockwork_varcalloneTask

workflow ClockworkWalkthrough {
	input {
		# Used to identify sample names in map_reads, and if bluepeter__fastqs
		# is not defined, these are also downloaded by enaDataGet.
		Array[String] samples

		### This should only be defined if you're skipping enaDataGet;
		### please make sure to read the notes at the top of this WDL!
		Array[Array[File]]? bluepeter__fastqs
	}

	call clockwork_ref_prepWF.ClockworkRefPrepTB

	if(!defined(bluepeter__fastqs)) {
		scatter(sample in samples) {
			call ena.enaDataGet {
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
		call clockwork_map_readsTask.map_reads as map_reads {
			input:
				#sample_name = data.left,
				reads_files = data.right,
				unsorted_sam = true,
				tarball_ref_fasta_and_index = ClockworkRefPrepTB.tar_indexd_dcontm_ref,
				ref_fasta_filename = "ref.fa"
		}
	}


	scatter(sam_file in map_reads.mapped_reads) {
		call clockwork_removecontamTask.remove_contam as remove_contamination {
			input:
				bam_in = sam_file,
				tarball_metadata_tsv = ClockworkRefPrepTB.tar_indexd_dcontm_ref,
		}

		call clockwork_varcalloneTask.variant_call_one_sample_simple as variant_call_one_sample {
			input:
				ref_dir = ClockworkRefPrepTB.tar_indexd_H37Rv_ref,
				reads_files = [remove_contamination.decontaminated_fastq_1, remove_contamination.decontaminated_fastq_2]


		}
	}

	output {
		File vcf = variant_call_one_sample.adjudicated_vcf
	}
}
