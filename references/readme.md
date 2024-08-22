# Reference Genomes

I provide support for running clockwork-wdl on one of three reference genome collections. All of them use H37RV as the TB reference, but have different decontamination references.
* CDC-varpipe
* clockwork-v0.11.3
* clockwork-v0.12.5

Some parts of these reference genomes are very large, so md5 checksums are provided instead. Mirrors of these files are provided here: gs://ucsc-pathogen-genomics-public/tb/ref/


## CDC-varpipe
This reference genome is widely used by CDC-affiliated tuberculosis projects, such as my myco_raw pipeline and Thiagen's fork of TBProfiler. I sourced it from the CDC's varpipe repository: https://github.com/CDCgov/NCHHSTP-DTBE-Varpipe-WGS

Unfortunately, there are several issues with this decontamination reference:
* It seems to preform slightly worse at detecting NTM
* It seems to be missing human tongue contigs
* The metadata TSV doesn't distinguish between different types of contamination, so human/NTM/bacteria/viral DNA cannot be differenciated from each other
* The provenance is unknown
* The ref.fa file in [the Docker image](ghcr.io/cdcgov/varpipe_wgs_with_refs@sha256:2bc7234074bd53d9e92a1048b0485763cd9bbf6f4d12d5a1cc82bfec8ca7d75e) does not md5 match the ref.fa file you end up with via [build_references.sh](https://github.com/CDCgov/NCHHSTP-DTBE-Varpipe-WGS/commit/006e71aaa93b1dcd0c82bee35e573e08d792908b)

As such, I generally recommend people use either of the two clockwork references rather than this one. However, my preliminary testing (n=200 SRA samples) indicates that if your focus is calling variants and your TB data isn't low-quality, the differences in output will be minimal. My napkin estimate is that if you see a difference, it'll be in the realm of 1 or 2 SNPs -- but be aware that difference will increase if you filter out variants based on coverage, such as what myco_raw does when creating diff files to place on a phylogenetic tree.


## clockwork-v0.11.3
Created using 0.11.3 of clockwork reference_prepare.
* Uses hg38 for human

## clockwork-v0.12.5
Created using 0.12.5 of clockwork reference_prepare.
* Uses CHM13 for human