version 1.0
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/refprep-improvements/tasks/ref_prep.wdl"
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/refprep-improvements/tasks/dl_TB_ref.wdl" as dl_TB_ref

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
		# As of version 4.1.0 of clockwork-wdl I no longer allow users to skip H37Rv 
		# indexing by defining bluepeter__tar_indexd_H37Rv_ref. Nope. Not allowed.
		# Nowadays, that indexing step also creates the reference genome used by
		# myco's later steps (tbprofiler and phylogenetic tree stuff), in order to
		# stop users from having to upload two more copies of the TB genome for myco's
		# later tasks. Thusly, it just isn't a good idea to let people skip the 
		# (most likely quickest) step of this workflow anymore. Sure, I could
		# allow users to input that particular fa file, but because the tree steps
		# require such a specific chromosome title that just happens to match what
		# gets downloaded here, it's safer to just tell users to run this workflow once
		# and then rely on call cacheing.
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
		call ref_prep.reference_prepare_myco as index_decontamination_ref {
			input:
				reference_folder = select_first([bluepeter__tar_tb_ref_raw,
					download_tb_reference_files.tar_tb_ref_raw]),
				reference_fa_string                        = "remove_contam.fa.gz",
				filename_of_contam_tsv_in_reference_folder = "remove_contam.tsv",
				outdir                                     = "Ref.remove_contam"
		}

		# Ref.remove_contam.tar
		#  ├── ref.fa
		#  ├── ref.fa.fai
		#  ├── ref.fa.minimap2_idx
		#  └── remove_contam_metadata.tsv
	}

	call ref_prep.reference_prepare_myco as index_H37Rv_reference {
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

	output {
		File  tar_indexd_dcontm_ref    = select_first([bluepeter__tar_indexd_dcontm_ref,
														index_decontamination_ref.tar_ref_prepd])
		
		File  tar_indexd_H37Rv_ref     = select_first([index_H37Rv_reference.tar_ref_prepd])
											 
		File  reference_genome_fasta   = select_first([index_H37Rv_reference.H37Rv_for_later])

	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}