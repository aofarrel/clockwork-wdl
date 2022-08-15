version 1.0
# The original clockwork function being replicated here would normally take in
# a ref_fasta file and a ref_index file. But WDL 1.0 cannot pass around directories,
# so we are anticipating this being given a zipped directory. As such, instead
# of having a directory containing ref_fasta in our workdir and having the ref_fasta
# argument tell us exactly where ref_fasta is located, we have to instead:
# 1. Take in the zipped directory + the basename of ref_fasta
# 2. Get the basename of the zipped dir without the .zip extension or preceding folders,
#    which tells us the basename of the dir we want in our workdir
# 3. Combine that dir basename with the filename of the fasta
# 4. Begin executing the actual task and localize the zipped dir
# 5. Copy the zipped dir into the workdir
# 6. Unzip the workdir copy
# 7. Actually run the task

# TODO: Double check help output of `clockwork map_reads` and ensure we don't need ref_index

task map_reads {
	input {
		String sample_name
		Array[File] reads_files
		Boolean unsorted_sam = false
		Int threads = 1

		# usually, what you're passing in is the decomination reference
		File optionB__ref_folder_zipped
		String? optionB__ref_filename

		# runtime attributes
		Int disk = 100
		Int cpu = 4
		Int memory = 8
		Int preempt = 2
	}
	String outfile = "~{sample_name}.sam" # hardcoded for now
	String basename_zip = basename(optionB__ref_folder_zipped)
	String basename_zip_noext = sub(basename_zip, "\.zip(?!.{5,})", "")  # TODO: double check the regex
	String arg_unsorted_sam = if unsorted_sam == true then "--unsorted_sam" else ""
	String arg_ref_fasta = "~{basename_zip_noext}/~{optionB__ref_filename}"

	# TODO: support threads

	command <<<
	set -eux -o pipefail

	echo "optionB__ref_folder_zipped" ~{optionB__ref_folder_zipped}
	echo "optionB__ref_filename" ~{optionB__ref_filename}
	echo "basename_zip" ~{basename_zip}
	echo "sample_name" ~{sample_name}
	echo "outfile" ~{outfile}
	echo "arg_unsorted_sam" ~{arg_unsorted_sam}
	echo "arg_ref_fasta" ~{arg_ref_fasta}

	# on local tests we can get away with not doing this + not passing in fastq basenames
	# still need to ensure Terra-Cromwell localization doesn't require this 
	#FASTQ_FILES=(~{sep=" " reads_files})
	#for FASTQ_FILE in ${FASTQ_FILES[@]};
	#do
	#	cp ${FASTQ_FILE} .
	#done

	if [[ ! "~{optionB__ref_folder_zipped}" = "" ]]
	then
		cp ~{optionB__ref_folder_zipped} .
		unzip ~{basename_zip}
	fi

	clockwork map_reads ~{arg_unsorted_sam} ~{sample_name} ~{arg_ref_fasta} ~{outfile} ~{sep=" " reads_files}
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + disk + " HDD"
		memory: "${memory} GB"
		preemptibles: "${preempt}"
	}

	output {
		File mapped_reads = glob("*.sam")[0]
	}
}
