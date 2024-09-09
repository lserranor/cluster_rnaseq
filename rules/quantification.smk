def featurecounts_args(sample):
    pars = ""
    if single_end == False:
        pars = "-p"
    return pars


## Deal with aligned reads that will be used for quantification.
if UMIs:
    aligned_reads = f"{OUTDIR}/dedup/alignments/{{sample}}/{{sample}}.bam"
else:
    aligned_reads = f"{OUTDIR}/mapped/{chosen_aligner}/{{sample}}/Aligned.sortedByCoord.out.bam"


## Let stablish rule order whether data is single end or paired end for deduplication,
## when reads contain UMIs.
if single_end:
    ruleorder: umi_dedup_single_end > umi_dedup_paired_end
else:
    ruleorder: umi_dedup_paired_end > umi_dedup_single_end


###  BAM INDEXING ###
rule bam_indexing:
    input:
        aligned=f"{OUTDIR}/mapped/{chosen_aligner}/{{sample}}/Aligned.sortedByCoord.out.bam"
    output:
        bai_index=f"{OUTDIR}/mapped/{chosen_aligner}/{{sample}}/Aligned.sortedByCoord.out.bam.bai"
    log:
        f"{LOGDIR}/bam_indexing/{{sample}}.log"
    threads:
        get_resource("bam_indexing", "threads")
    resources:
        mem_mb=get_resource('bam_indexing', 'mem_mb'),
        runtime=get_resource('bam_indexing', 'runtime')
    conda:
        '../envs/aligners.yaml'
    shell:
        'samtools index -@ {threads} {input.aligned}'


### DEDUPLICATION OF READS WITH UMIs AND MAPPING COORDINATES ###
rule umi_dedup_single_end: 
    input:
        bam=f"{OUTDIR}/mapped/{chosen_aligner}/{{sample}}/Aligned.sortedByCoord.out.bam",
        bai_index=f"{OUTDIR}/mapped/{chosen_aligner}/{{sample}}/Aligned.sortedByCoord.out.bam.bai"
    output:
        dedup=f"{OUTDIR}/dedup/alignments/{{sample}}/{{sample}}.bam"
    conda:
        "../envs/umi-tools.yaml"
    threads:
        get_resource('umi_dedup_single_end', 'threads')
    resources:
        mem_mb=get_resource('umi_dedup_single_end', 'mem_mb'),
        walltime=get_resource('umi_dedup_single_end', 'walltime')
    params:
        stats=f"{OUTDIR}/dedup/alignments/{{sample}}/{{sample}}"
    log:
        f"{LOGDIR}/dedup/{{sample}}/{{sample}}.log"
    shell:"""
    umi_tools dedup -I {input.bam} --log={log} -S {output.dedup} --output-stats={params.stats} \
    --method=unique --multimapping-detection-method=NH
    """

rule umi_dedup_paired_end: 
    input:
        bam=f"{OUTDIR}/mapped/{chosen_aligner}/{{sample}}/Aligned.sortedByCoord.out.bam",
        bai_index=f"{OUTDIR}/mapped/{chosen_aligner}/{{sample}}/Aligned.sortedByCoord.out.bam.bai"
    output:
        dedup=f"{OUTDIR}/dedup/alignments/{{sample}}/{{sample}}.bam"
    conda:
        "../envs/umi-tools.yaml"
    threads:
        get_resource('umi_dedup_paired_end', 'threads')
    resources:
        mem_mb=get_resource('umi_dedup_paired_end', 'mem_mb'),
        walltime=get_resource('umi_dedup_paired_end', 'walltime')
    params:
        stats=f"{OUTDIR}/dedup/alignments/{{sample}}/{{sample}}"
    log:
        f"{LOGDIR}/dedup/{{sample}}/{{sample}}.log"
    shell:"""
    umi_tools dedup -I {input.bam} --log={log} -S {output.dedup} --output-stats={params.stats} \
    --method=unique --multimapping-detection-method=NH
    """

### BAM INDEXING OF DEDUPLICATED ALIGNMENTS ###
rule dedup_bam_indexing:
    input:
        aligned_dedup=f"{OUTDIR}/dedup/alignments/{{sample}}/{{sample}}.bam"
    output:
        bai_index=f"{OUTDIR}/dedup/alignments/{{sample}}/{{sample}}.bam.bai"
    log:
        f"{LOGDIR}/dedup_bam_indexing/{{sample}}.log"
    threads:
        get_resource("bam_indexing", "threads")
    resources:
        mem_mb=get_resource('bam_indexing', 'mem_mb'),
        walltime=get_resource('bam_indexing', 'walltime')
    conda:
        '../envs/aligners.yaml'
    shell:
        'samtools index -@ {threads} {input.aligned}'


### HTSEQ COUNT ###
rule htseq_count:
    input:
        bam_file=aligned_reads,
        bai_index=aligned_reads + "bai"
    output:
        quant=f"{OUTDIR}/quant/{chosen_aligner}/htseq/{{sample}}.tab"
    threads:
        get_resource('htseq_count', 'threads')
    resources:
        mem_mb=get_resource('htseq_count', 'mem_mb'),
        runtime=get_resource('htseq_count', 'runtime')
    params:
        annotation= lambda x: config['ref'][chosen_aligner]['annotation'] if chosen_aligner != 'salmon' else '',
        extra=config['parameters']['htseq-count']['extra'],
        mode = config['parameters']['htseq-count']['mode'],
        strandedness = config['parameters']['htseq-count']['strandedness']
    log:
        f"{LOGDIR}/htseq_count/{{sample}}.log"
    conda:
        '../envs/cuantification.yaml'
    shell: 'htseq-count -f bam -r pos {params.extra} {params.mode} {params.strandedness} {input.bam_file} {params.annotation} > {output.quant} 2> {log}'


rule htseq_count_matrix:
    input:
        quant=expand(f"{OUTDIR}/quant/{chosen_aligner}/htseq/{{sample}}.tab", \
                     sample=samples['sample'])
    output:
        counts=f"{OUTDIR}/deseq2/{chosen_aligner}/htseq/counts.tsv"
    threads:
        get_resource("htseq_count_matrix", "threads")
    resources:
        mem_mb=get_resource("htseq_count_matrix", "mem_mb"),
        runtime=get_resource("htseq_count_matrix", "runtime")
    log: f"{LOGDIR}/deseq2/{chosen_aligner}/htseq_count_matrix.log"
    conda:
        '../envs/deseq2.yaml'
    script:
        "../scripts/htseq_count_matrix.R"


### FEATURECOUNTS ###
rule featurecounts:
    input:
        bam_file= aligned_reads
    output:
        quant=f"{OUTDIR}/quant/{chosen_aligner}/featureCounts/{{sample}}.tab",
        quant_summary=f"{OUTDIR}/quant/{chosen_aligner}/featureCounts/{{sample}}.tab.summary"
    threads:
        get_resource('featureCounts', 'threads')
    resources:
        mem_mb=get_resource('featureCounts', 'mem_mb'),
        runtime=get_resource('featureCounts', 'runtime')
    params:
        args= lambda wc: featurecounts_args(wc.sample),
        extra= config['parameters']['featureCounts']['extra'],
        annotation= lambda x: config['ref'][chosen_aligner]['annotation'] if chosen_aligner != 'salmon' else '',
        strandedness = config['parameters']['featureCounts']['strandedness']
    log:
        f"{LOGDIR}/featureCounts/{{sample}}.log"
    conda:
        '../envs/cuantification.yaml'
    shell: 'featureCounts {params.args} -T {threads} {params.extra} {params.strandedness} -a {params.annotation} -o {output.quant} {input.bam_file} &> {log}'


rule fcounts_count_matrix:
    input:
        expand(f"{OUTDIR}/quant/{chosen_aligner}/featureCounts/{{sample}}.tab", sample=samples['sample'])
    output:
        counts=f"{OUTDIR}/deseq2/{chosen_aligner}/featureCounts/counts.tsv"
    threads:
        get_resource('fcounts_count_matrix', 'threads')
    resources:
        mem_mb=get_resource('fcounts_count_matrix', 'mem_mb'),
        runtime=get_resource('fcounts_count_matrix', 'runtime')
    params:
        samples=config['samples'],
    script:
        "../scripts/fcounts_count_matrix.py"


### SALMON MATRIX ###
rule salmon_matrix_from_quants:
    input:
        quants = expand(f"{OUTDIR}/quant/salmon/{{sample}}/quant.sf",  sample=samples['sample'])
    output:
        gene_level_matrix    = f"{OUTDIR}/deseq2/salmon/counts.tsv",
        transcript_estimates = f"{OUTDIR}/deseq2/salmon/transcript_level_estimates.rds",
        metadata_cache      = temp(directory(f"{OUTDIR}/quant/salmon/metadata_cache"))

    threads:  
        get_resource('salmon_matrix_from_quants', 'threads')
    resources:
        mem_mb=get_resource('salmon_matrix_from_quants', 'mem_mb'),
        runtime=get_resource('salmon_matrix_from_quants', 'runtime')
    params:
        salmon_quant_directory = f"{OUTDIR}/quant/salmon",
        samples                  = config['samples']
    log:
        f"{LOGDIR}/salmon_matrix_from_quants.log"
    conda:
        '../envs/cuantification.yaml'
    script:
        '../scripts/salmon_matrix_from_quant.R'
