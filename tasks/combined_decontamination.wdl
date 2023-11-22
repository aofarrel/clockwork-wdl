version 1.0

# These tasks combine the rm_contam and map_reads steps into one WDL task.
# This can save money on some backends.

task clean_and_decontam_and_check {
	# This is similar to combined_decontamination_single but with the decontamination ref included
	# in the Docker image, and also includes fastp. The decision was made to make this one "mega
	# task" because "clockwork rm_contam" and "clockwork map_reads" were already combined, and
	# adding fastp is trival in terms of execution resources. This also makes it much easier to
	# toggle fastp filtering -- optional tasks in WDL workflows are much more difficult to deal
	# with than an optional few lines of bash script.
	input {
		
		Array[File] reads_files
		
		# subsampling options (happens first)
		Int         subsample_cutoff = -1
		Int         subsample_seed = 1965
		
		# fastp cleaning options (happens second)
		Int fastp_clean_avg_qual = 29
		Boolean fastp_clean_disable_adapter_trimming = false
		Boolean fastp_clean_detect_adapter_for_pe = true
		Boolean fastp_clean_before_decontam = true
		Boolean fastp_clean_after_decontam = false
		
		# decontamination options (happens third)
		Boolean     crash_on_timeout = false
		Int         timeout_map_reads = 120
		Int         timeout_decontam  = 120
		Boolean     unsorted_sam = false
		
		# post-decontamination QC options (happens forth)
		Boolean no_qc = false
		Int pre_decontam_min_q30 = 10
		Int post_decontam_min_q30 = 50

		# rename outs
		String? no_match_out_1
		String? no_match_out_2
		String? contam_out_1
		String? contam_out_2
		String? done_file

		# runtime attributes (applies to entire WDL task)
		Int addldisk = 100
		Int cpu = 8
		String docker_image = "ashedpotatoes/clockwork-plus:v0.11.3.9-full"
		Int max_retries = 0
		Int memory = 32
		Int preempt = 1
		Boolean ssd = true
	}

	parameter_meta {
		reads_files: "FASTQs to decontaminate"
		
		crash_on_timeout: "If true, fail entire pipeline if a task times out (see timeout_minutes)"
		docker_image: "Docker image with /ref/Ref.remove_contam.tar inside. Use default to use default CRyPTIC ref, or set to ashedpotatoes/clockwork-plus:v0.11.3.9-CDC for CDC varpipe ref"
		fastp_clean_avg_qual: "If one read's average quality score <avg_qual, then this read/pair is discarded. WDL default: 29. fastp default: 0 (no requirement)."
		fastp_clean_disable_adapter_trimming: "Disable adaptor trimming. WDL and fastp default: false"
		fastp_clean_detect_adapter_for_pe: "Enable auto-detection for adapter for PE data, not just SE data. WDL default: true. fastp default: false."
		subsample_cutoff: "If a FASTQ is larger than this size in megabytes, subsample 1,000,000 random reads and use that instead (-1 to disable)"
		subsample_seed: "Seed to use when subsampling (default: year UCSC was founded)"
		timeout_decontam: "If decontamination takes longer than this number of minutes, stop processing this sample"
		timeout_map_reads: "If read mapping takes longer than this number of minutes, stop processing this sample"
		unsorted_sam: "It's best to leave this as false"
	}

	# The Docker image has our reference information, so these can be hardcoded.
	String arg_metadata_tsv = "Ref.remove_contam/remove_contam_metadata.tsv"
	String arg_ref_fasta = "Ref.remove_contam/ref.fa"

	# We need to derive the sample name from our inputs because sample name is a
	# required input for clockwork map_reads. This needs to be to handle inputs
	# like sample+run+num (ERS457530_ERR551697_1.fastq) or inputs like
	# sample+num (ERS457530_1.fastq). In both cases, we want to convert to just
	# sample name (ERS457530). 
	#
	# We are doing this here, instead of within the command block, because our
	# output is optional (because that allows us to handle samples timing out
	# without breaking the entire pipeline). Optional WDL outputs do not work
	# correctly when you use glob()[0] because Cromwell doesn't realize an array
	# having nothing at index 0 is okay if that output is an optional file.
	# So, we instead need to know output filenames before the command block
	# executes.
	String read_file_basename = basename(reads_files[0]) # used to calculate sample name + outfile_sam
	String sample_name = sub(sub(read_file_basename, "_.*", ""), ".gz", "")
	String outfile_sam = sample_name + ".sam"
	
	# Hardcoded to make delocalization less of a pain
	String arg_counts_out = sample_name + ".decontam.counts.tsv"
	String arg_reads_out1 = sample_name + "_1.decontam.fq.gz"
	String arg_reads_out2 = sample_name + "_2.decontam.fq.gz"
	String clean_after_decontamination1 = sub(arg_reads_out1, "_1.decontam.fq.gz", ".decontam.clean_1.fq.gz")
	String clean_after_decontamination2 = sub(arg_reads_out2, "_2.decontam.fq.gz", ".decontam.clean_2.fq.gz")
	String final_fastq1 = if(fastp_clean_after_decontam) then clean_after_decontamination1 else arg_reads_out1
	String final_fastq2 = if(fastp_clean_after_decontam) then clean_after_decontamination2 else arg_reads_out2

	# This region handles optional arguments
	String arg_contam_out_1 = if(!defined(contam_out_1)) then "" else "--contam_out_1 ~{contam_out_1}"
	String arg_contam_out_2 = if(!defined(contam_out_1)) then "" else "--contam_out_2 ~{contam_out_2}"
	String arg_done_file = if(!defined(done_file)) then "" else "--done_file ~{done_file}"
	String arg_no_match_out_1 = if(!defined(no_match_out_1)) then "" else "--no_match_out_1 ~{no_match_out_1}"
	String arg_no_match_out_2 = if(!defined(no_match_out_2)) then "" else "--no_match_out_2 ~{no_match_out_2}"

	# Estimate disk size
	Int readsSize = 5*ceil(size(reads_files, "GB"))
	Int finalDiskSize = readsSize + addldisk
	String diskType = if((ssd)) then " SSD" else " HDD"

	command <<<
	# shellcheck disable=SC2002,SC2004
	# SC2002 results in less readable code and SC2004 detecting is iffy on WDL
	start_total=$SECONDS

	echo "----------------------------------------------"
	echo "(1) [bash] Ensure reads are paired correctly"
	echo "----------------------------------------------"
	# What it does: Makes an array to ensure _1 and _2 reads are in the right order.
	#
	# Rationale: clockwork map_reads seems to require each pair of fqs are consecutive, eg:
	#                    (SRR1_1.fq, SRR1_2.fq, SRR2_1.fq, SRR2_2.fq)
	# If you instead had (SRR1_1.fq, SRR2_1.fq, SRR1_2.fq, SRR2_2.fq) then fqcount would
	# fail assuming SRR1 and SRR2 have different read counts. This hack does not seem to be
	# needed if reads were piped in from an SRANWRP downloaload, but to support Terra data 
	# table input of reads this seems to be necessary.
	start_first=$SECONDS
	READS_FILES_UNSORTED=("~{sep='" "' reads_files}")
	readarray -t READS_FILES < <(for fq in "${READS_FILES_UNSORTED[@]}"; do echo "$fq"; done | sort)
	echo 'fqs as recieved:' "~{sep='" "' reads_files}"
	echo 'fqs after sorting:' 
	for fq in "${READS_FILES[@]}"; do echo "$fq"; done 
	timer_first=$(( SECONDS - start_first ))
	echo ${timer_first} > timer_1_process

	echo "----------------------------------------------"
	echo "(2) [fqtools/seqtk] Check size & maybe subsample"
	echo "---> subsample_cutoff: ~{subsample_cutoff} MB (-1 means never)"
	echo "----------------------------------------------"
	# What it does: Use fqtools count and du to see how big our fastqs are, and downsample
	# if above user-defined limit.
	#
	# Rationale: We don't necessarily want 500 GB of data when dealing with a bacterium.
	#
	# Dev note: Downsampling relies on deleting inputs and then putting a new file where the
	# input was. This works on Terra, but there is a chance this gets iffy elsewhere.
	# If you're having issues with miniwdl, --copy-input-files might help
	start_subsample=$SECONDS
	input_fq_reads=0
	for inputfq in "${READS_FILES[@]}"
	do
		size_inputfq=$(du -m "$inputfq" | cut -f1)
		reads_inputfq=$(fqtools count "$inputfq")
		input_fq_reads=$((input_fq_reads+reads_inputfq))
		if [[ "~{subsample_cutoff}" != "-1" ]]
		then
			echo "Subsampling..."
			if (( $size_inputfq > ~{subsample_cutoff} ))
			then
				seqtk sample -s~{subsample_seed} "$inputfq" 1000000 > temp.fq
				rm "$inputfq"
				mv temp.fq "$inputfq"
				echo "WARNING: downsampled $inputfq (was $size_inputfq MB, $reads_inputfq reads)"
			fi
		fi
	done
	if (( $input_fq_reads < 1000 ))
	then
		echo "WARNING: There seems to be less than a thousand input reads in total!"
	fi
	echo $(( SECONDS - start_subsample )) > timer_2_size
	
	echo "----------------------------------------------"
	echo "(3) [fastp] Check and maybe clean reads"
	echo "---> fastp_clean_before_decontam: ~{fastp_clean_before_decontam}"
	echo "----------------------------------------------"
	# What it does: Runs fastp
	#
	# Rationale: This cleans our input fastqs if fastp_clean_before_decontam
	#
	# TODO: Support multi-lane-multi-file fastq sets!!
	start_fastp_1=$SECONDS
	fastp --in1 "${READS_FILES[0]}" --in2 "${READS_FILES[1]}" \
		--out1 "~{sample_name}_cleaned_1.fq" --out2 "~{sample_name}_cleaned_2.fq" \
		--average_qual ~{fastp_clean_avg_qual} \
		~{true="--detect_adapter_for_pe" false="" fastp_clean_detect_adapter_for_pe} \
		~{true="--disable_adapter_trimming" false="" fastp_clean_disable_adapter_trimming} \
		--json "~{sample_name}_first_fastp.json"
	if [[ "~{fastp_clean_before_decontam}" = "true" ]]
	then		
		CLEANED_FQS=("~{sample_name}_cleaned_1.fq" "~{sample_name}_cleaned_2.fq")
		readarray -t MAP_THESE_FQS < <(for fq in "${CLEANED_FQS[@]}"; do echo "$fq"; done | sort)
	else
		# this is basically a repeat of step 1
		readarray -t MAP_THESE_FQS < <(for fq in "${READS_FILES_UNSORTED[@]}"; do echo "$fq"; done | sort)
	fi
	echo $(( SECONDS - start_fastp_1 )) > timer_3_clean

	echo "----------------------------------------------"
	echo "(4) [tar] Expand decontamination reference"
	echo "---> reference used: ~{docker_image}"
	echo "----------------------------------------------"
	# What it does: Untars and moves the decontamination reference
	#
	# Rationale: We need it to decontaminate!
	#
	# Dev note: Terra-Cromwell does not place you in the home dir, but rather one folder down, so we
	# go up one to get the ref genome. miniwdl goes further. So, we place the untarred directory in
	# the workdir rather than in-place for consistency's sake. If we are using the CDC (varpipe) 
	# decontamination reference, this also renames the output from "varpipe.Ref.remove_contam"
	start_untar=$SECONDS
	mkdir Ref.remove_contam
	tar -xvf /ref/Ref.remove_contam.tar -C Ref.remove_contam --strip-components 1
	echo $(( SECONDS - start_untar ))  > timer_4_untar

	echo "----------------------------------------------"
	echo "(5) [clockwork] Map FQs to decontam reference"
	echo "----------------------------------------------"
	# What it does: clockwork map_reads to decontamination ref
	start_map_reads=$SECONDS
	timeout -v ~{timeout_map_reads}m clockwork map_reads \
		~{true="--unsorted_sam" false="" unsorted_sam} \
		~{sample_name} \
		~{arg_ref_fasta} \
		~{outfile_sam} \
		"${MAP_THESE_FQS[@]}"
	exit=$?
	if [[ $exit = 124 ]]
	then
		echo "ERROR -- clockwork map_reads timed out"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "DECONTAMINATION_MAP_READS_TIMEOUT" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_MAP_READS_TIMEOUT" >> ERROR
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork map_reads was killed -- it may have run out of memory"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "DECONTAMINATION_MAP_READS_KILLED" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_MAP_READS_KILLED" >> ERROR
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully mapped to decontamination reference" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork map_reads errored out for unknown reasons"
		echo "DECONTAMINATION_MAP_READS_UNKNOWN_ERROR" >> ERROR # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork map_reads returned $exit for unknown reasons"
		echo "DECONTAMINATION_MAP_READS_UNKNOWN_ERROR" >> ERROR # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	fi
	echo $(( SECONDS - start_map_reads )) > timer_5_map_reads

	echo "----------------------------------------------"
	echo "(6) [samtools] Sort by read name"
	echo "----------------------------------------------"
	# What it does: samtools sort the sam file we just created by read name
	#
	# Rationale/Dev Notes: This seems to be required, although exactly why is it a bit unclear. 
	# samtools sort doesn't seem to be in the nextflow version of this pipeline, for instance:
	# https://github.com/iqbal-lab-org/clockwork/issues/77
	# https://github.com/iqbal-lab-org/clockwork/blob/v0.11.3/python/clockwork/contam_remover.py#L170
	#
	# This might intereact with unsorted_sam, which seems to actually be a dupe remover
	# https://github.com/iqbal-lab-org/clockwork/blob/v0.11.3/python/clockwork/tasks/map_reads.py#L18
	# https://github.com/iqbal-lab-org/clockwork/blob/v0.11.3/python/clockwork/read_map.py#L26
	start_samtools_sort=$SECONDS
	samtools sort -n ~{outfile_sam} > sorted_by_read_name_~{sample_name}.sam
	echo $(( SECONDS - start_samtools_sort )) > timer_6_sort

	echo "----------------------------------------------"
	echo "(7) [clockwork] Remove contamination"
	echo "----------------------------------------------"
	# What it does: clockwork remove_contam on the sam file we sorted
	# 
	# Dev notes: One of the subtasks will throw a warning about index files. Ignore it.
	# See: https://github.com/mhammell-laboratory/TEtranscripts/issues/99
	start_rm_contam=$SECONDS
	timeout -v ~{timeout_decontam}m clockwork remove_contam \
		~{arg_metadata_tsv} \
		sorted_by_read_name_~{sample_name}.sam \
		~{arg_counts_out} \
		~{arg_reads_out1} \
		~{arg_reads_out2} \
		~{arg_no_match_out_1} ~{arg_no_match_out_2} \
		~{arg_contam_out_1} ~{arg_contam_out_2} \
		~{arg_done_file}
	exit=$?
	if [[ $exit = 124 ]]
	then
		echo "ERROR -- clockwork remove_contam timed out"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "DECONTAMINATION_RM_CONTAM_TIMEOUT" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_RM_CONTAM_TIMEOUT" >> ERROR
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork remove_contam was killed -- it may have run out of memory"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "DECONTAMINATION_RM_CONTAM_KILLED" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_RM_CONTAM_KILLED" >> ERROR
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully decontaminated" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork remove_contam errored out for unknown reasons"
		echo "DECONTAMINATION_RM_CONTAM_UNKNOWN_ERROR" >> ERROR  # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork remove_contam returned $exit for unknown reasons"
		echo "DECONTAMINATION_RM_CONTAM_UNKNOWN_ERROR" >> ERROR  # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	fi
	echo $(( SECONDS - start_rm_contam )) > timer_7_rm_contam
	
	echo "----------------------------------------------"
	echo "(8) [fastp] Post-decontam QC check and/or clean"
	echo "----------------------------------------------"
	# What it does: Run fastp again, this time as a QC filter
	start_fastp_2=$SECONDS	
	fastp --in1 ~{arg_reads_out1} --in2 ~{arg_reads_out2} \
		--out1 ~{clean_after_decontamination1} --out2 ~{clean_after_decontamination2} \
		--average_qual ~{fastp_clean_avg_qual} \
		~{true="--detect_adapter_for_pe" false="" fastp_clean_detect_adapter_for_pe} \
		~{true="--disable_adapter_trimming" false="" fastp_clean_disable_adapter_trimming} \
		--json "~{sample_name}_second_fastp.json"
	if [[ "~{fastp_clean_after_decontam}" = "true" ]]
	then
		CLEANED_FQS=("~{sample_name}_cleaned_1.fq" "~{sample_name}_cleaned_2.fq")
		readarray -t MAP_THESE_FQS < <(for fq in "${CLEANED_FQS[@]}"; do echo "$fq"; done | sort)
	else
		# ignore 'em!
		pass
	fi
	fastp_clean_after_decontam
	
	
	echo $(( SECONDS - start_fastp_2 )) > timer_8_qc
	
	echo "----------------------------------------------"
	echo "(9) [python/bash] Parse reports"
	echo "----------------------------------------------"
	start_parse=$SECONDS
	python3 << CODE
	import os
	import json
	
	# first fastp
	with open("~{sample_name}_first_fastp.json", "r") as fastpJSON:
		fastp = json.load(fastpJSON)
	with open("~{sample_name}_first_fastp.txt", "w") as outfile:
		for keys, values in fastp["summary"]["before_filtering"].items():
			outfile.write(f"{keys}\t{values}\n")
		if "~{fastp_clean_before_decontam}" == "true":
			outfile.write("after fastp cleaned the fastqs:\n")
			for keys, values in fastp["summary"]["after_filtering"].items():
				outfile.write(f"{keys}\t{values}\n")
			with open("q20_cleaned.txt", "w") as q20_out: q20_out.write(str(fastp["summary"]["after_filtering"]["q20_rate"]))
			with open("q30_cleaned.txt", "w") as q30_out: q30_out.write(str(fastp["summary"]["after_filtering"]["q30_rate"]))
			with open("reads_cleaned.txt", "w") as reads_out: reads_out.write(str(fastp["summary"]["after_filtering"]["total_reads"]))
		else:
			outfile.write("fastp cleaning was skipped, so the above represent the final result of these fastqs (before decontaminating)")
	with open("q20_raw.txt", "w") as q20_in: q20_in.write(str(fastp["summary"]["before_filtering"]["q20_rate"]))
	with open("q30_raw.txt", "w") as q30_in: q30_in.write(str(fastp["summary"]["before_filtering"]["q30_rate"]))
	with open("total_reads_raw.txt", "w") as reads_in: reads_in.write(str(fastp["summary"]["before_filtering"]["total_reads"]))
	
	# second fastp
	with open("~{sample_name}_second_fastp.json", "r") as fastpJSON:
		fastp = json.load(fastpJSON)
	with open("~{sample_name}_second_fastp.txt", "w") as outfile:
		for keys, values in fastp["summary"]["before_filtering"].items():
			outfile.write(f"{keys}\t{values}\n")
	with open("q20_decontaminated.txt", "w") as q20_in: q20_in.write(str(fastp["summary"]["before_filtering"]["q20_rate"]))
	with open("q30_decontaminated.txt", "w") as q30_in: q30_in.write(str(fastp["summary"]["before_filtering"]["q30_rate"]))
	with open("reads_decontaminated.txt", "w") as reads_in: reads_in.write(str(fastp["summary"]["before_filtering"]["total_reads"])) 
	
	CODE
	
	# parse decontam.counts.tsv
	cat "~{arg_counts_out}" | head -2 | tail -1 | cut -f3 > reads_is_contam
	cat "~{arg_counts_out}" | head -3 | tail -1 | cut -f3 > reads_reference
	cat "~{arg_counts_out}" | head -4 | tail -1 | cut -f3 > reads_unmapped
	cat "~{arg_counts_out}" | head -5 | tail -1 | cut -f3 > reads_kept
	
	## TODO: add qc cutoffs here
	
	echo $(( SECONDS - start_parse )) > timer_9_parse
	
	timer_total=$(( SECONDS - start_total ))
	echo ${timer_total} > timer_total
	echo "Completed! 🎉"
	>>>

	runtime {
		bootDiskSizeGb: 20
		cpu: cpu
		docker: docker_image
		disks: "local-disk " + finalDiskSize + diskType
		maxRetries: max_retries
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		# the fastqs
		File? decontaminated_fastq_1 = final_fastq1
		File? decontaminated_fastq_2 = final_fastq2
		
		# other important things
		String sample = sample_name # needed by ThiagenTBProfiler
		
		# fastp stuff
		Float  raw_pct_above_q20  = read_float("q20_raw.txt")
		Float  raw_pct_above_q30  = read_float("q30_raw.txt")
		Int    raw_total_reads    = read_int("reads_raw.txt")
		Float  cleaned_pct_above_q20     = if fastp_clean_before_decontam then read_float("q20_cleaned.txt") else read_float("q20_raw.txt")
		Float  cleaned_pct_above_q30     = if fastp_clean_before_decontam then read_float("q30_cleaned.txt") else read_float("q30_raw.txt")
		Int    cleaned_total_reads       = if fastp_clean_before_decontam then read_int("reads_cleaned.txt") else read_int("reads_raw.txt")
		Float  dcntmd_pct_above_q20  = read_float("q20_decontaminated.txt")
		Float  dcntmd_pct_above_q30  = read_float("q30_decontaminated.txt")
		Int    dcntmd_total_reads    = read_int("reads_decontaminated.txt")
		Float pct_loss_cleaning = ((raw_total_reads - cleaned_total_reads) / raw_total_reads) * 100
		Float pct_loss_decon = ((cleaned_total_reads - dcntmd_total_reads) / cleaned_total_reads) * 100
		Float pct_loss_total = ((raw_total_reads - dcntmd_total_reads) / raw_total_reads) * 100
		
		# timers and debug information
		String errorcode = read_string("ERROR")
		Int timer_1_prep  = read_int("timer_1_process")
		Int timer_2_size  = read_int("timer_2_size")
		Int timer_3_clean = read_int("timer_3_clean")
		Int timer_4_untar = read_int("timer_4_untar")
		Int timer_5_mapFQ = read_int("timer_5_map_reads")
		Int timer_6_sort  = read_int("timer_6_sort")
		Int timer_7_dcnFQ = read_int("timer_7_rm_contam")
		Int timer_8_qchck = read_int("timer_8_qc")
		Int timer_9_parse = read_int("timer_9_parse")
		Int timer_total   = read_int("timer_total")
		String docker_used = docker_image
		Int reads_is_contam = read_int("reads_is_contam")
		Int reads_reference = read_int("reads_reference")
		Int reads_unmapped  = read_int("reads_unmapped")
		Int reads_clck_kept = read_int("reads_kept")
		File? counts_out_tsv = sample_name + ".decontam.counts.tsv"      # should match $arg_counts_out
		
		# you probably don't want these...
		#File? mapped_to_decontam = glob("*.sam")[0]
	}
	
}

task combined_decontamination_single_ref_included {
	# This is similar to combined_decontamination_single but with the decontamination ref included
	# in the Docker image. Note that the Docker image is a bit hefty.
	input {
		
		Array[File] reads_files

		# bonus options
		Boolean     crash_on_timeout = false
		Int         subsample_cutoff = -1
		Int         subsample_seed = 1965
		Int?        threads
		Int         timeout_map_reads = 120
		Int         timeout_decontam  = 120
		Boolean     unsorted_sam = false

		# rename outs
		String? no_match_out_1
		String? no_match_out_2
		String? contam_out_1
		String? contam_out_2
		String? done_file

		# runtime attributes
		Int addldisk = 100
		Int cpu = 8
		String docker_image = "ashedpotatoes/clockwork-plus:v0.11.3.2-full"
		Int max_retries = 0
		Int memory = 32
		Int preempt = 1
		Boolean ssd = true
	}

	parameter_meta {
		reads_files: "FASTQs to decontaminate"
		
		crash_on_timeout: "If true, fail entire pipeline if a task times out (see timeout_minutes)"
		docker_image: "Docker image with /ref/Ref.remove_contam.tar inside. Use default to use default CRyPTIC ref, or set to ashedpotatoes/clockwork-plus:v0.11.3.8-CDC for CDC varpipe ref"
		subsample_cutoff: "If a FASTQ is larger than this size in megabytes, subsample 1,000,000 random reads and use that instead (-1 to disable)"
		subsample_seed: "Seed to use when subsampling (default: year UCSC was founded)"
		threads: "Attempt to use these many threads when mapping reads"
		timeout_decontam: "If decontamination takes longer than this number of minutes, stop processing this sample"
		timeout_map_reads: "If read mapping takes longer than this number of minutes, stop processing this sample"
		unsorted_sam: "It's best to leave this as false"
	}
	# The Docker image has our reference information, so these can be hardcoded.
	String arg_metadata_tsv = "Ref.remove_contam/remove_contam_metadata.tsv"
	String arg_ref_fasta = "Ref.remove_contam/ref.fa"

	# We need to derive the sample name from our inputs because sample name is a
	# required input for clockwork map_reads. This needs to be to handle inputs
	# like sample+run+num (ERS457530_ERR551697_1.fastq) or inputs like
	# sample+num (ERS457530_1.fastq). In both cases, we want to convert to just
	# sample name (ERS457530). 
	#
	# We are doing this here, instead of within the command block, because our
	# output is optional (because that allows us to handle samples timing out
	# without breaking the entire pipeline). Optional WDL outputs do not work
	# correctly when you use glob()[0] because Cromwell doesn't realize an array
	# having nothing at index 0 is okay if that output is an optional file.
	# So, we instead need to know output filenames before the command block
	# executes.
	String read_file_basename = basename(reads_files[0]) # used to calculate sample name + outfile_sam
	String sample_name = sub(read_file_basename, "_.*", "")
	String outfile_sam = sample_name + ".sam"

	# This region handles optional arguments
	String arg_contam_out_1 = if(!defined(contam_out_1)) then "" else "--contam_out_1 ~{contam_out_1}"
	String arg_contam_out_2 = if(!defined(contam_out_1)) then "" else "--contam_out_2 ~{contam_out_2}"
	String arg_done_file = if(!defined(done_file)) then "" else "--done_file ~{done_file}"
	String arg_no_match_out_1 = if(!defined(no_match_out_1)) then "" else "--no_match_out_1 ~{no_match_out_1}"
	String arg_no_match_out_2 = if(!defined(no_match_out_2)) then "" else "--no_match_out_2 ~{no_match_out_2}"
	String arg_threads = if defined(threads) then "--threads ~{threads}" else ""
	String arg_unsorted_sam = if unsorted_sam == true then "--unsorted_sam" else ""

	# Estimate disk size
	Int readsSize = 5*ceil(size(reads_files, "GB"))
	Int finalDiskSize = readsSize + addldisk
	String diskType = if((ssd)) then " SSD" else " HDD"

	command <<<
	# shellcheck disable=SC2004
	# WDL parsers can get a little iffy with SC2004 so let's just. not.
	start_total=$SECONDS
	READS_FILES_UNSORTED=("~{sep='" "' reads_files}")

	# make sure reads are paired correctly
	#
	# clockwork map_reads seems to require each pair of fqs are consecutive, such as:
	# (SRR1_1.fq, SRR1_2.fq, SRR2_1.fq, SRR2_2.fq)
	# If you instead had (SRR1_1.fq, SRR2_1.fq, SRR1_2.fq, SRR2_2.fq) then fqcount would
	# fail assuming SRR1 and SRR2 have different read counts. Interestingly, this was
	# never an issue when downloading reads via SRANWRP, but to better support direct
	# input of reads, this sort of hack is necessary.
	readarray -t READS_FILES < <(for fq in "${READS_FILES_UNSORTED[@]}"; do echo "$fq"; done | sort)

	# downsample, if necessary
	#
	# Downsampling relies on deleting inputs and then putting a new file where the the old
	# input was. This works on Terra, but there is a chance this gets iffy elsewhere.
	# If you're having issues with miniwdl, --copy-input-files might help
	start_subsample=$SECONDS
	input_fq_reads=0
	for inputfq in "${READS_FILES[@]}"
	do
		size_inputfq=$(du -m "$inputfq" | cut -f1)
		reads_inputfq=$(fqtools count "$inputfq")
		input_fq_reads=$((input_fq_reads+reads_inputfq))
		if [[ "~{subsample_cutoff}" != "-1" ]]
		then
			echo "Subsampling..."
			if (( $size_inputfq > ~{subsample_cutoff} ))
			then
				seqtk sample -s~{subsample_seed} "$inputfq" 1000000 > temp.fq
				rm "$inputfq"
				mv temp.fq "$inputfq"
				echo "WARNING: downsampled $inputfq (was $size_inputfq MB, $reads_inputfq reads)"
			fi
		fi
	done
	if (( $input_fq_reads < 1000 ))
	then
		echo "WARNING: There seems to be less than a thousand input reads in total!"
	fi
	timer_subsample=$(( SECONDS - start_subsample ))
	echo ${timer_subsample} > timer_subsample

	# Terra-Cromwell does not place you in the home dir, but rather one folder down, so we have
	# to go up one to get the ref genome. miniwdl goes further. Who knows what other executors do.
	# The tar command will however place the untarred directory in the workdir.
	# If we are using the CDC (varpipe) version, this also prevents it from untaring to a folder
	# named "varpipe.Ref.remove_contam"
	start_untar=$SECONDS
	echo "Expanding decontamination reference..."
	mkdir Ref.remove_contam
	tar -xvf /ref/Ref.remove_contam.tar -C Ref.remove_contam --strip-components 1
	timer_untar=$(( SECONDS - start_untar ))
	echo ${timer_untar} > timer_untar

	# anticipate bad fastqs
	#
	# This is a hack to make sure the check_this_fastq task output is defined iff this
	# WDL task fails. The duplicate will be deleted if we decontam successfully. We use
	# copies of the inputs WDL gets iffy when trying to glob on optionals, and because
	# deleting inputs is wonky on some backends (understandably!)
	echo "Preparing for bad fastqs..."
	for inputfq in "${READS_FILES[@]}"
	do
		cp "$inputfq" "~{read_file_basename}_dcntmfail.fastq"
	done

	# map reads for decontamination
	echo "Mapping reads..."
	start_map_reads=$SECONDS
	timeout -v ~{timeout_map_reads}m clockwork map_reads \
		~{arg_unsorted_sam} \
		~{arg_threads} \
		~{sample_name} \
		~{arg_ref_fasta} \
		~{outfile_sam} \
		"${READS_FILES[@]}"
	exit=$?
	if [[ $exit = 124 ]]
	then
		echo "ERROR -- clockwork map_reads timed out"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "DECONTAMINATION_MAP_READS_TIMEOUT" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_MAP_READS_TIMEOUT" >> ERROR
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork map_reads was killed -- it may have run out of memory"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "DECONTAMINATION_MAP_READS_KILLED" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_MAP_READS_KILLED" >> ERROR
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully mapped to decontamination reference" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork map_reads errored out for unknown reasons"
		echo "DECONTAMINATION_MAP_READS_UNKNOWN_ERROR" >> ERROR # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork map_reads returned $exit for unknown reasons"
		echo "DECONTAMINATION_MAP_READS_UNKNOWN_ERROR" >> ERROR # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	fi
	timer_map_reads=$(( SECONDS - start_map_reads ))
	echo ${timer_map_reads} > timer_map_reads

	arg_counts_out="~{sample_name}.decontam.counts.tsv"
	arg_reads_out1="~{sample_name}_1.decontam.fq.gz"
	arg_reads_out2="~{sample_name}_2.decontam.fq.gz"

	# handle samtools sort
	#
	# TODO: samtools sort doesn't seem to be in the nextflow version of this pipeline, but it seems
	# we need it in the WDL version?
	# https://github.com/iqbal-lab-org/clockwork/issues/77
	# https://github.com/iqbal-lab-org/clockwork/blob/v0.11.3/python/clockwork/contam_remover.py#L170
	#
	# This might intereact with unsorted_sam, which seems to actually be a dupe remover
	# https://github.com/iqbal-lab-org/clockwork/blob/v0.11.3/python/clockwork/tasks/map_reads.py#L18
	# https://github.com/iqbal-lab-org/clockwork/blob/v0.11.3/python/clockwork/read_map.py#L26
	start_samtools_sort=$SECONDS
	echo "Sorting by read name..."
	samtools sort -n ~{outfile_sam} > sorted_by_read_name_~{sample_name}.sam
	timer_samtools_sort=$(( SECONDS - start_samtools_sort ))
	echo ${timer_samtools_sort} > timer_samtools_sort

	start_rm_contam=$SECONDS
	echo "Removing contamination..."
	# One of remove_contam's tasks will throw a warning about index files. Ignore it.
	# https://github.com/mhammell-laboratory/TEtranscripts/issues/99
	timeout -v ~{timeout_decontam}m clockwork remove_contam \
		~{arg_metadata_tsv} \
		sorted_by_read_name_~{sample_name}.sam \
		$arg_counts_out \
		$arg_reads_out1 \
		$arg_reads_out2 \
		~{arg_no_match_out_1} ~{arg_no_match_out_2} \
		~{arg_contam_out_1} ~{arg_contam_out_2} \
		~{arg_done_file}
	exit=$?
	if [[ $exit = 124 ]]
	then
		echo "ERROR -- clockwork remove_contam timed out"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "DECONTAMINATION_RM_CONTAM_TIMEOUT" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_RM_CONTAM_TIMEOUT" >> ERROR
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork remove_contam was killed -- it may have run out of memory"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			echo "DECONTAMINATION_RM_CONTAM_KILLED" >> ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_RM_CONTAM_KILLED" >> ERROR
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully decontaminated" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork remove_contam errored out for unknown reasons"
		echo "DECONTAMINATION_RM_CONTAM_UNKNOWN_ERROR" >> ERROR  # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork remove_contam returned $exit for unknown reasons"
		echo "DECONTAMINATION_RM_CONTAM_UNKNOWN_ERROR" >> ERROR  # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	fi
	timer_rm_contam=$(( SECONDS - start_rm_contam ))
	echo ${timer_rm_contam} > timer_rm_contam

	# if we got here, then we passed, so delete the output that would signal to run fastqc
	rm "~{read_file_basename}_dcntmfail.fastq"
	echo "PASS" >> ERROR
	
	# parse decontam.counts.tsv
	cat $arg_counts_out | head -2 | tail -1 | cut -f3 > reads_is_contam
	cat $arg_counts_out | head -3 | tail -1 | cut -f3 > reads_reference
	cat $arg_counts_out | head -4 | tail -1 | cut -f3 > reads_unmapped
	cat $arg_counts_out | head -5 | tail -1 | cut -f3 > reads_kept
	
	timer_total=$(( SECONDS - start_total ))
	echo ${timer_total} > timer_total

	echo "Decontamination completed."
	ls -lha
	>>>

	runtime {
		bootDiskSizeGb: 20
		cpu: cpu
		docker: docker_image
		disks: "local-disk " + finalDiskSize + diskType
		maxRetries: max_retries
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		File? counts_out_tsv = sample_name + ".decontam.counts.tsv"
		File? decontaminated_fastq_1 = sample_name + "_1.decontam.fq.gz"
		File? decontaminated_fastq_2 = sample_name + "_2.decontam.fq.gz"
		File? check_this_fastq = read_file_basename + "_dcntmfail.fastq"
		String errorcode = read_string("ERROR")
		
		# timers and debug information
		Int timer_map_reads = read_int("timer_map_reads")
		Int timer_rm_contam = read_int("timer_rm_contam")
		Int timer_total = read_int("timer_total")
		String docker_used = docker_image
		Int reads_is_contam = read_int("reads_is_contam")
		Int reads_reference = read_int("reads_reference")
		Int reads_unmapped = read_int("reads_unmapped")
		Int reads_kept = read_int("reads_kept")
		
		# you probably don't want these...
		#File? mapped_to_decontam = glob("*.sam")[0]
		#Int timer_sort = read_int("timer_samtools_sort")
		#Int seconds_to_untar = read_int("timer_untar")
	}
	
}

task combined_decontamination_single {
	# This is the task you probably should be using. It works on one sample.
	# If you're working on multiple samples, scatter upon this task.
	input {

		# the important stuff
		File        tarball_ref_fasta_and_index
		String      ref_fasta_filename
		Array[File] reads_files
		String      filename_metadata_tsv = "remove_contam_metadata.tsv"

		# bonus options
		Boolean     crash_on_timeout = false
		Int         subsample_cutoff = -1
		Int         subsample_seed = 1965
		Int?        threads
		Int         timeout_map_reads = 120
		Int         timeout_decontam  = 120
		Boolean     unsorted_sam = false
		Boolean     verbose = true

		# rename outs
		String? counts_out     # must end in counts.tsv
		String? no_match_out_1
		String? no_match_out_2
		String? contam_out_1
		String? contam_out_2
		String? done_file

		# runtime attributes
		Int addldisk = 100
		Int cpu = 8
		Int memory = 16
		Int preempt = 1
		Boolean ssd = true
	}

	parameter_meta {
		tarball_ref_fasta_and_index: "Tarball of decontamination ref and its index"
		ref_fasta_filename: "Name of the decontamination ref within tarball_ref_fasta_and_index"
		reads_files: "FASTQs to decontaminate"
		filename_metadata_tsv: "Name of the metadata tsv within tarball_ref_fasta_and_index"
		
		crash_on_timeout: "If true, fail entire pipeline if a task times out (see timeout_minutes)"
		subsample_cutoff: "If a FASTQ is larger than this size in megabytes, subsample 1,000,000 random reads and use that instead (-1 to disable)"
		subsample_seed: "Seed to use when subsampling (default: year UCSC was founded)"
		threads: "Attempt to use these many threads when mapping reads"
		timeout_decontam: "If decontamination takes longer than this number of minutes, stop processing this sample"
		timeout_map_reads: "If read mapping takes longer than this number of minutes, stop processing this sample"
		unsorted_sam: "It's best to leave this as false"
		verbose: "Increase amount of stuff sent to stdout"
	}
	# We need to derive the sample name from our inputs because sample name is a
	# required input for clockwork map_reads. This needs to be to handle inputs
	# like sample+run+num (ERS457530_ERR551697_1.fastq) or inputs like
	# sample+num (ERS457530_1.fastq). In both cases, we want to convert to just
	# sample name (ERS457530). 
	#
	# We are doing this here, instead of within the command block, because our
	# output is optional (because that allows us to handle samples timing out
	# without breaking the entire pipeline). Optional WDL outputs do not work
	# correctly when you use glob()[0] because Cromwell doesn't realize an array
	# having nothing at index 0 is okay if that output is an optional file.
	# So, we instead need to know output filenames before the command block
	# executes.
	String read_file_basename = basename(reads_files[0]) # used to calculate sample name + outfile_sam
	String sample_name = sub(read_file_basename, "_.*", "")
	String outfile_sam = sample_name + ".sam"

	# This region handles the metadata TSV and ref fasta within in the tarball
	String basename_tsv = sub(basename(tarball_ref_fasta_and_index), "\.tar(?!.{5,})", "")
	String arg_metadata_tsv = "~{basename_tsv}/~{filename_metadata_tsv}"
	String basestem_reference = sub(basename(tarball_ref_fasta_and_index), "\.tar(?!.{5,})", "")
	String arg_ref_fasta = "~{basestem_reference}/~{ref_fasta_filename}"

	# This region handles optional arguments
	String arg_contam_out_1 = if(!defined(contam_out_1)) then "" else "--contam_out_1 ~{contam_out_1}"
	String arg_contam_out_2 = if(!defined(contam_out_1)) then "" else "--contam_out_2 ~{contam_out_2}"
	String arg_done_file = if(!defined(done_file)) then "" else "--done_file ~{done_file}"
	String arg_no_match_out_1 = if(!defined(no_match_out_1)) then "" else "--no_match_out_1 ~{no_match_out_1}"
	String arg_no_match_out_2 = if(!defined(no_match_out_2)) then "" else "--no_match_out_2 ~{no_match_out_2}"
	String arg_threads = if defined(threads) then "--threads ~{threads}" else ""
	String arg_unsorted_sam = if unsorted_sam == true then "--unsorted_sam" else ""

	# Estimate disk size
	Int refSize = 2*ceil(size(tarball_ref_fasta_and_index, "GB"))
	Int readsSize = 5*ceil(size(reads_files, "GB"))
	Int finalDiskSize = refSize + readsSize + addldisk
	String diskType = if((ssd)) then " SSD" else " HDD"

	command <<<
	READS_FILES_UNSORTED=("~{sep='" "' reads_files}")

	# make sure reads are paired correctly
	#
	# clockwork map_reads seems to require each pair of fqs are consecutive, such as:
	# (SRR1_1.fq, SRR1_2.fq, SRR2_1.fq, SRR2_2.fq)
	# If you instead had (SRR1_1.fq, SRR2_1.fq, SRR1_2.fq, SRR2_2.fq) then fqcount would
	# fail assuming SRR1 and SRR2 have different read counts. Interestingly, this was
	# never an issue when downloading reads via SRANWRP, but to better support direct
	# input of reads, this sort of hack is necessary.
	readarray -t READS_FILES < <(for fq in "${READS_FILES_UNSORTED[@]}"; do echo "$fq"; done | sort)

	# downsample, if necessary
	#
	# Downsampling relies on deleting inputs and then putting a new file where the the old
	# input was. This works on Terra, but there is a chance this gets iffy elsewhere.
	# If you're having issues with miniwdl, --copy-input-files might help
	if [[ "~{subsample_cutoff}" != "-1" ]]
	then
		for inputfq in "${READS_FILES[@]}"
		do
			size_inputfq=$(du -m "$inputfq" | cut -f1)
			# shellcheck disable=SC2004
			# just trust me on this one
			if (( $size_inputfq > ~{subsample_cutoff} ))
			then
				seqtk sample -s~{subsample_seed} "$inputfq" 1000000 > temp.fq
				rm "$inputfq"
				mv temp.fq "$inputfq"
				echo "WARNING: downsampled $inputfq (was $size_inputfq MB)"
			fi
		done
	fi
	
	# we need to mv ref to the workdir, then untar, or else the ref index won't be found
	mv ~{tarball_ref_fasta_and_index} .
	tar -xvf ~{basestem_reference}.tar

	# anticipate bad fastqs
	#
	# This is a hack to make sure the check_this_fastq task output is defined iff this
	# WDL task fails. The duplicate will be deleted if we decontam successfully. We use
	# copies of the inputs WDL gets iffy when trying to glob on optionals, and because
	# deleting inputs is wonky on some backends (understandably!)
	for inputfq in "${READS_FILES[@]}"
	do
		cp "$inputfq" "~{read_file_basename}_dcntmfail.fastq"
	done

	# some debug stuff
	if [[ ! "~{verbose}" = "true" ]]
	then
		echo "tarball_ref_fasta_and_index" ~{tarball_ref_fasta_and_index}
		echo "ref_fasta_filename" ~{ref_fasta_filename}
		echo "basestem_reference" ~{basestem_reference}
		echo "sample_name ~{sample_name}"
		echo "outfile_sam ~{outfile_sam}"
		echo "arg_ref_fasta" ~{arg_ref_fasta}
		echo "READS_FILES_UNSORTED" "${READS_FILES_UNSORTED[@]}"
		echo "READS_FILES" "${READS_FILES[@]}"

	fi

	# map reads for decontamination
	timeout -v ~{timeout_map_reads}m clockwork map_reads \
		~{arg_unsorted_sam} \
		~{arg_threads} \
		~{sample_name} \
		~{arg_ref_fasta} \
		~{outfile_sam} \
		"${READS_FILES[@]}"
	exit=$?
	if [[ $exit = 124 ]]
	then
		echo "ERROR -- clockwork map_reads timed out"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork map_reads was killed -- it may have run out of memory"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully mapped to decontamination reference" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork map_reads errored out for unknown reasons"
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork map_reads returned $exit for unknown reasons"
		set -eux -o pipefail
		exit 1
	fi
	
	echo "************ removing contamination *****************"

	# calculate the last three positional arguments of the rm_contam task
	if [[ ! "~{counts_out}" = "" ]]
	then
		arg_counts_out="~{counts_out}"
	else
		arg_counts_out="~{sample_name}.decontam.counts.tsv"
	fi

	arg_reads_out1="~{sample_name}_1.decontam.fq.gz"
	arg_reads_out2="~{sample_name}_2.decontam.fq.gz"

	# TODO: this doesn't seem to be in the nextflow version of this pipeline, but it seems
	# we need it in the WDL version?
	# https://github.com/iqbal-lab-org/clockwork/issues/77
	# https://github.com/iqbal-lab-org/clockwork/blob/v0.11.3/python/clockwork/contam_remover.py#L170
	#
	# This might intereact with unsorted_sam, which seems to actually be a dupe remover
	# https://github.com/iqbal-lab-org/clockwork/blob/v0.11.3/python/clockwork/tasks/map_reads.py#L18
	# https://github.com/iqbal-lab-org/clockwork/blob/v0.11.3/python/clockwork/read_map.py#L26
	
	samtools sort -n ~{outfile_sam} > sorted_by_read_name_~{sample_name}.sam

	# One of remove_contam's tasks will throw a warning about index files. Ignore it.
	# https://github.com/mhammell-laboratory/TEtranscripts/issues/99
	timeout -v ~{timeout_decontam}m clockwork remove_contam \
		~{arg_metadata_tsv} \
		sorted_by_read_name_~{sample_name}.sam \
		$arg_counts_out \
		$arg_reads_out1 \
		$arg_reads_out2 \
		~{arg_no_match_out_1} ~{arg_no_match_out_2} \
		~{arg_contam_out_1} ~{arg_contam_out_2} \
		~{arg_done_file}
	exit=$?
	if [[ $exit = 124 ]]
	then
		echo "ERROR -- clockwork remove_contam timed out"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork remove_contam was killed -- it may have run out of memory"
		if [[ "~{crash_on_timeout}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully decontaminated" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork remove_contam errored out for unknown reasons"
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork remove_contam returned $exit for unknown reasons"
		set -eux -o pipefail
		exit 1
	fi

	# We passed, so delete the output that would signal to run fastqc
	rm "~{read_file_basename}_dcntmfail.fastq"

	echo "Decontamination completed."

	if [[ ! "~{verbose}" = "true" ]]
	then
		ls -lha
	fi
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:v0.11.3"
		disks: "local-disk " + finalDiskSize + diskType
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		#File? mapped_to_decontam = glob("*.sam")[0]
		File? counts_out_tsv = sample_name + ".decontam.counts.tsv"
		File? decontaminated_fastq_1 = sample_name + "_1.decontam.fq.gz"
		File? decontaminated_fastq_2 = sample_name + "_2.decontam.fq.gz"
		File? check_this_fastq = read_file_basename + "_dcntmfail.fastq"
	}
}

task combined_decontamination_multiple {
	# This task should be considered deprecated. It's usually more expensive than 
	# decontaminating via a scattered task and it's more complicated. It also doesn't
	# support downsampling, nor timing out.
	input {
		File        tarball_ref_fasta_and_index
		String      ref_fasta_filename
		Array[File] tarballs_of_read_files # each tarball is one set of reads files
		Boolean     unsorted_sam = false
		Int?        threads

		String filename_metadata_tsv = "remove_contam_metadata.tsv"

		# dashes are forbidden in the filenames you choose
		String? counts_out # MUST end in counts.tsv
		String? no_match_out_1
		String? no_match_out_2
		String? contam_out_1
		String? contam_out_2
		String? done_file

		Boolean verbose = true

		# runtime attributes
		Int addldisk = 100
		Int cpu = 16
		Int memory = 32
		Int preempt = 0
	}

	# calculate stuff for the map_reads call
	String basestem_reference = sub(basename(tarball_ref_fasta_and_index), "\.tar(?!.{5,})", "")  # TODO: double check the regex
	String arg_unsorted_sam = if unsorted_sam == true then "--unsorted_sam" else ""
	String arg_ref_fasta = "~{basestem_reference}/~{ref_fasta_filename}"
	String arg_threads = if defined(threads) then "--threads ~{threads}" else ""

	# the metadata TSV will be zipped in tarball_ref_fasta_and_index
	String basename_tsv = sub(basename(tarball_ref_fasta_and_index), "\.tar(?!.{5,})", "")
	String arg_metadata_tsv = "~{basename_tsv}/~{filename_metadata_tsv}"
	
	# calculate the optional inputs for remove contam
	String arg_no_match_out_1 = if(!defined(no_match_out_1)) then "" else "--no_match_out_1 ~{no_match_out_1}"
	String arg_no_match_out_2 = if(!defined(no_match_out_2)) then "" else "--no_match_out_2 ~{no_match_out_2}"
	String arg_contam_out_1 = if(!defined(contam_out_1)) then "" else "--contam_out_1 ~{contam_out_1}"
	String arg_contam_out_2 = if(!defined(contam_out_1)) then "" else "--contam_out_2 ~{contam_out_2}"
	String arg_done_file = if(!defined(done_file)) then "" else "--done_file ~{done_file}"

	# estimate disk size
	Int refSize = 2*ceil(size(tarball_ref_fasta_and_index, "GB"))
	Int readsSize = 5*ceil(size(tarballs_of_read_files, "GB"))
	Int finalDiskSize = refSize + readsSize + addldisk

	command <<<
	set -eux -o pipefail

	if [[ ! "~{verbose}" = "true" ]]
	then
		echo "tarball_ref_fasta_and_index" ~{tarball_ref_fasta_and_index}
		echo "ref_fasta_filename" ~{ref_fasta_filename}
		echo "basestem_reference" ~{basestem_reference}
		echo "arg_ref_fasta" ~{arg_ref_fasta}
	fi
	
	mv ~{tarball_ref_fasta_and_index} .
	tar -xvf ~{basestem_reference}.tar

	# check for duplicates, part 1
	# We could use uniq -u to create an allowlist of acceptable
	# samples, but we still have to deal with tarballs in input
	# directories.
	echo "Listing out samples..."
	touch list_of_samples.txt
	for BALL in ~{sep=' ' tarballs_of_read_files}
	do
		basename_ball=$(basename $BALL .tar)
		sample_name="${basename_ball%%_*}"
		printf "%s\n" "$sample_name" >> list_of_samples.txt
	done
	sort list_of_samples.txt | uniq -d >> dupe_samples.txt

	echo "Now iterating..."
	for BALL in ~{sep=' ' tarballs_of_read_files}
	do

		# check for duplicates, part 2
		# TODO: This will cause a duplicated sample to always get skipped, ie, it won't even
		# get a first time. Ideally we still want to deal with once (and only once)
		basename_ball=$(basename $BALL .tar)
		sample_name="${basename_ball%%_*}"
		if grep -q "$sample_name" dupe_samples.txt
		then
			# skip this sample, go onto the next
			echo "$sample_name appears to be a duplicate and will be skipped."
			continue
		fi

		# mv read files into workdir and untar them
		mv $BALL .
		tar -xvf "$basename_ball.tar"

		# the docker image uses bash v5 so we can use readarray to make an array easily
		declare -a read_files
		readarray -t read_files < <(find ./*.fastq)

		# map the reads
		outfile_sam="$sample_name.sam"
		clockwork map_reads "~{arg_unsorted_sam}" ~{arg_threads} "$sample_name" ~{arg_ref_fasta} "$outfile_sam" "${read_files[@]}"
		echo "Mapped $sample_name to decontamination reference."

		if [[ "~{verbose}" = "true" ]]
		then
			ls -lhaR
		fi

		# calculate the last three positional arguments of the rm_contam task
		if [[ ! "~{counts_out}" = "" ]]
		then
			arg_counts_out="~{counts_out}"
		else
			arg_counts_out="$sample_name.decontam.counts.tsv"
		fi
		arg_reads_out1="$sample_name.decontam_1.fq.gz"
		arg_reads_out2="$sample_name.decontam_2.fq.gz"

		# https://github.com/iqbal-lab-org/clockwork/issues/77
		samtools sort -n "$outfile_sam" > "sorted_by_read_name_$sample_name.sam"

		# r/e the index file warning: https://github.com/mhammell-laboratory/TEtranscripts/issues/99
		clockwork remove_contam \
			~{arg_metadata_tsv} \
			"sorted_by_read_name_$sample_name.sam" \
			"$arg_counts_out" \
			"$arg_reads_out1" \
			"$arg_reads_out2" \
			~{arg_no_match_out_1} ~{arg_no_match_out_2} ~{arg_contam_out_1} ~{arg_contam_out_2} ~{arg_done_file}

		# tar outputs because Cromwell still can't handle nested arrays nor structs properly
		mkdir "$sample_name"
		#mv "*.sam" /$sample_name
		#mv "*counts.tsv" /$sample_name
		mv "$arg_reads_out1" "./$sample_name"
		mv "$arg_reads_out2" "./$sample_name"
		tar -cf "$sample_name.tar" "$sample_name"
		rm -rf "./${sample_name:?}"
		rm "${read_files[@]}" # if this isn't done, the next iteration will grab the wrong reads
		echo "Decontaminated $sample_name successfully."
	done
	rm ~{basestem_reference}.tar

	echo "Decontamination completed."
	if [[ "~{verbose}" = "true" ]]
	then
		ls -lhaR
	fi
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:v0.11.3"
		disks: "local-disk " + finalDiskSize + " SSD"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		Array[File] tarballs_of_decontaminated_reads = glob("*.tar")

		# to save space, these "debug" outs aren't included in the per sample tarballs
		Array[File] mapped_to_decontam = glob("*.sam")
		Array[File] counts = glob("*.counts.tsv")
		File? duplicated_input_files = "dupe_files.txt"
		File? duplicated_input_samples = "dupe_samples.txt"
	}
}