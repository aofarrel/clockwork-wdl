version 1.0

#usage: clockwork variant_call_one_sample [options] <ref_dir> <outdir> <reads_fwd.fq> <reads_rev.fq> [reads2_fwd.fq reads2_rev.fq ...]
#
#Runs the clockwork variant calling pipeline on a single sample. Can provide more than one run of reads from the same sample - if you do this then the reads are all
#used together, treated as if they were all from one big run. This is for convenience to save catting fastq files.
#
#positional arguments:
#  ref_dir            
#  outdir             
#  reads_files        
#
#optional arguments:
#  -h, --help         show this help message and exit
#  --sample_name STR  Name of sample [sample]
#  --mem_height INT    [22]
#  --force            
#  --keep_bam         
#  --debug            

task variant_call_one_sample {
	input {
		File ref_dir
		Array[File] reads_files

		# optional args
		String? sample_name
		String? outdir
		Int? mem_height
		Boolean force = false
		Boolean keep_bam = false
		Boolean debug = false

		# Runtime attributes
		Int addldisk = 250
		Int cpu      = 16
		Int retries  = 1
		Int memory   = 32
		Int preempt  = 1
	}
	# estimate disk size required
	Int size_in = ceil(size(reads_files, "GB")) + addldisk
	Int finalDiskSize = ceil(2*size_in + addldisk)

	String basestem_ref_dir = sub(basename(select_first([ref_dir, "bogus fallback value"])), "\.tar.gz(?!.{5,})", "") # TODO: double check the regex
	
	# generate command line arguments
	String arg_sample_name = if(defined(sample_name)) then "--sample_name ~{sample_name}" else ""
	String arg_outdir = "var_call_" + select_first([outdir, sample_name, "unnamed"])
	String arg_debug = if(debug) then "--debug" else ""
	String arg_mem_height = if(defined(mem_height)) then "--mem_height ~{mem_height}" else ""
	String arg_keep_bam = if(keep_bam) then "--keep_bam" else ""
	String arg_force = if(force) then "--force" else ""
	
	command <<<
	cp ~{ref_dir} .
	gunzip ~{basestem_ref_dir}.tar.gz
	tar -xvf ~{basestem_ref_dir}.tar

	clockwork variant_call_one_sample \
		~{arg_sample_name} ~{arg_debug} ~{arg_mem_height} ~{arg_keep_bam} ~{arg_force} \
		~{basestem_ref_dir} ~{arg_outdir} \
		~{sep=" " reads_files}

	>>>

	parameter_meta {
		ref_dir: "tar.gz'd directory of reference files, made by clockwork reference_prepare"
		outdir: "Output directory (must not exist, will be created). Will default to var_call_{sample_name} or var_call_unnamed if not provided."
		sample_name: "Name of the sample"
		reads_files: "List of forwards and reverse reads filenames (must provide an even number of files). For a single pair of files: reads_forward.fq reads_reverse.fq. For two pairs of files from the same sample: reads1_forward.fq reads1_reverse.fq reads2_forward.fq reads2_reverse.fq"
		mem_height: "cortex mem_height option. Must match what was used when reference_prepare was run"
		force: "Overwrite outdir if it already exists"
		keep_bam: "Keep BAM file of rmdup reads"
		debug: "Debug mode: do not clean up any files"
	}

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + finalDiskSize + " HDD"
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		File vcf_final_call_set = "final.vcf"
		File vcf_cortex = "cortex.vcf"
		File vcf_samtools = "samtools.vcf"
		File? bam_mapped_reads = "TODO replace this"
	}
}