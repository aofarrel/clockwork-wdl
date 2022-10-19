version 1.0

# ONLY USE FOR ONE SAMPLE AT A TIME
# (or scatter and change reads_files to nested array)

import "../tasks/variant_call_one_sample.wdl"

workflow DebugVarCall {
	input {
		File ref_dir
		Array[File] reads_files
	}

	call variant_call_one_sample.variant_call_one_sample {
		input:
			ref_dir = ref_dir,
			reads_files = reads_files
	}
}