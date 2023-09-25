version 1.0
import "../tasks/ref_prep.wdl"

workflow Clockworkref_prepGeneric {
	input {
		File? fasta_file
	}

	call ref_prep.reference_prepare_byob {
		input:
			fasta_file = fasta_file,
			outdir = "output_reference"
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}