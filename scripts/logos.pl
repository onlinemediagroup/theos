#!/usr/bin/env perl -w

# I WARN YOU
# THIS IS UGLY AS SIN
# SIN IS PRETTY UGLY
#
# NO WARRANTY YET

open(FILE, $ARGV[0]);

@selectors = ();
@selectors2 = ();
@classes = ();
$numselectors = 0;
@argnames = ();
@argreturns = ();
$argcount = 0;
while($line = <FILE>) {
	# Search for a discrete %x% or an open-ended %x
	if($line =~ /(%(.*?)($|%))/) {
		my $remainder = $line;

		# Start searches where the match starts.
		my $searchpos = $-[0];

		while($remainder =~ /(%(.*?)($|%))/) {
			my $cmdwrapper = $1;
			my $cmdspec = $2;

			# Get the position of this command in the full line after $searchpos.
			my $cmdidx = index($line, $cmdwrapper, $searchpos);
			# Add the beginning of the match to the search position
			$searchpos += $-[0];
			# And chop it out of the string.
			$remainder = $';

			# Gather up all the quotes in the line.
			my @quotes = ();
			if(index($line, "\"") != -1) {
				my $qpos = 0;
				while(($qpos = index($line, "\"", $qpos)) != -1) {
					# If there's a \ before the quote, discard it.
					if($qpos > 0 && substr($line, $qpos - 1, 1) eq "\\") { $qpos++; next; }
					push(@quotes, $qpos);
					$qpos++;
				}

				my $discard = 0;
				while(@quotes > 0) {
					my $open = shift(@quotes);
					my $close = shift(@quotes);
					if($cmdidx > $open && (!$close || $cmdidx < $close)) { $discard = 1; last; }
				}
				if($discard == 1) {
					# We're discarding this match, so, add the match length (+ - -) to the search position.
					$searchpos += $+[0] - $-[0];
					next;
				}
			}

			my $replacement = parseCommand($cmdspec);
			# This is so that we always replace "blahblah%command%" with "blahblah$REPLACEMENT"
			my $preline = substr($line, 0, $cmdidx);
			$searchpos += length($replacement) - $-[0]; # Add the replacement length to the search position.
			$line =~ s/\Q$preline$cmdwrapper\E/$preline$replacement/;
		}
		print $line;
	} else {
		print $line;
	}
}

close(FILE);


sub parseCommand {
	my ($cmdspec) = @_;
	my $replacement = "";
	$cmdspec =~ /(\w*)/;
	my $command = $1;
	$cmdspec = $';

	$replacement = "";
	if($command eq "hook") {
		# Hook Macro Syntax
		# %hook Class [+|-](returnvalue)keyword:(argtype)arg keyword:(argtype)arg
		# %hook Class [+|-](returnvalue)keyword
		$cmdspec =~ /^\s*([\$\w]+?)\s+/; # Any identifier, bounded by any number of spaces
		$cmdspec = $';
		$class = $1;

		$cmdspec =~ /^\s*([-+]?)\s*/; # + or - bounded by any number of spaces
		$cmdspec = $';
		my $scope = "instance";
		$scope = "class" if $1 && $1 eq "+";

		$cmdspec =~ /^\s*\(\s*(.+?)\s*\)\s*/; # (returntype) with any number of spaces
		$cmdspec = $';
		$return = $1;

		$selector = "";
		@argnames = ();
		@argreturns = ();
		$argcount = 0;

		# Yeah it's a hack to avoid finding a simple selector after a complex one.
		my $complexselector = 0;

		# word, then an optional: ": (argtype)argname"
		while($cmdspec =~ /([\$\w]+)(:[\s]*\((.+?)\)[\s]*([\$\w]+?)($|\s+))?/) {
			$keyword = $1;
			if(!$2 && $complexselector != 1) {
				$selector = $keyword;
				$cmdspec = $';
				last;
			} elsif (!$2 && $complexselector == 1) {
				last;
			} else {
				# build our selectors out of of keywords concat'd with :s
				$selector .= $keyword.":";
				$argreturn = $3;
				$argname = $4;
				$argreturns[$argcount] = $argreturn;
				$argnames[$argcount] = $argname;
				$argcount++;
				$complexselector = 1;
			}
			$cmdspec = $';
		}
		$newselector = $selector;
		$newselector =~ s/:/\$/g;

		$classes[$numselectors] = $class;
		$selectors[$numselectors] = $selector;
		$selectors2[$numselectors] = $newselector;
		$numselectors++;

		$build = "";
		$build = "META" if $scope eq "class";
		$build .= "HOOK($class, $newselector, $return";
		for($i = 0; $i < $argcount; $i++) {
			$build .= ", ".$argreturns[$i]." ".$argnames[$i];
		}
		$build .= ")";
		$replacement = $build;
		$replacement .= $cmdspec if $cmdspec ne "";
	} elsif($command eq "orig" || $command eq "original") {
		$replacement = "CALL_ORIG($class, $newselector";
		my $hasparens = 0;
		if($cmdspec) {
			# Walk a string char-by-char, noting parenthesis depth.
			# If we encounter a ) that puts us back at zero, we found a (
			# and have reached its closing ).
			my $parenmatch = $cmdspec;
			my $pdepth = 0;
			my $endindex = 0;
			my $last = "";
			my $ignore = 0;
			while($parenmatch =~ /(.)/g) {
				$endindex++;
				if($ignore == 0) {
					if($1 eq "(") { $pdepth++; }
					elsif($1 eq ")") {
						$pdepth--;
						if($pdepth == 0) { $hasparens = $endindex; last; }
					} elsif($1 eq "\"" || $1 eq "'") {
						# If we have an unescaped quote, turn on 'ignore' mode.
						if($last ne "\\") { $ignore = 1; }
					}
				} else {
					if($1 eq "\"" || $1 eq "'") {
						# If we have an unescaped quote, turn off 'ignore' mode.
						if($last ne "\\") { $ignore = 0; }
					}
				}
				$last = $1;
			}
		}
		if($hasparens > 0) {
			$parenstring = substr($cmdspec, 1, $hasparens-2);
			$cmdspec = substr($cmdspec, $hasparens);
			$replacement .= ", ".$parenstring;
		} else {
			for($i = 0; $i < $argcount; $i++) {
				$replacement .= ", ".$argnames[$i];
			}
		}
		$replacement .= ")";
		$replacement .= $cmdspec;
	} elsif($command eq "init") {
		for($i = 0; $i < $numselectors; $i++) {
			$replacement .= "HOOK_MESSAGE_REPLACEMENT(".$classes[$i].", ".$selectors[$i].", ".$selectors2[$i].");";
		}
	}
	return $replacement;
}