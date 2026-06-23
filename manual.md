# R432 reference manual

*What's as big as half the simulation area, burns tens of thousands of your particle budget, puts out a load of EHOLE and particle ID allocation noise, and cuts a DEUT bomb into three pieces? A TPT computer made to cut a DEUT bomb into four pieces!*

Check out [the showcase save](TODO) in your browser. This is an R4A0316M, see numbering scheme below.

![the showcase save](TODO)

Come and discuss it on the [Subframe Discord Server](https://discord.gg/fjF24Hc), an official branch of the [TPT Discord Server](https://tpt.io/discord) that happened to be created earlier.

Note: Ordinal numbers throughout this manual start at 0, yielding odd-looking constructs such as *0th* and *bit 0* (the LSB). For clarity's sake the English word *first* is never used to refer to ordinals.

Note: Instruction spellings and expansions reflect the state of integration with [TPTASM](https://github.com/LBPHacker/tptasm).

Note: Feel free to suggest improvements this manual, the computers, or their peripherals.

Note: **Please read through this manual, or at least use the "Find in page" or Ctrl+F feature of your browser on it, before asking for help with topics that it already covers.**

# Buzzwords

 - **real-life architecture**: RISC-V, supports real-life compilers and programming languages
 - **data bus**: 32-bit, works with *every* 32-bit value, no questions asked
 - **address bus**: likewise 32-bit, yielding a 4GiB address space
 - **registers**: 32-bit words, 31 general purpose read-write, 1 read-only *zero*
 - **ALU**: 32-bit addition, logic, and shifting, 32-by-32-bit *multiplication* with 64-bit results
 - **interal memory**: byte-addressed, any amount of 32-bit words from 512B to 32KiB in increments of 512B
 - ***spatial unrolling***: (much) more than 1 instruction executed in a simulation frame, exact figures depending on configuration
 - **input and output**: memory-mapped, control lines are exposed, *wait cycles* can be injected

## Real-life architecture: RISC-V

RISC-V, especially the subset of it that I chose to implement in this family of computers, is a really simple instruction set that, as others in the subframe community have pointed out, is very similar to the one that my R3 family of computers implement.

We tend to design our own instruction sets because our problems and goals are slightly different from those that real-life instruction sets solve and target. Modern instruction sets are designed for superscalar out-of-order execution, the sort of situation where a move operation ends up changing a pointer somewhere deep inside the register file, sometimes with zero latency, rather than actually move data around.

The average TPT computer is nowhere near this sophisticated: a simple move often takes the exact same "time" (has the same latency *and* throughput) as multiplication, if the instruction set supports it. Thus, TPT architectures and their instruction sets tend to be at least somewhat optimized to the problems at hand, and this manifests as some level of eccentricity compared to modern mainstream instruction sets. This is beneficial for performance, but it also isolates these computers from the rest of the industry, including decades' worth of advancements in compiler technology.

So, for a change, this family of computers uses an instruction set architecture that is arguably becoming mainstream, and indeed, many real-life tools exist that target RISC-V. This means that you can use well-established ahead-of-time-compiled native programming languages to program these computers, such as Rust, C++, C, or Ada.

The option to write programs in assembly the way more typical of my computers is also available through TPTASM support.

## 32-bit data and address buses

All 32-bit values can be read and written by these computers. This is in stark contrast with less-than-32-bit computers typically seen in TPT, which need a keepalive bit somewhere, and with my R3 family of computers, which are quasi-32-bit, meaning that a few out of all 32-bit values are taboo and cannot be properly read or written.

Addresses are also 32-bit, which in theory allows for addressing 4GiB of memory, though of course no configuration of this computer supports that much *built-in* memory, and there is little reason to need that much for memory-mapped peripherals. In practice, this is mainly a result of following the RISC-V specification, and also symmetry, i.e. it would feel weird if it was not 32-bit while everything else was.

## 32-bit registers

There are 31 general purpose read-write registers `x1` to `x31`, and also one read-only register `x0` that always reads `0x00000000`. This read-only register can be used as the destination operand to an operation, in which case the output produced by the operation is discarded. Again, this is just a RISC-V thing.

## ALU

The ALU operates on all 32 bits of registers and 12-bit immediate values, as is typical for RISC-V. It is capable of addition and subtraction, with or without carry and borrow, bitwise OR, AND, and XOR, and left shifting, and logical and arithmetic right shifting. Unlike all my precious computers, these operations do not output flags. Instead, comparisons are made with dedicated instructions and their results are stored in registers, again, as is typical for RISC-V.

The ALU is also capable of 32-by-32-bit unsigned and signed multiplication, which yields 64-bit numbers. Either or both halves of the result can be stored.

## Internal memory

The internal memory is arranged into a configurable number `memory_rows` of rows of 128 32-bit words. A 32KiB chunk of the 32-bit address space at the configurable base address `memory_base` is divided into 64 512B blocks, which are mapped to the internal memory as follows:

 - `memory_rows` blocks are mapped to the corresponding row in the internal memory in read-write mode, meaning that reads addressing them are by default served by the internal memory, and writes addressing them are by default handled by it;
 - `64 - memory_rows` blocks are mapped to the highest-address row of the internal memory in read-only mode, meaning that reads addressing them are by default served by the internal memory, but writes are ignored by it.

Consider the example of `memory_base` being `0x00458000` and `memory_rows` being `13`: in this case, the memory map is as follows:

| first byte | last byte | block number | reads served by | writes handled by |
|-|-|-|-|-|
| 0x00000000 | 0x00457FFF | | possibly peripherals | possibly peripherals |
| 0x00458000 | 0x004581FF | 0 | row 0 | row 0 |
| 0x00458200 | 0x004583FF | 1 | row 1 | row 1 |
| 0x00458400 | 0x004585FF | 2 | row 2 | row 2 |
| 0x00458600 | 0x004587FF | 3 | row 3 | row 3 |
| ... | ... | ... | ... | ... |
| 0x00459600 | 0x004597FF | 11 | row 11 | row 11 |
| 0x00459800 | 0x004599FF | 12 | row 12 | row 12 |
| 0x00459A00 | 0x00459BFF | 13 | row 12 | nothing |
| 0x00459C00 | 0x00459DFF | 14 | row 12 | nothing |
| 0x00459E00 | 0x00459FFF | 15 | row 12 | nothing |
| ... | ... | ... | ... | ... |
| 0x0045FC00 | 0x0045FDFF | 62 | row 12 | nothing |
| 0x0045FE00 | 0x0045FFFF | 63 | row 12 | nothing |
| 0x00460000 | 0xFFFFFFFF | | possibly peripherals | possibly peripherals |

## Spatial unrolling

A configurable amount of execution units (EUs) may be vertically stacked on top of one another. These act as a single computer sped up by a factor of however many EUs there are compared to a computer with only one EU, resulting in an instructions per frame figure larger than 1.

Further, a single EU can execute multiple instructions: each EU has three restricted-purpose sub-execution units (REU) and one general-purpose sub-execution unit (GEU), vertically stacked in this order. The details of what "restricted" means in this context are explained in [TODO](TODO) below, but the main idea is that GEUs can execute all instructions (almost, see immediately below), while REUs can only execute instructions that do not involve anything complicated, such as accessing memory or branching. Computers spend most of their time executing the simple sort of instructions that REUs can handle, so trading some number of GEUs for a greater number of REUs makes sense.

An additional layer of complexity on top of this is that the GEU in each EU can be either multiply-incapable, which does not have the 32-by-32-bit multiplier, or multiply-capable, which does have it. Thus, the EU itself is also either multiply-incapable or multiply-capable. A computer built entirely of multiply-incapable EUs cannot execute multiplication instructions and just hangs when attempting to do so anyway. See [Instruction scheduling](TODO) for further details.

## Input and output

Input and output are implemented via memory mapping, i.e. treating read and write accesses to specific addresses as receiving data from and sending data to peripherals.

Each EU exposes its memory bus as lines of FILT, which can be used to, effectively, put peripherals "on the bus", letting it intercept reads and writes, or they can be left disconnected altogether, in which case they do not influence execution in any way.

In response to memory accesses addressed to it, hardware may inject a wait cycle, which causes the EU executing the access to functionally do nothing and let the next EU retry the access on its bus. This repeats until an EU finishes the access without a wait cycle being injected.

# Architecture

The architecture this family of computers implements largely follows the RISC-V Unprivileged Architecture, Version 20250508 (the *specification*). If you know what that means, see [Details for those with RISC-V background](TODO) below. Otherwise, see [Details for those with no RISC-V background](TODO) below.

## Details for those with RISC-V background

These computers implement the 32-bit base integer instruction set, RV32I, with the extensions Zicond, Zmmul, and Zifencei. The memory system is little-endian.

Exceptions, interrupts, and traps do not exist. Thus, exceptions cannot be raised, interrupts cannot be serviced, and traps do not occur. `ecall` and `ebreak` are repurposed as "halt execution" instructions.

Many instructions reserved or declared illegal by the specification are perfectly valid and handled as *some* instruction by these computers. For example, as the optional 16-bit compressed instruction set is not supported, the lowest two bits of instructions are completely ignored and may take any configuration: behaviour in all cases is as if they take the configuration `11`.

In general, if implementing the aforementioned instruction set exactly as specified would cause a hole to appear in the 32-bit instruction space, these computers handle instruction encodings in that hole the same way as one of the instruction encodings that are actually in the instruction set, and are "close", in terms of number of differing bits, to those in the hole. The primary reason for this is that it makes instruction decoding much simpler, and as exceptions do not exist, there would be no way to report a decoding failure anyway.

See [Instruction reference](TODO) for exact details, including some not covered by the RISC-V specification.

## Details for those with no RISC-V background

TODO

See [Instruction reference](TODO) for details on the supported instructions.

## Hardware interface

*This section discusses in-depth details whose understanding is not strictly required for programming these computers, but is required if you plan on building your own peripherals. Building peripherals is a daunting task, but contributions are welcome. If unsure or if you have an idea for a new peripheral but no idea how to build it, ask me to see if I can maybe build it myself.*

TODO

### The buttons

The computer has three buttons on its bottom side, in this order from left to right:

 - reset: force execution to be halted, set the program counter to 0, cancel any injected wait cycles;
 - halt: request execution to be halted;
 - start: start execution.

It also has an indicator next to these buttons that lights up when the computer is running.

The difference between forcing and requesting execution to be halted is that forcing it brings the computer to an indeterminate state in terms of memory and register contents, though at least a state from which execution can be restarted normally nonetheless, while requesting it waits for all pending memory accesses to finish.

Note: As wait cycles prevent memory accesses from finishing, halt requests are ignored if a wait cycle has been injected into the bottommost execution unit. This can keep happening indefinitely if the execution unit is trying to access an address in memory that is not backed by either the built-in memory or any peripheral. In this case, the computer must be reset instead.

### The memory bus

The FILT lines of memory bus lines are, from top to bottom, as follows:

#### Address 24 LSB output

Produces the 24 least significant bits of the address being accessed by the EU. Hardware may decide to act based on this address.

Bit layout:

| bits | function |
|-|-|
| 31 to 29 | 0, unused |
| 28 | 1, sentinel |
| 27 to 26 | 0, unused |
| 25 | Write Access |
| 24 | Read Access |
| 23 to 0 | Address 24 LSB |

At most one of the *Write Access* and *Read Access* bits is ever set in any given frame.

The portion of the address available here is valid only if one of the *Write Access* and *Read Access* bits is set; it is indeterminate and should be ignored otherwise.

#### Address 8 MSB + Data 16 LSB output

Produces the 8 most significant bits of the address, and also the 16 least significant bits of the data being written.

Bit layout:

| bits | function |
|-|-|
| 31 to 29 | 0, unused |
| 28 | 1, sentinel |
| 27 | 0, unused |
| 26 | Sign Extend |
| 25 | Word Access |
| 24 | Halfword Access |
| 23 to 16 | Address 8 MSB |
| 15 to 0 | Data 16 LSB |

The portion of the data being written available here is valid only if the *Address 24 LSB* output indicates that the EU is executing a write; it is indeterminate and should be ignored otherwise.

The portion of the address available here and the *Sign Extend*, *Word Access*, and *Halfword Access* bits are valid only if the *Address 24 LSB* output indicates that the EU is executing a read or a write; they are indeterminate and should be ignored otherwise.

Any number of the *Word Access* and *Halfword Access* bits may be set in any given frame. If both the *Word Access* and *Halfword Access* bits are set, the *Halfword Access* bit should be ignored and the access treated as a word access.

In any sub-word write access, the peripheral is expected to extract the relevant portion of bits from the 32 bits of data being written. For example, if the *Halfword Access* bit is set, and the least significant bit of the 32-bit address is also set, the peripheral is expected to extract the 16 most significant bits of the 32 bits of data being written. Due to the added complexity of this requirement, it is conventional for a peripheral to only respond to word-sized write accesses.

In any sub-word read access, the peripheral is expected to provide 32 bits of data, with the relevant portion of bits filled with the data being read. For example, if the *Halfword Access* bit is set, and the least significant bit of the 32-bit address is also set, the peripheral is expected to deposit the data being read in the 16 most significant bits of the 32 bits it provides. Due to the added complexity of this requirement, it is conventional for a peripheral to only respond to word-sized read accesses.

The *Sign Extend* bit is only informative and a peripheral should make no decision based on it. Crucially, a peripheral does not have to do anything even remotely similar to sign extension on the data it provides in response to a read access; the bus does the sign extension of the relevant portion of the data on its own.

#### Data 16 MSB output

Produces the 16 most significant bits of the data being written.

Bit layout:

| bits | function |
|-|-|
| 31 to 29 | 0, unused |
| 28 | 1, sentinel |
| 27 to 16 | 0, unused |
| 15 to 0 | Data 16 MSB |

The portion of the data being written available here is valid only if the *Address 24 LSB* output indicates that the EU is executing a write; it is indeterminate and should be ignored otherwise.

#### Bus State input

Takes the bus state, which peripherals use this to indicate that they want the EU to wait (for data to be available to be read, for example) or that they want to handle an access, and also takes the 16 least significant bits of the data being read.

Bit layout:

| bits | function |
|-|-|
| 31 to 29 | must be 0, unused |
| 28 | must be 1, sentinel |
| 27 to 18 | must be 0, unused |
| 17 | Wait Request |
| 16 | Access Handled |
| 15 to 0 | Data 16 LSB |

If left disconnected, it is internally reset such that it indicates no wait cycle request and no access handled.

A peripheral sets the *Access Handled* bit if it wants to mark a read or write access handled. This prevents the internal memory from handling the access, and if it is a read access, overrides the its results with the data provided by this input and the *Data 16 MSB* input. It is only valid to set this bit if the *Address 24 LSB* output indicates that the EU is executing a read or a write.

A peripheral sets the *Wait Request* bit if it wants to defer the read or write access to a later EU, or potentially any EU in a later simulation frame. This prevents the internal memory from handling the access, and causes the next EU to retry the access. It is only valid to set this bit if the *Address 24 LSB* output indicates that the EU is executing a read or a write.

#### Data 16 MSB input

Takes the 16 most significant bits of the data being read.

Bit layout:

| bits | function |
|-|-|
| 31 to 29 | must be 0, unused |
| 28 | must be 1, sentinel |
| 27 to 16 | must be 0, unused |
| 15 to 0 | Data 16 MSB |

### Conventional bus structure

To make the bus, as explained so far, convenient to use, the convention is to include a dummy peripheral at the end of the part of the bus exposed on each EU that injects a wait cycle whenever an access happens on the bus that is not handled by the internal memory. This does two things. First, it ensures that the internal memory responds only in the address range configured by the `memory_base` property, and second, combined with peripherals that override the bus state and data input generated by all other peripherals to their right, it ensures that all bus accesses that are not handled by a real peripheral or the internal memory result in a wait cycle being injected.

This makes the bus much more convenient to use, as this means that an instruction that is meant to access a specific peripheral can be safely executed on any EU, not only the one the peripheral is connected to. If it is executed on another EU, the dummy peripherals at the ends inject wait cycles until the instruction is attempted to be executed on the correct EU.

If there is no ambiguity in which peripheral handles which bus access (i.e. there is no kind of bus access that multiple peripherals present on the bus may handle), this approach ensures that bus accesses are always routed to the correct peripheral, without any consideration required on the software side.

# Writing and uploading programs

TODO

## RISC-V assembly

TODO

## High-level languages

TODO

# Instruction reference

*This section discusses in-depth details whose understanding is not strictly required for programming these computers with high-level languages, but is required for programming them with RISC-V assembly through TPTASM. If unsure, see [High-level languages](TODO) above to see if they satisfy your needs and might save you from having to learn RISC-V.*

TODO

# Example saves

TODO

# Configuration

*This section discusses in-depth details whose understanding is not strictly required for programming these computers with high-level languages, but it is required for building your own save with a custom set of peripherals. If unsure, check [Example saves](TODO) above to see if there are any that fit your needs and might save you from having to build your own.*

TODO

## Terminal

TODO

## R316 peripheral adapter

TODO

## FILT input box

TODO

## FILT output box

TODO

## INST input box

TODO

## INST output box

TODO

## Random source

TODO

## Frame clock

TODO
