#!/usr/bin/env python3

import argparse
import hashlib
import math
import os
import sys
from parse import parse

PREP =          0x08
DESC =          0x20    #  infocom V1-5 only -- actually an adjective. 
NOUN =          0x80
VERB =          0x40    #  infocom V1-5 only 
DIR =           0x10    #  infocom V1-5 only 
VERB_INFORM =   0x01
VERB_V6 =       0x01
PLURAL =        0x04    #  inform only 
SPECIAL =       0x04    #  infocom V1-5 only 
META =          0x02    #  infocom V1-5 only 
DATA_FIRST =    0x03    #  infocom V1-5 only 
DIR_FIRST =     0x03    #  infocom V1-5 only 
ADJ_FIRST =     0x02    #  infocom V1-5 only 
VERB_FIRST =    0x01    #  infocom V1-5 only 
PREP_FIRST =    0x00    #  infocom V1-5 only 
ENDIT =         0x0F

def word(w):
    return w[0] * 256 + w[1]
    
class Zscii:
    modern_zscii = [
      " ^^^^^abcdefghijklmnopqrstuvwxyz ",
      " ^^^^^ABCDEFGHIJKLMNOPQRSTUVWXYZ ",
      " ^^^^^ \n0123456789.,!?_#'\"/\\-:() ",
    ]
    old_zscii = [
      " \n^^^^abcdefghijklmnopqrstuvwxyz ",
      " \n^^^^ABCDEFGHIJKLMNOPQRSTUVWXYZ ",
      " \n^^^^ 0123456789.,!?_#'\"/\\>-:() ",
      " \n^^^^abcdefghijklmnopqrstuvwxyz ",
    ]

    story = None

    def __init__(self, s_obj):
        self.story = s_obj
        self.bytes_read = None

        v = s_obj.header["version"]
        if v < 2:
            self.zscii = self.old_zscii
        else:
            self.zscii = self.modern_zscii

    def convert_zscii_bytes(self, bytes):
        zstring = ""
        shift_lock, shift, abbrev_flag, ascii_flag = 0, -1, False, False

        v = self.story.header["version"]
        zscii = self.zscii

        for i, b in enumerate(bytes):
            if ascii_flag:
                ascii_flag = False
                i += 1
                if i == len(bytes):
                    return zstring
                zstring += chr(bytes[i-1] << 5 | b)
                continue
            if abbrev_flag:
                ndx = 32 * (bytes[i-1]-1) + b
                zstring += self.story.abbreviations[ndx]
                abbrev_flag = False
                shift = -1
                continue

            if b == 0:
                zstring += " "
                continue
            elif b == 1:
                if v < 2:
                    zstring += "\n"
                else:
                    abbrev_flag = True
                continue
            elif b == 2:
                if v < 3:
                    shift = (shift_lock + 1) % 3
                else:
                    abbrev_flag = True
                continue
            elif b == 3:
                if v < 3:
                    shift = (shift_lock + 2) % 3
                else:
                    abbrev_flag = True
                continue
            elif b == 4:
                if v < 3:
                    shift_lock = (shift_lock + 1) % 3
                else:
                    shift = 1
                    abbrev_flag = False
                continue
            elif b == 5:
                if v < 3:
                    shift_lock = (shift_lock + 2) % 3
                else:
                    shift = 2
                    abbrev_flag = False
                continue
            elif b == 6:
                if shift == 2:
                    shift = -1
                    ascii_flag = True
                    continue

            if shift > -1:
                zstring += zscii[shift][b]
            else:
                zstring += zscii[shift_lock][b]
            shift = -1
            abbrev_flag = False
        return zstring

    def read_text(self, addr, len, inform_escapes=True):
        bytes = []
        
        i = 0
        for i in range(len):
            w = word(self.story.contents[addr + i * 2:addr + i * 2 + 2])
            bit = w >> 15
            c3 = w & 31
            c2 = (w & 0x3e0) >> 5
            c1 = (w & 0x7c00) >> 10

            bytes += [ c1, c2, c3 ]
            if bit: 
                i += 1
                break

        self.bytes_read = i * 2
        zs = self.convert_zscii_bytes(bytes)
        if inform_escapes:
            zs = zs.replace('"', "~").replace("\n", "^")
        return zs
    
# https://stackoverflow.com/questions/1524126/how-to-print-a-list-more-nicely
def list_columns(obj, cols=4, columnwise=True, gap=4):
    """
    Print the given list in evenly-spaced columns.

    Parameters
    ----------
    obj : list
        The list to be printed.
    cols : int
        The number of columns in which the list should be printed.
    columnwise : bool, default=True
        If True, the items in the list will be printed column-wise.
        If False the items in the list will be printed row-wise.
    gap : int
        The number of spaces that should separate the longest column
        item/s from the next column. This is the effective spacing
        between columns based on the maximum len() of the list items.
    """

    sobj = [str(item) for item in obj]
    if cols > len(sobj): cols = len(sobj)
    max_len = max([len(item) for item in sobj])
    if columnwise: cols = int(math.ceil(float(len(sobj)) / float(cols)))
    plist = [sobj[i: i+cols] for i in range(0, len(sobj), cols)]
    if columnwise:
        if not len(plist[-1]) == cols:
            plist[-1].extend(['']*(len(sobj) - len(plist[-1])))
        plist = zip(*plist)
    printer = '\n'.join([
        ''.join([c.ljust(max_len + gap) for c in p])
        for p in plist])
    print(printer)

def print_table(arr):
    if not arr:
        return

    maxlen = len(max(arr, key=len))
    list_columns(arr, cols=(80 // maxlen))
    
class Dictword:
    def determine_type(self):
        bytes = self.bytes

        dir_t, adj_t, verb_t, prep_t, noun_t, special_t = 0, 0, 0, 0, 0, 0

        flag = bytes[0] & DATA_FIRST
        if flag == DIR_FIRST:
            if bytes[0] & DIR:
                dir_t = "<dir>"
        elif flag == ADJ_FIRST:
            if bytes[0] & DESC:
                adj_t = "<adj>"
        elif flag == VERB_FIRST:
            if bytes[0] & VERB:
                verb_t = "<verb>"
        elif flag == PREP_FIRST:
            if bytes[0] & PREP:
                prep_t = "<prep>"

        if (bytes[0] & DIR)  and (flag != DIR_FIRST):  dir_t = "<dir>";
        if (bytes[0] & DESC) and (flag != ADJ_FIRST):  adj_t = "<adj>";
        if (bytes[0] & VERB) and (flag != VERB_FIRST): verb_t = "<verb>";
        if (bytes[0] & PREP) and (flag != PREP_FIRST): prep_t = "<prep>";
        if bytes[0] & NOUN: noun_t = "<noun>";
        if bytes[0] & SPECIAL: noun_t = "<special>";

        self.types = [x for x in [ dir_t, adj_t, verb_t, prep_t, noun_t, special_t ] if x != 0]

    def __init__(self, story, addr, ws, num):
        self.addr = addr
        self.size = ws
        self.num = num
        self.text = story.zscii.read_text(addr, 4)
        self.bytes = story.contents[addr + 4:addr + ws]
        self.determine_type()

    def query_type(self, s):
        if s in self.types:
            return self.bytes[1]
        return False

    def show_me(self, show_addr=False, show_type=False):
        if show_type:
            return "[{0:3d] @ ${1:04x} {2} [{3}] {4}".format(self.num, self.addr, self.text.ljust(self.size),
                " ".join(["{:02x}".format(h) for h in bytes]), " ".join(self.types))
        if show_addr:
            return "[{0:04x} {1}".format(self.addr, self.text.ljust(self.size))
        return "[{0:3d}] {1}".format(self.num, self.text.ljust(self.size))

    def __str__(self):
        return self.show_me()

    def __repr__(self):
        return self.show_me()

class Zobj:
    def parse_attributes(self, bytes):
        a = set()
        for j, b in enumerate(bytes):
            for i in range(7, -1, -1):
                if (1 << i) & b:
                    a.add(j*8 + (8-i) - 1)
        self.attributes = a

    def __init__(self, story, bytes, attr):
        self.bytes = bytes
        self.story = story
        self.parse_attributes(attr)

    def __repr__(self):
        return "Obj({0})".format(self.description)

class Story:
    zscii = False
    configuration = None

    def fatal(self, s):
        print("{0}: {1}".format(self.filename, s))
        sys.exit(1)
        
    def parse_header(self):
        h = self.header = dict()
        c = self.contents

        if 0 < c[0] < 9:
            h["version"] = version = c[0]
        else:
            self.fatal("unknown zmachine version (byte 0x00={:d}, expecting 1-8)".format(c[0]))

        h["flags"] = c[1]
        h["release"] = word(c[2:4])
        h["highmem"] = word(c[4:6])
        h["pc"]      = word(c[6:8])
        h["dict"]    = word(c[8:10])
        h["otable"]  = word(c[0xa:0xc])
        h["globals"] = word(c[0xc:0xe])
        h["static"]  = word(c[0xe:0x10])
        h["gflags"]  = word(c[0x10:0x12])
        h["serial"]  = c[18:24].decode("utf-8")
        if version >= 2:
            h["abbr"]    = word(c[0x18:0x1a])
        else:
            h["abbr"] = None
        if version >= 3:
            h["filelen"] = word(c[0x1a:0x1c])
            h["cksum"]   = word(c[0x1c:0x1e])
        else:
            h["cksum"]   = None
            h["filelen"] = None
        

    def read_dictionary(self):
        self.dictionary = []
        self.verb_map = dict()

        addr = self.header["dict"]

        separator_count = self.contents[addr]
        addr += 1

        separators = []
        for i in range(separator_count):
            separators.append(chr(self.contents[addr + i]))
        addr += separator_count

        word_size = self.contents[addr]
        addr += 1
        word_count = word(self.contents[addr:addr+2])
        addr += 2

        for i in range(word_count):
            d = Dictword(self, addr, word_size, i)
            if "<verb>" in d.types:
                if d.bytes[2] == 0:
                    v_num = d.bytes[1]
                    if v_num not in self.verb_map:
                        self.verb_map[v_num] = [ 0, []]
                    self.verb_map[v_num][1].append(d)
            if "<adj>" in d.types:
                if d.bytes[1] == 1:
                    self.adjectives[d.bytes[2]] = d
                else:
                    self.adjectives[d.bytes[1]] = d

            self.dictionary.append(d)
            self.addr_to_dict[addr] = self.dictionary[-1]

            addr += word_size
        self.game_map.append([ self.header["dict"], addr - 1, "Dictionary" ])
        if self.hs_addr:
            self.game_map.append([addr, self.hs_addr - 1, "Routines" ])
        else:
            self.game_map.append([addr, self.header["filelen"] or len(self.contents), "Paged memory (routines + high_strings)"])

    def read_abbreviations(self):
        v = self.header["version"]
        hi, lo = -1, 0x7ffff

        if v == 1:
            return

        z = self.zscii
        addr = self.header["abbr"]
        if not addr:
            return

        max_a = 32 if v == 2 else 96
        abbr = self.abbreviations = [0] * max_a

        zo = self.zscii
        for i in range(max_a):
            abbr[i] = z.read_text(word(self.contents[addr:addr+2]) * 2, 753)
            lo = min(word(self.contents[addr:addr+2]) * 2, lo)
            hi = max(word(self.contents[addr:addr+2]) * 2 + z.bytes_read - 1, hi)
            addr += 2
        self.game_map.append([ self.header["abbr"], addr - 1, "Abbreviation pointer data" ])
        self.game_map.append([ lo, hi, "Abbreviation data" ])
            
    def interpret_flags(self, b):
        flags = []
        
        if self.header["version"] < 4:
            flag_str = [ "Byte swapped data", "Display time", "Split across disks",
                "Tandy", "No status line", "Windows available", "Proportional fonts used",
                "Unknown (0x80)" ]
        else:
             flag_str = [ "Colours", "Pictures", "Bold font", "Emphasis", "Fixed space font",
                "Unknown (0x20)", "Unknown (0x40)", "Timed input" ]

        for i in range(8):
            if b & (1 << i):
                flags.append(flag_str[i])
            elif self.header["version"] < 4 and i == 1:
                flags.append("Display score/moves")

        if flags:
            return ", ".join(flags) # + " ({0:08b})".format(b)
        else:
            return "None"

    def game_flags(self, b):
        flags = []
        if self.header["version"] < 4:
            flag_str = [ "Scripting", "Use fixed font", "Unknown (0x0004)", "Unknown (0x0008)",
                "Supports sound", "Unknown (0x0010)", "Unknown (0x0020)", "Unknown (0x0040)",
                "Unknown (0x0080)", "Unknown (0x0200)", "Unknown (0x0400)", "Unknown (0x0800)",
                "Unknown (0x1000)", "Unknown (0x2000)", "Unknown (0x4000)", "Unknown (0x8000)" ]
        else:
            flag_str = [     "Scripting", "Use fixed font", "Screen refresh required",
                "Supports graphics", "Supports undo", "Supports mouse", "Supports colour",
                "Supports sound", "Supports menus", "Unknown (0x0200)", "Printer error",
                "Unknown (0x0800)", "Unknown (0x1000)", "Unknown (0x2000)", "Unknown (0x4000)",
                "Unknown (0x8000)" ]
        for i in range(16):
            if b & (1 << i):
                flags.append(flag_str[i])
        if flags:
            return ", ".join(flags)
        else:
            return "None"

    def display_abbreviations(self):
        abbr = []
        print("\n    **** Abbreviations ****\n")
        if not self.abbreviations:
            return

        for i, a in enumerate(self.abbreviations):
            abbr.append('[{0:d}] "{1:s}"'.format(i, a))
        print_table(abbr)

    def display_dictionary(self):
        d = []
        print("\n    **** Dictionary ****\n")
        for i, a in enumerate(self.dictionary):
            d.append(str(a))

        print_table(d)

    def read_property_table(self, addr):
        p = dict()

        sz_byte = self.contents[addr]
        while sz_byte != 0:
            sz = (sz_byte >> 5) + 1
            propnum = sz_byte & 31

            p[propnum] = list()
            addr += 1
            for i in range(sz):
                p[propnum].append(self.contents[addr+i])
            addr += sz

            sz_byte = self.contents[addr]

        self.high_prop = max(addr, self.high_prop)
        return p

    def build_object(self, bytes, addr):
        v = self.header["version"]

        if v <= 3:
            alist = bytes[:4]
        else:
            alist = bytes[:6]
        zo = Zobj(self, addr, alist)
        if v <= 3:
            zo.parent = bytes[4]
            zo.sibling = bytes[5]
            zo.child = bytes[6]
            ptable = word(bytes[7:9])
        else:
            zo.parent = bytes[6] * 256 + bytes[7]
            zo.sibling =  bytes[8] * 256 + bytes[9]
            zo.child = bytes[10] * 256 + bytes[11]
            ptable = word(bytes[12:14])

        #print("Buiilding obj from {0} (attr: {1})".format(addr, " ".join(["{:08b}".format(x) for x in alist])))
        #print("Parent: {0} Sibling: {1} Child: {2} Prop: {3}".format(zo.parent, zo.sibling, zo.child, ptable))

        zo.property_table = ptable
        zo.description = self.zscii.read_text(ptable + 1, self.contents[ptable] * 2)
        zo.properties = self.read_property_table(ptable + self.contents[ptable] * 2 + 1)
        self.zobjects.append(zo)

        return zo.property_table

    def read_objects(self):
        addr = self.header["otable"]
        self.zobjects = []
        v = self.header["version"]
        self.high_prop = -1
        max_props = 32 if v <= 3 else 64

        self.prop_default = [0] * max_props
        for i in range(1, max_props):
            self.prop_default[i] = word(self.contents[addr:addr+2])
            addr += 2

        count = 1

  # We rely on the fact that the first property tables come directly
  # after the object table.  It's how we know the object table is finished
        if v <= 3:
            prop_table = 0xfffff
            while addr < prop_table:
                prop_table = min(self.build_object(self.contents[addr:addr+9], addr), prop_table)
                self.zobjects[-1].number = count
                addr += 9
                count += 1
        else:
            prop_table = 0xfffff
            while addr < prop_table:
                prop_table = min(self.build_object(self.contents[addr:addr+14], addr), prop_table)
                self.zobjects[-1].number = count
                addr += 14
                count += 1

        self.game_map.append([ self.header["otable"], prop_table - 1, "Object table"])
        self.game_map.append([ prop_table, self.high_prop, "Object property table"])
        self.property_table = prop_table


    def display_header(self, style="infodump"):
        h = self.header

        if style == "infodump":
            print("    **** Story file header ****\n")
            print("Z-code version:           {0}".format(h["version"]))
            print("Interpreter flags:        {0}".format(self.interpret_flags(h["flags"])))
            print("Release number:           {0}".format(h["release"]))
            print("Size of resident memory:  {0:04x}".format(h["highmem"]))
            print("Start PC:                 {0:04x}".format(h["pc"]))
            print("Dictionary address:       {0:04x}".format(h["dict"]))
            print("Object table address:     {0:04x}".format(h["otable"]))
            print("Global variables address: {0:04x}".format(h["globals"]))
            print("Size of dynamic memory:   {0:04x}".format(h["static"]-1))
            print("Game flags:               {0}".format(self.game_flags(h["gflags"])))
            print("Serial number:            {0}".format(h["serial"]))
            print("Abbreviations address:    {0:04x}".format(h["abbr"]))
            if h["version"] > 2 and h["filelen"]:
                if h["version"] < 4:
                    print("File size:                {0:x}".format(h["filelen"]*2))
                elif 4<= h["version"] <= 5:
                    print("File size:                {0:x}".format(h["filelen"]*4))
                else:
                    print("File size:                {0:x}".format(h["filelen"]*8))
                print("Checksum:                 {0:04x}".format(h["cksum"]))


    def abbr_str(self, a):
        if not self.configuration:
            return str(a)

        attr = self.configuration.attributes
        if a in attr:
            return attr[a]

    def display_objects(self, style="infodump"):
        print("\n    **** Objects ****\n")
        print("  Object count = {0}\n".format(len(self.zobjects)))
        for i, o in enumerate(self.zobjects):
            print("{:3d}. Attributes: {}".format(o.number, ", ".join(self.abbr_str(x) for x in sorted(list(o.attributes))) if o.attributes else "None"))
            print("     Parent object: {:3d}  Sibling object: {:3d}  Child object: {:3d}".format(o.parent, o.sibling, o.child))
            print("     Property address: {:04x}".format(o.property_table))
            print("         Description: \"{}\"".format(o.description))  
            print("          Properties:")
            for p in sorted(o.properties.keys(), reverse=True):
                print("              [{:2d}] {} ".format(p, " ".join("{:02x}".format(x) for x in o.properties[p])))
            print()


    def display_ob(self, obj, indent):
        print(" . " * indent + "[{:3d}] \"{}\"".format(obj.number, obj.description))
        if obj.child:
            self.display_ob(self.zobjects[obj.child-1], indent+1)
        if obj.sibling:
            self.display_ob(self.zobjects[obj.sibling-1], indent)
                

    def display_tree(self, style="infodump"):
        print("\n    **** Object tree ****\n")
        if style == "infodump":
            for o in [z for z in self.zobjects if z.parent == 0]:
                self.display_ob(o, 0)


    def __init__(self, storyfile):
        self.filename = storyfile
        try:
            fd = open(storyfile, "rb")
        except OSError as err:
            self.fatal(err)

        self.contents = fd.read()
        self.md5 = hashlib.md5(self.contents).hexdigest().upper()

        if len(self.contents) < 0x40:
            self.fatal("story file too short to be zmachine file")

        self.abbreviations = None
        self.game_map = []
        self.addr_to_dict = dict()
        self.hs_addr = None
        self.adjectives = dict()

        self.parse_header()

        self.zscii = Zscii(self)
        self.read_abbreviations()
        self.read_dictionary()
        self.read_objects()

    def pair_configuration(self, conf_obj):
        self.configuration = conf_obj
        
class Configuration:
    md5 = None
    
    def __init__(self, fn):
        self.filename = fn    

        try:
            fd = open(fn, "r")
        except OSError as err:
            print(sys.argv[0] + ": {0}".format(err))
            sys.exit(1)

        self.attributes = dict()
        self.properties = dict()
        self.routines = dict()
        self.globals = dict()

        for line in fd:
            line = line.strip()
            if "!" in line:
                line = line[:line.index("!")]
            p = parse("Attribute {attr:d} {aname:w}", line)
            if p:
                self.attributes[p["attr"]] = p["aname"]
            p = parse("MD5 {md5:w}", line)
            if p:
                self.md5 = p["md5"]
        print(self.attributes)
        fd.close()

def main(args):
    if args.conf:
        conf = Configuration(args.conf)
    else:
        conf = None

    stories = [Story(fn) for fn in args.storyfile]
    for s in stories:
        if conf and conf.md5 and s.md5 == conf.md5:
            s.pair_configuration(conf)

        if args.style == "infodump":
            print("\nStory file is {0}".format(s.filename))
        if args.info:
            s.display_header()
        if args.abbreviations:
            s.display_abbreviations()
        if args.dictionary:
            s.display_dictionary()
        if args.objects:
            s.display_objects()
        if args.tree:
            s.display_tree()
            
if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Z-machine information tool")
    ap.add_argument("storyfile", help="zmachine story file", nargs="+")
    ap.add_argument("-i", "--info", action="store_true", help="Present information from header")
    ap.add_argument("-a", "--abbreviations", action="store_true", help="Show abbreviations")
    ap.add_argument("-d", "--dictionary", action="store_true", help="Show dictionary")
    ap.add_argument("-o", "--objects", action="store_true", help="Show objects")
    ap.add_argument("-t", "--tree", action="store_true", help="Show object tree")
    ap.add_argument("-s", "--style", default="infodump", help="Style. Options: infodump, zil, inform")
    ap.add_argument("-c", "--conf", help="Conf file (reform style)")
    args = ap.parse_args()
    main(args)
