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
usage: ./estimate_centrality.sh [-h][-s binSize][-p binStep]
                                -o outdir [BEDFILE]...

 Description:
  Calculate global centrality metrics. Requires bedtools for bin assignment.

 Mandatory arguments:
  -o outdir     Output folder.
  BEDFILE       At least two (2) GPSeq condition bedfiles, space-separated and
                in increasing order of restriction conditions intensity.
                Expected to be ordered per condition.

 Optional arguments:
  -h	Show this help page.
  -s binSize    Bin size in bp. Default to chromosome-wide bins.
  -p binStep    Bin step in bp. Default to bin sizeinStep.
"

# Default values
binSize=0
binStep=0
chrWide=true

# Parse options
while getopts hs:p:o: opt; do
	case $opt in
		h)
			# Help page
			echo -e "$helps"
			exit 0
		;;
		s)
			# Bin size
			if [ $OPTARG -le 0 ]; then
				msg="!!! Invalid -s option. Bin size must be > 0."
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
				msg="!!! Invalid -p option. Bin step must be > 0."
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
		?)
			msg="!!! Unrecognized option."
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
if [ ! -x "$(command -v bedtools)" -o -z "$(command -v bedtools)" ]; then
	echo -e "$helps\n!!! ERROR! Missing bedtools.\n"
	exit 1
fi

# Read bedfile paths
shift $(($OPTIND - 1))
bedfiles=()
for bf in $*; do
	if [ -e $bf ]; then
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
settings="$settings
 
 Output dir : $outdir
  Bed files :
   $(echo ${bedfiles[@]} | sed 's/ /\n   /g')"

echo -e "$settings\n"

# RUN ==========================================================================

# 0) Identify chromosome sizes -------------------------------------------------
echo -e " Retrieving chromosome sizes ..."
chrSize=$(cat ${bedfiles[@]} | grep -v 'track' | datamash -sg1 -t$'\t' max 3)

# Sort chromosomes
awk_add_chr_id='
BEGIN {
	OFS = FS = "\t";
	convert["X"] = 23;
	convert["Y"] = 24;
}
{
	chrid = substr($1, 4);
	if ( chrid in convert ) {
		chrid = convert[chrid];
	}
	print chrid OFS $0;
}'
echo -e "$chrSize" | awk "$awk_add_chr_id" | sort -k1,1n | cut -f2,3 \
	> "$outdir/chr_size.tsv"


# 1) Generate bin bed file -----------------------------------------------------
echo -e " Generating bins ..."

prefix="bins.size$binSize.step$binStep"
if $chrWide; then
	cat "$outdir/chr_size.tsv" | awk "{ print $1 '\t' 0 '\t' $2 }" \
		> "$outdir/bins.size$binSize.step$binStep.bed"
else
	awk_mk_bins='
	BEGIN {
		OFS = FS = "\t";
	}
	{
		for ( i = 0; i < $2; i += step ) {
			print $1 OFS i OFS i+size
		}
	}'
	cat "$outdir/chr_size.tsv" | \
		awk -v size=$binSize -v step=$binStep "$awk_mk_bins" \
		> "$outdir/$prefix.bed"
fi

# 2) Intersect with bedtools ---------------------------------------------------
echo -e " Intersecting ..."

for bfi in $(seq 0 $(bc <<< "${#bedfiles[@]} - 1")); do
	fname=$(echo -e "${bedfiles[$bfi]}" | tr "/" "\t" | awk '{ print $NF }')
	echo -e " > Intersecting ${bedfiles[$bfi]} ..."
	bedtools intersect -a "$outdir/$prefix.bed" \
		 -b "${bedfiles[$bfi]}" -wa -wb \
		> "$outdir/intersected.$prefix.$fname.tsv"
done

# 3) Calculate centrality ------------------------------------------------------



# END ==========================================================================

################################################################################
