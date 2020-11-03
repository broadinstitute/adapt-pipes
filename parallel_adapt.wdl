version 1.0

task format_taxa {
    
    input {
        File taxa_file
        File all_taxa_file
        String queueArn
    }

    command <<<
        i=1000000000
        while read -r taxonomy; do
            family=$(echo "$taxonomy" | cut -f1)
            taxid=$(echo "$taxonomy" | cut -f4)
            segment=$(echo "$taxonomy" | cut -f5)
            ref_accs=$(echo "$taxonomy" | cut -f6)
            sptaxa="sptax_${i}_${taxid}.tsv"
            i=$((i+1))
            awk -F'\t' -v taxid="$taxid" -v family="$family" '$1==family && $4!=taxid {print $4"\t"$5}' ~{all_taxa_file} > $sptaxa
        done < <(tail -n +2 ~{taxa_file})
    >>>

    runtime {
        docker: "ubuntu:18.04"
        queueArn: "~{queueArn}"
    }

    output {
        Array[File] sptaxa_files = glob("sptax_*_*.tsv")
    }
}

task adapt {

    input {
        Int taxid
        String ref_accs
        String segment
        String obj
        Int gl = 28
        Int pl = 30
        Int pm = 3
        Float pp = 0.98
        Float primer_gc_lo = 0.35
        Float primer_gc_hi = 0.65
        Float objfnweights_a = 0.5
        Float objfnweights_b = 0.25
        Int bestntargets = 20
        Float cluster_threshold = 0.3

        Boolean specific
        File? specificity_taxa
        Int? idm = 4
        Float? idfrac = 0.01
        Int? maxprimersatsite = 10
        Int? maxtargetlength = 250

        Int? gm = 3
        Float? gp = 0.98
        Int? softguideconstraint = 1
        Int? hardguideconstraint = 1
        Float? penaltystrength = 0.25
        String? maximizationalgorithm = 'random-greedy'

        String? bucket

        String? rand_sample
        String? rand_seed

        String image
        String queueArn
        String memory = "2GB"
    }

    String base_cmd = "design.py complete-targets auto-from-args ~{taxid} ~{segment} ~{ref_accs} guides.tsv -gl ~{gl} -pl ~{pl} -pm ~{pm} -pp ~{pp} --primer-gc-content-bounds ~{primer_gc_lo} ~{primer_gc_hi} --max-primers-at-site ~{maxprimersatsite} --max-target-length ~{maxtargetlength} --obj-fn-weights ~{objfnweights_a} ~{objfnweights_b} --best-n-targets ~{bestntargets} --predict-activity-model-path $WORK_DIR/models/classify//model-51373185 $WORK_DIR/models/regress/model-f8b6fd5d --mafft-path $MAFFT_PATH --cluster-threshold ~{cluster_threshold}"
    String args_specificity = if specific then "--id-m ~{idm} --id-frac ~{idfrac} --id-method shard --specific-against-taxa ~{specificity_taxa}" else ""
    String args_obj = if "~{obj}" == "minimize-guides" then "--obj minimize-guides -gm ~{gm} -gp ~{gp} --require-flanking3 H" else if "~{obj}" == "maximize-activity" then "--obj ~{obj} --soft-guide-constraint ~{softguideconstraint} --hard-guide-constraint ~{hardguideconstraint} --penalty-strength ~{penaltystrength} --maximization-algorithm ~{maximizationalgorithm}" else ""
    String args_influenza = if "~{taxid}" == "11320" || "~{taxid}" == "11520" || "~{taxid}" == "11552"  then "--prep-influenza" else ""
    String args_memo = if defined(bucket) then "--prep-memoize-dir s3://~{bucket}/memo" else ""
    Int args_rand = if defined(rand_sample) then "--sample-seqs ~{rand_sample}" else ""
    Int args_seed = if defined(rand_seed) then "--seed ~{rand_seed}" else ""
    
    command <<<
        /usr/bin/time -v ~{base_cmd} ~{args_specificity} ~{args_obj} ~{args_influenza} ~{args_memo} ~{args_rand} ~{args_seed}
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

workflow parallel_adapt {
    
    meta {
        description: "Runs ADAPT to find optimal design guides for a set of species"
    }

    input {
        String queueArn
        Array[String] objs = ["maximize-activity", "minimize-guides"]
        Array[Boolean] sps = [true, false]
    }

    parameter_meta {
        objs: "List of objectives to use (only 'maximize-activity' or 'minimize-guides' allowed)"
        sps: "List of booleans of whether or not to design specific guides"
    }

    call format_taxa {
        input:
            queueArn = queueArn
    }
    Array[Object] taxa = read_objects(taxa_file)
    scatter(sp in sps) {
        scatter(obj in objs) {
            scatter(i in range(length(taxa))) {
                Object taxon = taxa[i]
                call adapt {
                    input: 
                        taxid = taxon["taxid"],
                        ref_accs = taxon["refseqs"],
                        segment = taxon["segment"],
                        obj = obj,
                        specific = sp,
                        specificity_taxa = format_taxa.sptaxa_files[i]
                        queueArn = queueArn
                }
            }
        }
    }

    output {
        Array[Array[Array[Array[File]]]] guides = adapt.guides
        Array[Array[Array[File]]] stats = adapt.stats
    }
}
