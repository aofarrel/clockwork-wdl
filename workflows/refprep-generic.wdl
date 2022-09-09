version 1.0
import "./tasks/ref_prep.wdl"

workflow Clockworkref_prepGeneric {
	input {
		File? genome
	}

	call ref_prep.reference_prepare {
		input:
			ref_file = genome
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}