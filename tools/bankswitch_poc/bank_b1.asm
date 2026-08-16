; --- Bank-switch POC: "bank 1" (window 8000h-BFFFh) content. ---
; Entry stub deliberately placed near the very END of the 16KB window
; (not the head) so that as real stage-2 content is added later,
; growing upward from 8000h, it never has to push this stub around -
; the jump target address stays fixed forever.
;
; SCREEN1 (T32) VRAM layout, set up by bank 0's INIT32 call:
;   0000h-07FFh  pattern generator table (BIOS default font left as-is)
;   1800h-1AFFh  name table (32 cols x 24 rows, 1 byte/cell = char code)
;   2000h-201Fh  color table (32 groups of 8 codes)
; so on-screen text is written at 1800h + row*32 + col, using the
; BIOS's normal ASCII-ish default font (no custom patterns loaded by
; this POC), which is why real ASCII codes are used below instead of
; this game's own custom pattern numbering.
    ORG 0BF00h

WRTVDP EQU 0047h   ; BIOS: write VDP register (C=reg#, B=data)

STAGE2_ENTRY:
    ; --- DIAGNOSTIC checkpoint: border color 8 = "landed at         ---
    ; --- STAGE2_ENTRY successfully" - the very first instruction    ---
    ; --- executed after the switch+jump. If the border never gets   ---
    ; --- past whatever MAINLOOP last set (color 7), the jump itself ---
    ; --- - or the fetch immediately after it - is what's freezing.  ---
    LD B,8 : LD C,7 : CALL WRTVDP

    ; one-shot: clear the whole name table (1800h-1AFFh, 32x24=768   ---
    ; cells) to blank (32=space) and hide every sprite (write the     ---
    ; standard MSX "stop here" Y sentinel 0D1h to sprite 0's Y byte   ---
    ; at 1B00h, which halts sprite processing for the whole table).   ---
    ; Real-hardware finding: without this, stage 1's leftover clouds/ ---
    ; ship/terrain stayed on screen under the new single-color        ---
    ; palette below, which made the un-cleared terrain patterns       ---
    ; render as visual noise instead of their intended look.          ---
    DI
    LD A,00h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,58h : OUT (99h),A   ; 1800h low=00h high=(18h|40h)=58h
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,32           ; space
    LD B,0            ; 256
STAGE2_CLR1:
    OUT (98h),A
    DJNZ STAGE2_CLR1
    LD B,0            ; 256 more (512 total)
STAGE2_CLR2:
    OUT (98h),A
    DJNZ STAGE2_CLR2
    LD B,0            ; 256 more (768 total = 32*24, exactly fills 1800h-1AFFh)
STAGE2_CLR3:
    OUT (98h),A
    DJNZ STAGE2_CLR3

    LD A,00h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,5Bh : OUT (99h),A   ; 1B00h low=00h high=(1Bh|40h)=5Bh (sprite attribute table)
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,0D1h
    OUT (98h),A
    EI

    ; one-shot: paint the whole color table (2000h, 32 groups) a single
    ; readable color (white text on blue background = 0F4h). The real
    ; game's own COLORDATA (loaded during INIT, long before this bank
    ; is ever selected) is tuned for its own custom graphics, not for
    ; displaying ASCII text - a real BlueMSX test showed "STAGE 2"
    ; drawing correctly but in garbled/unintended colors without this.
    DI
    LD A,00h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,60h : OUT (99h),A   ; 2000h low=00h high=(20h|40h)=60h
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD B,32
STAGE2_COLORLOOP:
    LD A,0F4h
    OUT (98h),A
    DJNZ STAGE2_COLORLOOP
    EI

    ; --- DIAGNOSTIC checkpoint: border color 9 = "color table fill  ---
    ; --- done".                                                      ---
    LD B,9 : LD C,7 : CALL WRTVDP

    ; one-shot: write "STAGE 2" into name table row0 cols0-7 (VRAM 1800h)
    DI
    LD A,00h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,58h : OUT (99h),A   ; 1800h low=00h high=(18h|40h)=58h
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD HL,STAGE2_TEXT
    LD B,8
STAGE2_TXTLOOP:
    LD A,(HL)
    OUT (98h),A
    INC HL
    DJNZ STAGE2_TXTLOOP
    EI

    ; --- DIAGNOSTIC checkpoint: border color 10 = "text draw done,  ---
    ; --- entering the counter loop". If this never appears, the     ---
    ; --- text-draw block itself is what's freezing.                 ---
    LD B,10 : LD C,7 : CALL WRTVDP

    XOR A
    LD (0E000h),A

STAGE2_LOOP:
    ; visible pacing: ~30 vblanks (roughly half a second) per digit step,
    ; using this codebase's own EI+HALT idiom for vblank sync
    LD B,30
STAGE2_WAIT:
    EI
    HALT
    DJNZ STAGE2_WAIT

    LD A,(0E000h)
    INC A
    CP 10
    JR C,STAGE2_NOWRAP
    XOR A
STAGE2_NOWRAP:
    LD (0E000h),A

    ; draw it as an ASCII digit at name table row1 col0 (VRAM 1820h)
    ADD A,30h   ; '0'
    LD C,A
    DI
    LD A,20h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,58h : OUT (99h),A   ; 1820h low=20h high=(18h|40h)=58h
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,C
    OUT (98h),A
    EI

    JR STAGE2_LOOP

STAGE2_TEXT:
    DB "STAGE 2 "
