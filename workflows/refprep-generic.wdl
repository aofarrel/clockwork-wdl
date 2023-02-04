version 1.0
import "../tasks/ref_prep.wdl"

workflow Clockworkref_prepGeneric {
	input {
		File? fasta_file
	}

	call ref_prep.reference_prepare {
		input:
			fasta_file = fasta_file
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}