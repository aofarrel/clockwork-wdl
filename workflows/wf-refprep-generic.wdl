version 1.0
import "./tasks/refprep.wdl"

workflow ClockworkRefPrepGeneric {
	input {
		File? genome
	}

	call refprep.reference_prepare {
		input:
			ref_file = genome
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}