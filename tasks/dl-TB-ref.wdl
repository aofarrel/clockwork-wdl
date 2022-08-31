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
	String STRG_DIRNOZIP_outdir_TASKIN = "Ref.download" # hardcoded for now

	command <<<
	/clockwork/scripts/download_tb_reference_files.pl ~{STRG_DIRNOZIP_outdir_TASKIN}

	ls -lhaR > workdir.txt

	zip -r ~{STRG_DIRNOZIP_outdir_TASKIN}.zip ~{STRG_DIRNOZIP_outdir_TASKIN}
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
		File   FILE_DIRZIPPD_tbref_taskout = "~{STRG_DIRNOZIP_outdir_TASKIN}.zip"
		File   debug_workdir = "workdir.txt"
	}
}