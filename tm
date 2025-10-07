#!/bin/sh
# the next line restarts using wish \
exec wish "$0" "$@"


;# NOTE!!! the above line must point at a working wish binary

;#
;#    Tue Dec  5 16:16:21 PST 1995
;#
;#    This is a typing/mousing monitor program "tm" for running
;#    with the Tcl/Tk wish interpreter (for Tk version 4.0). Check out
;#    "http://web.cs.ualberta.ca/~wade/Auto/Tcl.html" for the
;#    latest Tcl/Tk release.
;#
;#    Contact Rick Walker (walker@omnisterra.com) for updates and bug
;#    reports.
;#
;#    The distribution should also have included the man page "tm.1", and
;#    the "typehisto" script for creating a weekly typing summary for
;#    your doctor.
;#
;#    After unpacking, do:
;#
;#    mv tm.1 /usr/local/man/man1
;#    mv tm /usr/local/bin
;#    mv typehisto /usr/local/bin
;#
;#    If "tm" doesn't run, check out the first line of this script.
;#    "/usr/local/bin/wish4.0" must be edited to point to the proper
;#    location and name of your "wish" binary.
;#
;#    Do "man tm" for details on the running the program.
;#
;#    In particular, this program assumes that it is running on
;#    an HP-UX platform.  For other platforms, you will need to
;#    explicitly tell "tm" which /dev files are used by your
;#    keyboard and mouse.  Alternatively, I encourage you to
;#    hack up the routine "get_dev_files" below, and mail me
;#    your changes.
;#
;#

;# tm version number
set tm_version "1.2"

;# command line global variables
set t_pause 10.0
set t_rest 30.0
set t_type 200.0
set t_mouse 400.0

;# set default obnoxiousness level:
;#   VALUE   beep?    cancel_button?   recenter_warn_window?  grab_focus?
;#     0     no	             yes	      no		     no
;#     1     yes             no		      no		     no
;#     2     yes	     no		      yes		     no
;#    >=3    yes	     no		      yes		     yes

set obnox   0

set verbose 0

;# use Stephen's xprintidle to get idle time
;# using /proc/interrupts is currently broken

set xprintidle 1

;# set up geometry for dialog boxes to be in approximately the center of
;# the display area
;#
set xmax [winfo vrootwidth .]
set ymax [winfo vrootheight .]
set geometry_dialog [format "+%d+%d" [expr int($xmax/2)] [expr int($ymax/2)]]

wm geometry . +0+0

;# global variables
set nextstate Active
set tidle 0.0
set midle 0.0
set toldidle 0.0
set moldidle 0.0
set t_total 0.0
set m_total 0.0
set a_total 0.0
set latency 2.5
set delta_time 0.0
set ACTIVITY_LIMIT 100.0
set activity 0.0
set fplog ""
set fpquest ""
set state Active
set mode 1.0
set queried 0

set now [clock seconds]
set x ""
set y ""
set xold ""
set yold ""

set logfile ~/.typelogx
#set logfile ~/.typelog

# variables for question asking functionality

set questfile ~/.typequestions
# $questions set to 1 if question file is successfully opened
set questions 0

proc openlog {mode permission} {
	global fplog
	global logfile

	catch {close $fplog}

	set c [catch {open $logfile $mode $permission} fplog]
	if {$c != 0} {
		tkerror "couldn't open logfile!"
	}
	return $c
}

openlog {CREAT RDWR APPEND} 0600

set now [clock seconds]
set then $now

set date [clock format [clock seconds] -format "+%m/%d/%y %H:%M:%S"]

set old_date $date

scan $date "%s" day
set old_day $day
scan $date "%s %d:%d:%d" tmp1 H M tmp2
set time [format "%02d:%02d" $H $M]

proc usage {} {
	puts {usage: [options] [keyboard_dev_path] [mouse_dev_path]}
	puts {   [-b] run in background, ie., don't create main status window}
	puts {   [-geometry <X11_geometry_spec>] set main status window location}
	puts {   [-l <seconds>] latency time in main loop - shorter times use more CPU}
	puts {   [-m <seconds>] set maximum mousing time}
	puts {   [-o <1-3>] set warning obnoxiousness level}
	puts {   [-p <seconds>] set pause time}
	puts {   [-r <seconds>] set resting time}
	puts {   [-t <seconds>] set maximim typing time}
	puts {   [-v] enable verbose log file}
	puts {   [-i] use old /proc/interrupts code instead of xprintidle}
}

;# options "dfngsh" are already grabbed by wish!
#set c [catch {eval exec getopt bl:m:o:p:r:t:v $argv 2>/dev/null} s]
#if { $c != 0} {
#    puts "$argv0: $s"
#    puts ""
#    usage
#    exit 2
#}

set s $argv
set nargs [llength $s]

;# options "dfngsh" are already grabbed by wish!
set argind 0
while {$argind < $nargs} {
	set opt [lindex $s $argind]
	switch -- $opt {
		-b { wm withdraw . ; incr argind 1 }
		-i {set xprintidle 0; incr argind 1}
		-l {set latency [lindex $s [incr argind 1]]; incr argind 1}
		-m {set t_mouse [lindex $s [incr argind 1]]; incr argind 1}
		-o {set obnox   [lindex $s [incr argind 1]]; incr argind 1}
		-p {set t_pause [lindex $s [incr argind 1]]; incr argind 1}
		-r {set t_rest  [lindex $s [incr argind 1]]; incr argind 1}
		-t {set t_type  [lindex $s [incr argind 1]]; incr argind 1}
		-v {set verbose 1; incr argind 1}
		-- {incr argind 1; break}
		default {
			puts "argv0: unknown option $opt";
			usage;
			exit 3;
		}
	}
}

proc get_dev_files {} {

	;# set definitions for get_idle() routine
	;#

	global tcl_platform

	switch $tcl_platform(platform) {
	    unix {

		proc get_idle {t m d} {
		    upvar $m midle
		    upvar $t tidle
		    upvar $d delta_time

		    global now
		    global x
		    global y
		    global xold
		    global yold
		    global xprintidle

		    set then $now
		    set now [clock seconds]

		    set delta_time [expr {$now - $then}]

		    if {$xprintidle == 1} {

			;# both mouse and keyboard idle time is reported by xprintidle
			;# maybe merge midle and tidle into single idle variable?
			;# - stephen

			# get idle time from xprintidle
			if {[catch {exec xprintidle} idle_ms]} {
			    puts "ERROR: xprintidle not available"
			    puts "you can download it with sudo apt install xprintidle"
			    exit 5
			}

			set idle_sec [expr {$idle_ms / 1000.0}]

			set tidle $idle_sec
			set midle $idle_sec

		    } else {
			;# use old /proc/interrupts code
			;# this is probably broken on newer systems
			;# so is turned off by default
			;#
			;# left here to show how to handle keyboard and mouse time
			;# separately since they have different physiological impacts
			;# for most people.

			set f [open {| cat /proc/interrupts}]
			while {[gets $f line] >= 0} {
			    if [regexp " 12:" $line] {
                                set xold $x
				set x [lindex $line 1]
			    } elseif [regexp " 1:" $line] {
				set yold $y
				set y [lindex $line 1]
			    }
                         }
                         close $f

                         if {$yold == $y} {
                             set tidle [expr $tidle + $delta_time]
                         } else {
                             set tidle 0
                         }

                         if {$xold == $x} {
                             set midle [expr $midle + $delta_time]
                         } else {
                             set midle 0
                         }
		    }
		}
	    }

	    windows {
		    puts "on WINDOWS"
	    }

	    macintosh {
		    puts "on MAC"
	    }
	}
}

get_dev_files

proc show_options {} {
	global t_mouse obnox t_pause t_rest t_type verbose latency xprintidle
	set text ""
	set text "$text t_type  (-t) = $t_type\n"
	set text "$text t_mouse (-m) = $t_mouse\n"
	set text "$text t_pause (-p) = $t_pause\n"
	set text "$text t_rest  (-r) = $t_rest\n"
	set text "$text latency (-l) = $latency\n"
	set text "$text obnox   (-o) = $obnox\n"
	set text "$text verbose (-v) = $verbose\n"
	set text "$text xprintidle (-x) = $xprintidle\n"

	tk_dialog .options tm.options $text "" 0 ok
}

proc show_version {} {
	global tm_version
	set text ""
	set text "$text tm version $tm_version is copyright"
	set text "$text 1995,1996,1997,1998,1999,2005,2025 by"
	set text "$text Richard Walker (walker@omnisterra.com), and"
	set text "$text Tom Knotts (tomknotts@gmail.com).  It may"
	set text "$text be freely used and copied for personal use, as"
	set text "$text long as this notice is preserved intact."

	tk_dialog .options tm.version $text "" 0 ok
}

frame .mbar -relief raised -bd 2
menubutton .mbar.options -text Options -underline 0 -menu .mbar.options.menu
label .mbar.time  -font *-*-bold-r-normal--*-140-*-*-m-*-*-* -textvariable time -relief flat -anchor w

menu .mbar.options.menu
.mbar.options.menu add command -label "reset timer" -command {
	set activity 0.0
	if {$obnox == 0} {
		changestate Rest Idle $date;
		end_rest
	}
}

;#.mbar.options.menu add command -label "cancel rest" -command {
	;#    set activity 0.0;
	;#    changestate Rest Idle $date;
	;#    end_rest
	;#
;#}

.mbar.options.menu add command -label "show options" -command "show_options"
.mbar.options.menu add command -label "show version" -command "show_version"

set mode 1.0
button .mbar.going -text stop -command {
	global mode
	if [expr ($mode == 0.0)] {
		set mode 1.0
		.mbar.going config -text "stop "
		.wrap.bar config -bg SteelBlue1
	} elseif [expr ($mode == 1.0)] {
		set mode 0.0

		;# uncommenting these next few lines cause the "Stop" button
		;# to zero out any accumulated working time

		;# changestate Rest Idle $date;
		;# end_rest

		.mbar.going config -text "start"
		.wrap.bar config -bg Red
	}
}

;#pack .mbar -side top -fill x
;#pack .mbar.options .mbar.going -side left
;#pack .mbar.going -side right
;#pack .mbar.time -expand 1 -fill x

pack .mbar -side top -fill x
pack .mbar.options .mbar.time .mbar.going -expand 1 -side left -fill x

frame .space -width 234 -height 1
frame .wrap -width 230 -height 20 -borderwidth 2 -relief sunken
frame .wrap.bar -width 220 -height 15 -relief flat -borderwidth 2 -bg SteelBlue1
frame .wrap.barrest -width 220 -height 5 -relief flat -borderwidth 2 -bg Green
pack .space -side top
pack .wrap -fill x -side top -padx 5 -pady 5 -anchor sw
pack .wrap.bar -side top -anchor sw
pack .wrap.barrest -side top -anchor sw

label .mode  -font *-*-bold-r-normal--*-140-*-*-m-*-*-* -textvariable annunciate1 -relief flat -anchor w

pack .mode -side top
wm maxsize . 1000 1000

proc tick {} {
	global ACTIVITY_LIMIT
	global a_total
	global activity
	global date old_date
	global day old_day
	global delta_time
	global fplog
	global latency
	global logfile
	global m_total
	global midle
	global moldidle
	global mode
	global nextstate
	global now then
	global obnox
	global state
	global t_mouse
	global t_pause
	global t_rest
	global t_total
	global t_type
	global tidle toldidle
	global verbose
	global time
	global queried
	global geometry_dialog
	global xprintidle

	set old_date $date
	set date [clock format [clock seconds] -format "+%m/%d/%y %H:%M:%S"]
	scan $date "%s %d:%d:%d" tmp1 H M tmp2
	set time [format "%02d:%02d" $H $M]

	set toldidle $tidle
	set moldidle $midle

	get_idle tidle midle delta_time

	set old_day  $day
	scan $date "%s" day

	;# reset total times everyday at midnight

	if { $day != $old_day } {
		changestate NULL Summary $old_date
		set t_total 0.0
		set m_total 0.0
		set a_total 0.0
	}

	set state $nextstate

	set width [expr int($activity * 220 / $ACTIVITY_LIMIT)]
	set rwidth [min [expr int(220.0*[min $tidle $midle]/$t_rest)] 220]
	.wrap.bar config -width ${width} -height 15
	.wrap.barrest config -width ${rwidth} -height 5

	switch $state  {
		Idle {
			set queried 0
			set activity 0.0
			if { $tidle <= $t_rest || $midle <= $t_rest } {
				changestate $state Active $date
			}
		}
		Active {
			if { $tidle <= $t_pause } {
				set t_total [expr $t_total + $delta_time]
				set t_activity [expr $ACTIVITY_LIMIT * $delta_time / $t_type]
			} else {
				set t_activity 0.0
			}
			if { $midle <= $t_pause } {
				set m_total [expr $m_total + $delta_time]
				set m_activity [expr $ACTIVITY_LIMIT * $delta_time / $t_mouse]
			} else {
				set m_activity 0.0
			}
			if { $tidle <= $t_pause || $midle <= $t_pause} {
				set a_total [expr $a_total + $delta_time]
			}

			set aval [expr $activity+$mode*[max $t_activity $m_activity]]
			set activity [expr [min $aval $ACTIVITY_LIMIT]]

			if { $tidle >= $t_rest && $midle >= $t_rest } {
				end_rest
				set activity 0.0
				changestate $state Idle $date
			} elseif { $tidle >= $t_pause && $midle >= $t_pause } {
				changestate $state Paused $date
			} elseif { $activity >= $ACTIVITY_LIMIT } {
				end_rest
				catch {doWarn .warn "Take a Break" $geometry_dialog}
				changestate $state Warning $date
			}
		}
		Paused {
			if { $tidle <= $t_pause || $midle <= $t_pause} {
				changestate $state Active $date
			} elseif { $tidle >= $t_rest && $midle >= $t_rest } {
				end_rest
				set activity 0.0
				changestate $state Idle $date
			}
		}
		Warning {
			# We use the $queried variable to make sure we only ask
			# *one* question per rest cycle.  $queried is only cleared
			# in Idle state.

			if { $queried == 0 } {
				do_quest
				set queried 1
			}

			if { $tidle <= $t_pause } {
				set t_total [expr $t_total + $delta_time]
				set t_activity [expr $ACTIVITY_LIMIT * $delta_time / $t_type]
			} else {
				set t_activity 0.0
			}
			if { $midle <= $t_pause } {
				set m_total [expr $m_total + $delta_time]
				set m_activity [expr $ACTIVITY_LIMIT * $delta_time / $t_mouse]
			} else {
				set m_activity 0.0
			}
			if { $tidle <= $t_pause || $midle <= $t_pause} {
				set a_total [expr $a_total + $delta_time]
			}

			set aval [expr $activity+$mode*[max $t_activity $m_activity]]
			set activity [expr [min $aval $ACTIVITY_LIMIT]]

			if {$tidle > $toldidle && $midle > $moldidle} {
				catch {doWarn .warn "Continue Resting" +6+6}
				changestate $state Resting $date
			} elseif {$tidle <= $toldidle || $midle <= $moldidle} {
				change_rest 0.0
				switch $obnox {
					0 { ; }
					1 { doWarn .warn "Continue Resting" +6+6; beep }
					2 { doWarn .warn "Take a Break!" $geometry_dialog; beep }
					default {
						doWarn .warn "Take a Break!" $geometry_dialog;
						catch { grab set -global . }
						beep
					}
				}
			}
		}
		Resting {
			change_rest [expr [min $tidle $midle]/($t_rest + 0.0)]
			if {$tidle >= $t_rest && $midle >= $t_rest} {
				beep
				end_rest
				set activity 0.0
				if {$obnox > 2} {
					catch { grab release . }
				}
				changestate $state Idle $date
			} elseif {$tidle <= $toldidle || $midle <= $moldidle} {
				change_rest 0.0
				switch $obnox {
					0 { ; }
					1 { doWarn .warn "Continue Resting" +6+6; beep }
					2 { doWarn .warn "Take a Break!" $geometry_dialog; beep }
					default {
						doWarn .warn "Take a Break!" $geometry_dialog;
						catch { grab set -global . }
						beep
					}
				}
				changestate $state Warning $date
			}
		}
		default {
			puts "$argv0: error in state table!" > stderr
			exit 4
			break
		}
	}

	global annunciate1

	set annunciate1 [format "\[%-7s\] Total=%s " $state \
		[ptime $a_total] ]

	if { $state == "Resting" || $state == "Warning" } {
		after 1000 tick	;# high res for bargraph display
	} else {
		after [expr int($latency * 1000) ] tick
	}
}

proc ptime {t} {
	set sec [expr fmod($t,60.0)]
	set min [expr fmod(($t-$sec)/60.0,60.0)]
	set hrs [expr (((($t-$sec)/60.0)-$min)/60.0)]
	return [format "%02d:%02d:%02d"\
		[expr int($hrs)] [expr int($min)] [expr int($sec)] ]
}

proc min {a b} {
	if { $a <= $b } {
		return $a
	} else {
		return $b
	}
}

proc max {a b} {
	if { $a >= $b } {
		return $a
	} else {
		return $b
	}
}



proc changestate {oldstate ns datestring} {

	global fplog
	global t_total m_total a_total
	global nextstate verbose

	if { $oldstate != "NULL" } {
		set nextstate $ns
	}

	if { $ns == "Summary" || \
		$ns == "KILLED"  || \
			$ns == "RESTART" || $verbose }  {

			openlog {CREAT RDWR APPEND} 0600
		puts -nonewline $fplog [format "%s \[%s\] " $datestring $ns]
		puts -nonewline $fplog " T = "
		puts -nonewline $fplog [ptime $t_total]
		puts -nonewline $fplog ", M = "
		puts -nonewline $fplog [ptime $m_total]
		puts -nonewline $fplog ", A = "
		puts $fplog [ptime $a_total]

		# dump out question tally summary
		set text [ query_quest ]
		if { $text != "" } {
			puts -nonewline $fplog [format "%s \[%s\] " $datestring "QUESTION"]
			puts $fplog $text
		}

		flush $fplog
	}
}

proc inittime {} {

	global m_total t_total a_total
	global fplog

	if {[openlog {RDWR CREAT} 0600 ] == 1} {
		puts "can\'t open logfile"
		exit 2
	}

	scan [clock format [clock seconds] -format "+%m %d %y"] "%d %d %d" \
		today_month today_day today_year

	while { [gets $fplog line] != -1 } {
		set string $line
		regsub -all {\[|\]} $string " " line

		set test [scan $line \
			"%d/%d/%d %s %s T = %d:%d:%d, M = %d:%d:%d, A = %d:%d:%d" \
			month day year hms state th tm ts mh mm ms ah am as]

		if { $test == 14 && \
			$today_month == $month && \
				$today_day == $day &&  \
				$today_year == $year && \
				$state != "Summary"} {
				set t_total [expr 60.0*60.0*$th + 60.0*$tm + 1.0*$ts]
			set m_total [expr 60.0*60.0*$mh + 60.0*$mm + 1.0*$ms]
			set a_total [expr 60.0*60.0*$ah + 60.0*$am + 1.0*$as]
		}
	}
}

proc change_rest {value} {
	.warn.wrap.bar config -width [eval expr int(220 * $value)] -height 20
}

proc end_rest {} {
	catch {destroy .warn}
}

proc beep {} {
	bell
	# puts -nonewline "\a"
}

proc doWarn {w msg geometry} {

	global $w.wrap.bar
	global activity

	if { [winfo exists $w] } {
		raise $w;
		wm deiconify $w;
		wm geometry $w $geometry
		$w.msg configure -text $msg
	} else {
		toplevel $w -width 220
		wm title $w tm.warn

		# don't allow warning window to be deleted
		wm protocol $w WM_DELETE_WINDOW { beep }

		wm geometry $w $geometry
		label $w.bmap -bitmap warning -relief flat
		label $w.msg -text $msg  -relief flat -anchor w -font *-*-bold-r-normal--*-140-*-*-m-*-*-*
		frame $w.space -width 220 -height 1
		frame $w.wrap -width 220 -height 30 -borderwidth 2 -relief raised -bg White
		frame $w.wrap.bar -width 1 -height 20 -relief raised -borderwidth 2 -bg Red
		pack $w.space -side bottom
		pack $w.wrap -side bottom -fill x -anchor sw
		pack $w.wrap.bar -side bottom -anchor sw
		pack $w.bmap -side left -fill both
		pack $w.msg -side left -fill both
		if {$obnox == 0} {
			button $w.cancel -text cancel -command {
				set activity 0.0;
				changestate Rest Idle $date;
				end_rest
			}
			pack $w.cancel -side right -fill x
		}
	}
}

proc abort {} {
	global fplog date
	end_rest
	changestate NULL KILLED $date
	flush $fplog
	destroy .
}


#################################################################
# code for question functionality
# RCW 6/17/99
#

proc load_quests {} {

	global quests
	global questfile
	global questions

	set c [catch {open $questfile} fd]
	if {$c != 0} {
		set text ""
		set text "$text typemon could not open the questions file"
		set text "$text at \"$questfile\".  The program will still run"
		set text "$text but won't be able to prompt you for any"
		set text "$text ergonomics questions.  Please copy the file"
		set text "$text \"/usr/local/doc/tm/typequestions\" to your"
		set text "$text home directory as \"$questfile\", edit it to"
		set text "$text select which questions to use, and restart tm."
		tk_dialog .error tm.warning $text "warning" 0 Ok
		set questions 0
		return
	}

	set s ""
	set state "out"
	set recordno 1

	while {[gets $fd line] > -1} {

		#set s [list $line]

		if {($line == "")} {
			if { $state == "in" } {
				set quests($recordno) $s
				set s ""
				incr recordno
				set state "out"
			}
		} elseif {([ string first "#" $line ] == 0)} {
			#puts "got comment $line"
		} else {
			set s "$s $line"
			set state "in"
		}
	}
	if { ($state == "in")  && ($recordno > 1)} {
		set quests($recordno) $s
	}
	close $fd

	if {$recordno > 1} {
		set questions 1
	} else {
		set text ""
		set text "$text typemon found no questions in the file"
		set text "$text questions file.  The program"
		set text "$text will still run but won't be able to prompt"
		set text "$text you for any ergonomics questions.  Perhaps you"
		set text "$text should uncomment a few of the questions in"
		set text "$text the \"$questfile\" questions file?"
		tk_dialog .error tm.warning $text "warning" 0 Ok
		set questions 0
	}
}

proc do_quest {} {

	global quests
	global yes
	global no
	global asked
	global questions

	if { $questions != 1 } {
		# no questions loaded, so skip questions
		return
	}

	# generate a random quote:
	set n [array size quests]
	set x [expr "int(fmod(rand()*$n*1000,$n))+1"]
	set questnum [lindex $quests($x) 0]

	# eliminate any extra punctuation on the question number.
	# this allows questions to be introduced with eg: 1), 1., or 1> etc.
	regsub -all {[^0-9]} $questnum "" questnum
	#puts "$questnum: $quests($x)"

	set retcode [dialog .query tm.query "$quests($x)" "question" -1 yes no]

	# atouch sets null array elements to "0" and is used
	# to avoid getting an error from incrementing a non-existant
	# array element.

	atouch asked questnum
	incr asked($questnum)
	if { $retcode == "0" } {
		atouch yes questnum
		atouch no  questnum
		incr yes($questnum)
	} else {
		atouch yes questnum
		atouch no  questnum
		incr no($questnum)
	}

}

# query_quest returns a string summarizing the questions asked since
# the previous call.  The question tally counter are zero'ed by the
# call, so question counting starts over from scratch.  Normally this
# routine is called at midnight each night, to put the question info
# into the typemon log file for later analysis.  The format is:
# <question_number>:<number_of_yes>/<number_of_no>, eg: yes10:2/3

proc query_quest {} {

	global yes
	global no
	global asked

	if ![ info exists asked ] {
		return ""
	}

	set text ""
	foreach el [ lsort -integer [array names asked] ] {
		set text "$text $el:$yes($el)/$no($el)"
		unset asked($el)
		unset yes($el)
		unset no($el)
	}
	return $text
}

# this routine is used to touch an array entry.  It tests if the array
# element doesn't already exist, and if so, sets the contents of
# array($index) to 0. This makes it possible to write code that doesn't
# produce a "variable array($index) doesn't exist!" error message.

proc atouch {array index} {
	upvar $array a
	upvar $index i
	if ![ info exists a($i) ] {
		set a($i) 0
	}
}

proc dialog {w title text bitmap default args} {
	global button
	global geometry_dialog

	# 1. Create the top-level window and divide it into  top
	# and bottom parts.

	toplevel $w -class Dialog
	wm title $w $title
	wm iconname $w Dialog
	wm geometry $w $geometry_dialog
	frame $w.top -relief raised -bd 1
	pack $w.top -side top -fill both
	frame $w.bot -relief raised -bd 1
	pack $w.bot -side bottom -fill both

	# 2. Fill the top part with the bitmap and message.

	message $w.top.msg -width 3i -text $text\
		-font *-*-bold-r-normal--*-140-*-*-m-*-*-*
	pack $w.top.msg -side right -expand 1 -fill both\
		-padx 3m -pady 3m
	if {$bitmap != ""} {
		label $w.top.bitmap -bitmap $bitmap
		pack $w.top.bitmap -side left -padx 3m -pady 3m
	}

	# 3. Create a row of buttons at the bttom of the dialog.

	set i 0
	foreach but $args {
		button $w.bot.button$i -text $but -command\
			"set button $i"
		if {$i == $default} {
			frame $w.bot.default -relief sunken -bd 1
			raise $w.bot.button$i
			pack $w.bot.default -side left -expand 1\
				-padx 3m -pady 2m
			pack $w.bot.button$i -in $w.bot.default\
				-side left -padx 2m -pady 2m\
				-ipadx 2m -ipady 1m
		} else {
			pack $w.bot.button$i -side left -expand 1\
				-padx 3m -pady 3m -ipadx 2m -ipady 1m
		}
		incr i
	}

	# 4. Set up a binding for <Return>, if there's a default,
	# set a grab, and claim the focus too.

	if {$default >= 0} {
		bind $w <Return> "$w.bot.button$default flash; \
			set button $default"
	}
	set oldFocus [focus]
	tkwait visibility $w
	catch { grab set -global $w }
	focus $w

	# 5. Wait for the user to respond, then restore the focus
	# and return the index of the selected button.

	tkwait variable button
	destroy $w
	focus $oldFocus
	return $button
}

# some stubs for testing
#load_quests
#do_quest
#puts [ query_quest ]
#exit

##################################################
# end of code for question functionality
#


;# Set as many traps as we can to ensure that the
;# logfile gets updated whenever typemon is killed
;#
wm protocol . WM_DELETE_WINDOW { abort }
wm protocol . WM_SAVE_YOURSELF { abort }
bind . <Control-c> {abort}
bind . <Control-q> {abort}
focus .

inittime
load_quests
openlog {RDWR CREAT APPEND} 0600
puts $fplog [format "#Options: -t%g -m%g -r%g -p%g -o%d" \
	$t_type $t_mouse $t_rest $t_pause $obnox ]
changestate NULL RESTART $date

tick


