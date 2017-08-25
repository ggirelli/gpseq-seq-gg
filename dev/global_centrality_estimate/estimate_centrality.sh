#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# 
# Author: Gabriele Girelli
# Email: gigi.ga90@gmail.com
# Version: 1.0.0
# Date: 20170821
# Project: GPSeq - centrality estimation
# Description: estimate genomic region nuclear centrality.
# 
# ------------------------------------------------------------------------------



# ENV VAR ======================================================================

export LC_ALL=C

# PARAMS =======================================================================


# Help string
helps="
usage: ./estimate_centrality.sh [-h][-d][-s binSize][-p binStep]
                                -o outdir -c csBed [BEDFILE]...

 Description:
  Calculate global centrality metrics. Requires bedtools for bin assignment,
  datamash for calculations, and gawk for text manipulation.

 Mandatory arguments:
  -o outdir     Output folder.
  -c csBed      Cutsite bedfile.
  BEDFILE       At least two (2) GPSeq condition bedfiles, space-separated and
                in increasing order of restriction conditions intensity.
                Expected to be ordered per condition.

 Optional arguments:
  -h            Show this help page.
  -d            Debugging mode: save intermediate results.
  -s binSize    Bin size in bp. Default to chromosome-wide bins.
  -p binStep    Bin step in bp. Default to bin sizeinStep.
"

# Default values
binSize=0
binStep=0
chrWide=true
debugging=false

# Parse options
while getopts hds:p:o:c: opt; do
    case $opt in
        h)
            # Help page
            echo -e "$helps"
            exit 0
        ;;
        d)
            # Debugging mode
            debugging=true
        ;;
        s)
            # Bin size
            if [ $OPTARG -le 0 ]; then
                msg="!!! ERROR! Invalid -s option. Bin size must be > 0."
                echo -e "$help\n$msg"
                exit 1
            else
                binSize=$OPTARG
                chrWide=false
            fi
        ;;
        p)
            # Bin step
            if [ $OPTARG -le 0 ]; then
                msg="!!! ERROR! Invalid -p option. Bin step must be > 0."
                echo -e "$help\n$msg"
                exit 1
            else
                binStep=$OPTARG
            fi
        ;;
        o)
            # Output directory
            if [ ! -d $OPTARG ]; then
                mkdir -p $OPTARG
            fi
            outdir=$OPTARG
        ;;
        c)
            # Cutsite bedfile
            if [ ! -e $OPTARG ]; then
                msg="!!! ERROR! Invalid -c option. File not found: $OPTARG"
                echo -e "$help\n$msg"
                exit 1
            else
                csBed=$OPTARG
            fi
        ;;
        ?)
            msg="!!! ERROR! Unrecognized option."
            echo -e "$help\n$msg"
            exit 1
        ;;
    esac
done

# Check mandatory options
if [ -z "$outdir" ]; then
    echo -e "$helps\n!!! ERROR! Missing mandatory -o option.\n"
    exit 1
fi
if [ -z "$csBed" ]; then
    echo -e "$helps\n!!! ERROR! Missing mandatory -c option.\n"
    exit 1
fi
if [ ! -x "$(command -v bedtools)" -o -z "$(command -v bedtools)" ]; then
    echo -e "$helps\n!!! ERROR! Missing bedtools.\n"
    exit 1
fi
if [ ! -x "$(command -v datamash)" -o -z "$(command -v datamash)" ]; then
    echo -e "$helps\n!!! ERROR! Missing datamash.\n"
    exit 1
fi
if [ ! -x "$(command -v gawk)" -o -z "$(command -v gawk)" ]; then
    echo -e "$helps\n!!! ERROR! Missing gawk.\n"
    exit 1
fi

# Read bedfile paths
shift $(($OPTIND - 1))
bedfiles=()
for bf in $*; do
    if [ -e $bf -a -n $bf ]; then
        bedfiles+=("$bf")
    else
        msg="!!! Invalid bedfile, file not found.\n    File: $bf"
        echo -e " $helps\n$msg"
        exit 1
    fi
done
if [ 0 -eq ${#bedfiles[@]} ]; then
    msg="!!! No bedfile was specified!\n"
    echo -e " $helps\n$msg"
    exit 1
fi

# Additional checks
if [ ! $binStep -eq 0 -a $binSize -eq 0 ]; then
    echo -e "WARNING: missing bin size, ignoring -p option.\n"
fi
if [ ! $binSize -eq 0 -a $binStep -eq 0 ]; then
    binStep=$binSize
fi

# Print settings
settings=""
if $chrWide; then
    settings="$settings
 Using chr-wide bins."
else
    settings="$settings
   Bin size : $binSize
   Bin step : $binStep"
fi
if $debugging; then settings="$settings\n Debugging mode ON."; fi
settings="$settings
 
 Output dir : $outdir
   Cutsites : $csBed
  Bed files :
   $(echo ${bedfiles[@]} | sed 's/ /\n   /g')"

echo -e "$settings\n"

# Constants
awkdir="`dirname ${BASH_SOURCE}`/awk/"

# RUN ==========================================================================

# 0) Identify chromosome sizes -------------------------------------------------

echo -e " Retrieving chromosome sizes ..."
chrSize=$(cat ${bedfiles[@]} | grep -v 'track' | datamash -sg1 -t$'\t' max 3)

# Sort chromosomes
echo -e "$chrSize" | gawk -f "$awkdir/add_chr_id.awk" | sort -k1,1n | \
    cut -f2,3 > "$outdir/chr_size.tsv"


# 1) Generate bin bed file -----------------------------------------------------
echo -e " Generating bins ..."

# Set output prefix
if $chrWide; then
    prefix="bins.chrWide"
else
    prefix="bins.size$binSize.step$binStep"
fi

# Generate bins
if $chrWide; then
    cat "$outdir/chr_size.tsv" | gawk '{ print $1 "\t" 0 "\t" $2 }' \
        > "$outdir/$prefix.bed" & pid=$!
else
    cat "$outdir/chr_size.tsv" | \
        gawk -v size=$binSize -v step=$binStep -f "$awkdir/mk_bins.awk" \
        > "$outdir/$prefix.bed" & pid=$!
fi
wait $pid; if [ false == $debugging ]; then rm "$outdir/chr_size.tsv"; fi

# 2) Intersect with bedtools ---------------------------------------------------
echo -e " Intersecting ..."

# Assign bed reads to bins
for bfi in $(seq 0 $(bc <<< "${#bedfiles[@]} - 1")); do
    fname=$(echo -e "${bedfiles[$bfi]}" | tr "/" "\t" | gawk '{ print $NF }')
    echo -e " > Intersecting $fname ..."
    bedtools intersect -a "$outdir/$prefix.bed" \
         -b "${bedfiles[$bfi]}" -wa -wb | cut -f 1-3,8\
        > "$outdir/intersected.$prefix.$fname.tsv"
done

# Assign cutsites to bins
echo -e " > Intersecting $csBed ..."
bedtools intersect -a "$outdir/$prefix.bed" -b "$csBed" -c \
    > "$outdir/intersected.$prefix.cutsites.tsv" & pid=$!
wait $pid; if [ false == $debugging ]; then rm "$outdir/$prefix.bed"; fi

# 3) Calculate bin statistics --------------------------------------------------
echo -e " Calculating bin statistics ..."

# Stats of cutsites
echo -e " > Calculating for $csBed ..."
cat "$outdir/intersected.$prefix.cutsites.tsv" | \
    datamash -sg1,2,3 sum 4 | gawk -f "$awkdir/add_chr_id.awk" | \
        sort -k1,1n -k3,3n |  cut -f2- \
        > "$outdir/bin_stats.$prefix.cutsites.tsv" & pid=$!
wait $pid;
if [ false == $debugging ]; then
    rm "$outdir/intersected.$prefix.cutsites.tsv";
fi

# Stats of beds
for bfi in $(seq 0 $(bc <<< "${#bedfiles[@]} - 1")); do
    fname=$(echo -e "${bedfiles[$bfi]}" | tr "/" "\t" | gawk '{ print $NF }')
    binned="$outdir/intersected.$prefix.$fname.tsv"

    # Calculate statistics
    echo -e " > Calculating for $fname ..."
    bin_stats=$(cat "$binned" | datamash -sg1,2,3 sum 4 mean 4 svar 4 | \
        gawk -f "$awkdir/add_chr_id.awk" | sort -k1,1n -k3,3n | cut -f2-)

    # Add number of cutsites
    gawk -f "$awkdir/merge_beds.awk" \
        <(cat "$outdir/bin_stats.$prefix.cutsites.tsv") \
        <(echo -e "$bin_stats") | cut -f 1-6,10 \
        > "$outdir/bin_stats.$prefix.$fname.tsv" & pid=$!
    wait $pid; if [ false == $debugging ]; then rm "$binned"; fi
done
if [ false == $debugging ]; then
    rm "$outdir/bin_stats.$prefix.cutsites.tsv";
fi

# 4) Assemble into bin data table ----------------------------------------------
echo -e " Combining information ..."

# Normalize read count by cutsite and condition
norm=""
for bfi in $(seq 0 $(bc <<< "${#bedfiles[@]} - 1")); do
    fname=$(echo -e "${bedfiles[$bfi]}" | tr "/" "\t" | gawk '{ print $NF }')
    stats="$outdir/bin_stats.$prefix.$fname.tsv"

    # Normalize
    #echo -e " > Normalizing for $fname ..."
    cond_n_reads=$(cat "${bedfiles[$bfi]}" | grep -v "track" | datamash sum 5)
    norm="$norm"$(cat "$stats" | gawk -v cnr=$cond_n_reads -v bfi=$bfi \
        -f "$awkdir/add_cnr_bfi.awk")"\n"
    if [ false == $debugging ]; then rm "$stats"; fi
done
# Columns of $norm:
# 1   2     3   4        5       6      7         8   9
# chr|start|end|condRead|readSum|readMu|readSigma|nCS|condID
norm=$(echo -e "$norm" | gawk -f "$awkdir/add_chr_id.awk" | \
    sort -k1,1n -k3,3n -k10,10n  | cut -f2- | sed 1d )

# Output

# 5) Estimate centrality -------------------------------------------------------
echo -e " Estimating centrality ..."

# Prepare paste string
spaste=""; for i in $(seq 1 ${#bedfiles[@]}); do spaste="$spaste -"; done

#---------------------#
# Probability metrics #
#---------------------#

# Probability metric
prob_mat=$(echo -e "$norm" | cut -f4,5,8 | \
    gawk '{ print $2 / ($1 * $3) }' | paste $spaste)
probability_two_points=$(echo -e "$prob_mat" | \
    gawk -v calc="ratio" -v type="2p" -f "$awkdir/estimate_centrality.awk")
probability_fixed=$(echo -e "$prob_mat" | \
    gawk -v calc="ratio" -v type="f" -f "$awkdir/estimate_centrality.awk")
probability_global=$(echo -e "$prob_mat" | \
    gawk -v calc="ratio" -v type="g" -f "$awkdir/estimate_centrality.awk")

# Cumulative ratio metric
cumrat=$(echo -e "$norm" | cut -f4,5,8 | \
    gawk '{ print $2 / ($1 * $3) }' | paste $spaste)
cumrat_two_points=$(echo -e "$cumrat" | \
    gawk -v calc="ratio" -v cumrat=1 -v type="2p" \
    -f "$awkdir/estimate_centrality.awk")
cumrat_fixed=$(echo -e "$cumrat" | \
    gawk -v calc="ratio" -v cumrat=1 -v type="f" \
    -f "$awkdir/estimate_centrality.awk")
cumrat_global=$(echo -e "$cumrat" | \
    gawk -v calc="ratio" -v cumrat=1 -v type="g" \
    -f "$awkdir/estimate_centrality.awk")

# Ratio cumulative metric
ratcum=$(echo -e "$norm" | cut -f4,5,8 | \
    tr '\t' ',' | paste $spaste)
ratcum_two_points=$(echo -e "$ratcum" | \
    gawk -v calc="ratio" -v ratcum=1 -v type="2p" \
    -f "$awkdir/estimate_centrality.awk")
ratcum_fixed=$(echo -e "$ratcum" | \
    gawk -v calc="ratio" -v ratcum=1 -v type="f" \
    -f "$awkdir/estimate_centrality.awk")
ratcum_global=$(echo -e "$ratcum" | \
    gawk -v calc="ratio" -v ratcum=1 -v type="g" \
    -f "$awkdir/estimate_centrality.awk")

#---------------------#
# Variability metrics #
#---------------------#

# Variance metric
var_mat=$(echo -e "$norm" | cut -f7 | paste $spaste)
var_two_points=$(echo -e "$var_mat" | \
    gawk -v calc="logratio" -v type="2p" -f "$awkdir/estimate_centrality.awk")
var_fixed=$(echo -e "$var_mat" | \
    gawk -v calc="logratio" -v type="f" -f "$awkdir/estimate_centrality.awk")
#var_global=$(echo -e "$var_mat" | \
#   gawk -v calc="logratio" -v type="g" -f "$awkdir/estimate_centrality.awk")

# Fano factor metric
ff_mat=$(echo -e "$norm" | cut -f6,7 | \
    gawk '{ print $2 ** 2 / $1 }' | paste $spaste)
ff_two_points=$(echo -e "$ff_mat" | \
    gawk -v calc="diff" -v type="2p" -f "$awkdir/estimate_centrality.awk")
ff_fixed=$(echo -e "$ff_mat" | \
    gawk -v calc="diff" -v type="f" -f "$awkdir/estimate_centrality.awk")
#ff_global=$(echo -e "$ff_mat" | \
#   gawk -v calc="diff" -v type="g" -f "$awkdir/estimate_centrality.awk")

# Coefficient of variation metric
cv_mat=$(echo -e "$norm" | cut -f6,7 | \
    gawk '{ print $2 / $1 }' | paste $spaste)
cv_two_points=$(echo -e "$cv_mat" | \
    gawk -v calc="diff" -v type="2p" -f "$awkdir/estimate_centrality.awk")
cv_fixed=$(echo -e "$cv_mat" | \
    gawk -v calc="diff" -v type="f" -f "$awkdir/estimate_centrality.awk")
#cv_global=$(echo -e "$cv_mat" | \
#   gawk -v calc="diff" -v type="g" -f "$awkdir/estimate_centrality.awk")

#----------#
# Assemble #
#----------#

# Prepare output table
metrics=$(echo -e "$norm" | cut -f1-3 | uniq | paste -d$'\t' - \
    <(echo -e "$probability_two_points") \
    <(echo -e "$probability_fixed") \
    <(echo -e "$probability_global") \
    <(echo -e "$cumrat_two_points") \
    <(echo -e "$cumrat_fixed") \
    <(echo -e "$cumrat_global") \
    <(echo -e "$ratcum_two_points") \
    <(echo -e "$ratcum_fixed") \
    <(echo -e "$ratcum_global") \
    <(echo -e "$var_two_points") \
    <(echo -e "$var_fixed") \
    <(echo -e "$ff_two_points") \
    <(echo -e "$ff_fixed") \
    <(echo -e "$cv_two_points") \
    <(echo -e "$cv_fixed") \
    )

# 6) Rank bins -----------------------------------------------------------------
echo -e " Ranking bins ..."

ranked=""
n_metrics=$(echo -e "$metrics" | awk '{print NF}' | sort -nu | tail -n 1)
for mi in $(seq 4 $n_metrics); do
    m=$(echo -e "$metrics" | cut -f1,$mi | sort -k2,2n | cut -f1)
    if [ -z "$ranked" ]; then
        ranked=$m
    else
        ranked=$(paste -d$'\t' <(echo -e "$ranked") <(echo -e "$m"))
    fi
done


# 7) Output --------------------------------------------------------------------
echo -e " Writing output ..."

#------------#
# Add header #
#------------#

# Normalization table
header="chr\tstart\tend"
header="$header\tcondRead\treadSum\treadMu\treadSigma\tnCS\tcondID"
norm=$(echo -e "$norm" | \
    gawk -v header="$header" -f "$awkdir/add_header.awk")

# Metrics table
header="chr\tstart\tend"
header="$header\tprob_2p\tprob_f\tprob_g"   # Probability
header="$header\tCoR_2p\tCoR_f\tCoR_g"      # Cumulative of Ratio
header="$header\tRoC_2p\tRoC_f\tRoC_g"      # Ratio of Cumulative
header="$header\tvar_2p\tvar_f"             # Variance
header="$header\tff_2p\tff_f"               # Fano factor
header="$header\tcv_2p\tcv_f"               # Coefficient of Variation
metrics=$(echo -e "$metrics" | \
    gawk -v header="$header" -f "$awkdir/add_header.awk")

# Ranked table
header=$(echo -e "$metrics" | head -n1 | cut -f4-)
ranked=$(echo -e "$ranked" | \
    gawk -v header="$header" -f "$awkdir/add_header.awk")

#-------#
# Write #
#-------#

# Remove bin positions if chromosome wide
if $chrWide; then
    norm=$(echo -e "$norm" | cut -f1,4-)
    metrics=$(echo -e "$metrics" | cut -f1,4-)
fi

# Write
echo -e "$norm" > "$outdir/normalized.$prefix.tsv"
echo -e "$metrics" > "$outdir/estimates.$prefix.tsv"
echo -e "$ranked" > "$outdir/ranked.$prefix.tsv"

# END ==========================================================================

################################################################################
