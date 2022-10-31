version 1.0

# Runs the clockwork variant calling pipeline on a single sample.
# Can provide more than one run of reads from the same sample - if you do this then the reads are all
# used together, treated as if they were all from one big run.

task variant_call_one_sample {
	input {
		File ref_dir
		Array[File] reads_files

		# optional args
		String? sample_name
		String? outdir
		Int? mem_height
		Boolean force    = false
		Boolean debug    = true

		# Runtime attributes
		Int addldisk = 250
		Int cpu      = 16
		Int retries  = 1
		Int memory   = 32
		Int preempt  = 1
	}
	# forcing this to be true so we can make mapped_to_ref output non-optional,
	# which will avoid awkwardness when it comes to passing that to other tasks
	Boolean keep_bam = true

	# estimate disk size required
	Int size_in = ceil(size(reads_files, "GB")) + addldisk
	Int finalDiskSize = ceil(2*size_in + addldisk)

	String basestem_sample = sub(basename(select_first([sample_name, "unnamed"])), "\.sam(?!.{5,})", "") # TODO: double check the regex
	String basestem_ref_dir = sub(basename(select_first([ref_dir, "bogus fallback value"])), "\.tar(?!.{5,})", "") # TODO: double check the regex
	
	# generate command line arguments
	String arg_sample_name = if(defined(sample_name)) then "--sample_name ~{basestem_sample}" else ""
	String arg_outdir = "var_call_" + select_first([outdir, basestem_sample, "unnamed"])
	String arg_debug = if(debug) then "--debug" else ""
	String arg_mem_height = if(defined(mem_height)) then "--mem_height ~{mem_height}" else ""
	String arg_keep_bam = if(keep_bam) then "--keep_bam" else ""
	String arg_force = if(force) then "--force" else ""

	parameter_meta {
		ref_dir: "tarball directory of reference files, made by clockwork reference_prepare"
		outdir: "Output directory (must not exist, will be created). Will default to var_call_{sample_name} or var_call_unnamed if not provided."
		sample_name: "Name of the sample"
		reads_files: "List of forwards and reverse reads filenames (must provide an even number of files). For a single pair of files: reads_forward.fq reads_reverse.fq. For two pairs of files from the same sample: reads1_forward.fq reads1_reverse.fq reads2_forward.fq reads2_reverse.fq"
		mem_height: "cortex mem_height option. Must match what was used when reference_prepare was run"
		force: "Overwrite outdir if it already exists"
		debug: "Debug mode: do not clean up any files"
	}
	
	command <<<
	cp ~{ref_dir} .
	tar -xvf ~{basestem_ref_dir}.tar

	clockwork variant_call_one_sample \
		~{arg_sample_name} ~{arg_debug} ~{arg_mem_height} ~{arg_keep_bam} ~{arg_force} \
		~{basestem_ref_dir} ~{arg_outdir} \
		~{sep=" " reads_files}
	mv var_call_~{basestem_sample}/final.vcf ./~{basestem_sample}_final.vcf
	mv var_call_~{basestem_sample}/cortex.vcf ./~{basestem_sample}_cortex.vcf
	mv var_call_~{basestem_sample}/samtools.vcf ./~{basestem_sample}_samtools.vcf

	# rename the bam file to the basestem
	mv var_call_~{basestem_sample}/map.bam ./~{basestem_sample}_to_~{basestem_ref_dir}.bam

	# debugging stuff
	ls -lhaR > workdir.txt
	tar -c var_call_~{basestem_sample}/ > ~{basestem_sample}.tar
	head -22 var_call_~{basestem_sample}/cortex/cortex.log | tail -1 > $CORTEX_WARNING
	CORTEX_WARNING=$(head -22 var_call_~{basestem_sample}/cortex/cortex.log | tail -1)
	if [[ $CORTEX_WARNING == WARNING* ]] ;
	then
		echo "***********"
		echo "This sample threw a warning during cortex's clean binaries step. This likely means it's too small for variant calling. Expect this task to have errored at minos adjudicate."
		echo "Read 1 is $(ls -lh var_call_~{basestem_sample}/trimmed_reads.0.1.fq.gz | awk '{print $5}')"
		echo "Read 2 is $(ls -lh var_call_~{basestem_sample}/trimmed_reads.0.2.fq.gz | awk '{print $5}')"
		pigz -dk var_call_~{basestem_sample}/trimmed_reads.0.2.fq.gz
		echo "Decompressed read 2 is $(ls -lh var_call_~{basestem_sample}/trimmed_reads.0.2.fq | awk '{print $5}')"
		echo "The first 50 lines of the Cortex VCF (if all you see are about 30 lines of headers, this is likely an empty VCF!):"
		head -50 var_call_~{basestem_sample}/cortex/cortex.out/vcfs/cortex_wk_flow_I_RefCC_FINALcombined_BC_calls_at_all_k.decomp
		echo "***********"
	else
		echo "This sample likely didn't throw a warning during cortex's clean binaries step. If this task errors out, open an issue on GitHub so the dev can see what's going on!"
	fi
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
		File mapped_to_ref = "~{basestem_sample}_to_~{basestem_ref_dir}.bam"
		File vcf_final_call_set = "~{basestem_sample}_final.vcf"
		File vcf_cortex = "~{basestem_sample}_cortex.vcf"
		File vcf_samtools = "~{basestem_sample}_samtools.vcf"
		File debug_workdir = "workdir.txt"
		File debug_tarball = "~{basestem_sample}.tar"
	}
}