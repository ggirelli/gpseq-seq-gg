
# Estimate centrality, requires two input variables:
#
# Args:
#	calc (string): 'ratio', 'diff' or 'logratio'
#	type (string): '2p' (two point), 'f' (fixed) or 'g' (global)
#	cumrat (bool): pre-processing for Cumulative of Ratio metric
#	ratcum (bool): pre-processing for Ratio of Cumulative metric

BEGIN {
	OFS = FS = "\t";

}

function estimate(calc, a, b) {
	# Return NA if either factors are NA
	if ( "NA" == a || "NA" == b ) {
		return "NA";
	} else {
		switch (calc) {
			case "ratio": {
				# Do not allow division by 0
				if ( 0 == b ) {
					return "NA";
				} else {
					return a / b;
				}
				break;
			}
			case "diff": {
				return a - b;
				break;
			}
			case "logratio": {
				# Do not allow division by 0 or log(0)
				if ( 0 <= b || 0 <= a ) {
					return "NA";
				} else {
					return log(a / b);
				}
				break;
			}
		}
	}
}

{
	# Cumulative ratio
	if ( 1 == cumrat) {
		# Sum probabilities
		for ( i = 2; i <= NF; i++ ) {
			$i = $i + $(i-1);
		}
	}

	# Ratio of cumulatives
	if ( 1 == ratcum ) {
		# Build table
		for ( i = 1; i <= NF; i++ ) {
			nf=split($i, ff, ",");
			for ( j = 1; j <= nf; j++ ) {
				a[i, j] = ff[j];
			}
		}
		# Calculate ratio of cumulatives
		for ( i = 1; i <= NF; i++ ) {
			a[i, 2] += a[i - 1, 2];
			a[i, 1] += a[i - 1, 1];
			if ( 0 == a[i, 2] || 0 == a[i, 3] || "NA" == $(i - 1)) {
				$i = "NA";
			} else {
				$i = a[i, 2] / (a[i, 1] * a[i, 3]);
			}
		}
	}

	# Calculate depending of 
	switch (type) {
		case "2p":
			print estimate(calc, $NF, $1);
			break;
		case "f":
			if ( "NA" == $1 ) {
				print "NA";
				break;
			}

			output = 0;
			for ( i = 2; i <= NF; i++ ) {
				new_value = estimate(calc, $i, $1);
				if ( "NA" == new_value ) {
					output = new_value;
				}
				if ( "NA" == output ) {
					break;
				} else {
					output = output + new_value;
				}
			}
			print output;
			break;
		case "g":
			output = 0;
			for ( i = 2; i <= NF; i++ ) {
				new_value = estimate(calc, $i, $(i-1));
				if ( "NA" == new_value ) {
					output = new_value;
				}
				if ( "NA" == output ) {
					break;
				} else {
					output = output + new_value;
				}
			}
			print output;
			break;
	}
}
