version 1.0

# These tasks are all-in-one decontamination tasks.
#
# clean_and_decontam_and_check [recommended]
#   * single sample
#   * includes decontamination reference in the Docker
#   * runs fastp for QC and read cleaning
#   * extremely verbose stdout for debugging
#   * has the most QC options
#   * supports timing out guardrail
#   * supports downsampling
#
# combined_decontamination_single_ref_included [legacy]
#   * single sample
#   * includes decontamination refernce in the Docker
#   * does not run fastp but does run trimmomatic
#   * supports timing out guardrail
#   * supports downsampling
#
# combined_decontamination_single [legacy]
#   * single sample
#   * must provide your own decontamination reference
#   * does not fastp but does run trimmomatic
#   * supports timing out guardrail
#   * supports downsampling
#
# combined_decontamination_multiple [deprecated/experimental]
#  An experimental version used to test if it was better
#  to scatter combined_decontamination_single to handle
#  multiple samples, or handle them all at once.
#
#

task clean_and_decontam_and_check {
	# This is similar to combined_decontamination_single but with the decontamination ref included
	# in the Docker image, and also includes fastp. The decision was made to make this one "mega
	# task" because "clockwork rm_contam" and "clockwork map_reads" were already combined, and
	# adding fastp is trival in terms of execution resources. This also makes it much easier to
	# toggle fastp filtering -- optional tasks in WDL workflows are much more difficult to deal
	# with than an optional few lines of bash script.
	input {
		
		Array[File] reads_files
		
		# guardrails, to prevent this task from taking forever
		Float      preliminary_min_q30 = 0.2   # 20%
		Int        subsample_cutoff = -1
		Int        subsample_seed = 1965
		Int        subsample_to_this_many_reads = 1000000
		Int        minimum_number_of_passing_reads = 20000
		
		# fastp cleaning options
		Int fastp_clean_avg_qual = 29
		Boolean fastp_clean_disable_adapter_trimming = false
		Boolean fastp_clean_detect_adapter_for_pe = true
		Boolean fastp_clean_before_decontam = true
		Boolean fastp_clean_after_decontam = false
		
		# decontamination options
		Boolean     crash_loudly = false
		Int         timeout_map_reads = 120
		Int         timeout_decontam  = 120
		Boolean     unsorted_sam = false
		
		# fastp QC cleaning options
		Boolean soft_qc = true
		Float QC_min_q30 = 0.5  # 50%

		# rename outs
		String? force_rename_out
		String? no_match_out_1
		String? no_match_out_2
		String? contam_out_1
		String? contam_out_2
		String? done_file

		# runtime attributes (applies to entire WDL task)
		Int addldisk = 100
		Int cpu = 8
		String docker_image = "ashedpotatoes/clockwork-plus:v0.12.5.1-CRyPTIC"
		Int max_retries = 0
		Int memory = 32
		Int preempt = 1
		Boolean ssd = true
	}

	parameter_meta {
		reads_files: "FASTQs to decontaminate"
		
		crash_loudly: "If true, force a WDL task failure if handled error (failed QC, timeout, etc). If false, handled errors will return 0 but give no fastq output."
		docker_image: "Docker image with /ref/Ref.remove_contam.tar inside. Use default to use default CRyPTIC ref, or set to ashedpotatoes/clockwork-plus:v0.12.5.2-CDC for CDC varpipe ref"
		fastp_clean_avg_qual: "If one read's average quality score <avg_qual, then this read/pair is discarded. WDL default: 29. fastp default: 0 (no requirement)."
		fastp_clean_disable_adapter_trimming: "Disable adaptor trimming. WDL and fastp default: false"
		fastp_clean_detect_adapter_for_pe: "Enable auto-detection for adapter for PE data, not just SE data. WDL default: true. fastp default: false."
		subsample_cutoff: "If a FASTQ is larger than this size in megabytes, subsample subsample_to_this_many_reads random reads and use that instead (-1 to disable)"
		subsample_to_this_many_reads: "This is the number of reads to subsample down to (default: 1,000,000)"
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
	String sample_name = sub(sub(sub(read_file_basename, "_.*", ""), ".gz", ""), ".tar", "")
	String outfile_sam = sample_name + ".sam"
	
	# Hardcoded to make delocalization less of a pain
	String arg_counts_out = if(defined(force_rename_out)) then select_first([force_rename_out, sample_name]) + ".decontam.counts.tsv" else sample_name + ".decontam.counts.tsv"
	String arg_reads_out1 = sample_name + "_1.decontam.fq.gz"
	String arg_reads_out2 = sample_name + "_2.decontam.fq.gz"
	String reads_cleaned_1 = sub(arg_reads_out1, ".fq.gz", ".clean.fq.gz")
	String reads_cleaned_2 = sub(arg_reads_out2, ".fq.gz", ".clean.fq.gz")
	String usual_final_fastq1 = if(fastp_clean_after_decontam) then reads_cleaned_1 else arg_reads_out1
	String usual_final_fastq2 = if(fastp_clean_after_decontam) then reads_cleaned_2 else arg_reads_out2
	String final_fastq1 = if(defined(force_rename_out)) then select_first([force_rename_out, arg_reads_out1]) + "_1.fq.gz" else usual_final_fastq1
	String final_fastq2 = if(defined(force_rename_out)) then select_first([force_rename_out, arg_reads_out2]) + "_2.fq.gz" else usual_final_fastq2

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
	
	# ----------------------------------------------
	# (0) [bash] Create fallback "output" files
	# ----------------------------------------------
	# What it does: Makes a bunch of fallback files which will later be overwritten
	# with actual data should this sample not be filtered out.
	#
	# Rationale: Terra-Cromwell outputs cannot rely on other outputs, so we have no
	# way of saying "don't try to read_int() this nonexistent file." Making the Int
	# an optional Int? does not work as the rest of the TB pipeline expects Ints,
	# even though those values will not even be called should a sample fail decontam.
	FALLBACK_FILES=( q20_raw.txt q30_raw.txt reads_raw.txt )
	FALLBACK_FILES+=( q20_cleaned.txt q30_cleaned.txt reads_cleaned.txt q20_decontaminated.txt q30_decontaminated.txt reads_decontaminated.txt )
	FALLBACK_FILES+=( timer_1_process timer_2_size timer_3_clean timer_4_untar timer_5_map_reads timer_6_sort timer_7_rm_contam timer_8_qc timer_9_parse timer_total )
	FALLBACK_FILES+=( ERROR reads_is_contam reads_reference reads_unmapped reads_kept )
	FALLBACK_FILES+=( pct_loss_total.txt pct_loss_decon.txt pct_loss_cleaning.txt )
	for fallback_file in "${FALLBACK_FILES[@]}"
	do
		echo -1 > "$fallback_file"
	done
	# TODO: force pct_loss_* to be negative

	echo "----------------------------------------------"
	echo "(0.5) [tar] Expand decontamination reference"
	echo "---> reference used: ~{docker_image}"
	echo "----------------------------------------------"
	# What it does: Untars and moves the decontamination reference
	#
	# Rationale: We need it to decontaminate! Also, this needs to be done before trying to
	# untar any of the read files.
	#
	# Dev note: Terra-Cromwell does not place you in the home dir, but rather one folder down, so we
	# go up one to get the ref genome. miniwdl goes further. So, we place the untarred directory in
	# the workdir rather than in-place for consistency's sake. If we are using the CDC (varpipe) 
	# decontamination reference, this also renames the output from "varpipe.Ref.remove_contam"
	if [ -f /ref/Ref.remove_contam.tar ]
	then
		mkdir Ref.remove_contam
		tar -xvf /ref/Ref.remove_contam.tar -C Ref.remove_contam --strip-components 1
	elif [ -f /ref/Ref.remove_contam/ref.fa ]
	then
		echo "Decontamination reference already expanded, moving to workdir"
	else
		echo "Failed to located decontamination reference"
		exit 1
	fi
	echo "workdir contents:"
	tree


	echo "----------------------------------------------"
	echo "(1) [bash] Ensure reads are paired correctly"
	echo "----------------------------------------------"
	# What it does: Makes an array to ensure _1 and _2 reads are in the right order, and
	# concatenate reads if there are more than two (necessary for pre-decontam fastp).
	#
	# Rationale: clockwork map_reads seems to require each pair of fqs are consecutive, eg:
	#                    (SRR1_1.fq, SRR1_2.fq, SRR2_1.fq, SRR2_2.fq)
	# If you instead had (SRR1_1.fq, SRR2_1.fq, SRR1_2.fq, SRR2_2.fq) then fqcount would
	# fail assuming SRR1 and SRR2 have different read counts. This hack does not seem to be
	# needed if reads were piped in from an SRANWRP download, but to support Terra data 
	# table input of reads this seems to be necessary.
	# Additionally, fastp doesn't support multi-lane-split-across-multiple-file situations, eg
	# (SRR1_1.fq, SRR1_2.fq, SRR2_1.fq, SRR2_2.fq) needs to become (SRR_1.fq, SRR_2.fq).
	# Also, we move reads into the workdir to avoid issues with find (which is only used
	# when ungzipping multilane files so we can concatenate them).
	start_first=$SECONDS
	fx_echo_array () {
		fq_array=("$@")
		for fq in "${fq_array[@]}"; do echo "$fq"; done
		printf "\n"
	}
	
	fx_move_to_workdir () { 
		fq_array=("$@")
		for fq in "${fq_array[@]}"; do mv "$fq" .; done 
	}
	
	fx_sort_array () {
		fq_array=("$@")
		readarray -t OUTPUT < <(for fq in "${fq_array[@]}"; do echo "$fq"; done | sort)
		echo "${OUTPUT[@]}" # this is a bit dangerous
	}
	READS_FILES_RAW=("~{sep='" "' reads_files}")
	fx_echo_array "Inputs as passed in:" "${READS_FILES_RAW[@]}"
	for fq in "${READS_FILES_RAW[@]}"; do mv "$fq" .; done 
	# I really did try to make these next three lines just one -iregex string but
	# kept messing up the syntax -- this approach is unsatisfying but cleaner
	readarray -d '' -t FQ < <(find . -iname "*.fq*" -print0) 
	readarray -d '' -t FASTQ < <(find . -iname "*.fastq*" -print0)
	readarray -d '' -t TAR < <(find . -iname "*.tar*" -print0)
	fx_echo_array "Located these .fq files: " "${FQ[@]}"
	fx_echo_array "Located these .fastq files: " "${FASTQ[@]}"
	fx_echo_array "Located these .tar files: " "${TAR[@]}"
	# check length of arrays -- we do not want "fq.fastq" files to cause issues
	if (( "${#FQ[@]}" != 0 && "${#FASTQ[@]}" != 0 ))
	then
		readarray -d ' ' -t READS_FILES_UNSORTED < <(echo "${FQ[@]}")
	elif (( "${#FQ[@]}" != 0 && "${#TAR[@]}" != 0 ))
	then
		readarray -d ' ' -t READS_FILES_UNSORTED < <(echo "${FQ[@]}")
	elif (( "${#FASTQ[@]}" != 0 && "${#TAR[@]}" != 0 ))
	then
		readarray -d ' ' -t READS_FILES_UNSORTED < <(echo "${FASTQ[@]}")
	else
		readarray -d ' ' -t READS_FILES_UNSORTED < <(echo "${FQ[@]}" "${FASTQ[@]}" "${TAR[@]}")
	fi
	fx_echo_array "Probable input files:" "${READS_FILES_UNSORTED[@]}"
	READS_FILES=( $(fx_sort_array "${READS_FILES_UNSORTED[@]}") ) # this appears to be more consistent than mapfile
	fx_echo_array "In workdir and sorted:" "${READS_FILES[@]}"
	
	if (( "${#READS_FILES[@]}" != 2 ))
	then
		# check for gzipped or tarball inputs
		# clockwork can handle gzipped inputs, we only unzip in case there's multiple fqs in a single zip
		some_base=$(basename -- "${READS_FILES[0]}") # just check the first element; should never be a mix of gzipped and not-gzipped fqs
		some_extension="${some_base##*.}"
		if [[ $some_extension = "gz" ]]
		then
			for fq in "${READS_FILES[@]}"; do pigz -d "$fq"; done
			# TODO: check that .gz originals got deleted to avoid issues with find
			readarray -d '' FQ < <(find . -iname "*.fq*" -print0) 
			readarray -d '' FASTQ < <(find . -iname "*.fastq*" -print0)
			readarray -d ' ' READS_FILES_UNZIPPED_UNSORTED < <(echo "${FQ[@]}" "${FASTQ[@]}") 
			READS_FILES=( $(fx_sort_array "${READS_FILES_UNZIPPED_UNSORTED[@]}") )  # this appears to be more consistent than mapfile
			fx_echo_array "After decompressing:" "${READS_FILES[@]}"
		elif [[ $some_extension = "tar" ]]
		then
			for tarball in "${READS_FILES[@]}"; do tar -xvf "$tarball"; done
			# TODO: check that .tar originals got deleted to avoid issues with find
			readarray -d '' FQ < <(find . -iname "*.fq*" -print0) 
			readarray -d '' FASTQ < <(find . -iname "*.fastq*" -print0)
			readarray -d ' ' READS_FILES_UNZIPPED_UNSORTED < <(echo "${FQ[@]}" "${FASTQ[@]}") 
			READS_FILES=( $(fx_sort_array "${READS_FILES_UNZIPPED_UNSORTED[@]}") )  # this appears to be more consistent than mapfile
			fx_echo_array "After untarring:" "${READS_FILES[@]}"
		else
			echo "Files do not appear to be gzipped nor in tar format."
		fi
	
		readarray -d '' READ1_LANES_IF_CDPH < <(find . -name "*_R1*" -print0)
		readarray -d '' READ2_LANES_IF_CDPH < <(find . -name "*_R2*" -print0)
		readarray -d '' READ1_LANES_IF_SRA < <(find . -name "*_1.f*" -print0)
		readarray -d '' READ2_LANES_IF_SRA < <(find . -name "*_2.f*" -print0)
		readarray -d ' ' READ1_LANES_UNSORTED < <(echo "${READ1_LANES_IF_CDPH[@]}" "${READ1_LANES_IF_SRA[@]}")
		readarray -d ' ' READ2_LANES_UNSORTED < <(echo "${READ2_LANES_IF_CDPH[@]}" "${READ2_LANES_IF_SRA[@]}")
		READ1_LANES=( $(fx_sort_array "${READ1_LANES_UNSORTED[@]}") )  # this appears to be more consistent than mapfile
		READ2_LANES=( $(fx_sort_array "${READ2_LANES_UNSORTED[@]}") )  # this appears to be more consistent than mapfile
		touch "~{sample_name}_cat_R1.fq"
		touch "~{sample_name}_cat_R2.fq"
		fx_echo_array "Read 1:" "${READ1_LANES[@]}"
		fx_echo_array "Read 2:" "${READ2_LANES[@]}"
		for fq in "${READ1_LANES[@]}"; do cat "$fq" ~{sample_name}_cat_R1.fq > temp; mv temp ~{sample_name}_cat_R1.fq; done
		for fq in "${READ2_LANES[@]}"; do cat "$fq" ~{sample_name}_cat_R2.fq > temp; mv temp ~{sample_name}_cat_R2.fq; done
		
		READS_FILES=( "~{sample_name}_cat_R1.fq" "~{sample_name}_cat_R2.fq" )
		fx_echo_array "After merging:" "${READS_FILES[@]}"
	fi
		
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
	#
	# TODO: if _1 is just barely above the cutoff and _2 is just barely below, you may end up
	# with two very differently size fastqs. Should probably check only one fastq then decide
	# to subsample/not everything else based on that.
	start_subsample=$SECONDS
	input_fq_reads=0
	for inputfq in "${READS_FILES[@]}"
	do
		size_inputfq=$(du -m "$inputfq" | cut -f1)
		reads_inputfq=$(fqtools count "$inputfq")
		input_fq_reads=$((input_fq_reads+reads_inputfq))
		if [[ "~{subsample_cutoff}" != "-1" ]]
		then
			if (( $size_inputfq > ~{subsample_cutoff} ))
			then
				seqtk sample -s~{subsample_seed} "$inputfq" ~{subsample_to_this_many_reads} > temp.fq
				rm "$inputfq"
				mv temp.fq "$inputfq"
				echo "WARNING: downsampled $inputfq (was $size_inputfq MB, $reads_inputfq reads)"
			else
				echo "$inputfq is $size_inputfq MB, and we will not be subsampling it"
			fi
		fi
	done
	if (( $input_fq_reads < ~{minimum_number_of_passing_reads} ))
	then
		echo "ERROR: We're already starting out below the minimum number of passing reads!"
		if [[ "~{crash_loudly}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			echo "LESS_THAN_~{minimum_number_of_passing_reads}_READS_EARLY" > ERROR
			echo $input_fq_reads > reads_raw.txt
			exit 0
		fi
	fi
	echo $(( SECONDS - start_subsample )) > timer_2_size
	
	echo "----------------------------------------------"
	echo "(3) [fastp] Check and maybe clean reads"
	echo "---> fastp_clean_before_decontam: ~{fastp_clean_before_decontam}"
	echo "----------------------------------------------"
	# What it does: Runs fastp
	#
	# Rationale: This cleans our input fastqs if fastp_clean_before_decontam,
	# and also filters out VERY bad fastqs.
	#
	# TODO: Support multi-lane-multi-file fastq sets!!
	echo "Fastp is taking in ${READS_FILES[0]} and ${READS_FILES[1]}"
	start_fastp_1=$SECONDS
	fastp --in1 "${READS_FILES[0]}" --in2 "${READS_FILES[1]}" \
		--out1 "~{reads_cleaned_1}" --out2 "~{reads_cleaned_2}" \
		--average_qual ~{fastp_clean_avg_qual} \
		~{true="--detect_adapter_for_pe" false="" fastp_clean_detect_adapter_for_pe} \
		~{true="--disable_adapter_trimming" false="" fastp_clean_disable_adapter_trimming} \
		--json "~{sample_name}_first_fastp.json"
		
	# very lenient filter to check for very bad fqs -- NOT AFFECTED BY soft_qc ON PURPOSE!
	python3 << CODE
	import os
	import json
	with open("~{sample_name}_first_fastp.json", "r") as fastpJSON:
		fastp = json.load(fastpJSON)
		q30_before_anything = fastp["summary"]["before_filtering"]["q30_rate"]
		if q30_before_anything < ~{preliminary_min_q30}:
			print(f"ERROR -- Q30 rate before filtering was just {q30_before_anything} (out of 1.0)")
			with open("ERROR", "w") as err:
				err.write(f"DECONTAMINATION_{q30_before_anything}_PRELIM_Q30_RATE")
			exit(100)
	CODE
	exit=$?
	if [[ $exit = 100 ]]
	then
		if [[ "~{crash_loudly}" = "true" ]]
		then
			set -eux -o pipefail
			exit 1
		else
			exit 0
		fi
	fi
		
	if [[ "~{fastp_clean_before_decontam}" = "true" ]]
	then		
		echo "Fastp output ~{reads_cleaned_1} and ~{reads_cleaned_2}"
		echo "Removing non-fastp'd ${READS_FILES[0]} and ${READS_FILES[1]}"
		rm "${READS_FILES[0]}"
		rm "${READS_FILES[1]}"
		CLEANED_FQS=("~{reads_cleaned_1}" "~{reads_cleaned_2}")
		readarray -t MAP_THESE_FQS < <(for fq in "${CLEANED_FQS[@]}"; do echo "$fq"; done | sort)
	else
		# this is basically a repeat of step 1
		# READS_FILES is updated whether or not there were fastqs to merge
		readarray -t MAP_THESE_FQS < <(for fq in "${READS_FILES[@]}"; do echo "$fq"; done)
		echo "Not using this fastp run's cleaned fastqs, so we will remove them"
		rm "~{reads_cleaned_1}"
		rm "~{reads_cleaned_2}"
	fi
	echo $(( SECONDS - start_fastp_1 )) > timer_3_clean

	echo "----------------------------------------------"
	echo "(4) [clockwork] Map FQs to decontam reference"
	echo "----------------------------------------------"
	# What it does: clockwork map_reads to decontamination ref
	fx_echo_array "Fastqs we will be mapping with clockwork:" "${MAP_THESE_FQS[@]}"
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
		if [[ "~{crash_loudly}" = "true" ]]
		then
			echo "DECONTAMINATION_MAP_READS_TIMEOUT" > ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_MAP_READS_TIMEOUT" > ERROR
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork map_reads was killed -- it may have run out of memory"
		if [[ "~{crash_loudly}" = "true" ]]
		then
			echo "DECONTAMINATION_MAP_READS_KILLED" > ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_MAP_READS_KILLED" > ERROR
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully mapped to decontamination reference" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork map_reads errored out for unknown reasons"
		echo "DECONTAMINATION_MAP_READS_UNKNOWN_ERROR" > ERROR # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork map_reads returned $exit for unknown reasons"
		echo "DECONTAMINATION_MAP_READS_UNKNOWN_ERROR" > ERROR # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	fi
	echo "SAM file created, so we'll delete the fastqs that have been mapped"
	rm "${MAP_THESE_FQS[0]}"
	rm "${MAP_THESE_FQS[1]}"
	echo $(( SECONDS - start_map_reads )) > timer_5_map_reads

	echo "----------------------------------------------"
	echo "(5) [samtools] Sort by read name"
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
	echo "(6) [clockwork] Remove contamination"
	echo "If you see 'Could not retrieve index file' you"
	echo "can safely ignore it; it's a false warning."
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
		if [[ "~{crash_loudly}" = "true" ]]
		then
			echo "DECONTAMINATION_RM_CONTAM_TIMEOUT" > ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_RM_CONTAM_TIMEOUT" > ERROR
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork remove_contam was killed -- it may have run out of memory"
		if [[ "~{crash_loudly}" = "true" ]]
		then
			echo "DECONTAMINATION_RM_CONTAM_KILLED" > ERROR  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_RM_CONTAM_KILLED" > ERROR
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully decontaminated" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork remove_contam errored out for unknown reasons"
		echo "DECONTAMINATION_RM_CONTAM_UNKNOWN_ERROR" > ERROR  # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork remove_contam returned $exit for unknown reasons"
		echo "DECONTAMINATION_RM_CONTAM_UNKNOWN_ERROR" > ERROR  # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	fi
	echo $(( SECONDS - start_rm_contam )) > timer_7_rm_contam
	
	echo "----------------------------------------------"
	echo "(7) [fastp] Post-decontam QC check and/or clean"
	echo "--> fastp_clean_after_decontam: ~{fastp_clean_after_decontam}"
	echo "----------------------------------------------"
	# What it does: Run fastp again, this time as a QC filter... or a cleaner.
	#
	# Rationale: There is no point in running fastp as a cleaner twice, but users
	# can do it. Our actual goal is to provide the option to do fastp before
	# or after decontamination in order to test how the end result differs.
	start_fastp_2=$SECONDS
	if [ -f "~{reads_cleaned_1}" ]
	then
		# remove previous cleaned-before-decontam fastqs, because we are
		# going to overwrite them with outputs with a similar filename
		rm "~{reads_cleaned_1}" "~{reads_cleaned_2}"
	fi
	fastp --in1 ~{arg_reads_out1} --in2 ~{arg_reads_out2} \
		--out1 ~{reads_cleaned_1} --out2 ~{reads_cleaned_2} \
		--average_qual ~{fastp_clean_avg_qual} \
		~{true="--detect_adapter_for_pe" false="" fastp_clean_detect_adapter_for_pe} \
		~{true="--disable_adapter_trimming" false="" fastp_clean_disable_adapter_trimming} \
		--json "~{sample_name}_second_fastp.json"
	if [[ "~{fastp_clean_after_decontam}" = "true" ]]
	then
		CLEANED_FQS=("~{reads_cleaned_1}" "~{reads_cleaned_2}")
		readarray -t MAP_THESE_FQS < <(for fq in "${CLEANED_FQS[@]}"; do echo "$fq"; done | sort)
	fi
	echo $(( SECONDS - start_fastp_2 )) > timer_8_qc
	
	echo "----------------------------------------------"
	echo "(8) [python/bash] Parse reports"
	echo "----------------------------------------------"
	start_parse=$SECONDS
	
	# parse decontam.counts.tsv
	# different decontamination references have a different format, this should work with CDC and CRyPTIC
	sum_contam_reads=0
	tb_reads=0
	unmapped_reads=0
	kept_reads=0
	while IFS=$'\t' read -r name is_contam reads
	do
		if [[ "$name" == "Name" ]]; then continue; fi
		if [[ "$is_contam" -eq 1 ]]; then sum_contam_reads=$((sum_contam_reads + reads)); fi
		if [[ "$name" == "Reads_kept_after_remove_contam" ]]; then kept_reads=$((kept_reads + reads)); fi
		if [[ "$name" == "Unmapped" ]]; then unmapped_reads=$((unmapped_reads + reads)); fi
		if [[ "$name" == "TB" || "$name" == "Reference" ]]  # CDC and CRyPTIC refs differ here
		then
			tb_reads=$((tb_reads + reads))
		fi
	done < "~{arg_counts_out}"
	echo $sum_contam_reads > reads_is_contam
	echo $tb_reads > reads_reference
	echo $unmapped_reads > reads_unmapped
	echo $kept_reads > reads_kept
	
	# parse fastp reports
	python3 << CODE
	import os
	import json
	
	# second fastp run
	# we handle this one first to account for the "cleaning twice" case, as we want the first run's cleaned stats to be saved
	with open("~{sample_name}_second_fastp.json", "r") as fastpJSON_2:
		fastp_2 = json.load(fastpJSON_2)
	with open("~{sample_name}_fastp.txt", "a") as outfile: # appends to the same outfile as the first fastp
		outfile.write("after decontamination:\n")
		for keys, values in fastp_2["summary"]["before_filtering"].items():
			outfile.write(f"{keys}\t{values}\n")
			if "~{fastp_clean_after_decontam}" == "true":
				outfile.write("after fastp cleaned the decontaminated fastqs:\n")
				for keys, values in fastp_2["summary"]["after_filtering"].items():
					outfile.write(f"{keys}\t{values}\n")
				reads_cleaned = fastp_1["summary"]["after_filtering"]["total_reads"] # like the files, this can be overwritten
				with open("q20_cleaned.txt", "w") as q20_out: q20_out.write(str(fastp_2["summary"]["after_filtering"]["q20_rate"]))
				with open("q30_cleaned.txt", "w") as q30_out: q30_out.write(str(fastp_2["summary"]["after_filtering"]["q30_rate"]))
				with open("reads_cleaned.txt", "w") as reads_out: reads_out.write(str(reads_cleaned))
			else:
				outfile.write("no additional cleaning was performed post-decontamination.\n")
	dcntmd_total_reads = fastp_2["summary"]["before_filtering"]["total_reads"]
	with open("q20_decontaminated.txt", "w") as q20_in: q20_in.write(str(fastp_2["summary"]["before_filtering"]["q20_rate"]))
	with open("q30_decontaminated.txt", "w") as q30_in: q30_in.write(str(fastp_2["summary"]["before_filtering"]["q30_rate"]))
	with open("reads_decontaminated.txt", "w") as reads_in: reads_in.write(str(dcntmd_total_reads))
	
	
	# first fastp run
	with open("~{sample_name}_first_fastp.json", "r") as fastpJSON_1:
		fastp_1 = json.load(fastpJSON_1)
	with open("~{sample_name}_fastp.txt", "w") as outfile:
		outfile.write("before any filtering or decontamination:\n")
		for keys, values in fastp_1["summary"]["before_filtering"].items():
			outfile.write(f"{keys}\t{values}\n")
		if "~{fastp_clean_before_decontam}" == "true":
			outfile.write("after fastp cleaned the non-decontaminated fastqs:\n")
			for keys, values in fastp_1["summary"]["after_filtering"].items():
				outfile.write(f"{keys}\t{values}\n")
			# if both cleans are true, this section will overwrite the other files and dcntmd_total_reads -- this is intended!
			# cleaning a second time doesn't do much, so what we care about are stats from the first cleaning
			cleaned_total_reads = fastp_1["summary"]["after_filtering"]["total_reads"]
			with open("q20_cleaned.txt", "w") as q20_out: q20_out.write(str(fastp_1["summary"]["after_filtering"]["q20_rate"]))
			with open("q30_cleaned.txt", "w") as q30_out: q30_out.write(str(fastp_1["summary"]["after_filtering"]["q30_rate"]))
			with open("reads_cleaned.txt", "w") as reads_out: reads_out.write(str(cleaned_total_reads))
		else:
			outfile.write("reads were not cleaned before decontamination.\n")
	raw_total_reads = fastp_1["summary"]["before_filtering"]["total_reads"]
	with open("q20_raw.txt", "w") as q20_in: q20_in.write(str(fastp_1["summary"]["before_filtering"]["q20_rate"]))
	with open("q30_raw.txt", "w") as q30_in: q30_in.write(str(fastp_1["summary"]["before_filtering"]["q30_rate"]))
	with open("reads_raw.txt", "w") as reads_in: reads_in.write(str(raw_total_reads))

	# actual filtering
	try:
		q30_after_everything = fastp_2["summary"]["after_filtering"]["q30_rate"] # post clean and decontam
		print("Checking Q30 rate post-decontamination-then-cleaning...")
	except KeyError:
		q30_after_everything = fastp_2["summary"]["before_filtering"]["q30_rate"] # post decontam (pre-decontam cleaning not relevent)
		print("Checking Q30 rate post-decontamination...")
	
	if q30_after_everything < ~{QC_min_q30}:
		print(f"ERROR -- Q30 rate after filtering was only {q30_after_everything} (out of 1.0, minimum ~{QC_min_q30})")
		with open("ERROR", "w") as err:
			err.write(f"DECONTAMINATION_{q30_after_everything}_Q30_RATE")
		exit(100)
	
	# more stats, because Terra doesn't support outputs based on other outputs
	pct_loss_cleaning = ((raw_total_reads - cleaned_total_reads) / raw_total_reads) * 100
	pct_loss_decon = ((cleaned_total_reads - dcntmd_total_reads) / cleaned_total_reads) * 100
	pct_loss_total = ((raw_total_reads - dcntmd_total_reads) / raw_total_reads) * 100
	with open("pct_loss_cleaning.txt", "w") as reads_in: reads_in.write(str(pct_loss_cleaning))
	with open("pct_loss_decon.txt", "w") as reads_in: reads_in.write(str(pct_loss_decon))
	with open("pct_loss_total.txt", "w") as reads_in: reads_in.write(str(pct_loss_total))
	
	CODE
	exit=$?
	if [[ $exit = 100 ]]
	then
		if [[ "~{soft_qc}" = "false" ]]
		then
			if [[ "~{crash_loudly}" = "true" ]]
			then
				set -eux -o pipefail
				echo "Due to QC failure, no .fq output will be given. Crashing!"
				exit 1
			else
				rm "~{usual_final_fastq1}" 
				rm "~{usual_final_fastq2}"
				echo "Due to QC failure, no .fq output will be given."
				exit 0
			fi
		fi
	fi

	if [[ $(fqtools count "~{usual_final_fastq1}") -le ~{minimum_number_of_passing_reads} ]]
	then
		echo "This sample has less than ~{minimum_number_of_passing_reads} reads and risks breaking the variant caller. We're getting rid of it."
		echo "LESS_THAN_~{minimum_number_of_passing_reads}_READS_LATE" > ERROR
		rm "~{usual_final_fastq1}" 
		rm "~{usual_final_fastq2}"
		exit 0
	fi
	
	# rename outputs if necessary
	if [[ ! "~{force_rename_out}" = "" ]]
	then
		mv "~{usual_final_fastq1}" "~{final_fastq1}"
		mv "~{usual_final_fastq2}" "~{final_fastq2}"
	fi
	
	echo "PASS" > ERROR
	
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
		Float  cleaned_pct_above_q20   = if (fastp_clean_before_decontam || fastp_clean_after_decontam) then read_float("q20_cleaned.txt") else read_float("q20_raw.txt")
		Float  cleaned_pct_above_q30   = if (fastp_clean_before_decontam || fastp_clean_after_decontam) then read_float("q30_cleaned.txt") else read_float("q30_raw.txt")
		Int    cleaned_total_reads     = if (fastp_clean_before_decontam || fastp_clean_after_decontam) then read_int("reads_cleaned.txt") else read_int("reads_raw.txt")
		Float  dcntmd_pct_above_q20  = read_float("q20_decontaminated.txt")
		Float  dcntmd_pct_above_q30  = read_float("q30_decontaminated.txt")
		Int    dcntmd_total_reads    = read_int("reads_decontaminated.txt")
		Float pct_loss_cleaning = read_float("pct_loss_cleaning.txt")
		Float pct_loss_decon    = read_float("pct_loss_decon.txt")
		Float pct_loss_total    = read_float("pct_loss_total.txt")
		
		# timers and debug information
		String errorcode = read_string("ERROR")
		#Int timer_1_prep  = read_int("timer_1_process")
		#Int timer_2_size  = read_int("timer_2_size")
		#Int timer_3_clean = read_int("timer_3_clean")
		Int timer_a_mapFQ = read_int("timer_5_map_reads")
		Int timer_b_sort  = read_int("timer_6_sort")
		Int timer_c_dcnFQ = read_int("timer_7_rm_contam")
		#Int timer_8_qchck = read_int("timer_8_qc")
		#Int timer_9_parse = read_int("timer_9_parse")
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