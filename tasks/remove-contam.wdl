version 1.0

#usage: clockwork remove_contam [options] <ref seq metadata tsv> <bam file> <counts outfile> <reads_out_1> #<reads_out_2>
#
#(SAM or BAM) -> paired FASTQ files split into OK, contaminated, and unmapped
#
#positional arguments:
#  metadata_tsv          Metadata TSV file. Format: one group of ref seqs per line. Tab-delimited columns: 1) group name; 2) 1|0 for is|is not contamination; 3+) sequence names.
#  bam_in                Name of input bam file
#  counts_out            Name of output file of read counts
#  reads_out_1           Name of output reads file 1
#  reads_out_2           Name of output reads file 2
#
#optional arguments:
#  -h, --help            show this help message and exit
#  --no_match_out_1 NO_MATCH_OUT_1
#                        Name of output file 1 of reads that did not match. If not given, reads are included in reads_out_1. Must be used with --no_match_out_2
#  --no_match_out_2 NO_MATCH_OUT_2
#                        Name of output file 2 of reads that did not match. If not given, reads are included in reads_out_2. Must be used with --no_match_out_1
#  --contam_out_1 CONTAM_OUT_1
#                        Name of output file 1 of contamination reads. If not given, reads are discarded. Must be used with --contam_out_2
#  --contam_out_2 CONTAM_OUT_2
#                        Name of output file 2 of contamination reads. If not given, reads are discarded. #Must be used with --contam_out_1
#  --done_file DONE_FILE#
#                        Write a file of the given name when the script is finished

task remove_contam {
	input {
		File metadata_tsv
		File bam_in # can also be a sam
		File counts_out
		File reads_out_1
		File reads_out_2

		String? dirnozip_tsv
		String? no_match_out_1
		String? no_match_out_2
		String? contam_out_1
		String? contam_out_2
		String? done_file
	}
	String arg_metadata_tsv = if(!defined(dirnozip_tsv)) then "~{dirnozip_tsv}/~{metadata_tsv}" else "~{metadata_tsv}"
	String arg_no_match_out_1 = if(!defined(no_match_out_1)) then "" else "--no_match_out_1 ~{no_match_out_1}"
	String arg_no_match_out_2 = if(!defined(no_match_out_2)) then "" else "--no_match_out_2 ~{no_match_out_2}"
	String arg_contam_out_1 = if(!defined(contam_out_1)) then "" else "--contam_out_1 ~{contam_out_1}"
	String arg_contam_out_2 = if(!defined(contam_out_1)) then "" else "--contam_out_2 ~{contam_out_2}"
	String arg_done_file = if(!defined(done_file)) then "" else "--done_file ~{done_file}"

	command <<<
	clockwork remove_contam ~{arg_metadata_tsv}
	>>>

	runtime {
		docker: "ashedpotatoes/iqbal-unofficial-clockwork-mirror:latest"
	}

	output {

	}
}