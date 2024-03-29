version 1.0

task adapt {

    input {
        Int? taxid
        String? ref_accs
        Array[File]? fasta
        Boolean unaligned_fasta = false

        String obj
        String segment = 'None'
        Int gl = 28
        Int pl = 30
        Int pm = 3
        Float pp = 0.98
        Float primer_gc_lo = 0.35
        Float primer_gc_hi = 0.65
        Float objfnweights_a = 0.5
        Float objfnweights_b = 0.25
        Int bestntargets = 10
        Float cluster_threshold = 0.3
        Int max_primers_at_site = 10
        Int max_target_length = 250

        Array[File]? specificity_fasta
        File? specificity_taxa
        Int idm = 4
        Float idfrac = 0.01

        Int gm = 3
        Float gp = 0.98

        Int soft_guide_constraint = 1
        Int hard_guide_constraint = 5
        Float penalty_strength = 0.25
        String maximization_algorithm = 'random-greedy'

        String? require_flanking3
        String? require_flanking5
        String? bucket

        Int? rand_sample
        Int? rand_seed

        Boolean write_aln = false

        String image = "quay.io/broadinstitute/adaptcloud"
        String queueArn
        String memory = "2GB"
    }

    Boolean fasta_cmd = defined(fasta)
    String args_in = if fasta_cmd then "-o guides" else "~{taxid} ~{segment} guides --mafft-path $MAFFT_PATH --cluster-threshold ~{cluster_threshold} --write-annotation annotation"
    String args_base = " -gl ~{gl} -pl ~{pl} -pm ~{pm} -pp ~{pp} --primer-gc-content-bounds ~{primer_gc_lo} ~{primer_gc_hi} --max-primers-at-site ~{max_primers_at_site} --max-target-length ~{max_target_length} --obj-fn-weights ~{objfnweights_a} ~{objfnweights_b} --best-n-targets ~{bestntargets} --predict-cas13a-activity-model"
    Boolean sp_taxa = defined(specificity_taxa)
    Boolean sp_fasta = defined(specificity_fasta)
    String args_specificity = if (sp_taxa || sp_fasta) then " --id-m ~{idm} --id-frac ~{idfrac} --id-method shard" else ""
    String args_obj = if "~{obj}" == "minimize-guides" then " --obj minimize-guides -gm ~{gm} -gp ~{gp}" else if "~{obj}" == "maximize-activity" then " --obj ~{obj} --soft-guide-constraint ~{soft_guide_constraint} --hard-guide-constraint ~{hard_guide_constraint} --penalty-strength ~{penalty_strength} --maximization-algorithm ~{maximization_algorithm}" else ""
    String args_flank3 = if defined(require_flanking3) then " --require-flanking3 ~{require_flanking3}" else ""
    String args_flank5 = if defined(require_flanking5) then " --require-flanking5 ~{require_flanking5}" else ""
    String args_influenza = if "~{taxid}" == "11320" || "~{taxid}" == "11520" || "~{taxid}" == "11552"  then " --prep-influenza" else ""
    String args_refs = if defined(ref_accs) then " --ref-accs ~{ref_accs}" else ""
    String args_memo = if defined(bucket) then " --prep-memoize-dir s3://~{bucket}/memo" else ""
    String args_rand = if defined(rand_sample) then " --sample-seqs ~{rand_sample}" else ""
    String args_seed = if defined(rand_seed) then " --seed ~{rand_seed}" else ""
    String args_aln = if (write_aln && !(fasta_cmd && !unaligned_fasta)) then " --write-input-aln alignment" else ""
    String args_unaligned = if (fasta_cmd && unaligned_fasta) then " --unaligned --mafft-path $MAFFT_PATH" else ""
    String args = "~{args_in}~{args_base}~{args_specificity}~{args_obj}~{args_flank3}~{args_flank5}~{args_influenza}~{args_refs}~{args_memo}~{args_rand}~{args_seed}~{args_aln}~{args_unaligned}"

    command <<<
        if ~{fasta_cmd}
        then
            if ~{sp_taxa}
            then
                if ~{sp_fasta}
                then
                    design.py complete-targets fasta ~{sep=" " fasta} ~{args} --specific-against-taxa ~{specificity_taxa} --specific-against-fasta ~{sep=" " specificity_fasta}
                else
                    design.py complete-targets fasta ~{sep=" " fasta} ~{args} --specific-against-taxa ~{specificity_taxa}
                fi
            else
                if ~{sp_fasta}
                then
                    design.py complete-targets fasta ~{sep=" " fasta} ~{args} --specific-against-fasta ~{sep=" " specificity_fasta}
                else
                    design.py complete-targets fasta ~{sep=" " fasta} ~{args}
                fi
            fi
        else
            if ~{sp_taxa}
            then
                if ~{sp_fasta}
                then
                    design.py complete-targets auto-from-args ~{args} --specific-against-taxa ~{specificity_taxa} --specific-against-fasta ~{sep=" " specificity_fasta}
                else
                    design.py complete-targets auto-from-args ~{args} --specific-against-taxa ~{specificity_taxa}
                fi
            else
                if ~{sp_fasta}
                then
                    design.py complete-targets auto-from-args ~{args} --specific-against-fasta ~{sep=" " specificity_fasta}
                else
                    design.py complete-targets auto-from-args ~{args}
                fi
            fi
        fi
    >>>

    runtime {
        docker: "~{image}"
        queueArn: "~{queueArn}"
        memory: "~{memory}"
        maxRetries: 1
    }

    output {
        Array[File] guides = glob("*guides.*.tsv")
        Array[File] alns = glob("*alignment.*.fasta")
        Array[File] anns = glob("*annotation.*.tsv")
        File stats = stderr()
    }
}

workflow adapt_web {
    call adapt

    output {
        Array[File] guides = adapt.guides
        Array[File] alns = adapt.alns
        Array[File] anns = adapt.anns
    }
}
