version 1.0
import "./tasks/refprep.wdl"
import "./tasks/dl-TB-ref.wdl" as dl_TB_ref

#import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/refprep.wdl"
#import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/dl-TB-ref.wdl" as dl_TB_ref

# correspond with https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only#get-and-index-reference-genomes

workflow ClockworkRefPrepTB {
	input {
		File? genome

		############################## danger zone ###############################
		# These inputs should ONLY be used if you intend on skipping steps, using
		# "here's one I made earlier" inputs.
		# The first two skip the download of the TB reference files.
		File?   bluepeter__download_tb_reference_files__file_dirzippd_tbref_taskout
		String? bluepeter__download_tb_reference_files__strg_dirnozip_tbref_taskout
		#
		# If you define these next two, then download_tb_reference_files will be
		# skipped, and so will index_H37v_reference.
		File?   bluepeter__file_dirzippd_indxddeconref_wrkfout
		String? bluepeter__decontam_strg_filename_refprepd_taskout
		#
		# If you define these last two, then download_tb_reference_files and
		# will be skipped.
		File?   bluepeter__file_indxdH37Rvref_wrkfout
		String? bluepeter__H37Rv_strg_filename_refprepd_taskout
		#
		# Yes, that does mean that the *entire* pipeline can be skipped if the
		# user inputs the last four inputs, and those four inputs will be considered
		# the workflow outputs. Why? This workflow is called by other workflows, and
		# is very slow, so for testing it is worth being able to skip these steps
		# while still having the hard part (coaxing your WDL executor to localize
		# files where you expect them to go) getting tested.
	}

	if (!defined(bluepeter__download_tb_reference_files__file_dirzippd_tbref_taskout)) {
		call dl_TB_ref.download_tb_reference_files
		#################### output ####################
		# Ref.download.zip
		#  ├── NC_000962.1.fa
		#  ├── NC_000962.2.fa
		#  ├── NC_000962.3.fa
		#  ├── remove_contam.fa.gz
		#  └── remove_contam.tsv
	}

	if (!defined(bluepeter__file_dirzippd_indxddeconref_wrkfout)) {
		call refprep.reference_prepare as index_decontamination_ref {
			input:
				file_dirzippd_reference_taskin = select_first([bluepeter__download_tb_reference_files__file_dirzippd_tbref_taskout,
													download_tb_reference_files.file_dirzippd_tbref_taskout]),
				strg_dirnozip_reference_taskin = select_first([bluepeter__download_tb_reference_files__strg_dirnozip_tbref_taskout,
													download_tb_reference_files.strg_dirnozip_tbref_taskout]),
				strg_filename_reference_taskin = "remove_contam.fa.gz",
				strg_filename_tsv_taskin       = "remove_contam.tsv",
				strg_dirnozip_outdir_taskin    = "Ref.remove_contam"
		}
		#################### output ####################
		# Ref.remove_contam.zip
		#  ├── ref.fa
		#  ├── ref.fa.fai
		#  ├── ref.fa.minimap2_idx
		#  └── remove_contam_metadata.tsv
	}

	if (!defined(bluepeter__file_indxdH37Rvref_wrkfout)) {
		call refprep.reference_prepare as index_H37Rv_reference {
			input:
				file_dirzippd_reference_taskin = select_first([bluepeter__download_tb_reference_files__file_dirzippd_tbref_taskout,
													download_tb_reference_files.file_dirzippd_tbref_taskout]),
				strg_dirnozip_reference_taskin = select_first([bluepeter__download_tb_reference_files__strg_dirnozip_tbref_taskout,
													download_tb_reference_files.strg_dirnozip_tbref_taskout]),
				strg_filename_reference_taskin = "NC_000962.3.fa",
				strg_dirnozip_outdir_taskin    = "Ref.H37Rv"
		}
		#################### output ####################
		# Ref.H37Rv.zip
		#  ├── ref.fa
		#  ├── ref.fa.fai
		#  ├── ref.fa.minimap2_idx
		#  └── ref.k31.ctx
	}

	output {
		File   file_dirzippd_indxddeconref_wrkfout 		= select_first([bluepeter__file_dirzippd_indxddeconref_wrkfout,
														index_decontamination_ref.file_dirzipped_refprepd_taskout])
		
		String strg_filename_indxddeconref_wrkfout    = select_first([bluepeter__decontam_strg_filename_refprepd_taskout,
														"ref.fa"])
		
		File   file_indxdH37Rvref_wrkfout    		= select_first([bluepeter__file_indxdH37Rvref_wrkfout,
														index_H37Rv_reference.file_dirzipped_refprepd_taskout])
		
		String strg_filename_indxdH37Rvref_wrkfout       = select_first([bluepeter__H37Rv_strg_filename_refprepd_taskout,
														"ref.fa"])
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}