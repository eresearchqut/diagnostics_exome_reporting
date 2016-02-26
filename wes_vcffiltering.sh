#!/bin/bash
#
# Created: 2016/02/19
# Last modified: 2016/02/19
# Author: Miles Benton
#
# """
# This script generates a subset of vcf files defined by supplied gene lists.
# The script accepts 2 arguments: [file name] and [gene list].
#
# E.g. INPUT
# ./wes_vcffiltering.sh /path/to/annotated_sample.vcf.gz 
#
# """

# define the sample being processed
INPUTFILE="$1"
GENELIST="$2"
genelist=$(echo ${GENELIST} | sed 's/.txt//g')
filename=$(echo $INPUTFILE | tr "/ && ." " " | awk '{printf $2}')
# date
DATE=`date +%Y_%m_%d`

# check for gene filter
[[ -z "$GENELIST" ]] && { echo "...Please provide a disease gene list to filter on..." ; exit 1; }

# start filtering
echo "...starting filtering of sample $filename..."

## create text file containing software/database version details
echo "...extracting software and database version information..."
zcat vcf/${filename}.vcf.gz | grep '##' | grep 'VEP=v\|SnpSiftV\|file\|source=\|parameters[A-Z]\|tmap\|reference=' > vcf/${filename}_versions.txt

# get vcf header for out files
bcftools view -h vcf/${filename}.vcf.gz | tail -n 1 > vcf/vcf_header.txt

## Tier 1: Disease Specific Genes
# tier 1 filtering
echo "...filtering at tier 1: Disease Specific Genes..."
# prepare the list for searching
/bin/bash gene_lists/./genelist_prep.sh ${GENELIST}
# zcat vcf/${filename}.vcf.gz | grep -f gene_lists/test_genes.txt | grep -v '##' > results/Tier_1/${filename}_Tier_1_results.vcf
zcat vcf/${filename}.vcf.gz | grep -f ${genelist}_filter.txt | grep -v '##\|#' > results/Tier_1/${filename}_Tier_1_results.vcf
cat vcf/vcf_header.txt results/Tier_1/${filename}_Tier_1_results.vcf > results/Tier_1/${filename}_Tier_1_results_${DATE}.vcf
# clean up
rm results/Tier_1/${filename}_Tier_1_results.vcf
rm results/Tier_1/${genelist}_filter.txt 
# extract info for report and save as csv
/bin/bash ./vcfcompiler_diagnostics.sh results/Tier_1/${filename}_Tier_1_results_${DATE}.vcf

## Tier 2: Pathway Specific Genes
# generate combined pathways gene list
# remove previous versions
if [ -f gene_lists/wes_gene_lists/pathways_list.txt ]; then
    echo "...deleting existing pathways_list.txt"
    rm gene_lists/wes_gene_lists/pathways_list.txt
fi
#	
for file in gene_lists/wes_gene_lists/*.txt; do
	tail -n +3 $file >> gene_lists/wes_gene_lists/tmp_list.txt
done
sort gene_lists/wes_gene_lists/tmp_list.txt | uniq > gene_lists/wes_gene_lists/pathways_list.txt
rm gene_lists/wes_gene_lists/tmp_list.txt
# prepare the list for searching
/bin/bash gene_lists/./genelist_prep.sh gene_lists/wes_gene_lists/pathways_list.txt
# tier 2 filtering
echo "...filtering at tier 2: Pathway Specific Genes..."
zcat vcf/${filename}.vcf.gz | grep -f gene_lists/wes_gene_lists/pathways_list_filter.txt | grep -v '##\|#' > results/Tier_2/${filename}_Tier_2_results.vcf
cat vcf/vcf_header.txt results/Tier_2/${filename}_Tier_2_results.vcf > results/Tier_2/${filename}_Tier_2_results_${DATE}.vcf
# clean up
rm results/Tier_2/${filename}_Tier_2_results.vcf
rm gene_lists/wes_gene_lists/pathways_list_filter.txt
# extract info for report and save as csv
/bin/bash ./vcfcompiler_diagnostics.sh results/Tier_2/${filename}_Tier_2_results_${DATE}.vcf


## Tier 3: All Other Genes
# create list of all other genes
# combine the previously used filter lists and inverse grep
# remove previous versions
if [ -f gene_lists/filtered_list.txt ]; then
    echo "...deleting existing filtered_list.txt"
    rm gene_lists/filtered_list.txt
fi
#	
cat gene_lists/test_genes.txt gene_lists/wes_gene_lists/pathways_list.txt | sort | uniq > gene_lists/filtered_list.txt
# prepare the list for searching
/bin/bash gene_lists/./genelist_prep.sh gene_lists/filtered_list.txt
# tier 3 filtering
echo "...filtering at tier 3: All Other Genes..."
zcat vcf/${filename}.vcf.gz | grep -v -f gene_lists/filtered_list_filter.txt | grep -v '##\|#' > results/Tier_3/${filename}_Tier_3_results.vcf
cat vcf/vcf_header.txt results/Tier_3/${filename}_Tier_3_results.vcf > results/Tier_3/${filename}_Tier_3_results_${DATE}.vcf
# clean up
rm results/Tier_3/${filename}_Tier_3_results.vcf
rm gene_lists/filtered_list_filter.txt
# extract info for report and save as csv
/bin/bash ./vcfcompiler_diagnostics.sh results/Tier_3/${filename}_Tier_3_results_${DATE}.vcf


# ## Tier 4: Polymorphisms
# # tier 4 filtering
# echo "...filtering at tier 4: Polymorphisms..."
# zcat vcf/${filename}.vcf.gz | grep -f gene_lists/test_genes.txt | grep -v '##\|#' > results/Tier_4/${filename}_Tier_4_results.vcf
# cat vcf/vcf_header.txt results/Tier_4/${filename}_Tier_4_results.vcf > results/Tier_4/${filename}_Tier_4_results_${DATE}.vcf
# # clean up
# rm results/Tier_4/${filename}_Tier_4_results.vcf
# # extract info for report and save as csv
# /bin/bash ./vcfcompiler_diagnostics.sh results/Tier_4/${filename}_Tier_4_results_${DATE}.vcf

# final clean
rm vcf/vcf_header.txt

echo "...filtering done..."