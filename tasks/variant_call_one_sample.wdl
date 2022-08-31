version 1.0

#usage: clockwork variant_call_one_sample [options] <ref_dir> <outdir> <reads_fwd.fq> <reads_rev.fq> [reads2_fwd.fq reads2_rev.fq ...]
#
#Runs the clockwork variant calling pipeline on a single sample. Can provide more than one run of reads from the same sample - if you do this then the reads are all
#used together, treated as if they were all from one big run. This is for convenience to save catting fastq files.
#
#positional arguments:
#  ref_dir            Directory of reference files, made by clockwork reference_prepare
#  outdir             Output directory (must not exist, will be created)
#  reads_files        List of forwards and reverse reads filenames (must provide an even number of files). For a single pair of files: reads_forward.fq
#                     reads_reverse.fq. For two pairs of files from the same sample: reads1_forward.fq reads1_reverse.fq reads2_forward.fq reads2_reverse.fq
#
#optional arguments:
#  -h, --help         show this help message and exit
#  --sample_name STR  Name of sample [sample]
#  --mem_height INT   cortex mem_height option. Must match what was used when reference_prepare was run [22]
#  --force            Overwrite outdir if it already exists
#  --keep_bam         Keep BAM file of rmdup reads
#  --debug            Debug mode: do not clean up any files

task variant_call_one_sample {
	input {
		File ref_dir
		String outdir # you can construct this in the calling workflow
		Array[File] reads_files

		# optional args
		# TODO: finish implementing these
		String? sample_name
		Int? mem_height
		Boolean? force
		Boolean? keep_bam
		Boolean? debug
	}
	String basename_ref_dir = basename(ref_dir)
	String arg_sample_name = if(defined(sample_name)) then "--sample_name ~{sample_name}" else ""
	
	command <<<
	cp ~{ref_dir} .
	unzip ~{basename_ref_dir}
	FASTQ_FILES=(~{sep=" " reads_files})

	clockwork variant_call_one_sample \
		~{arg_sample_name} \
		~{basename_ref_dir} ~{outdir} \
		${FASTQ_FILES}

	>>>

	output {
		File vcf_final_call_set = "final.vcf"
		File vcf_cortex = "cortex.vcf"
		File vcf_samtools = "samtools.vcf"
		File? bam_mapped_reads = "TODO replace this"
	}
}