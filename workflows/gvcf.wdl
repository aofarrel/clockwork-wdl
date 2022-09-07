version 1.0

#import "./tasks/gvcf_from_vcf.wdl" as gvcftask
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/main/tasks/gvcf_from_vcf.wdl" as gvcftask

workflow ClockworkGVCFConversion {
	input {
		File ref_fasta
		File minos_vcf
		File samtools_vcf
		String? outfile
		String? ref_fasta_in_tarball
	}

	call gvcftask.gvcf_from_minos_and_samtools {
		input:
			ref_fasta = ref_fasta,
			minos_vcf = minos_vcf,
			samtools_vcf = samtools_vcf,
			outfile = outfile,
			ref_fasta_in_tarball = ref_fasta_in_tarball
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}