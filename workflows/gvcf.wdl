version 1.0

#import "./tasks/gvcf.wdl" as gvcftask
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/add-gvcf/tasks/gvcf.wdl" as gvcftask

workflow ClockworkGVCFConversion {
	input {
		File ref_fasta
		File minos_vcf
		File samtools_vcf
		String? outfile
		String? ref_fasta_filename
	}

	call gvcftask.gvcf_from_minos_and_samtools {
		input:
			ref_fasta = ref_fasta,
			minos_vcf = minos_vcf,
			samtools_vcf = samtools_vcf,
			outfile = outfile,
			ref_fasta_filename = ref_fasta_filename
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}