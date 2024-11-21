#! /usr/local/bin/bash
# ^ on Mac OS, this points to homebrew-installed bash 5.2 (if it exists) instead of /bin/bash which is v3
#
# This file is a test file for debugging file permissions, which can be an issue with some WDL executors or rootless Docker.

# cleanup previous runs
rm ~{sample_name}_cat_R1.fq
rm ~{sample_name}_cat_R2.fq
rm ./*.fq
rm ./*.fastq

# set up test files
READS_FILES_RAW=('testing/BIOSAMP_ERR1_1.fastq' 'testing/BIOSAMP_ERR1_2.fastq' 'testing/BIOSAMP_ERR2_1.fastq' 'testing/BIOSAMP_ERR2_2.fastq' 'testing/STRING_L001_R1_001.fq' 'testing/STRING_L002_R1_001.fq' 'testing/STRING_L001_R2_001.fq' 'testing/STRING_L002_R2_001.fq')
for test_file in "${READS_FILES_RAW[@]}"; do touch "$test_file"; done

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
	
	fx_echo_array "Inputs as passed in:" "${READS_FILES_RAW[@]}"
	for fq in "${READS_FILES_RAW[@]}"; do mv "$fq" .; done 
	# I really did try to make these next three lines just one -iregex string but
	# kept messing up the syntax -- this approach is unsatisfying but cleaner
	readarray -d '' -t FQ < <(find . -iname "*.fq*" -print0) 
	readarray -d '' FASTQ < <(find . -iname "*.fastq*" -print0)
	readarray -d ' ' -t READS_FILES_UNSORTED < <(echo "${FQ[@]}" "${FASTQ[@]}")
	fx_echo_array "Located files:" "${READS_FILES_UNSORTED[@]}"
	READS_FILES=( $(fx_sort_array "${READS_FILES_UNSORTED[@]}") ) # this appears to be more consistent than mapfile
	fx_echo_array "In workdir and sorted:" "${READS_FILES[@]}"
	
	if (( "${#READS_FILES[@]}" != 2 ))
	then
		# check for gzipped inputs
		some_base=$(basename -- "${READS_FILES[0]}") # just check the first element; should never be a mix of gzipped and not-gzipped fqs
		some_extension="${some_base##*.}"
		if [[ $some_extension = ".gz" ]]
		then
			apt-get install -y pigz # since we are decompressing, this will not be a huge performance increase
			for fq in "${READS_FILES[@]}"; do pigz -d "$fq"; done
			# TODO: check that .gz originals got deleted to avoid issues with find
			readarray -d '' FQ < <(find . -iname "*.fq*" -print0) 
			readarray -d '' FASTQ < <(find . -iname "*.fastq*" -print0)
			readarray -d ' ' READS_FILES_UNZIPPED_UNSORTED < <(echo "${FQ[@]}" "${FASTQ[@]}") 
			READS_FILES=( $(fx_sort_array "${READS_FILES_UNZIPPED_UNSORTED[@]}") )  # this appears to be more consistent than mapfile
			fx_echo_array "After decompressing:" "${READS_FILES[@]}"
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




# cleanup
#rm ./*.fq
#rm ./*.gz
exit



