# -*- mode: makefile -*-

# gdmd -- dmd-like wrapper for gdc.
# Copyright (C) 2011, 2012 Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GCC; see the file COPYING3.  If not see
# <http://www.gnu.org/licenses/>.


DC = gdc
DFLAGS = -O3 -frelease
DESTDIR = 
prefix = /usr/local
bindir = $(prefix)/bin
man1dir = $(prefix)/share/man/man1

src = gdmd.d
exe = gdmd
man = dmd-script.1

all:	$(exe)


install: $(DESTDIR)$(bindir)/gdmd $(DESTDIR)$(man1dir)/gdmd.1

$(exe): $(src)
	-gdc $(DFLAGS) -o $@ $<

$(DESTDIR)$(bindir)/gdmd: $(exe)
	-rm -f $@
	-install $< $@


$(DESTDIR)$(man1dir)/gdmd.1: $(man)
	-rm -f $@
	-install -m 644 $< $@


uninstall:
	-rm -f $(DESTDIR)$(bindir)/gdmd
	-rm -f $(DESTDIR)$(man1dir)/gdmd.1

clean:
	-rm -f $(exe) *.o

