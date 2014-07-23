#!/usr/bin/perl
#
# File: insert_tcga_study_names
# 
# Last Modified: 2014-07-18, Status: prototype

use strict;
use warnings;
use Data::Dumper;

my %study_names = ( 'BLCA-US' => "Bladder Urothelial Cancer - TGCA, US",
                    'BRCA-US' => "Breast Cancer - TCGA, US",
                    'CESC-US' => "Cervical Squamous Cell Carcinoma - TCGA, US",
                    'COAD-US' => "Colon Adenocarcinoma - TCGA, US",
                    'DLBC-US' => "Lymphoid Neoplasm Diffuse Large B-cell Lymphoma - TCGA, US ",
                    'GBM-US'  => "Brain Glioblastoma Multiforme - TCGA, US",
                    'HNSC-US' => "Head and Neck Squamous Cell Carcinoma - TCGA, US",
                    'KICH-US' => "Kidney Chromophobe - TCGA, US",
                    'KIRC-US' => "Kidney Renal Clear Cell Carcinoma - TCGA, US",
                    'KIRP-US' => "Kidney Renal Papillary Cell Carcinoma - TCGA, US",
                    'LAML-KR' => "Blood cancer - Acute myeloid leukaemia", 
                    'LAML-US' => "Acute Myeloid Leukemia - TCGA, US",
                    'LGG-US'  => "Brain Lower Grade Gliona - TCGA, US",
                    'LIHC-US' => "Liver Hepatocellular carcinoma - TCGA, US",
                    'LUAD-US' => "Lung Adenocarcinoma - TCGA, US",
                    'LUSC-US' => "Lung squamous cell carcinoma  - TCGA, US",
                    'OV-US'   => "Ovarian Serous Cystadenocarcinoma - TCGA, US",
                    'PRAD-US' => "Prostate Adenocarcinoma - TCGA, US",
                    'READ-US' => "Rectum Adenocarcinoma - TCGA, US",
                    'SARC-US' => "Sarcoma - TCGA, US",
                    'SKCM-US' => "Skin Cutaneous melanoma - TCGA, US",
                    'STAD-US' => "Gastric Adenocarcinoma - TCGA, US",
                    'THCA-US' => "Head and Neck Thyroid Carcinoma - TCGA, US",
                    'UCEC-US' => "Uterine Corpus Endometrial Carcinoma- TCGA, US",
);

while ( <> ) {
    my $study;
    my @fields = split /\t/;
    if ( $fields[0] =~ m/Project/ ) {
        $study = 'Study';
    }
    elsif ( $study_names{$fields[0]} ) {
        $study = $study_names{$fields[0]};
    }
    else {
        $study = 'NOT FOUND';
    }

    unshift @fields, $study;
    print join( "\t", @fields );
}

exit;

__END__

