version 1.0

task remove_contam {
	input {
		File bam_in

		# [not fully supported] for the metadata TSV, you can either pass in the file directly...
		File? metadata_tsv

		# [supported] ...or you can pass in the zipped prepared reference plus the name of the TSV file
		File?   tarball_metadata_tsv
		String? filename_metadata_tsv = "remove_contam_metadata.tsv"

		# these three are required in the original pipeline, but we can calculate them ourselves
		String? counts_out
		String? reads_out_1
		String? reads_out_2

		# these are optional in the both the original pipeline and our WDL
		String? no_match_out_1
		String? no_match_out_2
		String? contam_out_1
		String? contam_out_2
		String? done_file

		# runtime attributes
		Int addldisk = 100
		Int cpu	= 8
		Int retries	= 1
		Int memory = 16
		Int preempt	= 1
	}
	# calculate the last three positional arguments based on input sam/bam file's basename stem ("basestem")
	String intermed_basestem_bamin = sub(basename(bam_in), "\.bam(?!.{5,})|\.sam(?!.{5,})", "")  # TODO: double check the regex
	String arg_counts_out = if(defined(counts_out)) then "~{counts_out}" else "~{intermed_basestem_bamin}.decontam.counts.tsv"
	String arg_reads_out1 = if(defined(reads_out_1)) then "~{reads_out_1}" else "~{intermed_basestem_bamin}.decontam_1.fq.gz"
	String arg_reads_out2 = if(defined(reads_out_2)) then "~{reads_out_2}" else "~{intermed_basestem_bamin}.decontam_2.fq.gz"

	# the metadata TSV will be either be passed in directly, or will be zipped in tarball_metadata_tsv
	String basename_tsv = sub(basename(select_first([tarball_metadata_tsv, metadata_tsv])), "\.tar(?!.{5,})", "") # TODO: double check the regex
	String arg_metadata_tsv = if(defined(tarball_metadata_tsv)) then "~{basename_tsv}/~{filename_metadata_tsv}" else "~{basename_tsv}"
	
	# calculate the optional inputs
	String arg_no_match_out_1 = if(!defined(no_match_out_1)) then "" else "--no_match_out_1 ~{no_match_out_1}"
	String arg_no_match_out_2 = if(!defined(no_match_out_2)) then "" else "--no_match_out_2 ~{no_match_out_2}"
	String arg_contam_out_1 = if(!defined(contam_out_1)) then "" else "--contam_out_1 ~{contam_out_1}"
	String arg_contam_out_2 = if(!defined(contam_out_1)) then "" else "--contam_out_2 ~{contam_out_2}"
	String arg_done_file = if(!defined(done_file)) then "" else "--done_file ~{done_file}"

	# estimate disk size
	Int finalDiskSize = ceil(size(metadata_tsv, "GB")) + 3*ceil(size(tarball_metadata_tsv, "GB")) + ceil(size(bam_in, "GB")) + addldisk

	parameter_meta {
		metadata_tsv: "Metadata TSV file. 1st positional arg of ''clockwork remove_contam''. Format: one group of ref seqs per line. Tab-delimited columns: 1) group name; 2) 1|0 for is|is not contamination; 3+) sequence names."
		tarball_metadata_tsv: "Tarball decontamination reference. Only needed if metadata_tsv is not provided."
		filename_metadata_tsv: "Filename of the metadata TSV within tarball_metadata_tsv. Only needed if metadata_tsv is not provided. This plus tarball_metadata_tsv will be used to construct 1st positional arg of ''clockwork remove_contam'' Default: remove_contam_metadata.tsv"
		bam_in: "Input bam or sam file. 2nd positional arg of ''clockwork remove_contam''"
		counts_out: "Name of output file of read counts. 3rd positional arg of ''clockwork remove_contam''. If not provided, will be generated from the basename stem of bam_in."
		reads_out_1: "Name of output reads file 1. If not provided, will be generated from the basename stem of bam_in. 4th positional arg of ''clockwork remove_contam''"
		reads_out_2: "Name of output reads file 2. If not provided, will be generated from the basename stem of bam_in. 5th positional arg of ''clockwork remove_contam''"
		no_match_out_1: "Name of output file 1 of reads that did not match. If not given, reads are included in reads_out_1. Must be used with --no_match_out_2"
		no_match_out_2: "Name of output file 2 of reads that did not match. If not given, reads are included in reads_out_2. Must be used with --no_match_out_1"
		contam_out_1: "Name of output file 1 of contamination reads. If not given, reads are discarded. Must be used with --contam_out_2"
		contam_out_2: "Name of output file 2 of contamination reads. If not given, reads are discarded. Must be used with --contam_out_1"
		done_file: "Write a file of the given name when the script is finished."
	}
	
	command <<<
	set -eux -o pipefail

	if [[ ! "~{tarball_metadata_tsv}" = "" ]]
	then
		mv ~{tarball_metadata_tsv} .
		tar -xvf ~{basename_tsv}.tar
		samtools index ~{bam_in}
	fi

	if [[ ! "~{metadata_tsv}" = "" ]]
	then
		# for some reason it seems this requires a samtools index
		# TODO: see if the other version also needs it; 
		# if so this has been broken for a while
		cp ~{metadata_tsv} .
		samtools index ~{bam_in}
	fi

	# debug
	ls

	clockwork remove_contam \
		~{arg_metadata_tsv} \
		~{bam_in} \
		~{arg_counts_out} \
		~{arg_reads_out1} \
		~{arg_reads_out2} \
		~{arg_no_match_out_1} ~{arg_no_match_out_2} ~{arg_contam_out_1} ~{arg_contam_out_2} ~{arg_done_file}

	ls -lhaR > workdir.txt

	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + finalDiskSize + " SSD"
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		# paired FASTQ files split into OK, contaminated, and unmapped
		File decontaminated_fastq_1 = "${arg_reads_out1}"
		File decontaminated_fastq_2 = "${arg_reads_out2}"
		File debug_workdir = "workdir.txt"
	}
}