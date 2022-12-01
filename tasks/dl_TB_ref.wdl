version 1.0

# Note: It is possible a temporary outage/hiccup can cause this task to fail, so it's
# a good idea to set retries >= 2 just in case. If this task fails unexpectedly, check
# stderr (not the log Terra shows you by default!) and look for a wget error.

task download_tb_reference_files {
	input {
		String outdir = "Ref.download"

		# runtime attributes
		Int disk = 100
		Int cpu = 4
		Int retries = 2
		Int memory = 8
		Int preempt = 2
	}
	
	parameter_meta {
		outdir: "Output directory. Default: Ref.download (becomes Ref.download.tar)"
	}

	command <<<
	/clockwork/scripts/download_tb_reference_files.pl ~{outdir}
	tar -c ~{outdir}/ > ~{outdir}.tar
	ls -lhaR > workdir.txt
	>>>

	runtime {
		cpu: cpu
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:v0.11.3"
		disks: "local-disk " + disk + " SSD"
		maxRetries: "${retries}"
		memory: "${memory} GB"
		preemptible: "${preempt}"
	}

	output {
		File   tar_tb_ref_raw = "~{outdir}.tar"
		File   debug_workdir = "workdir.txt"
	}
}