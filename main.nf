#!/usr/bin/env nextflow
out_dir = file(params.outdir)

out_dir.mkdir()

//isoseq
Channel.fromPath("$params.isoseq/**/*.bam", type: 'file')
.buffer(size:1).into{bamiso,ibamiso}
//hifi reference
Channel.fromPath("$params.ref/*.bam", type: 'file')
.buffer(size:1).into{bamref,ibamref}
//hifi variants
Channel.fromPath("$params.hifi/**/*.bam", type: 'file')
.buffer(size:1).into{bamccs,ibamccs}
//hi-c reference
Channel.fromPath("$params.hic/**/*.fq.gz", type: 'file')
.buffer(size:2).set{hicref}

process pbbam {
	tag "pbbam.$x"

	input:
	file x from ibamiso.mix(ibamref,ibamccs)

	output:
	file "*.pbi" into pbi

	when:
	params.run == 'all' || params.run == 'pbbam'

	script:
	"""
	pbindex $x
	"""    
}

process bam2fastx {
	tag "bam2fastq.$x"

	input:
	file x from bamiso.mix(bamref,bamccs)

	output:
	file "*.fastq.gz" into i_fastqc, i_decontamination

	when:
	params.run == 'all' || params.run == 'bam2fastx'

	script:
	"""
    X=\$(echo 4W-MBC/ccs.bam | awk -v FS='/' '{print \$(NF-1)}')
	bam2fastq $x -o \$X
	"""
}

process fastqc {
    tag "fastqc.$x"

    input:
    file x from i_fastqc.mix(hicref)

    output:
    file "*_fastqc.{zip,html}" into fastqc

	when:
	params.run == 'all' || params.run == 'fastqc'

    script:
    """
    fastqc $x -t ${task.cpus} --noextract
    """
}

process multiqc {
    tag "multiqc.$x"

	input:
    tuple x, file('*') from fastqc.map { 
	if (it =~/.*ref.*/){  
		return ['ref', it]  
	}else if(it =~/.*hic.*/){ 
		return ['hic', it]  
	}else if(it =~/.*ccs.*/){ 
		return ['css', it]  
	}else if(it =~/.*iso.*/){ 
		return ['iso', it]  
	}  
	} 
	.groupTuple()

    output:
    file "multiqc_report.html" into multiqc

	when:
    params.run == 'all' || params.run == 'multiqc'

    script:
    """
    multiqc .
    """
}

process yiweiniu_decontamination {
	tag "canu.$x"

	input:
	file x from i_decontamination

	output:
    file "fastq" into all
	file "*$params.refname*" into ref_canu, ref_peregrine, ref_hifiasm, ref_flye, ref_pbipa, ref_nextdenovo, ref_pb_assembly

	when:
    params.run == 'all' || params.run == 'canu'

	script:
	"""
	canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
	"""
}

process canu {
	tag "canu.$x"

	input:
	file x from ref_canu

	output:
	file "*fasta" into canu, quast_canu, genomeqc_canu

	when:
    params.run == 'all' || params.run == 'canu'

	script:
	"""
	canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
	"""
}

process peregrine {
	tag "peregrine.$x"

    input:
    file x from ref_peregrine

    output:
    file "*fasta" into peregrine, quast_peregrine, genomeqc_peregrine

	when:
    params.run == 'all' || params.run == 'peregrine'

    script:
    """
    yes yes | python3 /data/korens/devel/Peregrine/bin/pg_run.py asm chm13.list 24 24 24 24 24 24 24 24 24 --with-consensus --shimmer-r 3 --best_n_ovlp 8 --output ./
    """
}

process hifiasm {
	tag "hifiasm.$x"

	input:
	file x from ref_hifiasm

	output:
	file "ref.asm" into hifiasm, quast_hifiasm, genomeqc_hifiasm

	when:
	params.run == 'all' || params.run == 'hifiasm'

	script:
	"""
	hifiasm -o ref.asm -t${task.cpus} $x
	"""
}

process pbipa {
	tag "pbipa.$x"

    input:
    file x from ref_pbipa

    output:
    file "ref.asm" into pbipa, quast_pbipa, genomeqc_pbipa

    when:
    params.run == 'all' || params.run == 'pbipa'

    script:
    """
    ipa local --nthreads ${task.cpus} --njobs 1 -i $x
    """
}

process flye {
	tag "flye.$x"

    input:
    file x from ref_flye

    output:
    file "ref.asm" into flye, quast_flye, genomeqc_flye

    when:
    params.run == 'all' || params.run == 'flye'

    script:
    """
	flye --pacbio-hifi $x -o large -t ${task.cpus} -g 1g -i 20
	flye --pacbio-hifi $x -o short -t ${task.cpus} -g 0.6g -i 20
    """
}

process nextdonovo {
	tag "nextdenovo.$x"
	
	input:
    file x from ref_nextdenovo

    output:
    file "ref.asm" into nextdenovo, quast_nextdenovo, genomeqc_nextdenovo

    when:
    params.run == 'all' || params.run == 'nextdenovo'

    script:
    """
	ls $x > input.fofn
	cp doc/run.cfg ./
	nextDenovo run.cfg
    """
}

process pb_assembly {
	tag "pb_assembly.$x"

    input:
    file x from ref_pb_assembly

    output:
    file "*fasta" into pb_assembly, quast_pb, genomeqc_pb

    when:
    params.run == 'all' || params.run == 'pb_assembly'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

canu.mix(peregrine,hifiasm,pbipa,flye,nextdenovo,pb_assembly)
.set{i_mummer}

process mummer {
	tag "mummer.$x"

    input:
    file x from i_mummer

    output:
    file "*fasta" into mummer

    when:
    params.run == 'all' || params.run == 'mummer'

    script:
    """
    nucmer --maxmatch --nosimplify delta-filter -i 98 -l 10000
    nucmer --maxmatch --noextend --nosimplify -l 500 -c 1000 delta-filter -i 99.9 -l 10000
    """
}

process transposonpsi {
    tag "transposonpsi.$x"

    input:
    file x from mummer

    output:
    file "*fasta" into transposonpsi

    when:
    params.run == 'all' || params.run == 'transposonpsi'

    script:
    """
    transposonPSI.pl $x nuc
    """
}

process tetools {
    tag "tetools.$x"

    input:
    file x from transposonpsi

    output:
    file "*fasta" into tetools

    when:
    params.run == 'all' || params.run == 'tetools'

    script:
    """
    BuildDatabase -name fog -engine ncbi $x
    RepeatModeler -database fog -engine ncbi -pa ${task.cpus} -LTRStruct
    RepeatMasker -lib fog-families.fa $x -pa ${task.cpus}
    """
}

process minimap2 {
    tag "mummer.$x"

    input:
    file x from tetools

    output:
    file "*fasta" into minimap2

    when:
    params.run == 'all' || params.run == 'mummer'

    script:
    """
    Quast.py --large --skip-unaligned-mis-contigs    
    """
}

process purge_dups {
	tag "purge_dups.$x"

    input:
    file x from minimap2

    output:
    file "*fasta" into purge_dups, quast_dups, genomeqc_dups

    when:
    params.run == 'all' || params.run == 'purge_dups'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

process racon {
	tag "racon.$x"

    input:
    file x from purge_dups

    output:
    file "*fasta" into racon, quast_racon, genomeqc_racon

    when:
    params.run == 'all' || params.run == 'racon'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

process nextpolish {
	tag "nextpolish.$x"

    input:
    file x from racon

    output:
    file "*fasta" into i_allhic, i_marginphase, i_falconphase, i_hirise, i_dipasm, quast_nextpolish, genomeqc_nextpolish

    when:
    params.run == 'all' || params.run == 'nextpolish'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

process allhic {
	tag "nextpolish.$x"

    input:
    file x from i_allhic

    output:
    file "*fasta" into allhic, mercury_allhic

    when:
    params.run == 'all' || params.run == 'allhic'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

process marginphase {
	tag "nextpolish.$x"

    input:
    file x from i_marginphase

    output:
    file "*fasta" into marginphase, mercury_marginphase

    when:
    params.run == 'all' || params.run == 'marginphase'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

process falconphase {
	tag "nextpolish.$x"

    input:
    file x from i_falconphase

    output:
    file "*fasta" into falconphase, mercury_falconphase

    when:
    params.run == 'all' || params.run == 'falconphase'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

process hirise {
	tag "nextpolish.$x"

    input:
    file x from i_hirise

    output:
    file "*fasta" into hirise, mercury_hirise

    when:
    params.run == 'all' || params.run == 'hirise'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

process dipasm {
	tag "nextpolish.$x"

    input:
    file x from i_dipasm

    output:
    file "*fasta" into dipasm, mercury_dipasm

    when:
    params.run == 'all' || params.run == 'hirise'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

allhic.mix(marginphase, falconphase, hirise, dipasm)
.into{ i_haplotypo; i_purge_haplotigs }

process haplotypo {
	tag "haplotypo.$x"

    input:
    file x from i_haplotypo

    output:
    file "*fasta" into haplotypo

    when:
    params.run == 'all' || params.run == 'hirise'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

process purge_haplotigs {
    tag "purge_haplotigs.$x"

    input:
    file x from i_purge_haplotigs

    output:
    file "*fasta" into final_ref, quast_purge_haplotigs, mercury_purge_haplotigs, genomeqc_purge_haplotigs, assembly_stats_purge_haplotigs

    when:
    params.run == 'all' || params.run == 'purge_haplotigs'

    script:
    """
    canu -assemble -p asm -d asm genomeSize=0.6g -pacbio-hifi $x
    """
}

process quast {
    tag "mummer.$x"

    input:
    file x from quast_canu.mix(quast_peregrine,quast_hifiasm,quast_pbipa,quast_flye,quast_nextdenovo,quast_pb,quast_dups,quast_racon,quast_nextpolish).collect()

    output:
    file "*fasta" into quast
    file "other" into squat

    when:
    params.run == 'all' || params.run == 'mummer'

    script:
    """
    Quast.py --large --skip-unaligned-mis-contigs    
    """
}

process icarus {
    tag "icarus.$x"

    input:
    file x from quast

    output:
    file "*fasta" into icarus

    when:
    params.run == 'all' || params.run == 'icarus'

    script:
    """
    Quast.py --large --skip-unaligned-mis-contigs    
    """
}

process genomeqc {
    tag "genomeqc.$x"

    input:
    file x from genomeqc_canu.mix(genomeqc_peregrine,genomeqc_hifiasm,genomeqc_pbipa,genomeqc_flye,genomeqc_nextdenovo,genomeqc_pb,genomeqc_dups,genomeqc_racon,genomeqc_nextpolish).collect()

    output:
    file "*fasta" into genomeqc

    when:
    params.run == 'all' || params.run == 'mummer'

    script:
    """
    Quast.py --large --skip-unaligned-mis-contigs    
    """
}

process merqury {
    tag "mummer.$x"

    input:
    file x from mercury_allhic.mix(mercury_marginphase,mercury_falconphase,mercury_hirise,mercury_dipasm).collect()

    output:
    file "*fasta" into merqury

    when:
    params.run == 'all' || params.run == 'mummer'

    script:
    """
    Quast.py --large --skip-unaligned-mis-contigs    
    """
}

process assembly_stats {
    tag "mummer.$x"

    input:
    file x from assembly_stats_purge_haplotigs

    output:
    file "*fasta" into assembly_stats

    when:
    params.run == 'all' || params.run == 'mummer'

    script:
    """
    Quast.py --large --skip-unaligned-mis-contigs    
    """
}

workflow.onComplete {
	println ( workflow.success ? """
        Pipeline execution summary
        ---------------------------
        Completed at: ${workflow.complete}
        Duration    : ${workflow.duration}
        Success     : ${workflow.success}
        workDir     : ${workflow.workDir}
        exit status : ${workflow.exitStatus}
        """ : """
        Failed: ${workflow.errorReport}
        exit status : ${workflow.exitStatus}
        """
 )
}