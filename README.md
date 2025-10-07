# typemon

Monitors typing activity and suggests rest breaks at programmable times

"typemon" is an HP-UX X11/curses-based program that attempts to reduce
repetitive stress injury (RSI) by monitoring mouse and keyboard activity
to suggest periodic rest breaks.  If the consecutive time of typing or
mousing exceeds the user-defined limits, then a warning window pops up
advising the user to take a rest break.  The window remains until there
has been no typing or mousing for the user-defined rest time. 

Included here is a version of typemon (abbreviated to "tm") for running
with the Tcl/Tk wish interpreter (for Tk version 8.4).  Check out
"https://www.tcl-lang.org/" for the latest Tcl/Tk release. 

Also included is the man page "tm.1", and the "typehisto" script for
creating a weekly typing summary for your doctor.

Do "man tm" for details on the running the program.  

Send comments, bugs, or questions to:

    Rick Walker, walker@omnisterra.com
    Tom Knotts,  tomknotts@gmail.com
