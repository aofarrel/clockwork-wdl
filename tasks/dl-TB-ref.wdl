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
	String strg_dirnozip_outdir_taskin = "Ref.download" # hardcoded for now

	command <<<
	/clockwork/scripts/download_tb_reference_files.pl ~{strg_dirnozip_outdir_taskin}

	ls -lhaR > workdir.txt

	zip -r ~{strg_dirnozip_outdir_taskin}.zip ~{strg_dirnozip_outdir_taskin}
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
		String strg_dirnozip_tbref_taskout = "~{strg_dirnozip_outdir_taskin}"
		File   file_dirzippd_tbref_taskout = "~{strg_dirnozip_outdir_taskin}.zip"
		File   debug_workdir = "workdir.txt"
	}
}