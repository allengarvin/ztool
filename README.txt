About 20 years ago, I wrote a replacement for the ztools suite of programs, in Pike (infodump and txd), eventually adding a decompiler. This is a port of that program, to modern Python. When finished, it should be a drop-in replacement. I don't plan to write a full-scale decompiler for it, but I do plan to have multiple styles of output, including the traditional infodump, a ZIL-like output, and an Inform-like output. It will also read reform- style configuration files and display accordingly.  
---
ZMOD:
I might as well put zmod here, a program I wrote years ago for modifying zmachine files. With it you can:
    - switch global variables
    - rearrange the object tree (like, move the lamp in planetfall to an accessible location!)
    - flip attributes of objects

You'll need the Pike programming language to make it work. You can make games more friendly, like changing the lamp burn-out time in zork.
