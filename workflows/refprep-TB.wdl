version 1.0
#import "./tasks/ref_prep.wdl"
#import "./tasks/dl_TB_ref.wdl" as dl_TB_ref

import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/ref_prep.wdl"
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/dl_TB_ref.wdl" as dl_TB_ref

# correspond with https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only#get-and-index-reference-genomes

workflow ClockworkRefPrepTB {
	input {

		############################## danger zone ###############################
		# These inputs should ONLY be used if you intend on skipping steps, using
		# "here's one I made earlier" ("Blue Peter") inputs.
		#
		# Define this input to skip downloading TB reference files.
		File?   bluepeter__tar_tb_ref_raw
		#
		# Define this input to skip indexing the decontamination reference.
		File?   bluepeter__tar_indexd_dcontm_ref
		#
		# Define this input to skip index_H37v_reference.
		File?   bluepeter__tar_indexd_H37Rv_ref
		#
		# If you define all three of these, this workflow basically does nothing and
		# will pass you inputs as outputs.
	}

	if (!defined(bluepeter__tar_tb_ref_raw)) {
		call dl_TB_ref.download_tb_reference_files

		# Ref.download.tar
		#  ├── NC_000962.1.fa
		#  ├── NC_000962.2.fa
		#  ├── NC_000962.3.fa
		#  ├── remove_contam.fa.gz
		#  └── remove_contam.tsv
	}

	if (!defined(bluepeter__tar_indexd_dcontm_ref)) {
		call ref_prep.reference_prepare as index_decontamination_ref {
			input:
				reference_folder = select_first([bluepeter__tar_tb_ref_raw,
					download_tb_reference_files.tar_tb_ref_raw]),
				reference_fa_string            = "remove_contam.fa.gz",
				contam_tsv_in_reference_folder = "remove_contam.tsv",
				outdir                         = "Ref.remove_contam"
		}

		# Ref.remove_contam.tar
		#  ├── ref.fa
		#  ├── ref.fa.fai
		#  ├── ref.fa.minimap2_idx
		#  └── remove_contam_metadata.tsv
	}

	if (!defined(bluepeter__tar_indexd_H37Rv_ref)) {
		call ref_prep.reference_prepare as index_H37Rv_reference {
			input:
				reference_folder = select_first([bluepeter__tar_tb_ref_raw,
					download_tb_reference_files.tar_tb_ref_raw]),
				reference_fa_string = "NC_000962.3.fa",
				outdir              = "Ref.H37Rv"
		}

		# Ref.H37Rv.tar
		#  ├── ref.fa
		#  ├── ref.fa.fai
		#  ├── ref.fa.minimap2_idx
		#  └── ref.k31.ctx
	}

	output {
		File   tar_indexd_dcontm_ref    = select_first([bluepeter__tar_indexd_dcontm_ref,
														index_decontamination_ref.tar_ref_prepd])
		
		File   tar_indexd_H37Rv_ref     = select_first([bluepeter__tar_indexd_H37Rv_ref,
														index_H37Rv_reference.tar_ref_prepd])
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}