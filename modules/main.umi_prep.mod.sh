#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# 
# Author: Gabriele Girelli
# Email: gigi.ga90@gmail.com
# Version: 0.1.1
# Description: module for UMI preparation.
# 
# ------------------------------------------------------------------------------



# START ========================================================================

function prepare_umi() {
	echo -e 'UMI grouping & deduplicating\n=====================\n'

	# Get cutsite list file by input
	input_fname 'Cutsite list file' 'a list of cutsite positions' $csList
	cutsitelist=$v

	# Get maskfile by input
	input_fname 'Mask file' 'a list of regions to be masked' $maskFile
	maskfile=$v

	# Update summary header
	new_fields="\tunmasked\tunmasked/umis"
	new_fields="$new_fields\tassigned_to_cs\tto_cs/unmasked"
	new_fields="$new_fields\tpass_read_qc\tread_qc/to_cs"
	new_fields="$new_fields\tunique_umis\tunique/read_qc"
	head -n 1 $outcontrol/summary_sam_filter | \
		awk -v nf="$new_fields" "{ print \$0 nf }" - \
		> $outcontrol/summary_umi_prep

	function prepare_umi_single_condition() {
		echo -e "\nPreparing UMIs from condition '$condition'..."
		cslbool=0
		if [[ -n $csList ]]; then
			cslbool=1
		fi

		# Group UMIs -----------------------------------------------------------
		if [[ -n $maskFile ]]; then
			time $scriptdir/umi_group.py $cout/$condition/ $expID $condition \
				$umiLength --mask-file $maskFile & pid0=$!
			wait $pid0
		else
			time $scriptdir/umi_group.py $cout/$condition/ $expID $condition \
				$umiLength & pid0=$!
			wait $pid0
		fi

		if [[ -n $csList ]]; then
			# Assign UMIs to cutsites ------------------------------------------
			time $scriptdir/pos2cutsites.R $cout/$condition/ $expID $condition \
				$csList -i $csRange -c $threads & pid0=$!
			wait $pid0
		fi

		if [[ $umiLength -ne 0 ]]; then
			# Deduplicating UMIs -----------------------------------------------
			echo -e "\nDeduplicating UMIs ..."
			time $scriptdir/umi_dedupl.R $cout/$condition/ $expID $condition \
				-p $platform -co $pthr -c $threads -cs $cslbool \
				-em $emax -ep $eperc & pid0=$!
			wait $pid0
		else
			if [[ -n $csList ]]; then
				cp $cout/$condition/UMIpos.atcs.txt \
					$cout/$condition/UMIpos.unique.atcs.txt
			else
				cp $cout/$condition/UMIpos.txt \
					$cout/$condition/UMIpos.unique.txt
			fi
		fi

		# Update summary -------------------------------------------------------

		# Input reads
		ir=`cat $cout/"$condition"/"$condition".umi_prep_notes.txt | \
			grep 'input reads' | head -n 1 | cut -d ' ' -f 1`

		# Masked reads
		c=`cat $cout/"$condition"/"$condition".umi_prep_notes.txt | \
			grep 'reads masked' | head -n 1 | cut -d ' ' -f 1`
		c=`expr $ir - $c`
		p=`printf "%.2f%%" "$(bc <<< "scale = 4; $c / $ir * 100")"`

		# Assigned to cutsite
		c2=`cat $cout/"$condition"/"$condition".umi_prep_notes.txt | \
			grep 'assigned to a cutsite' | head -n 1 | cut -d ' ' -f 1`
		p2=`printf "%.2f%%" "$(bc <<< "scale = 4; $c2 / $c * 100")"`
		
		# Pass the read quality filter	
		c3=`cat $cout/"$condition"/"$condition".umi_prep_notes.txt | \
			grep 'pass the read quality filter' | head -n 1 | cut -d ' ' -f 1`
		p3=`printf "%.2f%%" "$(bc <<< "scale = 4; $c3 / $c2 * 100")"`

		# Unique UMIs
		c4=`cat $cout/"$condition"/"$condition".umi_prep_notes.txt | \
			grep 'UMIs left after deduplication' | head -n 1 | cut -d ' ' -f 1`
		p4=`printf "%.2f%%" "$(bc <<< "scale = 4; $c4 / $c3 * 100")"`

		# Add to summary
		new_fields="\t$c\t$p\t$c2\t$p2\t$c3\t$p3\t$c4\t$p4"
		grep "$condition" "$outcontrol/summary_sam_filter" | \
			awk -v nf="$new_fields" "{ print \$0 nf }" - \
			>> $outcontrol/summary_umi_prep
	}
	for condition in "${condv[@]}"; do
		time prepare_umi_single_condition
	done

	cp $outcontrol/summary_umi_prep $out/summary
}

################################################################################
