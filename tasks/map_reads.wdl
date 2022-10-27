version 1.0
# Important notes:
# A. This step is usually used not to map reads to the reference genome per say, but
#    for mapping to a decontamination reference in preparation for generating
#    decontaminated reads.
# B. The original clockwork function being replicated here would normally take in
#    a ref_fasta file and a ref_index file. But WDL 1.0 cannot pass around folders,
#    so we are anticipating this being given a tarball. This is how it works:
#       1. Take in the tarball + the basename of ref_fasta
#       2. Get the basename of the tarball without the .tar extension or preceding folders,
#          which tells us the basename of the dir we want in our workdir
#       3. Combine that dir basename with the filename of the fasta
#       4. Begin executing the actual task and localize the tarball
#       5. Move the tarball into the workdir and untar it
#       6. Actually run the task
#   Note that this task assumes the tarball is NOT gzip compressed.

task map_reads {
	input {
		String      sample_name
		File        tarball_ref_fasta_and_index
		String      ref_fasta_filename
		Array[File] reads_files
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
	
	# we need to mv it to the workdir, then untar, or else the ref index won't be found
	if [[ ! "~{tarball_ref_fasta_and_index}" = "" ]]
	then
		mv ~{tarball_ref_fasta_and_index} .
		tar -xvf ~{basestem_reference}.tar
	fi

	clockwork map_reads ~{arg_unsorted_sam} ~{arg_threads} ~{sample_name} ~{arg_ref_fasta} ~{outfile} ~{sep=" " reads_files}

	ls -lhaR > workdir.txt
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + finalDiskSize + " SSD"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		File mapped_reads = glob("*.sam")[0]
		File debug_workdir = "workdir.txt"
	}
}
