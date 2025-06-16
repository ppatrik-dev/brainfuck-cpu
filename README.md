# INP Project 1 - Simple 8-bit CPU

This project implements a simple 8-bit CPU in VHDL, designed to interpret and execute a [Brainfuck](https://en.wikipedia.org/wiki/Brainfuck) program. It demonstrates basic processor architecture, memory management, and control flow using a finite state machine.

## Project Information

- **Author**: Patrik Prochazka  
- **Institution**: Brno University of Technology, Faculty of Information Technology  
- **Year**: 2024

## Overview

This CPU acts as a Brainfuck interpreter, reading and executing Brainfuck code from memory. It includes:

- 8-bit data width
- 13-bit address space
- Memory-mapped I/O
- Support for all Brainfuck instructions
- Additional instructions for temporary storage and halting

### Supported Instructions

| Brainfuck | Description                  |
|-----------|------------------------------|
| `>`       | Move data pointer right      |
| `<`       | Move data pointer left       |
| `+`       | Increment byte at pointer    |
| `-`       | Decrement byte at pointer    |
| `.`       | Output byte at pointer       |
| `,`       | Input byte to pointer        |
| `[`       | Begin loop                   |
| `]`       | End loop                     |
| `$`       | Load memory into TMP register|
| `!`       | Store TMP to memory          |
| `@`       | Halt execution               |

> **Note**: `$`, `!`, and `@` are non-standard Brainfuck extensions.

## Architecture Overview

- **Program Counter (PC)** – Tracks current instruction address
- **Pointer Register (PTR)** – Points to current data cell
- **Temporary Register (TMP)** – Stores an intermediate 8-bit value
- **Counter Register (CNT)** – Used for nested loop tracking
- **FSM (Finite State Machine)** – Drives execution of instructions
- **Multiplexers (MX1, MX2)** – Control memory addressing and data paths

## Port Descriptions

### Clock and Control

- `CLK` – Clock signal  
- `RESET` – Asynchronous reset  
- `EN` – Enable execution  

### Memory Interface

- `DATA_ADDR[12:0]` – Address bus  
- `DATA_WDATA[7:0]` – Data to write  
- `DATA_RDATA[7:0]` – Data read from memory  
- `DATA_RDWR` – Read (`1`) or Write (`0`)  
- `DATA_EN` – Enable memory access  

### Input Interface

- `IN_DATA[7:0]` – Input data (e.g., keyboard)  
- `IN_VLD` – Input data valid  
- `IN_REQ` – Request input  

### Output Interface

- `OUT_DATA[7:0]` – Data to output  
- `OUT_BUSY` – Output device busy flag  
- `OUT_INV` – Toggle inverse display  
- `OUT_WE` – Write enable for output  

### Status Signals

- `READY` – CPU initialized and running  
- `DONE` – Program has halted  

## Memory Format

Memory should be preloaded with a Brainfuck program, followed by the special character `@` (ASCII 0x40), which marks the end of code and beginning of data (data tape).

