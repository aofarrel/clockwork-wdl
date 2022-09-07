version 1.0

task gvcf_from_minos_and_samtools {
	input {
		File ref_fasta
		File minos_vcf
		File samtools_vcf
		String outfile = "output.gvcf"

		# If ref_fasta is actually a tarball, define this value with the name
		# of the actual reference fasta file within that directory
		String ref_fasta_filename = "ref.fa"

		# runtime attributes
		Int addldisk = 100
		Int cpu = 4
		Int memory = 8
		Int preempt = 2
	}
	String basename_reference = basename(ref_fasta)
	String basetarr_reference = basename(ref_fasta, ".tar")
	String arg_ref_fasta = if(basename_reference != basetarr_reference) then "~{basetarr_reference}/~{ref_fasta_filename}" else "~{basetarr_reference}"

	# estimate disk size
	Int finalDiskSize = ceil(size(ref_fasta, "GB")) + 
						3*ceil(size(minos_vcf, "GB")) + 
						3*ceil(size(samtools_vcf, "GB")) +
						addldisk

	command <<<
	set -eux -o pipefail

	echo "~{basename_reference}"
	echo "~{basetarr_reference}"
	echo "~{ref_fasta_filename}"
	echo "~{arg_ref_fasta}"

	if [[ ! "~{basename_reference}" = "~{basetarr_reference}" ]]
	then
		cp ~{ref_fasta} .
		tar -xvf ~{basetarr_reference}.tar
	fi

	clockwork gvcf_from_minos_and_samtools ~{arg_ref_fasta} ~{minos_vcf} ~{samtools_vcf} ~{outfile}

	ls -lhaR > workdir.txt
	>>>

	parameter_meta {
		ref_fasta: "Reference genome FASTA file, or a tarball directory containing said FASTA file. If tarball, also define ref_fasta_filename."
		minos_vcf: "VCF file made by minos to turn into gVCF."
		samtools_vcf: "VCF file made by samtools to turn into gVCF."
		outfile: "String used in the output gVCF name. Default: output"
		ref_fasta_filename: "If ref_fasta is tarball, this string is used to find the actual FASTA file after untaring. Do not include leading folders. Ex: If ref_fasta = foo.tar, and foo.tar contains buzz.fa and buzz.fai, then set ref_fasta_filename to buzz.fa. Default: ref.fa"
	}

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + finalDiskSize + " HDD"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		File gvcf = outfile
		File debug_workdir = "workdir.txt"
	}

}
