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

task map_reads {
	input {
		String      sample_name
		Array[File] reads_files
		Boolean     unsorted_sam = false
		Int         threads = 1

		# usually, what you're passing in is the decontamination reference
		File?    DIRZIPPD_reference
		String? FILENAME_reference

		File ref_fasta
		File tsv

		# runtime attributes
		Int addldisk = 100
		Int cpu = 4
		Int memory = 8
		Int preempt = 2
	}
	String outfile = "~{sample_name}.sam" # hardcoded for now
	String arg_ref_fasta = basename(ref_fasta)
	

	# TODO: properly support threads

	# estimate disk size
	Int finalDiskSize = ceil(size(reads_files, "GB")) + 2*ceil(size(ref_fasta, "GB")) + addldisk

	command <<<
	set -eux -o pipefail

	clockwork map_reads ~{sample_name} ~{arg_ref_fasta} ~{outfile} ~{sep=" " reads_files}

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
