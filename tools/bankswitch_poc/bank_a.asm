; --- Bank-switch POC: "bank 0" (window 4000h-7FFFh), the cartridge's ---
; boot bank. Real-hardware-bootable: valid "AB" header + INIT vector,
; standard BIOS SCREEN1 setup. Stays mapped in page 1 for the whole
; test - it never switches itself. Right after boot it simulates
; "stage 1 end" by switching window B (8000h-BFFFh) to bank 1 via a
; memory-mapped write to 7000h (ASCII16 mapper convention: segment 0
; select = write anywhere in 6000h-67FFh, segment 1 select = write
; anywhere in 7000h-77FFh - a normal Z80 memory write, not an OUT to
; an I/O port), then jumps straight to a fixed address near the very
; end of the newly-mapped bank.
    ORG 4000h

INIT32  EQU 006Fh   ; BIOS: switch to SCREEN1 (T32), default font/colors, clear name table

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

INIT:
    LD SP,0F380h

    ; --- bank-switch trampoline source, copied to RAM (0xF200) below. ---
    ; --- Call/jump to it with A=bank number for window B, HL=address  ---
    ; --- to jump to afterward. Executing the actual "LD (7000h),A"    ---
    ; --- from RAM instead of ROM means it can never itself be         ---
    ; --- affected by the very bank switch it's performing. A real     ---
    ; --- flashcart AND BlueMSX both froze on an earlier version of    ---
    ; --- this POC that switched-and-jumped directly from ROM.         ---
    JP BANKSWITCH_TRAMPOLINE_END
BANKSWITCH_TRAMPOLINE_SRC:
    LD (7000h),A
    JP (HL)
BANKSWITCH_TRAMPOLINE_LEN EQU $ - BANKSWITCH_TRAMPOLINE_SRC
BANKSWITCH_TRAMPOLINE_END:
    LD HL,BANKSWITCH_TRAMPOLINE_SRC
    LD DE,0F200h
    LD BC,BANKSWITCH_TRAMPOLINE_LEN
    LDIR

    ; --- map our own primary slot into page 2 (8000h-BFFFh) as well - ---
    ; --- same belt-and-suspenders step CYBER_GD_BOSS.asm's INIT does, ---
    ; --- harmless for a true mapper cartridge (the mapper's internal  ---
    ; --- bank select is a separate mechanism from this outer slot     ---
    ; --- register) but guards against a flashcart that doesn't auto-  ---
    ; --- map page 2 to the same slot as page 1 at boot.               ---
    IN A,(0A8h)
    LD B,A
    AND 0Ch
    ADD A,A
    ADD A,A
    LD C,A
    LD A,B
    AND 0CFh
    OR C
    OUT (0A8h),A

    DI
    CALL INIT32
    EI

STAGE1_END:
    LD A,1
    LD HL,0BF00h      ; jump to the entry stub near the tail of bank B/1
    JP 0F200h         ; select bank 1 for window B (8000h-BFFFh), then jump to HL
