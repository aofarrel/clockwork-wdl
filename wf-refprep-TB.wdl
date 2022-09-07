version 1.0
import "./tasks/refprep.wdl"
import "./tasks/dl-TB-ref.wdl" as dl_TB_ref

#import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/test-if-tar-is-necessary/tasks/refprep.wdl"
#import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/test-if-tar-is-necessary/tasks/dl-TB-ref.wdl" as dl_TB_ref

# correspond with https://github.com/iqbal-lab-org/clockwork/wiki/Walkthrough-scripts-only#get-and-index-reference-genomes

workflow ClockworkRefPrepTB {
	input {
		File ref_fa_remove_contam
		File ref_fa_the_other_one
		File tsv_remove_contamina
	}

	#if (!defined(bluepeter__download_tb_reference_files__tar_tb_ref_raw)) {
	#	call dl_TB_ref.download_tb_reference_files
		#################### output ####################
		# Ref.download.tar
		#  ├── NC_000962.1.fa
		#  ├── NC_000962.2.fa
		#  ├── NC_000962.3.fa
		#  ├── remove_contam.fa.gz
		#  └── remove_contam.tsv
	#}

	#if (!defined(bluepeter__tar_indexd_dcontm_ref)) {
	call refprep.reference_prepare as index_decontamination_ref {
		input:
			reference_fa_file        = ref_fa_remove_contam,
			FILE_LONESOME_tsv_TASKIN = tsv_remove_contamina,
			outdir                   = "Ref.remove_contam"
	}
	#################### output ####################
	# Ref.remove_contam.tar
	#  ├── ref.fa
	#  ├── ref.fa.fai
	#  ├── ref.fa.minimap2_idx
	#  └── remove_contam_metadata.tsv
	#}

	#if (!defined(bluepeter__tar_indexd_H37Rv_ref)) {
	call refprep.reference_prepare as index_H37Rv_reference {
		input:
			reference_fa_file = ref_fa_the_other_one,
			outdir            = "Ref.H37Rv"
	}
	#################### output ####################
	# Ref.H37Rv.tar
	#  ├── ref.fa
	#  ├── ref.fa.fai
	#  ├── ref.fa.minimap2_idx
	#  └── ref.k31.ctx
	#}

	output {
		File   tar_indexd_dcontm_ref    = select_first([index_decontamination_ref.tar_refprepd])
		File   tar_indexd_H37Rv_ref     = select_first([index_H37Rv_reference.tar_refprepd])
		File   metadata_tsv = index_decontamination_ref.metadata_tsv
		File   decontam_ref_out =  index_decontamination_ref.ref_out
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}