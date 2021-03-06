#!/usr/bin/env python3.4
"""serial_shell, - simple serial shell for talking to a serial device directly. Mostly does pretty printing and allows for easy encoding of non-ascii charaters using hex.

Usage:
  serial_shell.py [--device=<dev>] [--noline] (--ascii|--hex)
  serial_shell.py (-h | --help)
  serial_shell.py --version

Options:
  -h --help                 Show this screen.
  --version                 Show version.
  --device=<dev>            Path to /dev node corresponding to P115M. [default: /dev/mdb] 
  --noline                  Don't wait for new line to display characters as they appear
  --ascii                   Emit received data as ASCII
  --hex                     Emit received data as HEX
"""

import sys
import os
import cmd2
from docopt import docopt
from serial import setupFd
from threading import Thread
from select import select
from errno import EAGAIN
import string

args = docopt(__doc__, version="WTF")

def writeln(fd, s):
    if (isinstance(s, bytes)):
        os.write(fd, s + bytes([0xd]))
    else:
        assert(isinstance(s, str))
        os.write(fd, bytes(s+'\x0d', 'ascii'))

def readline(fd):
    res = b''
    while 1:
        b = os.read(fd, 1)
        res += b

        if (b == b'\x0d'):
            return res



# Devices
serial_fd = None
printable = set(map(ord, set(string.printable)))

noline = args['--noline']

def ppb(b):
    if b in printable:
        return "%02c" % chr(b)
    else:
        return "%02x" % b

def hexbs(s):
    return ''.join(["%02x" % x for x in s])

def ppbs(s):
    return ''.join(map(ppb, s))

def pp(s):
    if (args['--ascii']):
        return s.decode('ascii')
    else:
        return hexbs(s)

class SerialShell(cmd2.Cmd):
    def do_cmd(self, line):
        print ("SEND:[%d]: %s" % (len(line), line))
        writeln(serial_fd, line)

    def do_xcmd(self, line):
        els = line.split(' ')
        line = ''
        for x in els:
            if (x.startswith('0x')):
                line += chr(int(x, 16))
            else:
                line += x

        print ("SEND:[%d]: %s" % (len(line), line))
        writeln(serial_fd, line)

done = False
def lineReaderThr(fd):
    while (not done):
        s, dummy1, dummy2 = select([fd], [], [], 1)
        if (fd in s):
            l =readline(fd)
            print ("RECV[%03d]: %s" %(len(l), pp(l)))

def rawReaderThr(fd):
    while (not done):
        s, dummy1, dummy2 = select([fd], [], [], 1)
        if (fd in s):
            l = bytes('', 'ascii')
            while 1:
                try:
                    c = os.read(fd, 1)
                    l += c
                except IOError as e:
                    if e.errno == EAGAIN:
                        break
                    else:
                        raise e
                
            print ("RECV[%03d]: %s" %(len(l), pp(l)))

try:
    serial_fd = os.open(args['--device'], (os.O_RDWR | os.O_NOCTTY | (os.O_NONBLOCK if noline else 0)))
    setupFd(serial_fd)
except OSError as e:
    print ("Couldn't open %s: %s" % (args['--device'], str(e)))
    sys.exit(-1)

try:
    t = Thread(target=(rawReaderThr if noline else lineReaderThr), args=[serial_fd])
    t.start()
    sys.argv=[sys.argv[0]]
    shell = SerialShell()
    shell.cmdloop()
finally:
    done = True
    os.close(serial_fd)
    t.join()
