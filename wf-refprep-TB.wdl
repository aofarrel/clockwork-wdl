version 1.0
import "./tasks/refprep.wdl"
import "./tasks/dl-TB-ref.wdl" as dl_TB_ref
# correspond with https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only#get-and-index-reference-genomes

workflow ClockworkRefPrepTB {
	input {
		File? genome

		############################## danger zone ###############################
		# These inputs should ONLY be used if you intend on skipping steps, using
		# "here's one I made earlier" inputs.
		# The first two skip the download of the TB reference files.
		File?   bluepeter__download_tb_reference_files__dl_zipped
		String? bluepeter__download_tb_reference_files__dl_dir
		#
		# If you define these next two, then download_tb_reference_files will be
		# skipped, and so will index_H37v_reference.
		File?   bluepeter__indexed_decontam_reference
		String? bluepeter__decontam_ref_filename
		#
		# If you define these last two, then download_tb_reference_files and
		# will be skipped.
		File?   bluepeter__indexed_H37Rv_reference
		String? bluepeter__H37Rv_ref_filename
		#
		# Yes, that does mean that the *entire* pipeline can be skipped if the
		# user inputs the last four inputs, and those four inputs will be considered
		# the workflow outputs. Why? This workflow is called by other workflows, and
		# is very slow, so for testing it is worth being able to skip these steps
		# while still having the hard part (coaxing your WDL executor to localize
		# files where you expect them to go) getting tested.
	}

	if (!defined(bluepeter__download_tb_reference_files__dl_zipped)) {
		call dl_TB_ref.download_tb_reference_files
	}

	if (!defined(bluepeter__indexed_decontam_reference)) {
		call refprep.reference_prepare as index_decontamination_ref {
			input:
				ref_directory       = select_first([bluepeter__download_tb_reference_files__dl_zipped,
													download_tb_reference_files.dl_zipped]),
				ref_dir_without_zip = select_first([bluepeter__download_tb_reference_files__dl_dir,
													download_tb_reference_files.dl_dir]),
				ref_no_dir = "remove_contam.fa.gz",
				tsv_no_dir = "remove_contam.tsv",
				outdir     = "Ref.remove_contam"
		}
	}

	if (!defined(bluepeter__indexed_H37Rv_reference)) {
		call refprep.reference_prepare as index_H37Rv_reference {
			input:
				ref_directory       = select_first([bluepeter__download_tb_reference_files__dl_zipped,
													download_tb_reference_files.dl_zipped]),
				ref_dir_without_zip = select_first([bluepeter__download_tb_reference_files__dl_dir,
													download_tb_reference_files.dl_dir]),
				ref_no_dir = "NC_000962.3.fa",
				outdir     = "Ref.H37Rv"
		}
	}

	output {
		File indexed_decontam_reference = select_first([bluepeter__indexed_decontam_reference,
														index_decontamination_ref.zipped_outs])
		
		String decontam_ref_filename    = select_first([bluepeter__decontam_ref_filename,
														index_decontamination_ref.ref_filename])
		
		File indexed_H37Rv_reference    = select_first([bluepeter__indexed_H37Rv_reference,
														index_H37Rv_reference.zipped_outs])
		
		String H37Rv_ref_filename       = select_first([bluepeter__H37Rv_ref_filename,
														index_H37Rv_reference.ref_filename])
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}