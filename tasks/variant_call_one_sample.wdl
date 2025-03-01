version 1.0

# Runs the clockwork variant calling pipeline on a single sample.
# Can provide more than one run of reads from the same sample - if you do this then the reads are all
# used together, treated as if they were all from one big run.

# There are three versions of this task. You likely want variant_call_one_sample_ref_included. However, if
# you want more information about failures and/or want to fail variant calling without failing the
# whole pipeline, and can handle dealing with optional output, use variant_call_one_sample_verbose.
# variant_call_one_sample_verbose can also handle tarballed read files.
#
# variant_call_one_sample_ref_included [recommended]
# * Uses 0.12.5 of clockwork
# * Comes with H37Rv reference (cannot be overwritten)
# * Read files can be fq or fastq
# * Exits gracefully if variants cannot be called unless crash_on_error is true
# * Supports timing out after n minutes to avoid runaway cloud compute costs
#
# variant_call_one_sample_simple [legacy]
# * Uses 0.11.3 of clockwork
# * Must provide reference genome
# * Read files can be fq or fastq
# * If variants cannot be called, errors fatally (i.e., will crash pipeline)
#
# variant_call_one_sample_verbose [legacy]
# * Uses 0.11.3 of clockwork
# * Must provide reference genome
# * Read files can be fq, fastq, or tarballs
# * Exits gracefully if variants cannot be called

task variant_call_one_sample_ref_included {
	input {
		Array[File] reads_files

		# optional args
		Boolean debug            = false
		Boolean crash_on_error   = false
		Boolean crash_on_timeout = false
		Boolean tarball_bams_and_bais = false
		Int? mem_height
		Int timeout = 120

		# Runtime attributes
		Int addldisk = 100
		Int cpu      = 16
		Int retries  = 1
		Int memory   = 32
		Int preempt  = 1
		Boolean ssd  = true
	}
	# forcing this to be true so we can make bam output non-optional,
	# which will avoid awkwardness when it comes to passing that to other tasks
	# this seems to also allow us to hold onto bais without --debug
	Boolean keep_bam = true

	# this is a clockwork option that overwrites outdir if it already exists
	# this is essentially meaningless in WDL, where everything happens in a VM
	Boolean force = false

	# estimate disk size required and see what kind of disk we're using
	Int size_in = ceil(size(reads_files, "GB")) + addldisk
	Int finalDiskSize = ceil(2*size_in + addldisk)
	String diskType = if((ssd)) then " SSD" else " HDD"

	# we need to be able set the outputs name from an input name to use optional outs
	# WDL's sub()'s regex seems a little odd ("_\d\.decontam\.fq\.gz" doesn't work)
	# so we're going to do this in the most simply way possible
	String basename_reads = basename(reads_files[0], ".decontam.fq.gz")
	String sample_name = sub(basename_reads, "_1", "")
	
	# generate command line arguments
	String arg_debug = if(debug) then "--debug" else ""
	String arg_mem_height = if(defined(mem_height)) then "--mem_height ~{mem_height}" else ""
	String arg_keep_bam = if(keep_bam) then "--keep_bam" else ""
	String arg_force = if(force) then "--force" else ""

	parameter_meta {
		reads_files: "List of forwards and reverse reads filenames (must provide an even number of files). For a single pair of files: reads_forward.fq reads_reverse.fq. For two pairs of files from the same sample: reads1_forward.fq reads1_reverse.fq reads2_forward.fq reads2_reverse.fq"
		mem_height: "cortex mem_height option. Must match what was used when reference_prepare was run"
		debug: "Debug mode: do not clean up any files and be verbose"
	}
	
	command <<<
	
	# Untar the reference (this will put it in the workdir) 
	tar -xvf /ref/Ref.H37Rv.tar

	echo "~{sample_name}"
	arg_outdir="var_call_~{sample_name}"

	timeout -v ~{timeout}m clockwork variant_call_one_sample \
	--sample_name "~{sample_name}" \
	~{arg_debug} \
	~{arg_mem_height} \
	~{arg_keep_bam} \
	~{arg_force} \
	"Ref.H37Rv" "$arg_outdir" \
	~{sep=" " reads_files}
	
	exit=$?
	
	# rc 124 -- timed out
	if [[ $exit = 124 ]]
	then
		echo "ERROR -- clockwork variant_call_one_sample timed out"
		if [[ "~{debug}" = "true" ]]
		then
			tar -c "var_call_~{sample_name}/" > "~{sample_name}.tar"
		fi
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "VARIANT_CALLING_TIMEOUT" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "VARIANT_CALLING_TIMEOUT" >> ERROR 
			exit 0
		fi
	
	# rc 134 -- killed
	# you'll see a lot of this if you try to run this on a local machine on Cromwell default settings; Cromwell is
	# not good at managing hardware resources if you're running on a local machine. This can be partially mitigated
	# by setting your "hog factors" (cromwell.conf) to only run one concurrent task at a time.
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork variant_call_one_sample was killed -- it may have run out of memory"
		if [[ "~{debug}" = "true" ]]
		then
			tar -c "var_call_~{sample_name}/" > "~{sample_name}.tar"
		fi
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "VARIANT_CALLING_KILLED" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "VARIANT_CALLING_KILLED" >> ERROR
			exit 0
		fi
	
	# rc 0
	elif [[ $exit = 0 ]]
	then
		echo "Successfully called variants" 
	
	# rc 1
	# Previously, when cortex failed to call variants, clockwork would return 1 and we'd catch it here, then parse the
	# cortex log for clues. But that seems to have changed in v0.12.x of clockwork -- the clockwork command returns 0
	# and the cortex log doesn't seem helpful anymore.
	# In case there's some weird edge case where clockwork can still return 1, I'm keeping the basics of this check in
	# place, but we're no longer trying to parse logs. Instead, later on, we just check the line number in the final
	# VCF file -- if it's less than four (1: VCF format version, 2: header, 3: blank newline) than we declare it invalid.
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork variant_call_one_sample returned 1 for unknown reasons"
		echo "VARIANT_CALLING_UNKNOWN_ERROR" >> ERROR
		if [[ "~{debug}" = "true" ]]
		then
			tar -c "var_call_~{sample_name}/" > "~{sample_name}.tar"
		fi
		
		if [[ "~{crash_on_error}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	
	# rc is something mysterious 
	# I don't know if this ever happens, but sure, let's handle it just in case
	else
		echo "ERROR -- clockwork variant_call_one_sample returned $exit for unknown reasons"
		echo "VARIANT_CALLING_UNKNOWN_ERROR_$exit" >> ERROR
		if [[ "~{debug}" = "true" ]]
		then
			tar -c "var_call_~{sample_name}/" > "~{sample_name}.tar"
		fi
		if [[ "~{crash_on_error}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	fi

	# check that the final VCF file is more than four lines in length
	if [ "$(wc -l < file.txt)" -lt 4 ]
	then
		echo "Adjudicated VCF file is less than four lines long. This almost certainly means that no variants were found!"
		echo "Dump of all VCF files to stdout:"
		echo "Samtools:"
		cat var_call_"~{sample_name}"/samtools.vcf
		echo "Cortex:"
		cat var_call_"~{sample_name}"/cortex.vcf
		echo "Adjudicated:"
		cat var_call_"~{sample_name}"/final.vcf

		# delete the VCF so it doesn't get delocalized
		rm var_call_"~{sample_name}"/final.vcf
		echo "VARIANT_CALLING_EMPTY_FILE" >> ERROR
		if [[ "~{crash_on_error}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	else
		echo "VCF file is $(wc -l var_call_'~{sample_name}'/final.vcf) lines long. It's probably fine."
	fi

	echo mving VCFs from var_call_"~{sample_name}"/*.vcf to ./"~{sample_name}"*.vcf

	mv var_call_"~{sample_name}"/final.vcf ./"~{sample_name}".vcf

	# rename the bam and bai files
	mv var_call_"~{sample_name}"/map.bam ./"~{sample_name}"_to_H37Rv.bam
	mv var_call_"~{sample_name}"/map.bam.bai ./"~{sample_name}"_to_H37Rv.bam.bai
	
	if [[ "~{tarball_bams_and_bais}" = "true" ]]
	then
		mkdir "~{sample_name}_aligned_to_H37Rv"
		mv ./"~{sample_name}"_to_H37Rv.bam ./"~{sample_name}_aligned_to_H37Rv"/"~{sample_name}".bam
		mv ./"~{sample_name}"_to_H37Rv.bam.bai ./"~{sample_name}_aligned_to_H37Rv"/"~{sample_name}".bam.bai
		tar -c "~{sample_name}_aligned_to_H37Rv/" > "~{sample_name}_aligned_to_H37Rv.tar"
	fi

	if [[ "~{debug}" = "true" ]]
	then
		mv var_call_"~{sample_name}"/cortex.vcf ./"~{sample_name}"_cortex.vcf
		mv var_call_"~{sample_name}"/samtools.vcf ./"~{sample_name}"_samtools.vcf
	fi
	
	echo "PASS" >> ERROR
	echo "Variant calling completed."
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/clockwork-plus:v0.12.5.2-slim"
		disks: "local-disk " + finalDiskSize + diskType
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		String errorcode = read_string("ERROR")

		# these NEED to be optional to allow a sample to fail QC and get dropped without erroring out the entire pipeline
		File? bam = sample_name+"_to_H37Rv.bam"
		File? bai = sample_name+"_to_H37Rv.bam.bai"
		File? adjudicated_vcf = sample_name+".vcf"
		
		# only if debug is true
		File? debug_samtools_vcf = sample_name+"_samtools.vcf"
		File? debug_cortex_vcf = sample_name+"_cortex.vcf"
		File? debug_workdir_tarball = sample_name+".tar"  # only if debug is true and something breaks
	}
}



task variant_call_one_sample_simple {
	input {
		File ref_dir
		Array[File] reads_files

		# optional args
		Boolean debug            = false
		Boolean crash_on_error   = false
		Boolean crash_on_timeout = false
		Int? mem_height
		Int timeout = 120

		# Runtime attributes
		Int addldisk = 100
		Int cpu      = 16
		Int retries  = 1
		Int memory   = 32
		Int preempt  = 1
		Boolean ssd  = true
	}
	# forcing this to be true so we can make bam output non-optional,
	# which will avoid awkwardness when it comes to passing that to other tasks
	Boolean keep_bam = true

	# this is a clockwork option that overwrites outdir if it already exists
	# this is essentially meaningless in WDL, where everything happens in a VM
	Boolean force = false

	# estimate disk size required and see what kind of disk we're using
	Int size_in = ceil(size(reads_files, "GB")) + addldisk
	Int finalDiskSize = ceil(2*size_in + addldisk)
	String diskType = if((ssd)) then " SSD" else " HDD"

	String basestem_ref_dir = sub(basename(ref_dir), "\.tar(?!.{5,})", "")

	# we need to be able set the outputs name from an input name to use optional outs
	# WDL's sub()'s regex seems a little odd ("_\d\.decontam\.fq\.gz" doesn't work)
	# so we're going to do this in the most simply way possible
	String basename_reads = basename(reads_files[0], ".decontam.fq.gz")
	String sample_name = sub(basename_reads, "_1", "")
	
	# generate command line arguments
	String arg_debug = if(debug) then "--debug" else ""
	String arg_mem_height = if(defined(mem_height)) then "--mem_height ~{mem_height}" else ""
	String arg_keep_bam = if(keep_bam) then "--keep_bam" else ""
	String arg_force = if(force) then "--force" else ""

	parameter_meta {
		ref_dir: "tarball directory of reference files, made by clockwork reference_prepare"
		reads_files: "List of forwards and reverse reads filenames (must provide an even number of files). For a single pair of files: reads_forward.fq reads_reverse.fq. For two pairs of files from the same sample: reads1_forward.fq reads1_reverse.fq reads2_forward.fq reads2_reverse.fq"
		mem_height: "cortex mem_height option. Must match what was used when reference_prepare was run"
		debug: "Debug mode: do not clean up any files and be verbose"
	}
	
	command <<<
	mv ~{ref_dir} .
	tar -xvf ~{basestem_ref_dir}.tar
	rm ~{basestem_ref_dir}.tar # just to save disk space

	echo "~{sample_name}"
	arg_outdir="var_call_~{sample_name}"

	if [[ "~{debug}" = "true" ]]
	then
		ls -R ./* > contents_1.txt
		READS_FILES=("~{sep='" "' reads_files}")
		for inputfq in "${READS_FILES[@]}"
		do
			cp "$inputfq" "~{sample_name}_varclfail.fastq.gz"
		done
	fi

	timeout -v ~{timeout}m clockwork variant_call_one_sample \
	--sample_name "~{sample_name}" \
	~{arg_debug} \
	~{arg_mem_height} \
	~{arg_keep_bam} \
	~{arg_force} \
	~{basestem_ref_dir} "$arg_outdir" \
	~{sep=" " reads_files}
	
	exit=$?
	if [[ $exit = 124 ]]
	then
		echo "ERROR -- clockwork variant_call_one_sample timed out"
		if [[ "~{debug}" = "true" ]]
		then
			tar -c "var_call_~{sample_name}/" > "~{sample_name}.tar"
		fi
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork variant_call_one_sample was killed -- it may have run out of memory"
		if [[ "~{debug}" = "true" ]]
		then
			tar -c "var_call_~{sample_name}/" > "~{sample_name}.tar"
		fi
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Successfully called variants" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork variant_call_one_sample errored out for unknown reasons"
		if [[ "~{debug}" = "true" ]]
		then
			tar -c "var_call_~{sample_name}/" > "~{sample_name}.tar"
		fi
		if [[ "~{crash_on_error}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	else
		echo "ERROR -- clockwork variant_call_one_sample returned $exit for unknown reasons"
		if [[ "~{debug}" = "true" ]]
		then
			tar -c "var_call_~{sample_name}/" > "~{sample_name}.tar"
		fi
		if [[ "~{crash_on_error}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	fi
	
	if [[ "~{debug}" = "true" ]]
	then
		ls -R ./* > contents_2.txt
		echo mving VCFs from var_call_"~{sample_name}"/*.vcf to ./"~{sample_name}"*.vcf
	fi

	mv var_call_"~{sample_name}"/final.vcf ./"~{sample_name}".vcf
	mv var_call_"~{sample_name}"/cortex.vcf ./"~{sample_name}"_cortex.vcf
	mv var_call_"~{sample_name}"/samtools.vcf ./"~{sample_name}"_samtools.vcf

	# rename the bam file
	mv var_call_"~{sample_name}"/map.bam ./"~{sample_name}"_to_~{basestem_ref_dir}.bam

	if [[ "~{debug}" = "true" ]]
	then
		ls -R ./* > contents_3.txt
		tar -c "var_call_~{sample_name}/" > "~{sample_name}.tar"
		rm "~{sample_name}_varclfail.fastq"
	fi

	echo "Variant calling completed."
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:v0.11.3"
		disks: "local-disk " + finalDiskSize + diskType
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		# the outputs you care about
		File? bam = sample_name+"_to_"+basestem_ref_dir+".bam"
		File? adjudicated_vcf = sample_name+".vcf"

		# debugging stuff
		File? check_this_fastq = sample_name+"_varclfail.fastq.gz"
		File? cortex_log = "var_call_"+sample_name+"/cortex/cortex.log"
		File? ls1 = "contents_1.txt"
		File? ls2 = "contents_2.txt"
		File? ls3 = "contents_3.txt"
		File? workdir_tarball = sample_name+".tar"
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
	# forcing this to be true so we can make bam output non-optional,
	# which will avoid awkwardness when it comes to passing that to other tasks
	Boolean keep_bam = true

	# estimate disk size required
	Int size_in = ceil(size(select_first([reads_files, [tarball_of_reads_files]]), "GB"))
	Int finalDiskSize = ceil(2*size_in + addldisk)
	String basestem_ref_dir = sub((basename(ref_dir)), "\.tar(?!.{5,})", "") # TODO: clean up the regex
	
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
	#one_read_file=$(echo "${read_files_array[0]}")
	arg_outdir="var_call_$sample_name"

	if clockwork variant_call_one_sample \
		--sample_name "$sample_name" ~{arg_debug} ~{arg_mem_height} ~{arg_keep_bam} ~{arg_force} \
		~{basestem_ref_dir} "$arg_outdir" \
		"${read_files_array[@]}"; then echo "Task completed successfully (probably)"
	else
		echo "Caught an error."
		touch "$sample_name"
	fi
	
	mv var_call_"$sample_name"/final.vcf ./"$sample_name"_final.vcf
	mv var_call_"$sample_name"/cortex.vcf ./"$sample_name"_cortex.vcf
	mv var_call_"$sample_name"/samtools.vcf ./"$sample_name"_samtools.vcf

	# rename the bam file to the basestem
	mv var_call_"$sample_name"/map.bam ./"$sample_name"_to_~{basestem_ref_dir}.bam

	# debugging stuff
	ls -lhaR > workdir.txt
	tar -c "var_call_$sample_name/" > "$sample_name.tar"
	CORTEX_WARNING=$(head -22 var_call_"$sample_name"/cortex/cortex.log | tail -1)
	if [[ $CORTEX_WARNING == WARNING* ]] ;
	then
		echo "***********"
		echo "This sample threw a warning during cortex's clean binaries step. This likely means it's too small for variant calling, but not small enough to fail minimap2."
		echo "Expect this task to have errored at minos adjudicate."
		size_of_read1=$(stat -c %s var_call_"~{sample_name}"/trimmed_reads.0.1.fq.gz)
		echo "Read 1 is $size_of_read1"
		#echo "Read 2 is $(ls -lh var_call_$sample_name/trimmed_reads.0.2.fq.gz | awk '{print $5}')"
		#gunzip -dk var_call_$sample_name/trimmed_reads.0.2.fq.gz
		#echo "Decompressed read 2 is $(ls -lh var_call_$sample_name/trimmed_reads.0.2.fq | awk '{print $5}')"
		echo "The first 50 lines of the Cortex VCF (if all you see are about 30 lines of headers, this is likely an empty VCF!):"
		head -50 var_call_"$sample_name"/cortex/cortex.out/vcfs/cortex_wk_flow_I_RefCC_FINALcombined_BC_calls_at_all_k.decomp.vcf
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
		File? bam = glob("*~{basestem_ref_dir}.bam")[0]
		File? adjudicated_vcf = glob("*_final.vcf")[0]
		File? vcf_cortex = glob("*_cortex.vcf")[0]
		File? vcf_samtools = glob("*_samtools.vcf")[0]
		File debug_workdir = "workdir.txt"
		File? debug_error = "~{warning_file}.warning" # only exists if we error out, cannot glob otherwise
		# TODO: above comment implies that you can glob on nonexistent files sometimes -- is this true?
	}
}