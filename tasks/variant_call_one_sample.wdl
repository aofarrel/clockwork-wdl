version 1.0

# Runs the clockwork variant calling pipeline on a single sample.
# Can provide more than one run of reads from the same sample - if you do this then the reads are all
# used together, treated as if they were all from one big run.

# There are two versions of this task. You likely want variant_call_one_sample_simple. However, if
# you want more information about failures and/or want to fail variant calling without failing the
# whole pipeline, and can handle dealing with optional output, use variant_call_one_sample_verbose.
# variant_call_one_sample_verbose can also handle tarballed read files.

task variant_call_one_sample_simple {
	input {
		File ref_dir
		Array[File] reads_files

		# optional args
		Int? mem_height
		Boolean force    = false
		Boolean debug    = false

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

	String basestem_ref_dir = sub(basename(select_first([ref_dir, "bogus fallback value"])), "\.tar(?!.{5,})", "") # TODO: double check the regex
	
	# generate command line arguments
	String arg_debug = if(debug) then "--debug" else ""
	String arg_mem_height = if(defined(mem_height)) then "--mem_height ~{mem_height}" else ""
	String arg_keep_bam = if(keep_bam) then "--keep_bam" else ""
	String arg_force = if(force) then "--force" else ""

	parameter_meta {
		ref_dir: "tarball directory of reference files, made by clockwork reference_prepare"
		reads_files: "List of forwards and reverse reads filenames (must provide an even number of files). For a single pair of files: reads_forward.fq reads_reverse.fq. For two pairs of files from the same sample: reads1_forward.fq reads1_reverse.fq reads2_forward.fq reads2_reverse.fq"
		mem_height: "cortex mem_height option. Must match what was used when reference_prepare was run"
		force: "Overwrite outdir if it already exists"
		debug: "Debug mode: do not clean up any files"
	}
	
	command <<<
	mv ~{ref_dir} .
	tar -xvf ~{basestem_ref_dir}.tar
	rm ~{basestem_ref_dir}.tar # just to save disk space

	for READFILE in ~{sep=' ' reads_files} 
	do
		basename=$(basename $READFILE .fq.gz)
		sample_name="${basename%%.*}"
	done
	echo $sample_name
	arg_outdir="var_call_$sample_name"

	apt-get install -y tree
	tree > tree1.txt

	if clockwork variant_call_one_sample \
		--sample_name $sample_name ~{arg_debug} ~{arg_mem_height} ~{arg_keep_bam} ~{arg_force} \
		~{basestem_ref_dir} $arg_outdir \
		~{sep=" " reads_files}; then echo "Task completed successfully (probably)"	
	else	
		echo "Caught an error."	
		touch $sample_name	
	fi
	
	tree > tree2.txt

	echo "mv var_call_$sample_name/final.vcf $workdir/$sample_name.vcf"

	mv var_call_$sample_name/final.vcf ./"$sample_name"_final.vcf
	mv var_call_$sample_name/cortex.vcf ./"$sample_name"_cortex.vcf
	mv var_call_$sample_name/samtools.vcf ./"$sample_name"_samtools.vcf

	# rename the bam file to the basestem
	mv var_call_$sample_name/map.bam ./"$sample_name"_to_~{basestem_ref_dir}.bam

	# debugging stuff
	head -22 var_call_$sample_name/cortex/cortex.log | tail -1 > $CORTEX_WARNING
	CORTEX_WARNING=$(head -22 var_call_$sample_name/cortex/cortex.log | tail -1)
	if [[ $CORTEX_WARNING == WARNING* ]] ;
	then
		echo "***********"
		echo "This sample threw a warning during cortex's clean binaries step. This likely means it's too small for variant calling. Expect this task to have errored at minos adjudicate."
		echo "Read 1 is $(ls -lh var_call_$sample_name/trimmed_reads.0.1.fq.gz | awk '{print $5}')"
		echo "Read 2 is $(ls -lh var_call_$sample_name/trimmed_reads.0.2.fq.gz | awk '{print $5}')"
		gunzip -dk var_call_$sample_name/trimmed_reads.0.2.fq.gz
		echo "Decompressed read 2 is $(ls -lh var_call_$sample_name/trimmed_reads.0.2.fq | awk '{print $5}')"
		echo "The first 50 lines of the Cortex VCF (if all you see are about 30 lines of headers, this is likely an empty VCF!):"
		head -50 var_call_$sample_name/cortex/cortex.out/vcfs/cortex_wk_flow_I_RefCC_FINALcombined_BC_calls_at_all_k.decomp.vcf
		exit 0
	else
		echo "This sample likely didn't throw a warning during cortex's clean binaries step. If this task errors out, open an issue on GitHub so the dev can see what's going on!"
	fi

	tree > tree3.txt
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
		File mapped_to_ref = glob("*~{basestem_ref_dir}.bam")[0]
		File vcf_final_call_set = glob("*_final.vcf")[0]
		File vcf_cortex = glob("*_cortex.vcf")[0]
		File vcf_samtools = glob("*_samtools.vcf")[0]
		File debugtree1 = "tree1.txt"
		File debugtree2 = "tree2.txt"
		File debugtree3 = "tree3.txt"
	}
}

task variant_call_one_sample_verbose {
	input {
		File ref_dir
		Array[File]? reads_files
		File? tarball_of_reads_files

		# optional args
		String? sample_name # only used in warning_file
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
	Int size_in = ceil(size(select_first([reads_files, tarball_of_reads_files]), "GB"))
	Int finalDiskSize = ceil(2*size_in + addldisk)
	String basestem_ref_dir = sub(basename(select_first([ref_dir, "bogus fallback value"])), "\.tar(?!.{5,})", "") # TODO: double check the regex
	
	# generate command line arguments
	String arg_debug = if(debug) then "--debug" else ""
	String arg_mem_height = if(defined(mem_height)) then "--mem_height ~{mem_height}" else ""
	String arg_keep_bam = if(keep_bam) then "--keep_bam" else ""
	String arg_force = if(force) then "--force" else ""

	# just needed for the output since glob doesn't work with optionals, 
	# should be equivalent to $sample_name when running on a tarball
	# unfortunately as you cant deference arrays via indeces in WDL, it
	# seems we cannot set some equivalent of reads_files[0] as a fallback
	String warning_file = basename(select_first([tarball_of_reads_files, sample_name, "fallback"]), ".tar")

	parameter_meta {
		ref_dir: "tarball directory of reference files, made by clockwork reference_prepare"
		reads_files: "*MUST define either this OR tarball_of_reads_files, not both. Must have extension .fq.gz -- List of forwards and reverse reads filenames (must provide an even number of files). For a single pair of files: reads_forward.fq reads_reverse.fq. For two pairs of files from the same sample: reads1_forward.fq reads1_reverse.fq reads2_forward.fq reads2_reverse.fq"
		tarball_of_reads_files: "*MUST define either this OR reads_files, not both. Files within must have extension .fq.gz -- Same as reads_files but in a tar archive. Must be tar, not tar.gz"
		mem_height: "cortex mem_height option. Must match what was used when reference_prepare was run"
		force: "Overwrite outdir if it already exists"
		debug: "Debug mode: do not clean up any files"
	}
	
	command <<<
	mv ~{ref_dir} .
	tar -xvf ~{basestem_ref_dir}.tar
	rm ~{basestem_ref_dir}.tar # needs to be deleted to prevent next bit breaking

	if [[ ! "~{tarball_of_reads_files}" = "" ]]
	then
		mv ~{tarball_of_reads_files} .
		tar -xvf ./*.tar # if another tar is in the workdir this will fail
		sample_name="$(basename ~{tarball_of_reads_files} .tar)"
	fi
	if [[ ! "~{sep=" " reads_files}" = "" ]]
	then
		# this should ensure find *.fq.gz works as expected
		for READFILE in ~{sep=' ' reads_files}
		do
			sample_name="$(basename $READFILE decontam.fq.gz)"
			mv $READFILE .
		done
	fi
	
	# get sample name and reads files
	declare -a read_files_array
	readarray -t read_files_array < <(find ./"$sample_name" -name "*.fq.gz")
	one_read_file=$(echo "${read_files_array[0]}")
	arg_outdir="var_call_$sample_name"

	if clockwork variant_call_one_sample \
		--sample_name $sample_name ~{arg_debug} ~{arg_mem_height} ~{arg_keep_bam} ~{arg_force} \
		~{basestem_ref_dir} $arg_outdir \
		${read_files_array[@]}; then echo "Task completed successfully (probably)"
	else
		echo "Caught an error."
		touch $sample_name
	fi
	
	mv var_call_$sample_name/final.vcf ./"$sample_name"_final.vcf
	mv var_call_$sample_name/cortex.vcf ./"$sample_name"_cortex.vcf
	mv var_call_$sample_name/samtools.vcf ./"$sample_name"_samtools.vcf

	# rename the bam file to the basestem
	mv var_call_$sample_name/map.bam ./"$sample_name"_to_~{basestem_ref_dir}.bam

	# debugging stuff
	ls -lhaR > workdir.txt
	tar -c var_call_$sample_name/ > $sample_name.tar
	CORTEX_WARNING=$(head -22 var_call_$sample_name/cortex/cortex.log | tail -1)
	if [[ $CORTEX_WARNING == WARNING* ]] ;
	then
		echo "***********"
		echo "This sample threw a warning during cortex's clean binaries step. This likely means it's too small for variant calling. Expect this task to have errored at minos adjudicate."
		echo "Read 1 is $(ls -lh var_call_$sample_name/trimmed_reads.0.1.fq.gz | awk '{print $5}')"
		echo "Read 2 is $(ls -lh var_call_$sample_name/trimmed_reads.0.2.fq.gz | awk '{print $5}')"
		gunzip -dk var_call_$sample_name/trimmed_reads.0.2.fq.gz
		echo "Decompressed read 2 is $(ls -lh var_call_$sample_name/trimmed_reads.0.2.fq | awk '{print $5}')"
		echo "The first 50 lines of the Cortex VCF (if all you see are about 30 lines of headers, this is likely an empty VCF!):"
		head -50 var_call_$sample_name/cortex/cortex.out/vcfs/cortex_wk_flow_I_RefCC_FINALcombined_BC_calls_at_all_k.decomp.vcf
		echo "***********"
		echo "More data please!" > "~{warning_file}".warning
		exit 0
	else
		echo "This sample likely didn't throw a warning during cortex's clean binaries step. If this task errors out, open an issue on GitHub so the dev can see what's going on!"
	fi
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
		File? mapped_to_ref = glob("*~{basestem_ref_dir}.bam")[0]
		File? vcf_final_call_set = glob("*_final.vcf")[0]
		File? vcf_cortex = glob("*_cortex.vcf")[0]
		File? vcf_samtools = glob("*_samtools.vcf")[0]
		File debug_workdir = "workdir.txt"
		File? debug_error = "~{warning_file}.warning" # only exists if we error out, cannot glob otherwise
	}
}