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
        Int idm = 4
        Float idfrac = 0.01
        Int max_primers_at_site = 10
        Int max_target_length = 250

        Int gm = 3
        Float gp = 0.98
        Int soft_guide_constraint = 1
        Int hard_guide_constraint = 5
        Float penalty_strength = 0.25
        String maximization_algorithm = 'random-greedy'

        String? bucket

        Int? rand_sample
        Int? rand_seed

        String image
        String queueArn
        String memory = "2GB"
    }

    String base_cmd = "design.py complete-targets auto-from-args ~{taxid} ~{segment} guides.tsv -gl ~{gl} -pl ~{pl} -pm ~{pm} -pp ~{pp} --primer-gc-content-bounds ~{primer_gc_lo} ~{primer_gc_hi} --max-primers-at-site ~{max_primers_at_site} --max-target-length ~{max_target_length} --obj-fn-weights ~{objfnweights_a} ~{objfnweights_b} --best-n-targets ~{bestntargets} --predict-cas13a-activity-model --mafft-path $MAFFT_PATH --cluster-threshold ~{cluster_threshold}"
    String args_specificity = "--id-m ~{idm} --id-frac ~{idfrac} --id-method shard --specific-against-taxa"
    String args_obj = if "~{obj}" == "minimize-guides" then "--obj minimize-guides -gm ~{gm} -gp ~{gp} --require-flanking3 H" else if "~{obj}" == "maximize-activity" then "--obj ~{obj} --soft-guide-constraint ~{soft_guide_constraint} --hard-guide-constraint ~{hard_guide_constraint} --penalty-strength ~{penalty_strength} --maximization-algorithm ~{maximization_algorithm}" else ""
    String args_influenza = if "~{taxid}" == "11320" || "~{taxid}" == "11520" || "~{taxid}" == "11552"  then " --prep-influenza" else ""
    String args_refs = if defined(ref_accs) then " --ref-accs ~{ref_accs}" else ""
    String args_memo = if defined(bucket) then " --prep-memoize-dir s3://~{bucket}/memo" else ""
    String args_rand = if defined(rand_sample) then " --sample-seqs ~{rand_sample}" else ""
    String args_seed = if defined(rand_seed) then " --seed ~{rand_seed}" else ""

    command <<<
        if ~{specific}
        then
            ~{base_cmd} ~{args_specificity} ~{specificity_taxa} ~{args_obj}~{args_influenza}~{args_refs}~{args_memo}~{args_rand}~{args_seed}
        else
            ~{base_cmd} ~{args_obj}~{args_influenza}~{args_refs}~{args_memo}~{args_rand}~{args_seed}
        fi || echo "objective-value\ttarget-start\ttarget-end\ttarget-length\tleft-primer-start\tleft-primer-num-primers\tleft-primer-frac-bound\tleft-primer-target-sequences\tright-primer-start\tright-primer-num-primers\tright-primer-frac-bound\tright-primer-target-sequences\tnum-guides\ttotal-frac-bound-by-guides\tguide-set-expected-activity\tguide-set-median-activity\tguide-set-5th-pctile-activity\tguide-expected-activities\tguide-target-sequences\tguide-target-sequence-positions\n" > failed.tsv.0
    >>>

    runtime {
        docker: "~{image}"
        queueArn: "~{queueArn}"
        memory: "~{memory}" + "GB"
        maxRetries: 1
    }

    output {
        Array[File] guides = glob("*.tsv*")
    }
}

workflow parallel_adapt {

    meta {
        description: "Runs ADAPT to find optimal design guides for a set of species"
    }

    input {
        String queueArn
        File taxa_file
        File sp_mem_file = ''
        File nonsp_mem_file = ''
        Array[String] objs = ["maximize-activity", "minimize-guides"]
        Array[Boolean] sps = [true, false]
    }

    parameter_meta {
        queueArn: "Amazon Resource Number for queue to use"
        taxa_file: "TSV with columns for the inputs for ADAPT. Set to 'default' for the default value"
        sp_mem_file: "Two column TSV with families in the first column and memory to allocate for specific runs in the second column."
        nonsp_mem_file: "Two column TSV with families in the first column and memory to allocate for nonspecific runs in the second column."
        objs: "List of objectives to use (only 'maximize-activity' or 'minimize-guides' allowed)"
        sps: "List of booleans of whether or not to design specific guides"
    }

    call format_taxa {
        input:
            taxa_file = taxa_file,
            queueArn = queueArn
    }
    Array[Object] taxa = read_objects(taxa_file)
    scatter(sp in sps) {
        Map[String, String] mem_map = if (sp == true) then read_map(sp_mem_file) else read_map(nonsp_mem_file)
        scatter(obj in objs) {
            scatter(i in range(length(taxa))) {
                Object taxon = taxa[i]
                call adapt {
                    input:
                        taxid = taxon["taxid"],
                        ref_accs = taxon["refseqs"],
                        segment = taxon["segment"],
                        gl = if ('~{taxon["gl"]}' != "default") then taxon["gl"] else 28,
                        pl = if ('~{taxon["pl"]}' != "default") then taxon["pl"] else 30,
                        pm = if ('~{taxon["pm"]}' != "default") then taxon["pm"] else 3,
                        pp = if ('~{taxon["pp"]}' != "default") then taxon["pp"] else 0.98,
                        primer_gc_lo = if ('~{taxon["primer_gc_lo"]}' != "default") then taxon["primer_gc_lo"] else 0.35,
                        primer_gc_hi = if ('~{taxon["primer_gc_hi"]}' != "default") then taxon["primer_gc_hi"] else 0.65,
                        objfnweights_a = if ('~{taxon["objfnweights_a"]}' != "default") then taxon["objfnweights_a"] else 0.5,
                        objfnweights_b = if ('~{taxon["objfnweights_b"]}' != "default") then taxon["objfnweights_b"] else 0.25,
                        bestntargets = if ('~{taxon["bestntargets"]}' != "default") then taxon["bestntargets"] else 10,
                        cluster_threshold = if ('~{taxon["cluster_threshold"]}' != "default") then taxon["cluster_threshold"] else 0.3,
                        idm = if ('~{taxon["idm"]}' != "default") then taxon["idm"] else 4,
                        idfrac = if ('~{taxon["idfrac"]}' != "default") then taxon["idfrac"] else 0.01,
                        max_primers_at_site = if ('~{taxon["max_primers_at_site"]}' != "default") then taxon["max_primers_at_site"] else 10,
                        max_target_length = if ('~{taxon["max_target_length"]}' != "default") then taxon["max_target_length"] else 250,
                        gm = if ('~{taxon["gm"]}' != "default") then taxon["gm"] else 3,
                        gp = if ('~{taxon["gp"]}' != "default") then taxon["gp"] else 0.98,
                        soft_guide_constraint = if ('~{taxon["soft_guide_constraint"]}' != "default") then taxon["soft_guide_constraint"] else 1,
                        hard_guide_constraint = if ('~{taxon["hard_guide_constraint"]}' != "default") then taxon["hard_guide_constraint"] else 5,
                        penalty_strength = if ('~{taxon["penalty_strength"]}' != "default") then taxon["penalty_strength"] else 0.25,
                        maximization_algorithm = if ('~{taxon["maximization_algorithm"]}' != "default") then taxon["maximization_algorithm"] else 'random-greedy',
                        memory = mem_map['~{taxon["family"]}'],
                        obj = obj,
                        specific = sp,
                        specificity_taxa = format_taxa.sptaxa_files[i],
                        queueArn = queueArn
                }
            }
        }
    }

    output {
        Array[Array[Array[Array[File]]]] guides = adapt.guides
        File output_taxa_file = write_objects(taxa)
    }
}
