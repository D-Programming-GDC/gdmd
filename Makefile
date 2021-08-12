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


DESTDIR = 
target_prefix = 
prefix = /usr/local
bindir = $(prefix)/bin
man1dir = $(prefix)/share/man/man1

src = dmd-script
man = dmd-script.1

all:


install: $(DESTDIR)$(bindir)/$(target_prefix)gdmd $(DESTDIR)$(man1dir)/$(target_prefix)gdmd.1


$(DESTDIR)$(bindir)/$(target_prefix)gdmd: $(src)
	-rm -f $@
	-install $< $@


$(DESTDIR)$(man1dir)/$(target_prefix)gdmd.1: $(man)
	-rm -f $@
	-install -m 644 $< $@


uninstall:
	-rm -f $(DESTDIR)$(bindir)/$(target_prefix)gdmd
	-rm -f $(DESTDIR)$(man1dir)/$(target_prefix)gdmd.1



