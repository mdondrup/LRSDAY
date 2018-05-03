#!/bin/bash
set -e -o pipefail
#######################################
# load environment variables for LRSDAY
source ./../../env.sh
PATH=$gnuplot_dir:$hal_dir:$PATH

#######################################
# set project-specific variables
input_assembly="./../02.Illumina-read-based_Assembly_Polishing/SK1.pilon.fa" # path of the input genome assembly
prefix="SK1" # file name prefix for the output files
ref_genome_raw="./../00.Ref_Genome/S288C.ASM205763v1.fa" # path of the raw reference genome 
ref_genome_noncore_masked="./../00.Ref_Genome/S288C.ASM205763v1.noncore_masked.fa" # path of the specially masked reference genome where subtelomeres and chromosome-ends were hard masked. When the subtelomere/chromosome-end information is unavailable for the organism that you are interested in, you can just put the path of the raw reference genome assembly here
chrMT_tag="chrMT" # sequence name for the mitochondrial genome in the raw reference genome file
gap_size=5000 # number of Ns to insert between adjacent contigs during scaffolding; You can put "auto" here (with the quotes) if you do not want to resize the gap introduced by ragout.
threads=1 # number of threads to use
debug="no" # use "yes" if prefer to keep intermediate files, otherwise use "no".

######################################
# process the pipeline
#####################################
# run Ragout for scaffolding based on the reference genome
echo ".references = ref_genome" > ragout.recipe.txt
echo ".target = $prefix" >> ragout.recipe.txt
echo "ref_genome.fasta = $ref_genome_noncore_masked" >> ragout.recipe.txt
echo "$prefix.fasta = $input_assembly" >> ragout.recipe.txt
echo ".naming_ref = ref_genome" >> ragout.recipe.txt

python $ragout_dir/ragout.py -o ${prefix}_ragout_out  --solid-scaffolds  -t $threads  ragout.recipe.txt
cat ./${prefix}_ragout_out/${prefix}_scaffolds.fasta | sed "s/^>chr_/>/g" > ./${prefix}_ragout_out/${prefix}_scaffolds.renamed.fasta 
cat  ./${prefix}_ragout_out/${prefix}_scaffolds.renamed.fasta ./${prefix}_ragout_out/${prefix}_unplaced.fasta > ./${prefix}_ragout_out/${prefix}.ragout.raw.fa

if [[ $gap_size == "auto" ]]
then
    cp ./${prefix}_ragout_out/${prefix}.ragout.raw.fa  ${prefix}.ragout.fa
    cp ./${prefix}_ragout_out/${prefix}_scaffolds.agp  ${prefix}.ragout.agp
else
    perl $LRSDAY_HOME/scripts/adjust_assembly_by_ragoutAGP.pl -i $input_assembly -p $prefix -a ./${prefix}_ragout_out/${prefix}_scaffolds.agp -g $gap_size
fi

# generate assembly statistics
perl $LRSDAY_HOME/scripts/cal_assembly_stats.pl -i $prefix.ragout.fa -o $prefix.ragout.stats.txt

# generate genome-wide dotplot
$mummer_dir/nucmer -t $threads --maxmatch --nosimplify  -p $prefix.ragout  $ref_genome_raw $prefix.ragout.fa 
$mummer_dir/delta-filter -m  $prefix.ragout.delta > $prefix.ragout.delta_filter
$mummer_dir/show-coords -b -T -r -c -l -d   $prefix.ragout.delta_filter > $prefix.ragout.filter.coords
perl $LRSDAY_HOME/scripts/identify_contigs_for_RefChr_by_mummer.pl -i $prefix.ragout.filter.coords -chr chrMT -cov 90 -o $prefix.mt_contig.list
$mummer_dir/mummerplot --large --postscript $prefix.ragout.delta_filter -p $prefix.ragout.filter
perl $LRSDAY_HOME/scripts/fine_tune_gnuplot.pl -i $prefix.ragout.filter.gp -o $prefix.ragout.filter_adjust.gp -r $ref_genome_raw -q ${prefix}.ragout.fa
$gnuplot_dir/gnuplot < $prefix.ragout.filter_adjust.gp

# generate dotplot for the mitochondrial genome only
echo $chrMT_tag > ref.chrMT.list
perl $LRSDAY_HOME/scripts/select_fasta_by_list.pl -i $ref_genome_raw -l ref.chrMT.list -m normal  -o ref.chrMT.fa
perl $LRSDAY_HOME/scripts/select_fasta_by_list.pl -i $prefix.ragout.fa -l $prefix.mt_contig.list -m normal  -o $prefix.mt_contig.fa
$mummer_dir/nucmer --maxmatch --nosimplify  -p $prefix.ragout.chrMT ref.chrMT.fa $prefix.mt_contig.fa
$mummer_dir/delta-filter -m  $prefix.ragout.chrMT.delta > $prefix.ragout.chrMT.delta_filter
$mummer_dir/mummerplot --large --postscript $prefix.ragout.chrMT.delta_filter -p $prefix.ragout.chrMT.filter
perl $LRSDAY_HOME/scripts/fine_tune_gnuplot.pl -i $prefix.ragout.chrMT.filter.gp -o $prefix.ragout.chrMT.filter_adjust.gp -r ref.chrMT.fa -q $prefix.mt_contig.fa
$gnuplot_dir/gnuplot < $prefix.ragout.chrMT.filter_adjust.gp

# clean up intermediate files
if [[ $debug == "no" ]]
then
    rm ragout.recipe.txt
    rm *.ragout.filter.coords
    rm *.filter.fplot
    rm *.filter.rplot
    rm *.delta
    rm *.delta_filter
    rm *.filter.gp
    rm *.filter_adjust.gp
    rm *.filter.ps
fi

############################
# checking bash exit status
if [[ $? -eq 0 ]]
then
    echo ""
    echo "LRSDAY message: This bash script has been successfully processed! :)"
    echo ""
    echo ""
    exit 0
fi
############################