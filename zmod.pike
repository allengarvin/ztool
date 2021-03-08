#!/usr/local/bin/pike
/*
 You'll need the Pike language to make this work. 
 Also, I wrote this 15+ years ago. It's not maintained. I don't use Pike
    anymore. I've modified to work under current versions of Pike though.
 - Allen Garvin
 Standard BSD license applies to this.
*/

import Stdio;
import Getopt;

void fatal(string err) {
  if( strlen(err) )
    stderr->write(err + (err[-1] != '\n' ? "\n" : ""));
  exit(1);
}

#define VERSION "0.3"

#define H_RELEASE 2
#define H_RESIDENT_SIZE 4
#define H_START_PC 6
#define H_DICTIONARY 8
#define H_OBJECTS 10
#define H_GLOBALS 12
#define H_DYNAMIC_SIZE 14
#define H_FLAGS 16
#define H_SERIAL 18
#define H_ABBREVIATIONS 24
#define H_FILE_SIZE 26
#define H_CHECKSUM 28
#define H_INTERPRETER_NUMBER 30

#define DEBUG 1
#define SYNTAX "Usage: zmod.pike -c [command[,...]] [fromfile] [tofile]"

string story;
array z_commands = ({ });
int zversion;
array(string) abbreviations = allocate(96);
string serial_num;
int base_high_mem, start_pc, dict_addr, object_table, global_table,
    static_mem, abbr_table, prop_table, file_size, checksum, release,
    property_table, high_prop;


int word(int addr) {
  if( addr+1 >strlen(story) ) {
    fatal(sprintf("Address(word) 0x%04x past end of game length\n", addr));
    exit(1);
  }
  return story[addr] * 256 + story[addr+1];
}

// Grab 1-byte at address
int byte(int addr) {
  if( addr >strlen(story) ) {
    fatal(sprintf("Address(byte) 0x%04x past end of game length\n", addr));
    exit(1);
  }
  return story[addr];
}

int least(int a, int b) { return (a < b) ? a : b; }
int greatest(int a, int b) { return (a > b) ? a : b; }

void read_abbreviations() {
  int i, addr, max_a = 96;
  int lo = 0x7ffff, hi;

  addr = abbr_table;
  //write("Abbreviations table starts at "+sprintf("%d (%o)\n", addr, addr));

  if( zversion == 2 )
    max_a = 32;
  for( i=0; i<max_a; i++ ) {

    abbreviations[i] = read_text(word(addr) * 2, 753);

    lo = least(word(addr) * 2, lo);
    hi = greatest(word(addr) * 2 + byte_length() - 1, hi);
    //write("Abbreviation "+i+" is '"+abbreviations[i]+"'\n");
    addr += 2;
  }
}

int inform_escapes; // ~ for ", ^ for newline

array(string) modern_zscii = ({
    " ^^^^^abcdefghijklmnopqrstuvwxyz ",
    " ^^^^^ABCDEFGHIJKLMNOPQRSTUVWXYZ ",
    " ^^^^^ \n0123456789.,!?_#'\"/\\-:() ",
});
array(string) old_zscii = ({
    " \n^^^^abcdefghijklmnopqrstuvwxyz ",
    " \n^^^^ABCDEFGHIJKLMNOPQRSTUVWXYZ ",
    " \n^^^^ 0123456789.,!?_#'\"/\\>-:() ",
    " \n^^^^abcdefghijklmnopqrstuvwxyz ",
});

array zscii;

// Less than zero.  Why did I write it? I don't see that this is used here:
// zstring += sprintf("%c", zscii[shift][LTZ(bytes[i])]);
//#define LTZ(X) ((X)==(4-6) || (X)==(5-6) ? -1 : (X))

int debug;

string convert_zscii_bytes(array(int) bytes) {
  string zstring = "";
  int shift_lock, shift = -1, abbrev_flag, ascii_flag;

  for( int i=0; i<sizeof(bytes); i++ ) {
    if( ascii_flag ) {
      ascii_flag = 0;
      i++;
      if( i == sizeof(bytes) )
        return zstring;
      zstring += sprintf("%c", (bytes[i-1] << 5) | bytes[i]);
      continue;
    }
    if( abbrev_flag ) {
      int ndx;

      ndx = 32 * (bytes[i-1] - 1) + bytes[i];
      zstring += abbreviations[ndx];
      abbrev_flag = 0;
      shift = -1;
      continue;
    }
    switch( bytes[i] ) {
      case 0: zstring += " "; break;
      case 1: 
        if( zversion < 2 )
          zstring += "\n";
        else
          abbrev_flag = 1; 
        continue;
      case 2: 
        if( zversion < 3 )
          shift = (shift_lock + 1) % 3;
        else
          abbrev_flag = 1; 
        continue;
      case 3: 
        if( zversion < 3 )
          shift = (shift_lock + 2) % 3;
        else
          abbrev_flag = 1; 
        continue;
      case 4: 
        if( zversion < 3 )
          shift_lock = (shift_lock + 1) % 3;
        else {
          shift = 1; 
          abbrev_flag = 0; 
        }
        continue;
      case 5: 
        if( zversion < 3 )
          shift_lock = (shift_lock + 2) % 3;
        else {
          shift = 2; 
          abbrev_flag = 0; 
        }
        continue;
      case 6: 
        if( shift == 2 ) {
          shift = -1;
          ascii_flag = 1;
          continue;
        } // Else fall-through to default
      default:
        if( shift > -1 )
          zstring += sprintf("%c", zscii[shift][bytes[i]]);
        else
          zstring += sprintf("%c", zscii[shift_lock][bytes[i]]);
    }
    shift = -1;
    abbrev_flag = 0;
  }
  return zstring;
}

int bytes_read;

int byte_length() { return bytes_read; }

string read_text(int addr, int len) {
  string zs;
  array bytes = ({});
  int i;
  
  if( !zscii ) {
    if( zversion < 2 )
      zscii = old_zscii;
    else
      zscii = modern_zscii;
  }

  for( i=0; i<len; i++ ) {
    int bit, c1, c2, c3;
    int w;

    w = word(addr + i * 2);

    bit = w >> 15;            // bit 0
    c3 = w & 31;              // bits 11-15
    c2 = (w & 0x3e0) >> 5;    // 3e0 == 31 << 5, bits 6-10
    c1 = (w & 0x7c00) >> 10;  // 7c00 == 31 << 10, bits 1-5

    bytes += ({ c1, c2, c3 });
    if( bit ) {
      i++;
      break;
    }
  }
  bytes_read = i * 2;
  zs = convert_zscii_bytes(bytes);

  if( inform_escapes ) {
    inform_escapes = 0;
    zs = replace(zs, "\"", "~");
    zs = replace(zs, "\n", "^");
  }
  return zs;      
}

void read_story_file(string fn) {
  object o;

  if( DEBUG )
  write("* Story file is "+fn+"\n");

  o = File();
  if( !o->open(fn, "r") ) fatal("game file "+fn+" not found");

  story = o->read(0x7fffffff);

  if( strlen(story) < 32 ) fatal("game file "+fn+" too short to be zgame");

  zversion = byte(0);
  if( zversion == 0 || zversion > 8 )
    fatal("Wrong game or version [zmachine version "+zversion+"??]");
}

void read_header() {
  release = word(H_RELEASE);
  base_high_mem = word(H_RESIDENT_SIZE);
  start_pc = word(H_START_PC);
  dict_addr = word(H_DICTIONARY);
  object_table = word(H_OBJECTS);
  global_table = word(H_GLOBALS);
  static_mem = word(H_DYNAMIC_SIZE);
  abbr_table = word(H_ABBREVIATIONS);
  file_size = word(H_FILE_SIZE) * 2;
  checksum = word(H_CHECKSUM);
  serial_num = story[H_SERIAL .. H_SERIAL+5];
  if( file_size == 0 ) { // Infocom dates that predate the filesize header
    if( release == 2 && serial_num == "AS000C" )    // Zork1 rel 2
      file_size = 0x15dfe;
    if( release == 5 && start_pc == 0x47ad )        // Zork1 rel 5
      file_size = 0x14394;
    if( release == 15 && start_pc == 0x4859 )       // Zork1 rel 15
      file_size = 0x13ff4;
    if( release == 20 && start_pc == 0x49b5 )       // Zork1 rel 20
      file_size = 75734;
    if( release == 23 && serial_num == "820428")    // Zork1 rel 23
      file_size = 75780;
    if( release == 25 && serial_num == "820515")    // Zork1 rel 25
      file_size = 75808;
    if( release == 7 && start_pc == 0x45ab )        // Zork2 rel 7
      file_size = 0x15ffe;
    if( release == 18 && serial_num == "820515")    // Zork2 rel 18
      file_size = 82422;
    if( release == 18 && serial_num == "820517")    // Zork2 rel 18a
      file_size = 82422;
    if( release == 17 && serial_num == "820427")    // Zork2 rel 17
      file_size = 82368;
    if( release == 15 && serial_num == "820308")    // Zork2 rel 15
      file_size = 82424;
    if( !file_size )
      file_size = sizeof(story);
  }
}

mapping prop_default = ([]);
array(object) zobjects = ({ 0 });

program zobj = class {
    int parent, sibling, child;
    int property_table, addr;
    mapping properties = ([]);
    multiset attributes = (<>);

    int number, version;
    string description;

    void create() { version = zversion; }

    mixed cast(string type) {
        if( type == "string" )
            return sprintf("OBJ(%d,\"%s\")", number, description);
        if( type == "int" )
            return number;
    }

    array compress_attributes() {
        array astr;

        if( zversion <= 3 )
            astr = allocate(4);
        else
            astr = allocate(6);

        for( int i; i < (zversion <= 3 ? 32 : 48); i++ ) {
            if( !attributes[i] )
                continue;
            //write("Setting attribute "+i+" "+(attributes[i] << (7-(i % 8)))+"\n");
            astr[i / 8] = astr[i / 8] | (attributes[i] << (7-(i % 8)));
        }
        return astr;
    }

    void set_attribute(int i) {
        array a;

        //write(sprintf("%O\n", attributes));
        a = compress_attributes();        

        attributes[i] = 1;
        a = compress_attributes();        
        story[addr] = a[0];
        story[addr+1] = a[1];
        story[addr+2] = a[2];
        story[addr+3] = a[3];
        if( zversion > 3 ) {
          story[addr+4] = a[4];
          story[addr+5] = a[5];
        }
    }

    void unset_attribute(int i) {
        array a;

        //write(sprintf("%O\n", attributes));
        a = compress_attributes();        

        attributes[i] = 1;
        a = compress_attributes();        
        story[addr] = a[0];
        story[addr+1] = a[1];
        story[addr+2] = a[2];
        story[addr+3] = a[3];
        if( zversion > 3 ) {
          story[addr+4] = a[4];
          story[addr+5] = a[5];
        }
    }
};

multiset parse_attributes(array(int) bytes) {
    int i, j;
    multiset a = (<>);

    for( int j=0; j<sizeof(bytes); j++ ) {
        for( int i=7; i>=0; i-- ) {
            if( (1<<i) & bytes[j] )
                a[j * 8 + (8-i) - 1] = 1;
        }
    }
    return a;
}

mapping read_property_table(int addr) {
    int sz_byte;
    mapping p = ([]);

    // property tables terminated by a null byte
    while( (sz_byte = byte(addr)) != 0 ) {
        int sz, propnum;

        sz = (sz_byte >> 5) + 1;
        propnum = sz_byte & 31;

        p[propnum] = ({});

        addr++;
        for( int i=0; i<sz; i++ )
            p[propnum] += ({ story[addr+i] });
        addr += sz;
    }
    high_prop = greatest(addr, high_prop);
    return p;
}

int build_object(string zobj_bytes, int addr) {
    object zo;
    int ptable;
    array alist;

    if( zversion <= 3 )
        alist = ({ zobj_bytes[0], zobj_bytes[1], zobj_bytes[2], zobj_bytes[3] });
    else
        alist = ({ zobj_bytes[0], zobj_bytes[1], zobj_bytes[2],
                     zobj_bytes[3], zobj_bytes[4], zobj_bytes[5] });

    if( DEBUG >1 )
        write(sprintf("Building object from %d (attr %d %d %d %d)\n    "
                "par %d sib %d child %d prop %d %d\n", object_table,
                                zobj_bytes[0], zobj_bytes[1], zobj_bytes[2],
                zobj_bytes[3], zobj_bytes[4], zobj_bytes[5],
                zobj_bytes[6], zobj_bytes[7], zobj_bytes[8]));

    zo = zobj();
    zo->addr = addr;
    zo->attributes = parse_attributes(alist);

    if( zversion <= 3 ) {
        zo->parent = zobj_bytes[4];
        zo->sibling = zobj_bytes[5];
        zo->child = zobj_bytes[6];
        ptable = zobj_bytes[7] * 256 + zobj_bytes[8];
    } else {
        zo->parent = zobj_bytes[6] * 256 + zobj_bytes[7];
        zo->sibling = zobj_bytes[8] * 256 + zobj_bytes[9];
        zo->child = zobj_bytes[10] * 256 + zobj_bytes[11];
        ptable = zobj_bytes[12] * 256 + zobj_bytes[13];
    }

    zo->property_table = ptable;
    zo->description = read_text(ptable + 1, byte(ptable) * 2);

    zo->properties = read_property_table(ptable + byte(ptable) * 2 + 1);
    zobjects += ({ zo });
    return zo->property_table;
}

void display_tree_object(int parent, int indent) {
  for( int i; i<sizeof(zobjects); i++ ) {
    if( zobjects[i]->parent == parent ) {
      for( int j; j<indent; j++ )
        write(" . ");
      write(sprintf("[%3d] \"%s\"\n", i+1, zobjects[i]->description));
      display_tree_object(i+1, indent + 1);
    }
  }
}

void show_tree() {
  display_tree_object(0, 0);
/*
  else {
    mapping names = ([]);
    for( int i=0; i<sizeof(zobjects); i++ ) {
      string n;
      n = replace(zobjects[i]->description, " ", "_");
      n = replace(n, "'", "");
      n = replace(n, "-", "_");
      if( names[n] ) {
        names[n]++;
        n = n + "_" + names[n];
      } else
        names[n] = 1;
      write(sprintf("Object\t%d\t%s\n", i+1, n));
    }
  }
*/
}

void read_objects() {
    int addr, prop_table, count = 1;
    int max_props;

    addr = object_table;

    if( zversion <= 3 )
        max_props = 32;
    else
        max_props = 64;

    for( int i = 1; i<max_props; i++ ) {
        prop_default[i] = word(addr);
        addr += 2;
    }

    // We rely on the fact that the first property tables come directly
    // after the object table.    It's how we know the object table is finished

    if( zversion <= 3 ) {
        for( prop_table = 0xfffff; addr < prop_table; addr += 9 ) {
            prop_table = least(build_object(story[addr..addr+8], addr), prop_table);
            zobjects[-1]->number = count++;
        }
    } else {
        for( prop_table = 0xfffff; addr < prop_table; addr += 14 ) {
            prop_table = least(build_object(story[addr..addr+13], addr), prop_table);
            zobjects[-1]->number = count++;
        }
    }
}

void display_help() {
    write(SYNTAX + "\n");
    write("Valid commands\n");
    write("    g[num]=[val]        Set global variable #[num] to [val], where [val] is an integer\n");
    write("    m[obj1]=[obj2]      Move [obj1] to [obj2] (re-orders the object tree)\n");
    write("    a[obj],[attr]=[0/1] Set attribute #[attr] off (0) or on (1) in obj #[obj]\n");
}

int is_in(int obj, int dest) {
    if( !zobjects[dest]->parent )
        return 0;
    if( zobjects[dest]->parent == obj )
        return 1;
    return is_in(obj, zobjects[dest]->parent);
}

void move_object(int f, int t) {
    object f_obj, t_obj;

    f_obj = zobjects[f];
    t_obj = zobjects[t];

    f_obj->parent = t;

    // The from object's parent is now the to object
    if( zversion <= 3 ) {
        story[f_obj->addr + 4] = t;
    } else {
        story[f_obj->addr + 6] = t / 256;
        story[f_obj->addr + 7] = t % 256;
    }

    // The from object's sibling is now the former to object's first child
    f_obj->sibling = t_obj->child;
    if( zversion <= 3 ) {
        story[f_obj->addr + 5] = t_obj->child;
    } else {
        story[f_obj->addr + 8] = t_obj->child / 256;
        story[f_obj->addr + 9] = t_obj->child % 256;
    }
    
    // The to object's new first child is the from object
    t_obj->child = f;
    if( zversion <= 3 ) {
        story[t_obj->addr + 6] = f;
    } else {
        story[t_obj->addr + 10] = f / 256;
        story[t_obj->addr + 11] = f % 256;
    }
}
    

void unlink_object(int f) {
    int p;
    object p_obj, f_obj;

    f_obj = zobjects[f];
    if( p = f_obj->parent ) {
        p_obj = zobjects[p];
        if( p_obj->child == f ) {
            p_obj->child = f_obj->sibling;

            if( zversion <= 3 ) {
                story[p_obj->addr + 6] = f_obj->sibling;
            } else {
                story[p_obj->addr + 10] = f_obj->sibling / 256;
                story[p_obj->addr + 11] = f_obj->sibling % 256;
            }

        } else { 
            if( DEBUG )
                write("* Looping over "+(string) p_obj+"'s children\n");
            for( int c = p_obj->child; c; c = zobjects[c]->sibling ) {
                if( zobjects[c]->sibling == f ) {
                    zobjects[c]->sibling = f_obj->sibling;

                    if( zversion <= 3 ) {
                        story[zobjects[c]->addr + 5] = f_obj->sibling;
                    } else {
                        story[zobjects[c]->addr + 8] = f_obj->sibling / 256;
                        story[zobjects[c]->addr + 9] = f_obj->sibling % 256;
                    }

                    break;
                }
            }
        }
    }
    if( zversion <= 3 ) {
        story[f_obj->addr + 4] = 0;
        story[f_obj->addr + 5] = 0;
    } else {
        story[f_obj->addr + 6] = story[f_obj->addr + 7] = 0;
        story[f_obj->addr + 8] = story[f_obj->addr + 9] = 0;
    }
    f_obj->parent = 0;
    f_obj->sibling = 0;
    if( DEBUG )
        write("* "+(string) f_obj+" unlinked\n");
}

void do_move(int obj, int dest) {
    unlink_object(obj);
    move_object(obj, dest);
}

int execute_command(string c) {
    int globalvar, intval, trueintval, obj1, obj2, attr, state;

    if( sscanf(c, "g%d=%d", globalvar, intval) ) {
        int b1, b2;

        if( DEBUG )
            write("* Assigning value intword '"+intval+"' to global variable #"+globalvar+"\n");
        if( globalvar < 0 || globalvar > 239 ) {
            write("Global var numbers must be between 0 and 239 (inclusive)\n");
            return 0;
        }
        if( intval > 65535 || intval < -32768 ) {
            write("Values must be between -32768 and 65535 (inclusive)\n");
            return 0;
        }
        if( intval < 0 )
            trueintval = 65535 + intval;
        else
            trueintval = intval;
        b1 = trueintval / 256;
        b2 = trueintval % 256;
        story[global_table + globalvar * 2] = b1;
        story[global_table + globalvar * 2 + 1] = b2;
        write("Global variable #"+globalvar+" has been set to "+intval+"\n");
        return 1;
    } else if( sscanf(c, "m%d=%d", obj1, obj2) ) {
        if( DEBUG )
            write(sprintf("* Moving %s to %s\n",
                (string) zobjects[obj1], (string) zobjects[obj2]));
        //show_tree();
        if( obj1 <= 0 || obj2 <= 0 ) {
            write("Objects less than or equal to 0 doesn't make sense\n");
            return 0;
        }
        if( obj1 > sizeof(zobjects) || obj2 > sizeof(zobjects) ) {
            write("Error: There are only "+sizeof(zobjects)+" in the game file\n");
            return 0;
        }
        if( obj1 == obj2 ) {
            write("Error: cannot move an object to itself\n");
            return 0;
        }
        if( is_in(obj2, obj1) ) {
            write("Error: Can't move "+(string) zobjects[obj1]+" inside itself\n");
            return 0;
        }
        do_move(obj1, obj2);
        write("Object "+(string) zobjects[obj1]+" moved to "+(string) zobjects[obj2]+"\n");
        return 1;
    } else if( sscanf(c, "a%d,%d=%d", obj1, attr, state) == 3 ) {
        if( obj1 < 0 || obj1 >= sizeof(zobjects) ) {
            write("Object #"+obj1+" out of valid range (1 .. "+(sizeof(zobjects)-1)+" inclusive)\n");
            return 1;
        }
        state = !!state;
        if( attr < 0 || attr > (zversion > 3 ? 47 : 31) ) {
            write("Attribute #"+attr+" out of valid range (0 .. "+(zversion > 3 ? 47 : 31)+" inclusive)\n");
            return 1;
        }
        if( zobjects[obj1]->attributes[attr] == state ) {
            write("Attribute "+attr+" already "+(state ? "" : "un")+"set in "+(string) zobjects[obj1]+"\n");
            return 1;
        }
        if( state )
            zobjects[obj1]->set_attribute(attr);
        else    
            zobjects[obj1]->unset_attribute(attr);
        return 1;
    } else {
        write("Unrecognized command: "+c+"\n");
        return 0;
    }
}

void write_new_story(string fn, string ser, int cksum) {
    object f;
    string newstory;

    f = File();
    if( !f->open(fn, "wct") ) {
        write("Error: cannot open output file '"+fn+"' for writing\n");
        exit(1);
    }
    newstory = 
    newstory = story[0..H_SERIAL-1] + ser + story[H_SERIAL+6..];
    newstory[H_CHECKSUM] = cksum / 256;
    newstory[H_CHECKSUM+1] = cksum % 256;

    if( f->write(newstory) != strlen(newstory) )
        write("Error: write failed to file '"+fn+"'\n");
    else
        write("New story file written: "+fn+"\n");
}

int main(int argc, array(string) argv) {
    string cmd_line, fromfile, tofile;
    string comm, newserial;
    int newchecksum;

    cmd_line = argv[0] + " " + map(argv[1..], lambda(string s) { return "'"+s+"'"; }) * " ";

    if( find_option(argv, ({ "?", "h" }), "help") ) {
        display_help();
        return 0;
    }
    while( (comm = find_option(argv, "c", 0, 0, "error")) != "error" ) {
        z_commands += ({ comm });
    }
    if( !sizeof(z_commands) ) {
        write("Error: must supply at least one command\n");
        write(SYNTAX+"\n");
        return 1;
    }
    if( sizeof(argv - ({ 0 })) != 3 ) {
        write(SYNTAX + "\n");
        write("Error: one [fromfile] and one [tofile] must be given\n");
        return 1;
    }
    fromfile = (argv - ({0}))[1];
    tofile = (argv - ({0}))[2];
    if( fromfile == tofile ) {
        write("Error: [fromfile] cannot be same as [tofile]\n");
        return 1;
    }

    read_story_file(fromfile);
    read_header();
    read_abbreviations();
    read_objects();

    foreach( z_commands, comm ) {
        if( DEBUG )
            write("* executing: "+comm+"\n");
        if( !execute_command(comm) )
            write("Error: failed to execute '"+comm+"'\n");
    }

    mapping tm;
    tm = localtime(time());
    newserial = sprintf("%02d%02d%02d", tm["year"] % 100, tm["mon"]+1, tm["mday"]);
    for( int i=0x40; i<strlen(story); i++ )
        newchecksum += story[i];
    newchecksum %= 0x10000;
    write_new_story(tofile, newserial, newchecksum);    
}


