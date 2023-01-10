version 1.0

# These tasks combine the rm_contam and map_reads steps into one WDL task.
# This can save money on some backends.

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
		Int         subsample_cutoff = 450 # subsample if fastq > this value in MB
		Int         subsample_seed = 1965
		Int?        threads
		Boolean     unsorted_sam = false # it's recommend to keep this false
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
	}

	# calculate stuff for the map_reads call
	String read_file_basename = basename(reads_files[0]) # used to calculate sample name + outfile_sam
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
	Int readsSize = 5*ceil(size(reads_files, "GB"))
	Int finalDiskSize = refSize + readsSize + addldisk

	command <<<
	set -eux -o pipefail

	# this should handle the scenario where sample + run is passed, or just sample
	# eg, ERS457530_ERR551697_1.fastq and ERS457530_1.fastq
	basename="~{read_file_basename}"
	sample_name="${basename%%_*}"
	outfile_sam="$sample_name.sam"
	echo $sample_name > sample_name.txt # needed to pass sample_name to variant call task

	if [[ ! "~{verbose}" = "true" ]]
	then
		echo "tarball_ref_fasta_and_index" ~{tarball_ref_fasta_and_index}
		echo "ref_fasta_filename" ~{ref_fasta_filename}
		echo "basestem_reference" ~{basestem_reference}
		echo "sample_name $sample_name"
		echo "outfile_sam $outfile_sam"
		echo "arg_ref_fasta" ~{arg_ref_fasta}
	fi
	
	
	# we need to mv ref to the workdir, then untar, or else the ref index won't be found
	mv ~{tarball_ref_fasta_and_index} .
	tar -xvf ~{basestem_reference}.tar

	clockwork map_reads ~{arg_unsorted_sam} ~{arg_threads} $sample_name ~{arg_ref_fasta} $outfile_sam ~{sep=" " reads_files}

	echo "Reads mapped to decontamination reference."
	echo "*********************************************************************"
	if [[ "~{verbose}" = "true" ]]
	then
		ls -lhaR
	fi
	echo "*********************************************************************"

	# calculate the last three positional arguments of the rm_contam task
	if [[ ! "~{counts_out}" = "" ]]
	then
		arg_counts_out="~{counts_out}"
	else
		arg_counts_out="$sample_name.decontam.counts.tsv"
	fi

	arg_reads_out1="$sample_name.decontam_1.fq.gz"
	arg_reads_out2="$sample_name.decontam_2.fq.gz"

	# debug - this might not always be needed
	#samtools index $outfile_sam # TODO: check if no index file warning persists while testing sorted sam --> it does
	samtools sort -n $outfile_sam > sorted_by_read_name_$sample_name.sam

	clockwork remove_contam \
		~{arg_metadata_tsv} \
		sorted_by_read_name_$sample_name.sam \
		$arg_counts_out \
		$arg_reads_out1 \
		$arg_reads_out2 \
		~{arg_no_match_out_1} ~{arg_no_match_out_2} ~{arg_contam_out_1} ~{arg_contam_out_2} ~{arg_done_file}

	echo "Decontamination completed."
	echo "*********************************************************************"
	if [[ "~{verbose}" = "true" ]]
	then
		ls -lhaR
	fi
	echo "*********************************************************************"
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:v0.11.3"
		disks: "local-disk " + finalDiskSize + " SSD"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		File mapped_to_decontam = glob("*.sam")[0]
		File counts_out_tsv = glob("*counts.tsv")[0]
		File decontaminated_fastq_1 = glob("*decontam_1.fq.gz")[0]
		File decontaminated_fastq_2 = glob("*decontam_2.fq.gz")[0]
		String sample_name = read_string("sample_name.txt")
	}
}

task combined_decontamination_multiple {
	# This task should be considered deprecated. It's usually more expensive than 
	# decontaminating via a scattered task and it's more complicated. It also doesn't
	# support downsampling.
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
		echo "$sample_name\n" >> list_of_samples.txt
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
		tar -xvf $basename_ball.tar

		# the docker image uses bash v5 so we can use readarray to make an array easily
		declare -a read_files
		readarray -t read_files < <(find ./*.fastq)

		# map the reads
		outfile_sam="$sample_name.sam"
		clockwork map_reads ~{arg_unsorted_sam} ~{arg_threads} $sample_name ~{arg_ref_fasta} $outfile_sam "${read_files[@]}"
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
		mkdir $sample_name
		#mv "*.sam" /$sample_name
		#mv "*counts.tsv" /$sample_name
		mv $arg_reads_out1 ./$sample_name
		mv $arg_reads_out2 ./$sample_name
		tar -cf $sample_name.tar $sample_name
		rm -rf ./$sample_name
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