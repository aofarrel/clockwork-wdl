version 1.0
# Limitations: 
# * This does not support usage of a database nor db_config_file
# * outdir is hardcoded and output is given in the form of a single
#   zip file, as WDL does not support outputting a directory

# clockwork reference_prepare essentially runs these steps:
# 1) seqtk seq -C -l 60 {ref genome} > /cromwell_root/ref_dir/ref.fa
# 2) samtools faidx /cromwell_root/ref_dir/ref.fa
# 3) minimap2 -I 0.5G -x sr -d /cromwell_root/ref_dir/ref.fa.minimap2_idx \
#	/cromwell_root/ref_dir/ref.fa
# 4) /bioinf-tools/cortex/bin/cortex_var_31_c1 \
#	--kmer_size 31 --mem_height 22 --mem_width 100 \
#	--se_list /cromwell_root/ref_dir/ref.fofn --max_read_len 10000 \
#	--dump_binary /cromwell_root/ref_dir/ref.k31.ctx --sample_id REF

task reference_prepare {
	input {
		# one of these two MUST be defined
		# if ref_dir, assume download_tb_reference_files was run
		# if ref, then don't input contam_tsv
		File? ref_directory
		File? ref_file

		# only needed if ref_directory is defined
		String? ref_dir_without_zip # TODO: use sub() instead... carefully
		String? ref_no_dir
		String? tsv_no_dir

		Int? cortex_mem_height
		File? contam_tsv
		String? name
		String? outdir

		# runtime attributes
		Int addldisk = 1
		Int cpu = 8
		Int retries = 1
		Int memory = 8
		Int preempt = 1
	}
	# estimate disk size required
	Int finalDiskSize = select_first([ceil(size(ref_directory, "GB")), ceil(size(ref_file, "GB")), 0])

	# play with some variables
	String is_there_any_tsv = select_first([tsv_no_dir, contam_tsv, "false"])
	String str_tsv1 = if defined(tsv_no_dir) then "~{ref_dir_without_zip}/~{tsv_no_dir}" else ""
	String str_tsv2 = if defined(contam_tsv) then "~{contam_tsv}" else ""
	String arg_tsv  = if is_there_any_tsv == "false" then "" else "--contam_tsv ~{str_tsv1}~{str_tsv2}"
	
	String arg_ref               = if defined(ref_file) then "~{ref_file}" else "~{ref_dir_without_zip}/~{ref_no_dir}"
	String arg_cortex_mem_height = if defined(cortex_mem_height) then "--cortex_mem_height ~{cortex_mem_height}" else ""
	String arg_name              = if defined(name) then "--name ~{name}" else ""

	command <<<
		set -eux -o pipefail

		if [[ ! "~{ref_directory}" = "" ]]
		then
			unzip ~{ref_directory}
		fi

		clockwork reference_prepare --outdir ~{outdir} ~{arg_ref} ~{arg_cortex_mem_height} ~{arg_tsv} ~{arg_name}

		zip -r ~{outdir}.zip ~{outdir}
	>>>
	
	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + finalDiskSize + " HDD"
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptibles: "${preempt}"
	}
	output {
		File zipped_outs = glob("*.zip")[0]
		String ref_filename = select_first([ref_file, ref_no_dir, "error"])
	}
}
