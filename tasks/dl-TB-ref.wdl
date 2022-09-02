version 1.0

task download_tb_reference_files {
	input {
		String outdir = "Ref.download"

		# runtime attributes
		Int disk = 100
		Int cpu = 4
		Int retries = 1
		Int memory = 8
		Int preempt = 2
	}

	command <<<
	/clockwork/scripts/download_tb_reference_files.pl ~{outdir}
	tar cf - ~{outdir}/
	ls -lhaR > workdir.txt
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + disk + " HDD"
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		File   tar_tb_ref_raw = "~{outdir}.tar"
		File   debug_workdir = "workdir.txt"
	}
}