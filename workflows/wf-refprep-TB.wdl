version 1.0
#import "./tasks/refprep.wdl"
#import "./tasks/dl-TB-ref.wdl" as dl_TB_ref

import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/refprep.wdl"
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/dl-TB-ref.wdl" as dl_TB_ref

# correspond with https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only#get-and-index-reference-genomes

workflow ClockworkRefPrepTB {
	input {
		File? genome

		############################## danger zone ###############################
		# These inputs should ONLY be used if you intend on skipping steps, using
		# "here's one I made earlier" inputs.
		# The first two skip the download of the TB reference files.
		File?   bluepeter__download_tb_reference_files__tar_tb_ref_raw
		#
		# If you define these next two, then download_tb_reference_files will be
		# skipped, and so will index_H37v_reference.
		File?   bluepeter__tar_indexd_dcontm_ref
		#
		# If you define these last two, then download_tb_reference_files and
		# will be skipped.
		File?   bluepeter__tar_indexd_H37Rv_ref
		#
		# Yes, that does mean that the *entire* pipeline can be skipped if the
		# user inputs the last four inputs, and those four inputs will be considered
		# the workflow outputs. Why? This workflow is called by other workflows, and
		# is very slow, so for testing it is worth being able to skip these steps
		# while still having the hard part (coaxing your WDL executor to localize
		# files where you expect them to go) getting tested.
	}

	if (!defined(bluepeter__download_tb_reference_files__tar_tb_ref_raw)) {
		call dl_TB_ref.download_tb_reference_files
		#################### output ####################
		# Ref.download.tar
		#  ├── NC_000962.1.fa
		#  ├── NC_000962.2.fa
		#  ├── NC_000962.3.fa
		#  ├── remove_contam.fa.gz
		#  └── remove_contam.tsv
	}

	if (!defined(bluepeter__tar_indexd_dcontm_ref)) {
		call refprep.reference_prepare as index_decontamination_ref {
			input:
				reference_folder = select_first([bluepeter__download_tb_reference_files__tar_tb_ref_raw,
													download_tb_reference_files.tar_tb_ref_raw]),
				reference_fa_string = "remove_contam.fa.gz",
				STRG_FILENAME_tsv_TASKIN       = "remove_contam.tsv",
				outdir                         = "Ref.remove_contam"
		}
		#################### output ####################
		# Ref.remove_contam.tar
		#  ├── ref.fa
		#  ├── ref.fa.fai
		#  ├── ref.fa.minimap2_idx
		#  └── remove_contam_metadata.tsv
	}

	if (!defined(bluepeter__tar_indexd_H37Rv_ref)) {
		call refprep.reference_prepare as index_H37Rv_reference {
			input:
				reference_folder = select_first([bluepeter__download_tb_reference_files__tar_tb_ref_raw,
													download_tb_reference_files.tar_tb_ref_raw]),
				reference_fa_string = "NC_000962.3.fa",
				outdir                         = "Ref.H37Rv"
		}
		#################### output ####################
		# Ref.H37Rv.tar
		#  ├── ref.fa
		#  ├── ref.fa.fai
		#  ├── ref.fa.minimap2_idx
		#  └── ref.k31.ctx
	}

	output {
		File   tar_indexd_dcontm_ref    = select_first([bluepeter__tar_indexd_dcontm_ref,
														index_decontamination_ref.tar_refprepd])
		
		File   tar_indexd_H37Rv_ref     = select_first([bluepeter__tar_indexd_H37Rv_ref,
														index_H37Rv_reference.tar_refprepd])
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}