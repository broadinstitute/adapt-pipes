version 1.0

task adapt {

    input {
        Int taxid
        String segment
        String obj
        String? ref_accs
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

        Boolean specific
        File? specificity_taxa
        Int? idm = 4
        Float? idfrac = 0.01
        Int? max_primers_at_site = 10
        Int? max_target_length = 250

        Int? gm = 3
        Float? gp = 0.98
        Int? soft_guide_constraint = 1
        Int? hard_guide_constraint = 5
        Float? penalty_strength = 0.25
        String? maximization_algorithm = 'random-greedy'

        String? bucket

        Int? rand_sample
        Int? rand_seed

        String image
        String queueArn
        String memory = "2GB"
    }

    String base_cmd = "design.py complete-targets auto-from-args ~{taxid} ~{segment} guides.tsv -gl ~{gl} -pl ~{pl} -pm ~{pm} -pp ~{pp} --primer-gc-content-bounds ~{primer_gc_lo} ~{primer_gc_hi} --max-primers-at-site ~{max_primers_at_site} --max-target-length ~{max_target_length} --obj-fn-weights ~{objfnweights_a} ~{objfnweights_b} --best-n-targets ~{bestntargets} --predict-activity-model-path $WORK_DIR/models/classify//model-51373185 $WORK_DIR/models/regress/model-f8b6fd5d --mafft-path $MAFFT_PATH --cluster-threshold ~{cluster_threshold}"
    String args_specificity = "--id-m ~{idm} --id-frac ~{idfrac} --id-method shard --specific-against-taxa"
    String args_obj = if "~{obj}" == "minimize-guides" then "--obj minimize-guides -gm ~{gm} -gp ~{gp} --require-flanking3 H" else if "~{obj}" == "maximize-activity" then "--obj ~{obj} --soft-guide-constraint ~{soft_guide_constraint} --hard-guide-constraint ~{hard_guide_constraint} --penalty-strength ~{penalty_strength} --maximization-algorithm ~{maximization_algorithm}" else ""
    String args_influenza = if "~{taxid}" == "11320" || "~{taxid}" == "11520" || "~{taxid}" == "11552"  then "--prep-influenza" else ""
    String args_refs = if defined(ref_accs) then "--ref-accs ~{ref_accs}" else ""
    String args_memo = if defined(bucket) then "--prep-memoize-dir s3://~{bucket}/memo" else ""
    String args_rand = if defined(rand_sample) then "--sample-seqs ~{rand_sample}" else ""
    String args_seed = if defined(rand_seed) then "--seed ~{rand_seed}" else ""
    
    command <<<
        if ~{specific}
        then
            ~{base_cmd} ~{args_specificity} ~{specificity_taxa} ~{args_obj} ~{args_influenza} ~{args_memo} ~{args_rand} ~{args_seed}
        else
            ~{base_cmd} ~{args_obj} ~{args_influenza} ~{args_memo} ~{args_rand} ~{args_seed}
        fi
    >>>

    runtime {
        docker: "~{image}"
        queueArn: "~{queueArn}"
        memory: "~{memory}"
        maxRetries: 1
    }

    output {
        Array[File] guides = glob("*.tsv*")
        File stats = stderr()
    }
}

workflow single_adapt {
    call adapt

    output {
        Array[File] guides = adapt.guides
    }
}
