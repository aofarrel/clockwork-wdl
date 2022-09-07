version 1.0
# Limitations: 
# * This does not support usage of a database nor db_config_file
# * STRG_DIRNOZIP_outdir_TASKIN is hardcoded and output is given in the form of a single
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

# * TODO: previously assumed that if reference_fa_file, then don't input FILE_LONESOME_tsv_TASKIN, but
#   is that actually true? --> seems unlikely, could probably use reference_fa_file for an
#   index decontamination run which does need a tsv someway or another

task reference_prepare {
	input {
		# You need to define either this...
		File? reference_fa_file

		# Or both of these.
		File?   reference_folder     # download_tb_reference_files.tar_tb_ref_raw
		String? reference_fa_string  # "remove_contam.fa.gz" or "NC_000962.3.fa"

		# If you are indexing the decontamination reference, you need to define
		# one of these two. It is assumed that if STRG_FILENAME_tsv_TASKIN is defined, the
		# TSV is located inside reference_folder, and its path will be
		# constructed as "~{dirnozip_reference}/~{STRG_FILENAME_tsv_TASKIN}"
		File?   FILE_LONESOME_tsv_TASKIN
		String? STRG_FILENAME_tsv_TASKIN

		# Other stuff
		String outdir
		Int? cortex_mem_height
		String? name

		# Runtime attributes
		Int addldisk = 250
		Int cpu      = 16
		Int retries  = 1
		Int memory   = 32
		Int preempt  = 1
	}
	# estimate disk size required
	Int size_in = select_first([ceil(size(reference_folder, "GB")), ceil(size(reference_fa_file, "GB")), 0])
	Int finalDiskSize = ceil(2*size_in + addldisk)

	# find where the reference TSV is going to be located, if it exists at all
	# excessive usage of select_first() is required due to basename() and sub() not working on optional types, even if setting an optional variable
	String is_there_any_tsv = select_first([STRG_FILENAME_tsv_TASKIN, FILE_LONESOME_tsv_TASKIN, "false"])
	String basestem_reference = sub(basename(select_first([reference_folder, "bogus fallback value"])), "\.tar(?!.{5,})", "") # TODO: double check the regex
	String? intermed_tsv1 = if defined(STRG_FILENAME_tsv_TASKIN) then "~{basestem_reference}/~{STRG_FILENAME_tsv_TASKIN}" else ""
	String? intermed_tsv2 = if defined(FILE_LONESOME_tsv_TASKIN) then "~{FILE_LONESOME_tsv_TASKIN}" else ""
	String? arg_tsv               = if is_there_any_tsv == "false" then "" else "--contam_tsv ~{intermed_tsv1}~{intermed_tsv2}"
	
	# calculate the remaining arguments
	String arg_ref               = if defined(reference_fa_file) then "~{reference_fa_file}" else "~{basestem_reference}/~{reference_fa_string}"
	String arg_cortex_mem_height = if defined(cortex_mem_height) then "--cortex_mem_height ~{cortex_mem_height}" else ""
	String arg_name              = if defined(name) then "--name ~{name}" else ""

	command <<<
		set -eux -o pipefail

		if [[ ! "~{reference_folder}" = "" ]]
		then
			cp ~{reference_folder} .
			tar -xvf ~{basestem_reference}.tar
			rm ~{basestem_reference}.tar
		fi

		clockwork reference_prepare --outdir ~{outdir} ~{arg_ref} ~{arg_cortex_mem_height} ~{arg_tsv} ~{arg_name}

		tar -c ~{outdir}/ > ~{outdir}.tar

		ls -lhaR > workdir.txt
	>>>
	
	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + finalDiskSize + " HDD"
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}
	output {
		# if indexing the decontam ref, the file remove_contam_metadata.tsv will be in tar_ref_prepd
		File    tar_ref_prepd = glob("*.tar")[0]
		File    debug_workdir = "workdir.txt"
	}
}
