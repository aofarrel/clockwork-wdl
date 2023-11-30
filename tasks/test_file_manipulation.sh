#! /usr/local/bin/bash
# ^ on Mac OS, this points to homebrew-installed bash 5.2 instead of /bin/bash which is v3

# set up test files
mkdir inputs
#READS_FILES_RAW=('inputs/BIOSAMP_SRA2_1.fq' 'inputs/BIOSAMP_SRA2_2.fq')
READS_FILES_RAW=('inputs/STRING_L001_R1_001.fq' 'inputs/STRING_L002_R1_001.fq' 'inputs/STRING_L001_R2_001.fq' 'inputs/STRING_L002_R2_001.fq')
for test_file in "${READS_FILES_RAW[@]}"; do touch "$test_file"; done


fx_echo_array () {
		sleep 0.5
		fq_array=("$@")
		for fq in "${fq_array[@]}"; do echo "$fq"; done
		printf "\n"
	}
	
	fx_move_to_workdir () { 
		fq_array=("$@")
		for fq in "${fq_array[@]}"; do mv "$fq" .; done 
	}
	
	fx_sort_array () {
		# this could break if there's a space in a filename
		fq_array=("$@")
		readarray -t OUTPUT < <(for fq in "${fq_array[@]}"; do echo "$fq"; done | sort)
		echo "${OUTPUT[@]}"
	}
	fx_echo_array "Inputs as passed in:" "${READS_FILES_RAW[@]}"
	fx_move_to_workdir "${READS_FILES_RAW[@]}"
	readarray -d '' READS_FILES_UNSORTED < <(find . -name "*.fq*" -print0)
	READS_FILES=( $(fx_sort_array "${READS_FILES_UNSORTED[@]}") )
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
			readarray -d '' READS_FILES_UNZIPPED_UNSORTED < <(find . -name "*.fq*" -print0)
			READS_FILES=( $(fx_sort_array "${READS_FILES_UNZIPPED_UNSORTED[@]}") )
			fx_echo_array "After decompressing:" "${READS_FILES[@]}"
		fi
	
		readarray -d '' READ1_LANES_UNSORTED < <(find . -name "*R1*" -print0)
		readarray -d '' READ2_LANES_UNSORTED < <(find . -name "*R2*" -print0)
		READ1_LANES=( $(fx_sort_array "${READ1_LANES_UNSORTED[@]}") )
		READ2_LANES=( $(fx_sort_array "${READ2_LANES_UNSORTED[@]}") )
		touch ~{sample_name}_cat_R1.fq
		touch ~{sample_name}_cat_R2.fq
		fx_echo_array "Read 1:" "${READ1_LANES[@]}"
		fx_echo_array "Read 2:" "${READ2_LANES[@]}"
		for fq in "${READ1_LANES[@]}"; do cat "$fq" ~{sample_name}_cat_R1.fq > ~{sample_name}_cat_R1.fq; done
		for fq in "${READ2_LANES[@]}"; do cat "$fq" ~{sample_name}_cat_R2.fq > ~{sample_name}_cat_R2.fq; done
	fi




# cleanup
rm -rf ./inputs/
rm ./*.fq
rm ./*.gz
exit



