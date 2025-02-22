version 1.0
# reference_prepare_myco is used by myco to index both the "real" TB genome
# and the decontamination reference genome. If you are trying to build off
# this pipeline with some other reference genome, use reference_prepare_byob.
#
# Limitations: 
# * This does not support usage of a database nor db_config_file
# * Out is given in the form of a single tarball, as WDL does 
#   not support outputting a directory (clockwork assumes there's
#   a reference genome folder in workdir/getting passed around,
#   but in WDL we have to pass around a tarball instead)
#
# clockwork reference_prepare essentially runs these steps:
# 1) seqtk seq -C -l 60 {ref genome} > /cromwell_root/ref_dir/ref.fa
# 2) samtools faidx /cromwell_root/ref_dir/ref.fa
# 3) minimap2 -I 0.5G -x sr -d /cromwell_root/ref_dir/ref.fa.minimap2_idx \
#	/cromwell_root/ref_dir/ref.fa
# 4) /bioinf-tools/cortex/bin/cortex_var_31_c1 \
#	--kmer_size 31 --mem_height 22 --mem_width 100 \
#	--se_list /cromwell_root/ref_dir/ref.fofn --max_read_len 10000 \
#	--dump_binary /cromwell_root/ref_dir/ref.k31.ctx --sample_id REF


task reference_prepare_myco {
	# This version of reference_prepare specific to myco.
	input {
		File   reference_folder     # download_tb_reference_files.tar_tb_ref_raw
		String reference_fa_string  # "remove_contam.fa.gz" or "NC_000962.3.fa"
		String outdir               # "Ref.remove_contam" or "Ref.H37Rv"

		Int? cortex_mem_height # mem_height option for cortex

		# If you are indexing the decontamination reference, you need to point to where
		# your contam_tsv is located within your reference folder. Unless a major change
		# to dl_TB_ref's outs happens, it's probably "remove_contam.tsv".
		# If you are NOT indexing the decontamination reference, leave this string undefined.
		String? filename_of_contam_tsv_in_reference_folder

		# Runtime attributes
		Int addldisk = 250
		Int cpu      = 16
		Int retries  = 1
		Int memory   = 32
		Int preempt  = 1
	}
	# estimate disk size required
	Int size_in = ceil((size(reference_folder, "GB")))
	Int finalDiskSize = ceil(size_in + addldisk)

	# find where the reference TSV is going to be located, if it exists at all
	String basestem_reference = sub(basename(reference_folder), "\.tar(?!.{4,})", "")
	String arg_tsv = if defined(filename_of_contam_tsv_in_reference_folder) 
	                 then "--contam_tsv ~{basestem_reference}/~{filename_of_contam_tsv_in_reference_folder}" 
					 else ""
	
	# calculate the remaining arguments
	String arg_ref               = "~{basestem_reference}/~{reference_fa_string}"
	String arg_cortex_mem_height = if defined(cortex_mem_height)
	                               then "--cortex_mem_height ~{cortex_mem_height}"
								   else ""

	command <<<
		set -eux -o pipefail

		# if neither remove_contam.fa.gz or NC_000962.3.fa, error out
		if [[ "~{reference_fa_string}" != "remove_contam.fa.gz" && "~{reference_fa_string}" != "NC_000962.3.fa" ]]
		then
			echo -n 'reference_fa_string is ~{reference_fa_string} but should be either '
			echo    '"remove_contam.fa.gz" (note the gz) or "NC_000962.3.fa" (note the lack of .gz)'
			echo    "More information:"
			echo -n "In the refprep-TB pipeline, a tarball of reference genome files is downloaded by a WDL task "
			echo -n "upsteam of this one. The downloaded tarball is then used in this task to "
			echo -n "create a decontamination reference as well as a more typical TB reference. "
			echo -n "This WDL task is specifically made with these genomes in mind. If you are trying "
			echo -n "to modify it for a different reference genome, run task reference_prepare_byob instead."
			exit 1
		fi

		cp ~{reference_folder} .
		tar -xvf ~{basestem_reference}.tar
		rm ~{basestem_reference}.tar

		clockwork reference_prepare --outdir ~{outdir} ~{arg_ref} ~{arg_cortex_mem_height} ~{arg_tsv}
		tar -c ~{outdir}/ > ~{outdir}.tar

	>>>
	
	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:v0.11.3"
		disks: "local-disk " + finalDiskSize + " SSD"
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}
	output {
		File? H37Rv_for_later = "~{outdir}/ref.fa"
		File? remove_contam_tsv = "remove_contam_metadata.tsv"
		File  tar_ref_prepd = glob("*.tar")[0]

	}
}

task reference_prepare_byob {
	# * TODO: previously assumed that if fasta_file, then don't input contam_tsv, but
    #   is that actually true? --> seems unlikely, could probably use fasta_file for an
    #   index decontamination run which does need a tsv someway or another
	input {
		# You need to define either this...
		File? fasta_file

		# Or both of these.
		File?   reference_folder     # download_tb_reference_files.tar_tb_ref_raw
		String? reference_fa_string  # "remove_contam.fa.gz" or "NC_000962.3.fa"

		# If you are indexing the decontamination reference, you need to define
		# one of these two. It is assumed that if contam_tsv_in_reference_folder
		# is defined, the TSV is located in reference_folder.
		File?   contam_tsv
		String? contam_tsv_in_reference_folder

		# Other stuff
		String outdir          # Name of output directory
		Int? cortex_mem_height # mem_height option for cortex
		String? name           # Name of reference

		# Runtime attributes
		Int addldisk = 250
		Int cpu      = 16
		Int retries  = 1
		Int memory   = 32
		Int preempt  = 1
	}
	# estimate disk size required
	Int size_in = select_first([ceil(size(reference_folder, "GB")), ceil(size(fasta_file, "GB")), 0])
	Int finalDiskSize = ceil(2*size_in + addldisk)

	# find where the reference TSV is going to be located, if it exists at all
	# excessive usage of select_first() is required due to basename() and sub() not working on optional types, even if setting an optional variable
	String is_there_any_tsv = select_first([contam_tsv_in_reference_folder, contam_tsv, "false"])
	String basestem_reference = sub(basename(select_first([reference_folder, "bogus fallback value"])), "\.tar(?!.{5,})", "") # TODO: double check the regex
	String intermed_tsv1 = if defined(contam_tsv_in_reference_folder) then "~{basestem_reference}/~{contam_tsv_in_reference_folder}" else ""
	String intermed_tsv2 = if defined(contam_tsv) then "~{contam_tsv}" else ""
	String arg_tsv       = if is_there_any_tsv == "false" then "" else "--contam_tsv ~{intermed_tsv1}~{intermed_tsv2}"
	
	# calculate the remaining arguments
	String arg_ref               = if defined(fasta_file) then "~{fasta_file}" else "~{basestem_reference}/~{reference_fa_string}"
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
		# if not decontamination reference, grab ref.fa for later myco steps
		tar -c ~{outdir}/ > ~{outdir}.tar

	>>>
	
	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:v0.11.3"
		disks: "local-disk " + finalDiskSize + " SSD"
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}
	output {
		File? remove_contam_tsv = "remove_contam_metadata.tsv"
		File  tar_ref_prepd = glob("*.tar")[0]

	}
}