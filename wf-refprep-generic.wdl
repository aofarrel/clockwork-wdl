version 1.0
import "./tasks/refprep.wdl"

workflow ClockworkRefPrepGeneric {
	input {
		File? genome
	}

	call refprep.reference_prepare {
		input:
			ref_file = genome,
			strg_dirnozip_outdir_taskin = "ref_dir"
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}