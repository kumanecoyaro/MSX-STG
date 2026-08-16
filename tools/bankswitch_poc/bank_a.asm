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
    LD (7000h),A     ; select bank 1 for window B (8000h-BFFFh)
    ; --- settle delay: give the flashcart's flash chip time to    ---
    ; --- actually present the new bank's data before the very next ---
    ; --- fetch reads from it (real-hardware finding: without this, ---
    ; --- the jump below landed on stale/transitional bytes -       ---
    ; --- garbled display, then a freeze).                          ---
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    JP 0BF00h        ; jump to the entry stub near the tail of bank B/1
