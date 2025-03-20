version 1.0

# All-in-one read cleaning and decontamination. See also ./unsupported/unsupported_decontamination.wdl


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
		Int        preliminary_min_q30 = 20
		Int        subsample_cutoff = -1
		Int        subsample_seed = 1965
		Int        subsample_to_this_many_reads =  1000000
		Int        minimum_number_of_passing_reads = 20000
		
		# fastp cleaning options
		Int fastp_clean_avg_qual = 29
		Boolean fastp_clean_disable_adapter_trimming = false
		Boolean fastp_clean_detect_adapter_for_pe = true
		
		# decontamination options
		Boolean     crash_loudly = false
		Int         timeout_map_reads = 120
		Int         timeout_decontam  = 120
		Boolean     unsorted_sam = false
		
		# fastp QC cleaning options
		Float QC_min_q30 = 50

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
		preliminary_min_q30: "Throw out a sample immediately if it's got a Q30 rate below this, before any cleaning nor decontamination. Default: 20 (as in 20%)"
		QC_min_q30: "Q30 rate must be above this after cleaning and decontamination. Default: 50 (as in 50%)"
		subsample_cutoff: "If a FASTQ is larger than this size in megabytes, subsample subsample_to_this_many_reads random reads and use that instead (-1 to disable)"
		subsample_to_this_many_reads: "This is the number of reads to subsample down to (default: 1,000,000)"
		subsample_seed: "Seed to use when subsampling (default: year UCSC was founded)"
		timeout_decontam: "If decontamination takes longer than this number of minutes, stop processing this sample"
		timeout_map_reads: "If read mapping takes longer than this number of minutes, stop processing this sample"
		unsorted_sam: "It's best to leave this as false"
	}

	# The Docker image has our reference information, so these can be hardcoded.
	String arg_metadata_tsv = "/ref/Ref.remove_contam/remove_contam_metadata.tsv"
	String arg_ref_fasta = "/ref/Ref.remove_contam/ref.fa"

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
	String usual_final_fastq1 = arg_reads_out1
	String usual_final_fastq2 = arg_reads_out2
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
	FALLBACK_FILES=(  ERROR.TXT duplication_rate.txt reads_adapter.txt )
	FALLBACK_FILES+=( q20_in.txt q30_in.txt reads_in.txt mean_r1_len_in.txt mean_r2_len_in.txt )
	FALLBACK_FILES+=( q20_postclean.txt q30_postclean.txt reads_postclean_per_fastp.txt mean_r1_len_postclean.txt mean_r2_len_postclean.txt pct_loss_cleaning_per_fastp.txt reads_postclean_per_decon.txt )
	FALLBACK_FILES+=( reads_postdecon_per_decon.txt reads_TB.txt reads_NTM.txt reads_human.txt reads_contam.txt )
	FALLBACK_FILES+=( pct_reads_TB_predecon.txt pct_reads_NTM.txt pct_reads_human.txt pct_reads_TB_postdecon.txt )
	FALLBACK_FILES+=( pct_loss_decon_per_decon.txt pct_loss_total.txt pct_loss_decon_per_fastp.txt )
	FALLBACK_FILES+=( q20_postdecon.txt q30_postdecon.txt reads_postdecon_per_fastp.txt mean_r1_len_postdecon.txt mean_r2_len_postdecon.txt )
	FALLBACK_FILES+=( timer_1_process timer_2_size timer_3_clean timer_4_untar timer_5_map_reads timer_6_sort timer_7_rm_contam timer_8_qc timer_9_parse timer_total )
	for fallback_file in "${FALLBACK_FILES[@]}"
	do
		echo -1 > "$fallback_file"
	done
	# TODO: force pct_loss_* to be negative?

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
	# go up one to get the ref genome. miniwdl goes further. To account for this, we are using
	# absolute paths -- see also ~{arg_metadata_tsv} and ~{arg_ref_fasta}
	if [ -f /ref/Ref.remove_contam.tar ]
	then
		mv /ref/
		tar -xvf /ref/Ref.remove_contam.tar
		mv ..
	elif [ -f /ref/Ref.remove_contam/ref.fa ]
	then
		echo "Decontamination reference already expanded"
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
	readarray -d '' -t BADFQ < <(find . -iname "*.fq*" -print0)
	readarray -d '' -t FQ < <(find . -iname "*.fq" -print0)
	readarray -d '' -t FQ_GZ < <(find . -iname "*.fq.gz" -print0)
	readarray -d '' -t FASTQ < <(find . -iname "*.fastq" -print0)
	readarray -d '' -t FASTQ_GZ < <(find . -iname "*.fastq.gz" -print0)
	readarray -d '' -t TAR < <(find . -iname "*.tar*" -print0)
	fx_echo_array "Located these .fq* files: " "${BAD_FQ[@]}"
	echo "^ If your FQ files show up here, but not down here \/, rename them. We don't support matching on"
	echo "*.fq* because this sometimes picks up on temp files (tmp.FQnvHo, etc)"
	fx_echo_array "Located these .fq files: " "${FQ[@]}"
	fx_echo_array "Located these .fq.gz files: " "${FQ_GZ[@]}"
	fx_echo_array "Located these .fastq files: " "${FASTQ[@]}"
	fx_echo_array "Located these .fastq.gz files: " "${FASTQ_GZ[@]}"
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
		readarray -d ' ' -t READS_FILES_UNSORTED < <(echo "${FQ[@]}" "${FASTQ[@]}" "${TAR[@]}" "${FQ_GZ[@]}" "${FASTQ_GZ[@]}")
	fi
	fx_echo_array "Probable input files:" "${READS_FILES_UNSORTED[@]}"
	READS_FILES=( $(fx_sort_array "${READS_FILES_UNSORTED[@]}") ) # this appears to be more consistent than mapfile
	fx_echo_array "In workdir and sorted:" "${READS_FILES[@]}"
	
	if (( "${#READS_FILES[@]}" != 2 ))
	then
		# check for gzipped or tarball inputs
		# clockwork and fastp can handle gzipped inputs without unzipping; we only unzip in case there's multiple fqs in a single zip
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
			echo "LESS_THAN_~{minimum_number_of_passing_reads}_READS_EARLY" > ERROR.TXT
			echo $input_fq_reads > reads_raw.txt
			exit 0
		fi
	fi
	echo $(( SECONDS - start_subsample )) > timer_2_size
	
	echo "----------------------------------------------"
	echo "(3) [fastp] Check and clean reads"
	echo "----------------------------------------------"
	# What it does: Runs fastp
	#
	# Rationale: This cleans our input fastqs and filters out VERY bad fastqs
	#
	# low priority TODO: Support multi-lane-multi-file fastq sets
	echo "Fastp is taking in ${READS_FILES[0]} and ${READS_FILES[1]}"
	start_fastp_1=$SECONDS
	fastp --in1 "${READS_FILES[0]}" --in2 "${READS_FILES[1]}" \
		--out1 "~{reads_cleaned_1}" --out2 "~{reads_cleaned_2}" \
		--average_qual ~{fastp_clean_avg_qual} \
		~{true="--detect_adapter_for_pe" false="" fastp_clean_detect_adapter_for_pe} \
		~{true="--disable_adapter_trimming" false="" fastp_clean_disable_adapter_trimming} \
		--json "~{sample_name}_first_fastp.json"
		
	# VERY lenient filter to check for terrible samples
	python3 << CODE
	import os
	import json
	with open("~{sample_name}_first_fastp.json", "r") as fastpJSON:
		fastp = json.load(fastpJSON)
		q30_before_anything = fastp["summary"]["before_filtering"]["q30_rate"]
		if (100 * q30_before_anything) < ~{preliminary_min_q30}:
			print(f"ERROR -- Q30 rate before filtering was just {q30_before_anything} (out of 100)")
			with open("ERROR.TXT", "w") as err:
				err.write(f"DECONTAMINATION_{q30_before_anything}_PRELIM_Q30_RATE")
			exit(100)
	CODE
	if grep -q '_' ERROR.TXT
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
		
	echo "Fastp output ~{reads_cleaned_1} and ~{reads_cleaned_2}"
	echo "Removing non-fastp'd ${READS_FILES[0]} and ${READS_FILES[1]}"
	rm "${READS_FILES[0]}"
	rm "${READS_FILES[1]}"
	CLEANED_FQS=("~{reads_cleaned_1}" "~{reads_cleaned_2}")
	readarray -t MAP_THESE_FQS < <(for fq in "${CLEANED_FQS[@]}"; do echo "$fq"; done | sort)

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
			echo "DECONTAMINATION_MAP_READS_TIMEOUT" > ERROR.TXT  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_MAP_READS_TIMEOUT" > ERROR.TXT
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork map_reads was killed -- it may have run out of memory"
		if [[ "~{crash_loudly}" = "true" ]]
		then
			echo "DECONTAMINATION_MAP_READS_KILLED" > ERROR.TXT  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_MAP_READS_KILLED" > ERROR.TXT
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully mapped to decontamination reference" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork map_reads errored out for unknown reasons"
		echo "DECONTAMINATION_MAP_READS_UNKNOWN_ERROR" > ERROR.TXT # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork map_reads returned $exit for unknown reasons"
		echo "DECONTAMINATION_MAP_READS_UNKNOWN_ERROR" > ERROR.TXT # since we exit 1 after this, this output may not be delocalized
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
			echo "DECONTAMINATION_RM_CONTAM_TIMEOUT" > ERROR.TXT  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_RM_CONTAM_TIMEOUT" > ERROR.TXT
			exit 0
		fi
	elif [[ $exit = 137 ]]
	then
		echo "ERROR -- clockwork remove_contam was killed -- it may have run out of memory"
		if [[ "~{crash_loudly}" = "true" ]]
		then
			echo "DECONTAMINATION_RM_CONTAM_KILLED" > ERROR.TXT  # since we exit 1 after this, this output may not be delocalized
			set -eux -o pipefail
			exit 1
		else
			echo "DECONTAMINATION_RM_CONTAM_KILLED" > ERROR.TXT
			exit 0
		fi
	elif [[ $exit = 0 ]]
	then
		echo "Reads successfully decontaminated" 
	elif [[ $exit = 1 ]]
	then
		echo "ERROR -- clockwork remove_contam errored out for unknown reasons"
		echo "DECONTAMINATION_RM_CONTAM_UNKNOWN_ERROR" > ERROR.TXT  # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	else
		echo "ERROR -- clockwork remove_contam returned $exit for unknown reasons"
		echo "DECONTAMINATION_RM_CONTAM_UNKNOWN_ERROR" > ERROR.TXT  # since we exit 1 after this, this output may not be delocalized
		set -eux -o pipefail
		exit 1
	fi
	echo $(( SECONDS - start_rm_contam )) > timer_7_rm_contam
	
	echo "----------------------------------------------"
	echo "(7) [fastp] Post-decontam QC check"
	echo "----------------------------------------------"
	# What it does: Run fastp again, this time as a QC filter
	#
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
	echo $(( SECONDS - start_fastp_2 )) > timer_8_qc
	
	echo "----------------------------------------------"
	echo "(8) [python/bash] Parse reports"
	echo "----------------------------------------------"
	start_parse=$SECONDS

	python3 << CODE
	QC_min_q30 = ~{QC_min_q30}
	arg_counts_out = "~{arg_counts_out}"
	sample_name = "~{sample_name}"

	import os
	import json

	# parse decontam.counts.tsv
	# different decontamination references have a different format, this should work with CDC and CRyPTIC!
	# the exact metric CDC wants is "At least >90% of the reads should map to Mycobacterium tuberculosis complex," but we are not
	# going to filter on that yet as I'm unsure if this is measured before or after trying to decontaminate.
	total_reads_kept, total_reads, total_reads_contam, total_reads_TB, total_reads_NTM, total_reads_human = -1, -1, -1, -1, -1, -1
	pct_reads_TB_predecon, pct_reads_TB_postdecon, pct_reads_NTM, pct_reads_human = -1, -1, -1, -1

	with open(arg_counts_out, "r") as file:
		lines = file.readlines()

	header = lines[0].strip().split("\t")
	rows = [line.strip().split("\t") for line in lines[1:]]
	data = [{header[i]: row[i] for i in range(len(header))} for row in rows] # trying to stick to Python std library here
	for row in data:
		name, is_contam, read_counts = row["Name"], int(row["Is_contam"]), int(row["Reads"])
		if name == "Reads_kept_after_remove_contam":
			total_reads_kept = read_counts
		else:
			total_reads += read_counts
		if is_contam == 1:
			total_reads_contam += read_counts
		if name == "TB" or name == "reference":
			total_reads_TB = read_counts
		elif name == "NTM":
			total_reads_NTM = read_counts
		elif name == "Human" or name == "human":
			total_reads_human = read_counts
		else:
			pass
	print(f"{total_reads} found by decontamination")
	print(f"{total_reads_kept} kept by decontamination")


	if total_reads != -1:
		pct_reads_TB_predecon = int(((total_reads_TB / total_reads) * 100 * 10000)) / 10000
	if total_reads_NTM != -1:
		pct_reads_NTM = int(((total_reads_NTM / total_reads) * 100 * 10000)) / 10000
	if total_reads_human != -1:
		pct_reads_human = int(((total_reads_human / total_reads) * 100 * 10000)) / 10000
	if total_reads_kept != -1:
		pct_reads_TB_postdecon = int(((total_reads_TB / total_reads_kept) * 100 * 10000)) / 10000
	pct_loss_decon_per_decon = int(((total_reads - total_reads_kept) / total_reads) * 100 * 10000) / 10000

	with open("reads_postclean_per_decon.txt", "w") as file: file.write(str(total_reads))
	with open("reads_postdecon_per_decon.txt", "w") as file: file.write(str(total_reads_kept))
	with open("reads_TB.txt", "w") as file: file.write(str(total_reads_TB))
	with open("reads_NTM.txt", "w") as file: file.write(str(total_reads_NTM))
	with open("reads_human.txt", "w") as file: file.write(str(total_reads_human))
	with open("reads_contam.txt", "w") as file: file.write(str(total_reads_contam))
	with open("pct_reads_TB_predecon.txt", "w") as file: file.write(str(pct_reads_TB_predecon))
	with open("pct_reads_NTM.txt", "w") as file: file.write(str(pct_reads_NTM))
	with open("pct_reads_human.txt", "w") as file: file.write(str(pct_reads_human))
	with open("pct_reads_TB_postdecon.txt", "w") as file: file.write(str(pct_reads_TB_postdecon))
	with open("pct_loss_decon_per_decon.txt", "w") as file: file.write(str(pct_loss_decon_per_decon))

	# parse fastp reports
	with open(f"{sample_name}_first_fastp.json", "r") as fastpJSON_1:
		fastp_1 = json.load(fastpJSON_1)
	with open(f"{sample_name}_second_fastp.json", "r") as fastpJSON_2:
		fastp_2 = json.load(fastpJSON_2)

	# IN: Files before any decontamination or filtering
	q20_in = int(fastp_1["summary"]["before_filtering"]["q20_rate"] * 100 * 10000) / 10000
	q30_in = int(fastp_1["summary"]["before_filtering"]["q30_rate"] * 100 * 10000) / 10000
	reads_in = fastp_1["summary"]["before_filtering"]["total_reads"]
	mean_r1_len_in = fastp_1["summary"]["before_filtering"]["read1_mean_length"]
	mean_r2_len_in = fastp_1["summary"]["before_filtering"]["read2_mean_length"]
	duplication_rate = int(fastp_1["duplication"]["rate"] * 100 * 10000) / 10000
	adapter_trimmed_reads = fastp_1["adapter_cutting"]["adapter_trimmed_reads"]

	# CLEANED: Files after being cleaned by fastp, but before decontamination
	q20_postclean = int(fastp_1["summary"]["after_filtering"]["q20_rate"] * 100 * 10000) / 10000
	q30_postclean = int(fastp_1["summary"]["after_filtering"]["q30_rate"] * 100 * 10000) / 10000
	reads_postclean_per_fastp = fastp_1["summary"]["after_filtering"]["total_reads"]
	mean_r1_len_postclean = fastp_1["summary"]["after_filtering"]["read1_mean_length"]
	mean_r2_len_postclean = fastp_1["summary"]["after_filtering"]["read2_mean_length"]

	# DECON: Files after decontamination -- comes from the second fastp run, but before it tries to filter
	q20_postdecon = int(fastp_2["summary"]["before_filtering"]["q20_rate"] * 100 * 10000) / 10000
	q30_postdecon = int(fastp_2["summary"]["before_filtering"]["q30_rate"] * 100 * 10000) / 10000
	reads_postdecon_per_fastp = fastp_2["summary"]["before_filtering"]["total_reads"]
	mean_r1_len_postdecon = fastp_2["summary"]["before_filtering"]["read1_mean_length"]
	mean_r2_len_postdecon = fastp_2["summary"]["before_filtering"]["read2_mean_length"]

	if q30_postdecon < QC_min_q30:
		print(f"ERROR -- Q30 rate after filtering and decontamination was only {q30_postdecon} (out of 100, minimum ~{QC_min_q30})")
		with open("ERROR.TXT", "w") as err:
			err.write(f"DECONTAMINATION_{q30_postclean}_Q30_RATE")
		exit(100)

	# Terra doesn't support outputs based on other outputs, so it's best that we squeeze as much out of this in this block as we can
	pct_loss_cleaning_per_fastp = int(((reads_in - reads_postclean_per_fastp) / reads_in) * 100 * 10000) / 10000
	pct_loss_decon_per_fastp = int(((reads_postclean_per_fastp - reads_postdecon_per_fastp) / reads_postclean_per_fastp) * 100 * 10000) / 10000
	pct_loss_total_per_fastp = int(((reads_in - reads_postdecon_per_fastp) / reads_in) * 100 * 10000) / 10000

	with open("pct_loss_cleaning_per_fastp.txt", "w") as file: file.write(str(pct_loss_cleaning_per_fastp))
	with open("pct_loss_decon_per_fastp.txt", "w") as file: file.write(str(pct_loss_decon_per_fastp))
	with open("pct_loss_total.txt", "w") as file: file.write(str(pct_loss_total_per_fastp))
	with open("q20_in.txt", "w") as file: file.write(str(q20_in))
	with open("q30_in.txt", "w") as file: file.write(str(q30_in))
	with open("reads_in.txt", "w") as file: file.write(str(reads_in))
	with open("mean_r1_len_in.txt", "w") as file: file.write(str(mean_r1_len_in))
	with open("mean_r2_len_in.txt", "w") as file: file.write(str(mean_r2_len_in))
	with open("q20_postclean.txt", "w") as file: file.write(str(q20_postclean))
	with open("q30_postclean.txt", "w") as file: file.write(str(q30_postclean))
	with open("reads_postclean_per_fastp.txt", "w") as file: file.write(str(reads_postclean_per_fastp))
	with open("mean_r1_len_postclean.txt", "w") as file: file.write(str(mean_r1_len_postclean))
	with open("mean_r2_len_postclean.txt", "w") as file: file.write(str(mean_r2_len_postclean))
	with open("q20_postdecon.txt", "w") as file: file.write(str(q20_postdecon))
	with open("q30_postdecon.txt", "w") as file: file.write(str(q30_postdecon))
	with open("reads_postdecon_per_fastp.txt", "w") as file: file.write(str(reads_postdecon_per_fastp))
	with open("mean_r1_len_postdecon.txt", "w") as file: file.write(str(mean_r1_len_postdecon))
	with open("mean_r2_len_postdecon.txt", "w") as file: file.write(str(mean_r2_len_postdecon))
	with open("duplication_rate.txt", "w") as file: file.write(str(duplication_rate))
	with open("reads_adapter.txt", "w") as file: file.write(str(adapter_trimmed_reads))

	CODE

	if [[ $(fqtools count "~{usual_final_fastq1}") -le ~{minimum_number_of_passing_reads} ]]
	then
		echo "This sample has less than ~{minimum_number_of_passing_reads} reads and risks breaking the variant caller. We're getting rid of it."
		echo "LESS_THAN_~{minimum_number_of_passing_reads}_READS_LATE" > ERROR.TXT
		rm "~{usual_final_fastq1}" 
		rm "~{usual_final_fastq2}"
		# exit handled in grep block below
	fi

	# we used to be able to check exit codes of inline python for an exit code of 100, but something seems to have changed.
	# instead, we'll just check ERROR.TXT for underscores (this does mean we shouldn't reformat the error codes without
	# changing this block!)
	if grep -q '_' ERROR.TXT
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
	
	# rename outputs if necessary
	if [[ ! "~{force_rename_out}" = "" ]]
	then
		mv "~{usual_final_fastq1}" "~{final_fastq1}"
		mv "~{usual_final_fastq2}" "~{final_fastq2}"
	fi
	
	echo "PASS" > ERROR.TXT
	
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
		
		# before cleaning, before decontamination -- metrics according to fastp
		Float q20_in = read_float("q20_in.txt")
		Float q30_in = read_float("q30_in.txt")
		Int reads_in = read_int("reads_in.txt")
		Int mean_r1_len_in = read_int("mean_r1_len_in.txt")
		Int mean_r2_len_in = read_int("mean_r2_len_in.txt")
		Float duplication_rate = read_float("duplication_rate.txt")
		Int reads_adapter_trimmed = read_int("reads_adapter.txt")

		# after cleaning, before decontamination -- metrics according to fastp
		Float q20_postclean = read_float("q20_postclean.txt")
		Float q30_postclean = read_float("q30_postclean.txt")
		Int reads_postclean_per_fastp = read_int("reads_postclean_per_fastp.txt") # compare reads_postclean_per_decon
		Int mean_r1_len_postclean = read_int("mean_r1_len_postclean.txt")
		Int mean_r2_len_postclean = read_int("mean_r2_len_postclean.txt")
		Float pct_loss_cleaning_per_fastp = read_float("pct_loss_cleaning_per_fastp.txt")

		# after cleaning, before decontamination -- metrics according to decontamination
		Int reads_postclean_per_decon = read_int("reads_postclean_per_decon.txt") # compare reads_postclean_per_fastp
		Int reads_postdecon_per_decon = read_int("reads_postdecon_per_decon.txt") # compare reads_postdecon_per_fastp
		Int reads_TB = read_int("reads_TB.txt")
		Int reads_NTM = read_int("reads_NTM.txt")
		Int reads_human = read_int("reads_human.txt")
		Int reads_contam = read_int("reads_contam.txt")
		Float pct_reads_TB_predecon = read_float("pct_reads_TB_predecon.txt")
		Float pct_reads_NTM = read_float("pct_reads_NTM.txt")
		Float pct_reads_human = read_float("pct_reads_human.txt")

		# after cleaning, after decontamination -- metrics according to decontamination
		Float pct_reads_TB_postdecon = read_float("pct_reads_TB_postdecon.txt")
		Float pct_loss_decon_per_decon = read_float("pct_loss_decon_per_decon.txt")
		Float pct_loss_total = read_float("pct_loss_total.txt")

		# after cleaning, after decontamination -- metrics according to second run of fastp
		Float pct_loss_decon_per_fastp = read_float("pct_loss_decon_per_fastp.txt")
		Float q20_postdecon = read_float("q20_postdecon.txt")
		Float q30_postdecon = read_float("q30_postdecon.txt")
		Int reads_postdecon_per_fastp = read_int("reads_postdecon_per_fastp.txt") # compare reads_postdecon_per_decon
		Int mean_r1_len_postdecon = read_int("mean_r1_len_postdecon.txt") 
		Int mean_r2_len_postdecon = read_int("mean_r2_len_postdecon.txt")
		
		# timers and debug information
		String error_code = read_string("ERROR.TXT")
		Int timer_a_mapFQ = read_int("timer_5_map_reads")
		Int timer_b_sort  = read_int("timer_6_sort")
		Int timer_c_dcnFQ = read_int("timer_7_rm_contam")
		Int timer_total   = read_int("timer_total")
		String docker_used = docker_image
		File? counts_out_tsv = sample_name + ".decontam.counts.tsv"      # should match $arg_counts_out
		File? fastp_report_1 = sample_name + "_first_fastp.json"
		File? fastp_report_2 = sample_name + "_second_fastp.json"
		
		# you probably don't want these...
		#File? mapped_to_decontam = glob("*.sam")[0]
	}	
}