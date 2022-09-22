version 1.0
# The original clockwork function being replicated here would normally take in
# a ref_fasta file and a ref_index file. But WDL 1.0 cannot pass around directories,
# so we are anticipating this being given a tar directory. As such, instead
# of having a directory containing ref_fasta in our workdir and having the ref_fasta
# argument tell us exactly where ref_fasta is located, we have to instead:
# 1. Take in the tar directory + the basename of ref_fasta
# 2. Get the basename of the zipped dir without the .tar extension or preceding folders,
#    which tells us the basename of the dir we want in our workdir
# 3. Combine that dir basename with the filename of the fasta
# 4. Begin executing the actual task and localize the zipped dir
# 5. Copy the tar dir into the workdir
# 6. Untar the workdir copy
# 7. Actually run the task

task map_reads_combined_array {
	input {
		# This task is the same as map_reads_classic, except that there is no
		# sample_name variable and the Array[File] contains not only reads but
		# also a bogus file that tells us the sample name. This might be more
		# robust then relying on a dot-product scatter. The sample file is expected
		# to be called "sample.txt" and to have the name of the sample as its contents.

		Array[File] reads_and_sample

		File        tarball_ref_fasta_and_index
		String      ref_fasta_filename
		String      outfile      = "~{sample_name}.sam"
		Boolean     unsorted_sam = false
		Int?        threads

		# runtime attributes
		Int addldisk = 100
		Int cpu = 4
		Int memory = 8
		Int preempt = 2
	}
	String basestem_reference = sub(basename(tarball_ref_fasta_and_index), "\.tar(?!.{5,})", "")  # TODO: double check the regex
	String arg_unsorted_sam = if unsorted_sam == true then "--unsorted_sam" else ""
	String arg_ref_fasta = "~{basestem_reference}/~{ref_fasta_filename}"
	String arg_threads = if defined(threads) then "--threads {threads}" else ""

	# estimate disk size
	Int finalDiskSize = ceil(size(reads_and_sample, "GB")) + 2*ceil(size(tarball_ref_fasta_and_index, "GB")) + addldisk

	command <<<
	set -eux -o pipefail

	# This Python section is a little ridiculous, but it allows us to avoid having to do
	# more duplications to the workdir.
	python CODE <<
	py_reads_and_sample = ['~{sep="','" reads_and_sample}']
	target = ""
	for word in py_reads_and_sample:
		if "sample.txt" in word:
			target = word
	if target == "":
		print("ERROR - sample name not found. Make sure to write sample name in a file named sample.txt")
		exit(1)
	else:
		with open(word, "r"):
			sample = readline(word)
		# TODO: Write a file whose name is the sample


	CODE

	py_reads_and_sample = ["foo/bar/bizz.fq", "foo/bar/bizzR1.fq", "foo/bar/sample.txt", "foo/bar/bizzR2.Rq"]

	# might be useful when porting to non-Terra filesystems
	echo "tarball_ref_fasta_and_index" ~{tarball_ref_fasta_and_index}
	echo "ref_fasta_filename" ~{ref_fasta_filename}
	echo "basestem_reference" ~{basestem_reference}
	echo "outfile" ~{outfile}
	echo "arg_ref_fasta" ~{arg_ref_fasta}
	
	# we need to copy it to the workdir, then untar the copy, or else the ref index won't be found
	if [[ ! "~{tarball_ref_fasta_and_index}" = "" ]]
	then
		cp ~{tarball_ref_fasta_and_index} .
		tar -xvf ~{basestem_reference}.tar
	fi

	clockwork map_reads ~{arg_unsorted_sam} ~{arg_threads} ~{sample_name} ~{arg_ref_fasta} ~{outfile} ~{sep=" " reads_files}

	ls -lhaR > workdir.txt
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + finalDiskSize + " HDD"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		File mapped_reads = glob("*.sam")[0]
		File debug_workdir = "workdir.txt"
	}
}

task map_reads_classic {
	input {
		String      sample_name
		Array[File] reads_files

		File        tarball_ref_fasta_and_index
		String      ref_fasta_filename
		String      outfile      = "~{sample_name}.sam"
		Boolean     unsorted_sam = false
		Int?        threads

		# runtime attributes
		Int addldisk = 100
		Int cpu = 4
		Int memory = 8
		Int preempt = 2
	}
	String basestem_reference = sub(basename(tarball_ref_fasta_and_index), "\.tar(?!.{5,})", "")  # TODO: double check the regex
	String arg_unsorted_sam = if unsorted_sam == true then "--unsorted_sam" else ""
	String arg_ref_fasta = "~{basestem_reference}/~{ref_fasta_filename}"
	String arg_threads = if defined(threads) then "--threads {threads}" else ""

	# estimate disk size
	Int finalDiskSize = ceil(size(reads_files, "GB")) + 2*ceil(size(tarball_ref_fasta_and_index, "GB")) + addldisk

	command <<<
	set -eux -o pipefail

	# might be useful when porting to non-Terra filesystems
	echo "tarball_ref_fasta_and_index" ~{tarball_ref_fasta_and_index}
	echo "ref_fasta_filename" ~{ref_fasta_filename}
	echo "basestem_reference" ~{basestem_reference}
	echo "sample_name" ~{sample_name}
	echo "outfile" ~{outfile}
	echo "arg_ref_fasta" ~{arg_ref_fasta}
	
	# we need to copy it to the workdir, then untar the copy, or else the ref index won't be found
	if [[ ! "~{tarball_ref_fasta_and_index}" = "" ]]
	then
		cp ~{tarball_ref_fasta_and_index} .
		tar -xvf ~{basestem_reference}.tar
	fi

	clockwork map_reads ~{arg_unsorted_sam} ~{arg_threads} ~{sample_name} ~{arg_ref_fasta} ~{outfile} ~{sep=" " reads_files}

	ls -lhaR > workdir.txt
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + finalDiskSize + " HDD"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		File mapped_reads = glob("*.sam")[0]
		File debug_workdir = "workdir.txt"
	}
}
