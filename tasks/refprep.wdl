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

# * TODO: previously assumed that if fullpath_reference, then don't input fullpath_tsv, but
#   is that actually true? --> seems unlikely, could probably use fullpath_reference for an
#   index decontamination run which does need a tsv someway or another

task reference_prepare {
	input {
		# You need to define either this...
		File? fullpath_reference

		# Or all three of these.
		File?   dirzippd_reference  # download_tb_reference_files.file_dirzippd_tbref_taskout
		String? dirnozip_reference  # download_tb_reference_files.strg_dirnozip_tbref_taskout
		String? filename_reference  # "remove_contam.fa.gz" or "NC_000962.3.fa"

		# If you are indexing the decontamination reference, you need to define
		# one of these two. It is assumed that if filename_tsv is defined, the
		# TSV is located inside dirzippd_reference, and its path will be
		# constructed as "~{dirnozip_reference}/~{filename_tsv}"
		File?   fullpath_tsv
		String? filename_tsv

		# Other stuff
		Int?    cortex_mem_height
		String? name
		String? outdir

		# Runtime attributes
		Int addldisk = 100
		Int cpu      = 8
		Int retries  = 1
		Int memory   = 16
		Int preempt  = 1
	}
	# estimate disk size required
	Int size_in = select_first([ceil(size(dirzippd_reference, "GB")), ceil(size(fullpath_reference, "GB")), 0])
	Int finalDiskSize = 2*size_in + addldisk
	
	# play with some variables
	String is_there_any_tsv = select_first([filename_tsv, fullpath_tsv, "false"])
	String intermed_tsv1 = if defined(filename_tsv) then "~{dirnozip_reference}/~{filename_tsv}" else ""
	String intermed_tsv2 = if defined(fullpath_tsv) then "~{fullpath_tsv}" else ""
	String arg_tsv  = if is_there_any_tsv == "false" then "" else "--contam_tsv ~{intermed_tsv1}~{intermed_tsv2}"
	
	String arg_ref               = if defined(fullpath_reference) then "~{fullpath_reference}" else "~{dirnozip_reference}/~{filename_reference}"
	String arg_cortex_mem_height = if defined(cortex_mem_height) then "--cortex_mem_height ~{cortex_mem_height}" else ""
	String arg_name              = if defined(name) then "--name ~{name}" else ""

	command <<<
		set -eux -o pipefail

		if [[ ! "~{dirzippd_reference}" = "" ]]
		then
			unzip ~{dirzippd_reference}
		fi

		clockwork reference_prepare --outdir ~{outdir} ~{arg_ref} ~{arg_cortex_mem_height} ~{arg_tsv} ~{arg_name}

		ls -lhaR > workdir.txt

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
		String ref_filename = select_first([fullpath_reference, filename_reference, "error"])  # TODO: Is this accurate
		File debug_workdir = "workdir.txt"
	}
}
