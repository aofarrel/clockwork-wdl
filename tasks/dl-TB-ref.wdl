version 1.0

task download_tb_reference_files {
	input {
		# runtime attributes
		Int disk = 100
		Int cpu = 4
		Int retries = 1
		Int memory = 8
		Int preempt = 2
	}
	String outdir = "Ref.download" # hardcoded for now

	command <<<
	/clockwork/scripts/download_tb_reference_files.pl ~{outdir}

	ls -lhaR > workdir.txt

	zip -r ~{outdir}.zip ~{outdir}
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
		disks: "local-disk " + disk + " HDD"
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptibles: "${preempt}"
	}

	output {
		String dl_dir = "~{outdir}"
		File   dl_zipped = "~{outdir}.zip"
		File   debug_workdir = "workdir.txt"
	}
}