version 1.0
# Limitations: 
# * This does not support usage of a database nor db_config_file
# * strg_dirnozip_outdir_taskin is hardcoded and output is given in the form of a single
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

# * TODO: previously assumed that if file_lonesome_reference_taskin, then don't input file_lonesome_tsv_taskin, but
#   is that actually true? --> seems unlikely, could probably use file_lonesome_reference_taskin for an
#   index decontamination run which does need a tsv someway or another

task reference_prepare {
	input {
		# You need to define either this...
		File? file_lonesome_reference_taskin

		# Or all three of these.
		File?   file_dirzippd_reference_taskin  # download_tb_reference_files.file_dirzippd_tbref_taskout
		String? strg_dirnozip_reference_taskin  # download_tb_reference_files.strg_dirnozip_tbref_taskout
		String? strg_filename_reference_taskin  # "remove_contam.fa.gz" or "NC_000962.3.fa"

		# If you are indexing the decontamination reference, you need to define
		# one of these two. It is assumed that if strg_filename_tsv_taskin is defined, the
		# TSV is located inside file_dirzippd_reference_taskin, and its path will be
		# constructed as "~{strg_dirnozip_reference_taskin}/~{strg_filename_tsv_taskin}"
		File?   file_lonesome_tsv_taskin
		String? strg_filename_tsv_taskin

		# Other stuff
		Int?    cortex_mem_height
		String? name
		String? strg_dirnozip_outdir_taskin

		# Runtime attributes
		Int addldisk = 100
		Int cpu      = 8
		Int retries  = 1
		Int memory   = 16
		Int preempt  = 1
	}
	# estimate disk size required
	Int size_in = select_first([ceil(size(file_dirzippd_reference_taskin, "GB")), ceil(size(file_lonesome_reference_taskin, "GB")), 0])
	Int finalDiskSize = 2*size_in + addldisk
	
	# play with some variables
	String is_there_any_tsv = select_first([strg_filename_tsv_taskin, file_lonesome_tsv_taskin, "false"])
	String intermed_tsv1 = if defined(strg_filename_tsv_taskin) then "~{strg_dirnozip_reference_taskin}/~{strg_filename_tsv_taskin}" else ""
	String intermed_tsv2 = if defined(file_lonesome_tsv_taskin) then "~{file_lonesome_tsv_taskin}" else ""
	String arg_tsv  = if is_there_any_tsv == "false" then "" else "--contam_tsv ~{intermed_tsv1}~{intermed_tsv2}"
	
	String arg_ref               = if defined(file_lonesome_reference_taskin) then "~{file_lonesome_reference_taskin}" else "~{strg_dirnozip_reference_taskin}/~{strg_filename_reference_taskin}"
	String arg_cortex_mem_height = if defined(cortex_mem_height) then "--cortex_mem_height ~{cortex_mem_height}" else ""
	String arg_name              = if defined(name) then "--name ~{name}" else ""

	command <<<
		set -eux -o pipefail

		if [[ ! "~{file_dirzippd_reference_taskin}" = "" ]]
		then
			unzip ~{file_dirzippd_reference_taskin}
		fi

		clockwork reference_prepare --strg_dirnozip_outdir_taskin ~{strg_dirnozip_outdir_taskin} ~{arg_ref} ~{arg_cortex_mem_height} ~{arg_tsv} ~{arg_name}

		ls -lhaR > workdir.txt

		zip -r ~{strg_dirnozip_outdir_taskin}.zip ~{strg_dirnozip_outdir_taskin}
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
		File    file_dirzipped_refprepd_taskout = glob("*.zip")[0]
		String  strg_filename_refprepd_taskout = select_first([file_lonesome_reference_taskin, strg_filename_reference_taskin, "error"])  # TODO: Is this accurate
		#String? strg_filename_decontsv_taskout = strg_filename_tsv_taskin
		File    debug_workdir = "workdir.txt"
	}
}
