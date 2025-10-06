OBJECTS=tm

ALL=README tm tm.1 Makefile typehisto logformat typequestions

###############################################
# You may change the following to customize the installation
#
SYSBIN=/usr/local/bin/
MANDIR=/usr/local/man/man1/
CATDIR=/usr/local/man/cat1/
NINSTALL=/nfs/yaz/usr/local/ninstall/tm/files/
DOCDIR=/usr/local/doc/

MKDIR=/bin/mkdir
RM=nrm	    # safe remove (moves deleted target into ./.gone directory)
CP=ncp	    # safe copy   (doesn't overwrite)
MV=nmv	    # safe move   (doesn't overwrite)
#RM=/bin/rm
#CP=/bin/cp	 
#MV=/bin/mv	 

###############################################

install: tm
	-$(CP) tm $(SYSBIN)
	-$(CP) typehisto $(SYSBIN)
	-$(CP) tm.1 $(MANDIR)
	-$(RM) -f $(CATDIR)/tm.1
	-$(MKDIR) -p /usr/local/doc/tm
	-$(CP) -r typequestions /usr/local/doc/tm/typequestions
	-$(CP) -r README /usr/local/doc/tm/README

shar: $(ALL)  
	shar -bcvCZ $(ALL) > shar
