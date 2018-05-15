workflow hic {
    Array[Array[File]]? fastq_files
    File restriction_sites
    File chrsz
    File reference_index


    Int fastqs_len = length(fastq_files)
    
    scatter(i in range(fastqs_len)){
        call align { input:
            restriction = restriction_sites,
            fastqs = fastq_files[i],
            chrsz = chrsz,
            idx_tar = reference_index
        }
    }

    #call merge { input:
    #    bams = align.out_files
    #}

    #call merge_sort { input:
    #    sort_files = align.sort_file
    #}

    #call dedup { input:
    #    merged_sort = merge_sort.out_file
    #}

    #call create_hic { input:
    #    chrsz = chrsz,
    #    pairs_file = dedup.out_file
    #}

    #call call_tads { input:
    #    hic_file = create_hic.out_file
    #}
}


task align {
	File idx_tar 		# reference bwa index tar
	Array[File] fastqs 	# [read_end_id]
    File chrsz          # chromosome sizes file
    File restriction    # restriction enzyme sites in the reference genome

    command {       
        mkdir data && cd data && mkdir fastq && mkdir reference
        data_path=$(pwd)
        cd fastq
        ln -s ${fastqs[0]} $(pwd)/frag_R1.fastq.gz
        ln -s ${fastqs[1]} $(pwd)/frag_R2.fastq.gz
        cd ../reference && tar -xvf ${idx_tar}
        index_folder=$(ls)
        cd $index_folder
        reference_fasta=$(ls | head -1) 
        reference_folder=$(pwd)
        reference_index_path=$reference_folder/$reference_fasta
        cd ../..
        bash /opt/scripts/juicer.sh -D /opt -d $data_path -S alignonly -z $reference_index_path -p ${chrsz} -y ${restriction} -s MboI
    }

    output {
        File out_files = glob("data/splits/*alignable.bam")[0]
        File sort_file = glob("data/splits/*.sort.txt")[0]
       
    }

    runtime {
        docker : "quay.io/gabdank/juicer:encode05022018"
    }
}

task merge {
    Array[File] bams

    command {
        samtools merge merged.bam ${sep=' ' bams}   
    }

    output {
        File out_file = glob('merged.bam')[0]
    }

    runtime {
        docker : "quay.io/gabdank/juicer:encode05022018"
    }
}

task merge_sort {
    Array[File] sort_files

    command {
        sort -m -k2,2d -k6,6d -k4,4n -k8,8n -k1,1n -k5,5n -k3,3n --parallel=8 -S 10% ${sep=' ' sort_files}  > merged_sort.txt

    }

    output {
        File out_file = glob('merged_sort.txt')[0]
    }

    runtime {
        docker : "quay.io/gabdank/juicer:encode05022018"

        #> 8 processors
        #> a lot of memory
    }
}

task dedup {
    File merged_sort

    command {
        touch dups.txt
        touch optdups.txt
        touch merged_nodups.txt
        awk -f /opt/scripts/common/dups.awk ${merged_sort}
    }

    output {
        File out_file = glob('merged_nodups.txt')[0]
    }

    runtime {
        docker : "quay.io/gabdank/juicer:encode05022018"
    }
}

task create_hic {
    File pairs_file
    File chrsz

    command {
        /opt/scripts/common/juicer_tools pre -s inter.txt -g inter_hists.m -q 1 ${pairs_file} inter.hic ${chrsz}
    }

    output {
        # add inter_30 stuff
        File out_file = glob('inter.hic')[0]
    }

    runtime {
        docker : "quay.io/gabdank/juicer:encode05022018"
    }
}

task call_tads {
    File hic_file

    command {
        /opt/scripts/common/juicer_tools arrowhead ${hic_file} contact_domains --ignore_sparsity
    }

    output {
        Array[File] out_file = glob('contact_domains/*.bedpe')
    }

    runtime {
        docker : "quay.io/gabdank/juicer:encode05022018"
    }
}