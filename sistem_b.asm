; ==========================================================
;  SISTEM B  -  8086 Ikinci Birim
;  DUZELTMELER:
;   1. KEYMAP 3. satiri bozuk yorumdan kurtarildi (M-R kayip tus sorunu)
;   2. 8259 baslatma sirasindan gereksiz IN satirlari kaldirildi
;   3. Kesme vektoru adresleri sabitlendi (ES:[20h] ve ES:[22h])
;   4. Port adresleri ayri CPU icin dogru degerlerle ayarlanir
;      (Proteus'ta 2. 8086 ayni port adres uzayini kullaniyorsa
;       0040-0044h birakilabilir; ayri decode varsa degistirin)
; ==========================================================

CODE    SEGMENT PARA 'CODE'
        ASSUME CS:CODE, DS:DATA, SS:STAK

DATA    SEGMENT PARA 'DATA'

    LATEST_ROW_B DB ?
    LATEST_COL_B DB ?
    PORTAREAD_B  DB ?
    PORTBREAD_B  DB ?

    ; --- KEYMAP B ---
    ; DUZELTME 1: 3. satir ayri DB satirina alindi, bozuk yorum temizlendi
    KEYMAP_B DB 'A','B','C','D','E','F'
             DB 'G','H','I','J','K','L'
             DB 'M','N','O','P','Q','R'
             DB 'S','T','U','V','W',03h
             DB 'Y','Z','0','1','2','3'
             DB '4','5','6','7','8','9'
             DB 08h,0Dh,' ',0Ch,01h,02h
             DB '+','-','*','/',3Dh,0Fh

    ; --- PIN ---
    IS_LOCKED_B   DB 1
    MY_PIN_B      DB '1','2','3','4'
    PIN_INPUT_B   DB 4 DUP(0)
    PIN_COUNT_B   DB 0
    LOCK_MSG_B    DB 'PIN:', 0
    WRONG_MSG_B   DB 'WRONG', 0
    GREET_MSG_B   DB 'HAZIR', 0

    ; --- HESAP MAKINESI ---
    VAL1_B    DW 0
    CUR_VAL_B DW 0
    MATH_OP_B DB 0

    ; --- LCD ---
    MASK_HIGH_B   DB 0F0h
    MASK_LOW_B    DB 0Fh
    MASK_E_SET_B  DB 20h
    MASK_RS_SET_B DB 10h

    ; --- TUS KUYRUGU ---
    Q_SIZE_B     EQU 16
    KEY_QUEUE_B  DB Q_SIZE_B DUP(0)
    Q_HEAD_B     DB 0
    Q_TAIL_B     DB 0

    ; --- EKRAN ---
    CURSOR_POS_B    DB 0
    IS_FIRST_KEY_B  DB 1
    SCREEN_BUFFER_B DB 32 DUP(' ')

    ; --- OYUN ---
    IS_GAME_MODE_B DB 0
    GAME_OVER_B    DB 0
    DINO_ROW_B     DB 1
    CACTUS_COL_B   DB 15
    CACTUS_ROW_B   DB 1
    GAME_MSG_B     DB 'GAME OVER', 0

    ; --- 8251A HABERLESME ---
    RX_BUFFER_B   DB 32 DUP(' ')
    RX_COUNT_B    DB 0
    RX_READY_B    DB 0
    SEND_OK_MSG_B DB 'GONDERILDI', 0
    RX_HDR_MSG_B  DB 'GELEN:', 0

DATA    ENDS

STAK    SEGMENT PARA STACK 'STACK'
        DW 128 DUP(?)
STAK    ENDS

; ---- 8255B I/O Adresleri ----
; NOT: Proteus'ta 2. CPU icin hangi adresleri bagladiysan onlari yaz.
; Ayni adres uzayi kullaniliyorsa asagidaki degerler dogrudur.
PORTA_B       EQU 0040h
PORTB_B       EQU 0042h
PORTC_B       EQU 0044h
CONTROL8255_B EQU 0046h

; ---- 8259B PIC ----
COMMAND8259_B EQU 0030h
DATA8259_B    EQU 0032h   ; DUZELTME 2: 8259 veri portu 0021h (komut+1), 0022h degil

; ---- 8251A_B USART ----
USART_DATA_B  EQU 0060h
USART_CTRL_B  EQU 0062h

; ---- Ozel Tus Kodlari ----
KEY_GONDER_B EQU 03h
KEY_BS_B     EQU 08h
KEY_ENTER_B  EQU 0Dh
KEY_CLR_B    EQU 0Ch
KEY_LEFT_B   EQU 01h
KEY_RIGHT_B  EQU 02h
KEY_GAME_B   EQU 0Fh

; ---- 8251A Sabitler ----
USART_MODE_B  EQU 4Eh
USART_CMD_B   EQU 37h
USART_TxRDY_B EQU 01h
USART_RxRDY_B EQU 02h
STX_VAL_B     EQU 0FEh
ETX_VAL_B     EQU 0FFh

; ==========================================================
START PROC
    MOV AX, STAK
    MOV SS, AX
    MOV SP, 256
    
    MOV AX, DATA
    MOV DS, AX

    ; 8255B baslat: PA=giris, PB=giris, PC=cikis
    MOV DX, CONTROL8255_B
    MOV AL, 092h
    OUT DX, AL

    CALL LCD_INIT_B
    CALL USART_INIT_B

    ; PIN ekrani
    LEA SI, LOCK_MSG_B
    CALL PRINT_STRING_SI_B

    ; ----------------------------------------------------------
    ; DUZELTME 3: 8259 dogru baslatma sirasi
    ; ICW1 -> komut portuna, ICW2 ve ICW4 -> veri portuna
    ; Araya IN komutu GIRMEZ - 8259 yazma sirasi belirlidir
    ; ----------------------------------------------------------
    MOV AL, 013h            ; ICW1: kenar tetiklemeli, tek, ICW4 gerekli
    OUT COMMAND8259_B, AL
    MOV AL, 008h            ; ICW2: IRQ0 = INT 8 (vektor tabani)
    OUT DATA8259_B, AL
    MOV AL, 001h            ; ICW4: 8086 modu
    OUT DATA8259_B, AL
    MOV AL, 0FEh            ; OCW1: sadece IRQ0 maskesiz, digerleri maskeli
    OUT DATA8259_B, AL

    STI

    ; ----------------------------------------------------------
    ; DUZELTME 4: Kesme vektoru dogru adreslere yaziliyor
    ; ICW2=08h -> IRQ0 INT numarasi = 8
    ; INT 8 vektor adresi = 8 * 4 = 32 = 0020h
    ; ES:[20h] = offset, ES:[22h] = segment
    ; ----------------------------------------------------------
    XOR AX, AX
    MOV ES, AX

    ; NMI (INT 2) vektoru: adres = 2*4 = 8
    MOV WORD PTR ES:[0008h], OFFSET DUMMY_NMI_B
    MOV WORD PTR ES:[000Ah], CS

    ; IRQ0 (INT 8) vektoru: adres = 8*4 = 32 = 0020h
    MOV WORD PTR ES:[0020h], OFFSET KEY_ISR_B
    MOV WORD PTR ES:[0022h], CS

    MOV AX, DS
    MOV ES, AX

MAIN_LOOP_B:
    CALL USART_POLL_RX_B
    MOV AL, [IS_GAME_MODE_B]
    CMP AL, 1
    JE  DO_GAME_LOOP_B
    CALL PROCESS_QUEUE_B
    JMP MAIN_LOOP_B

DO_GAME_LOOP_B:
    CALL GAME_TICK_B
    JMP MAIN_LOOP_B
START ENDP

; ==========================================================
;  8251A USART BASLANGIC
; ==========================================================
USART_INIT_B PROC NEAR
    PUSH AX
    PUSH DX

    MOV DX, USART_CTRL_B
    ; Reset sekasi: 3x 00h, sonra 40h (internal reset)
    MOV AL, 00h
    OUT DX, AL
    CALL DELAY_2MS_B
    OUT DX, AL
    CALL DELAY_2MS_B
    OUT DX, AL
    CALL DELAY_2MS_B
    MOV AL, 40h
    OUT DX, AL
    CALL DELAY_2MS_B
    ; Mode: 8bit, no parity, 1 stop, x1 baud
    MOV AL, USART_MODE_B
    OUT DX, AL
    CALL DELAY_2MS_B
    ; Komut: TxEN=1, RxEN=1, RTS=1, DTR=1
    MOV AL, USART_CMD_B
    OUT DX, AL
    CALL DELAY_2MS_B

    POP DX
    POP AX
    RET
USART_INIT_B ENDP

; ==========================================================
;  8251A RX POLLING
; ==========================================================
USART_POLL_RX_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    MOV DX, USART_CTRL_B
    IN  AL, DX
    TEST AL, USART_RxRDY_B
    JZ  UPR_EXIT_B

    MOV DX, USART_DATA_B
    IN  AL, DX

    CMP AL, STX_VAL_B
    JNE UPR_CHECK_ETX_B
    LEA DI, RX_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [RX_COUNT_B], 0
    MOV BYTE PTR [RX_READY_B], 0
    JMP UPR_EXIT_B

UPR_CHECK_ETX_B:
    CMP AL, ETX_VAL_B
    JNE UPR_STORE_B
    MOV BYTE PTR [RX_READY_B], 1
    CALL SHOW_RX_MESSAGE_B
    JMP UPR_EXIT_B

UPR_STORE_B:
    MOV BL, [RX_COUNT_B]
    CMP BL, 31
    JAE UPR_EXIT_B
    LEA SI, RX_BUFFER_B
    XOR BH, BH
    ADD SI, BX
    MOV [SI], AL
    INC BYTE PTR [RX_COUNT_B]

UPR_EXIT_B:
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
USART_POLL_RX_B ENDP

; ==========================================================
;  GELEN MESAJI EKRANDA GOSTER
; ==========================================================
SHOW_RX_MESSAGE_B PROC NEAR
    PUSH AX
    PUSH CX
    PUSH SI
    PUSH DI

    MOV AL, 001h
    CALL LCD_CMD_B
    LEA DI, SCREEN_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS_B], 0

    LEA SI, RX_HDR_MSG_B
SRM_HDR_B:
    MOV AL, [SI]
    CMP AL, 0
    JE  SRM_BODY_B
    MOV DL, AL
    CALL UPDATE_BUFFER_AND_SCROLL_B
    INC SI
    JMP SRM_HDR_B

SRM_BODY_B:
    MOV BYTE PTR [CURSOR_POS_B], 16
    LEA SI, RX_BUFFER_B
    MOV CL, [RX_COUNT_B]
    XOR CH, CH
SRM_LOOP_B:
    CMP CX, 0
    JE  SRM_DONE_B
    MOV DL, [SI]
    CMP DL, 20h
    JB  SRM_SKIP_B
    CALL UPDATE_BUFFER_AND_SCROLL_B
SRM_SKIP_B:
    INC SI
    DEC CX
    JMP SRM_LOOP_B

SRM_DONE_B:
    CALL LCD_REDRAW_ALL_B
    POP DI
    POP SI
    POP CX
    POP AX
    RET
SHOW_RX_MESSAGE_B ENDP

; ==========================================================
;  GONDER_B - SCREEN_BUFFER_B'yi Sistem A'ya gonder
; ==========================================================
SEND_SCREEN_TO_A PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    MOV AL, STX_VAL_B
    CALL USART_SEND_BYTE_B

    LEA SI, SCREEN_BUFFER_B
    MOV CX, 16
SSA_LOOP:
    MOV AL, [SI]
    CALL USART_SEND_BYTE_B
    INC SI
    LOOP SSA_LOOP

    MOV AL, ETX_VAL_B
    CALL USART_SEND_BYTE_B

    MOV AL, 001h
    CALL LCD_CMD_B
    LEA DI, SCREEN_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS_B], 0
    LEA SI, SEND_OK_MSG_B
    CALL PRINT_STRING_SI_B

    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
SEND_SCREEN_TO_A ENDP

USART_SEND_BYTE_B PROC NEAR
    PUSH AX
    PUSH DX
    PUSH BX
    MOV BL, AL
USB_WAIT_B:
    MOV DX, USART_CTRL_B
    IN  AL, DX
    TEST AL, USART_TxRDY_B
    JZ  USB_WAIT_B
    MOV AL, BL
    MOV DX, USART_DATA_B
    OUT DX, AL
    POP BX
    POP DX
    POP AX
    RET
USART_SEND_BYTE_B ENDP

; ==========================================================
;  OYUN MOTORU B
; ==========================================================
GAME_TICK_B PROC NEAR
    CALL GAME_READ_KEYS_B
    MOV AL, [IS_GAME_MODE_B]
    CMP AL, 0
    JE  GT_EXIT_B
    CALL GAME_UPDATE_PHYSICS_B
    CALL GAME_DRAW_SCREEN_B
    CALL DELAY_GAME_SPEED_B
GT_EXIT_B:
    RET
GAME_TICK_B ENDP

GAME_READ_KEYS_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH SI
GRK_LOOP_B:
    MOV AL, [Q_HEAD_B]
    MOV BL, [Q_TAIL_B]
    CMP AL, BL
    JE  GRK_END_B
    LEA SI, KEY_QUEUE_B
    MOV BL, AL
    XOR BH, BH
    ADD SI, BX
    MOV DL, BYTE PTR [SI]
    INC AL
    CMP AL, Q_SIZE_B
    JB  GRK_HEAD_OK_B
    MOV AL, 0
GRK_HEAD_OK_B:
    MOV [Q_HEAD_B], AL
    CMP DL, KEY_CLR_B
    JE  GRK_EXIT_GAME_B
    CMP DL, KEY_LEFT_B
    JE  GRK_GO_UP_B
    CMP DL, KEY_RIGHT_B
    JE  GRK_GO_DOWN_B
    JMP GRK_LOOP_B

GRK_EXIT_GAME_B:
    MOV BYTE PTR [IS_GAME_MODE_B], 0
    MOV AL, 001h
    CALL LCD_CMD_B
    LEA DI, SCREEN_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS_B], 0
    MOV WORD PTR [CUR_VAL_B], 0
    MOV WORD PTR [VAL1_B], 0
    MOV BYTE PTR [MATH_OP_B], 0
    JMP GRK_END_B

GRK_GO_UP_B:
    MOV BYTE PTR [DINO_ROW_B], 0
    JMP GRK_LOOP_B
GRK_GO_DOWN_B:
    MOV BYTE PTR [DINO_ROW_B], 1
    JMP GRK_LOOP_B
GRK_END_B:
    POP SI
    POP BX
    POP AX
    RET
GAME_READ_KEYS_B ENDP

GAME_UPDATE_PHYSICS_B PROC NEAR
    MOV AL, [GAME_OVER_B]
    CMP AL, 1
    JE  GUP_END_B
    MOV AL, [CACTUS_COL_B]
    DEC AL
    CMP AL, 0FFh
    JNE GUP_SAVE_B
    IN  AL, 40h
    AND AL, 1
    MOV [CACTUS_ROW_B], AL
    MOV AL, 15
GUP_SAVE_B:
    MOV [CACTUS_COL_B], AL
    CMP AL, 2
    JNE GUP_END_B
    MOV BL, [DINO_ROW_B]
    CMP BL, [CACTUS_ROW_B]
    JNE GUP_END_B
    MOV BYTE PTR [GAME_OVER_B], 1
GUP_END_B:
    RET
GAME_UPDATE_PHYSICS_B ENDP

GAME_DRAW_SCREEN_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI
    PUSH DI
    LEA DI, SCREEN_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV AL, [GAME_OVER_B]
    CMP AL, 1
    JE  GDS_GO_B
    MOV AL, [CACTUS_ROW_B]
    MOV BL, 16
    MUL BL
    ADD AL, [CACTUS_COL_B]
    XOR AH, AH
    LEA SI, SCREEN_BUFFER_B
    ADD SI, AX
    MOV BYTE PTR [SI], '#'
    MOV AL, [DINO_ROW_B]
    MOV BL, 16
    MUL BL
    ADD AL, 2
    XOR AH, AH
    LEA SI, SCREEN_BUFFER_B
    ADD SI, AX
    MOV BYTE PTR [SI], '&'
    JMP GDS_RENDER_B
GDS_GO_B:
    LEA SI, GAME_MSG_B
    LEA DI, SCREEN_BUFFER_B + 3
GDS_GO_LOOP_B:
    MOV AL, [SI]
    CMP AL, 0
    JE  GDS_RENDER_B
    MOV [DI], AL
    INC SI
    INC DI
    JMP GDS_GO_LOOP_B
GDS_RENDER_B:
    CALL LCD_REDRAW_ALL_B
    POP DI
    POP SI
    POP CX
    POP BX
    POP AX
    RET
GAME_DRAW_SCREEN_B ENDP

DELAY_GAME_SPEED_B PROC NEAR
    PUSH CX
    PUSH DX
    MOV DX, 1
DGS_OUTER_B:
    MOV CX, 10000
DGS_INNER_B:
    NOP
    LOOP DGS_INNER_B
    DEC DX
    JNZ DGS_OUTER_B
    POP DX
    POP CX
    RET
DELAY_GAME_SPEED_B ENDP

; ==========================================================
;  KLAVYE KESME SERVISI B (IRQ0 -> INT 8)
; ==========================================================
KEY_ISR_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    MOV DX, PORTA_B
    IN  AL, DX
    MOV [PORTAREAD_B], AL

    XOR BX, BX
FIND_ROW_B:
    TEST AL, 1
    JZ  FOUND_ROW_B
    INC BL
    SHR AL, 1
    CMP BL, 8
    JB  FIND_ROW_B
    JMP EXIT_ISR_B

FOUND_ROW_B:
    MOV [LATEST_ROW_B], BL
    MOV DX, PORTB_B
    IN  AL, DX
    MOV [PORTBREAD_B], AL
    XOR BX, BX

FIND_COL_B:
    TEST AL, 1
    JZ  FOUND_COL_B
    INC BL
    SHR AL, 1
    CMP BL, 6
    JB  FIND_COL_B
    JMP EXIT_ISR_B

FOUND_COL_B:
    MOV [LATEST_COL_B], BL
    MOV AL, [LATEST_ROW_B]
    MOV BL, 6
    MUL BL
    ADD AL, [LATEST_COL_B]
    CMP AL, 47
    JA  EXIT_ISR_B

    LEA SI, KEYMAP_B
    MOV BL, AL
    XOR BH, BH
    MOV AL, BYTE PTR [SI + BX]
    CMP AL, 0
    JE  EXIT_ISR_B

    MOV DL, [Q_TAIL_B]
    MOV DH, DL
    INC DL
    CMP DL, Q_SIZE_B
    JB  NEXT_OK_ISR_B
    MOV DL, 0
NEXT_OK_ISR_B:
    CMP DL, [Q_HEAD_B]
    JE  QUEUE_FULL_ISR_B
    LEA SI, KEY_QUEUE_B
    MOV BL, DH
    XOR BH, BH
    ADD SI, BX
    MOV BYTE PTR [SI], AL
    MOV [Q_TAIL_B], DL

QUEUE_FULL_ISR_B:
EXIT_ISR_B:
    ; DUZELTME 5: EOI komutu dogru porta gitmeli
    MOV AL, 020h
    OUT COMMAND8259_B, AL
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    IRET
KEY_ISR_B ENDP

; ==========================================================
;  TUS KUYRUGU ISLEME B
; ==========================================================
PROCESS_QUEUE_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

NEXT_KEY_B:
    MOV AL, [Q_HEAD_B]
    MOV BL, [Q_TAIL_B]
    CMP AL, BL
    JE  NO_KEYS_B

    LEA SI, KEY_QUEUE_B
    MOV BL, AL
    XOR BH, BH
    ADD SI, BX
    MOV DL, BYTE PTR [SI]

    INC AL
    CMP AL, Q_SIZE_B
    JB  HEAD_OK_B
    MOV AL, 0
HEAD_OK_B:
    MOV [Q_HEAD_B], AL

    ; --- KILIT KONTROLU ---
    MOV AL, [IS_LOCKED_B]
    CMP AL, 0
    JE  IS_UNLOCKED_B

    CMP DL, '0'
    JB  KEY_PROC_B
    CMP DL, '9'
    JA  KEY_PROC_B
    LEA SI, PIN_INPUT_B
    XOR BH, BH
    MOV BL, [PIN_COUNT_B]
    ADD SI, BX
    MOV [SI], DL
    INC BYTE PTR [PIN_COUNT_B]
    MOV DL, '*'
    CALL PRINT_CHAR_DL_B
    CMP BYTE PTR [PIN_COUNT_B], 4
    JNE KEY_PROC_B
    CALL CHECK_PIN_B
    JMP KEY_PROC_B

IS_UNLOCKED_B:
    ; --- ILKTUŞ: PIN mesajini sil ---
    MOV CL, [IS_FIRST_KEY_B]
    CMP CL, 0
    JE  NOT_FIRST_B
    MOV BYTE PTR [IS_FIRST_KEY_B], 0
    MOV AL, 001h
    CALL LCD_CMD_B
    LEA DI, SCREEN_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS_B], 0

NOT_FIRST_B:
    ; --- GONDER_B ---
    CMP DL, KEY_GONDER_B
    JNE NOT_GONDER_B
    CALL SEND_SCREEN_TO_A
    JMP KEY_PROC_B
NOT_GONDER_B:

    ; --- OYUN ---
    CMP DL, KEY_GAME_B
    JNE NOT_GAME_B
    MOV BYTE PTR [IS_GAME_MODE_B], 1
    MOV BYTE PTR [GAME_OVER_B], 0
    MOV BYTE PTR [CACTUS_COL_B], 15
    JMP KEY_PROC_B
NOT_GAME_B:

    ; --- KONTROL TUSLARI ---
    CMP DL, KEY_BS_B
    JE  HDL_BS_B
    CMP DL, KEY_ENTER_B
    JE  HDL_ENTER_B
    CMP DL, KEY_CLR_B
    JE  HDL_CLR_B
    CMP DL, KEY_LEFT_B
    JE  HDL_CUR_L_B
    CMP DL, KEY_RIGHT_B
    JE  HDL_CUR_R_B

    ; --- MATEMATIK ---
    CMP DL, '+'
    JE  HDL_OP_B
    CMP DL, '-'
    JE  HDL_OP_B
    CMP DL, '*'
    JE  HDL_OP_B
    CMP DL, '/'
    JE  HDL_OP_B
    CMP DL, '='
    JE  HDL_EQ_B

    ; --- RAKAMLAR ---
    CMP DL, '0'
    JB  HDL_PRINT_B
    CMP DL, '9'
    JA  HDL_PRINT_B

HDL_DIGIT_B:
    PUSH AX
    PUSH BX
    PUSH DX
    MOV AX, WORD PTR [CUR_VAL_B]
    MOV BX, 10
    MUL BX
    MOV BX, AX
    POP DX
    PUSH DX
    SUB DL, '0'
    XOR DH, DH
    ADD BX, DX
    MOV WORD PTR [CUR_VAL_B], BX
    POP DX
    POP BX
    POP AX
    JMP HDL_PRINT_B

HDL_OP_B:
    MOV AX, WORD PTR [CUR_VAL_B]
    MOV WORD PTR [VAL1_B], AX
    MOV WORD PTR [CUR_VAL_B], 0
    MOV BYTE PTR [MATH_OP_B], DL
    JMP HDL_PRINT_B

HDL_EQ_B:
    CALL PRINT_CHAR_DL_B
    MOV AX, WORD PTR [VAL1_B]
    MOV BX, WORD PTR [CUR_VAL_B]
    MOV CL, BYTE PTR [MATH_OP_B]
    CMP CL, '+'
    JNE CHK_SUB_B
    ADD AX, BX
    JMP MATH_DONE_B
CHK_SUB_B:
    CMP CL, '-'
    JNE CHK_MUL_B
    CMP AX, BX
    JAE NO_NEG_B
    SUB BX, AX
    MOV AX, BX
    PUSH AX
    MOV DL, '-'
    CALL PRINT_CHAR_DL_B
    POP AX
    JMP MATH_DONE_B
NO_NEG_B:
    SUB AX, BX
    JMP MATH_DONE_B
CHK_MUL_B:
    CMP CL, '*'
    JNE CHK_DIV_B
    MUL BX
    JMP MATH_DONE_B
CHK_DIV_B:
    CMP CL, '/'
    JNE MATH_DONE_B
    CMP BX, 0
    JE  MATH_DONE_B
    XOR DX, DX
    DIV BX
MATH_DONE_B:
    MOV WORD PTR [CUR_VAL_B], AX
    MOV WORD PTR [VAL1_B], 0
    MOV BYTE PTR [MATH_OP_B], 0
    CALL PRINT_NUM_B
    JMP KEY_PROC_B

HDL_PRINT_B:
    CALL PRINT_CHAR_DL_B
    JMP KEY_PROC_B

HDL_BS_B:
    MOV CL, [CURSOR_POS_B]
    CMP CL, 0
    JE  KEY_PROC_B
    DEC CL
    MOV [CURSOR_POS_B], CL
    LEA SI, SCREEN_BUFFER_B
    XOR CH, CH
    ADD SI, CX
    MOV BYTE PTR [SI], ' '
    MOV AL, CL
    CALL SET_HW_CURSOR_B
    MOV AL, ' '
    CALL LCD_DATA_B
    MOV AL, CL
    CALL SET_HW_CURSOR_B
    JMP KEY_PROC_B

HDL_ENTER_B:
    MOV CL, [CURSOR_POS_B]
    CMP CL, 16
    JAE ENT_L2_B
    MOV CH, 16
    JMP ENT_FILL_B
ENT_L2_B:
    MOV CH, 32
ENT_FILL_B:
    MOV CL, [CURSOR_POS_B]
    CMP CL, CH
    JE  KEY_PROC_B
    MOV DL, ' '
    MOV CL, [CURSOR_POS_B]
    CMP CL, 32
    JNE NO_SCR_ENT_B
    CALL UPDATE_BUFFER_AND_SCROLL_B
    CALL LCD_REDRAW_ALL_B
    JMP ENT_FILL_B
NO_SCR_ENT_B:
    CALL UPDATE_BUFFER_AND_SCROLL_B
    MOV AL, [CURSOR_POS_B]
    DEC AL
    CALL SET_HW_CURSOR_B
    MOV AL, DL
    CALL LCD_DATA_B
    MOV AL, [CURSOR_POS_B]
    CMP AL, 32
    JE  ENT_FILL_B
    CALL SET_HW_CURSOR_B
    JMP ENT_FILL_B

HDL_CLR_B:
    MOV AL, 001h
    CALL LCD_CMD_B
    LEA DI, SCREEN_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS_B], 0
    MOV WORD PTR [CUR_VAL_B], 0
    MOV WORD PTR [VAL1_B], 0
    MOV BYTE PTR [MATH_OP_B], 0
    JMP KEY_PROC_B

HDL_CUR_L_B:
    MOV CL, [CURSOR_POS_B]
    CMP CL, 0
    JE  KEY_PROC_B
    DEC CL
    MOV [CURSOR_POS_B], CL
    MOV AL, CL
    CALL SET_HW_CURSOR_B
    JMP KEY_PROC_B

HDL_CUR_R_B:
    MOV CL, [CURSOR_POS_B]
    CMP CL, 32
    JE  KEY_PROC_B
    INC CL
    MOV [CURSOR_POS_B], CL
    MOV AL, CL
    CALL SET_HW_CURSOR_B
    JMP KEY_PROC_B

KEY_PROC_B:
    JMP NEXT_KEY_B

NO_KEYS_B:
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
PROCESS_QUEUE_B ENDP

; ==========================================================
;  PIN KONTROL B
; ==========================================================
CHECK_PIN_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI
    PUSH DI

    LEA SI, MY_PIN_B
    LEA DI, PIN_INPUT_B
    MOV CX, 4
    REPE CMPSB
    JNE CP_WRONG_B

    MOV BYTE PTR [IS_LOCKED_B], 0
    MOV AL, 001h
    CALL LCD_CMD_B
    LEA DI, SCREEN_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS_B], 0
    LEA SI, GREET_MSG_B
    CALL PRINT_STRING_SI_B
    MOV BYTE PTR [IS_FIRST_KEY_B], 1
    MOV BYTE PTR [PIN_COUNT_B], 0
    JMP CP_END_B

CP_WRONG_B:
    MOV AL, 001h
    CALL LCD_CMD_B
    LEA DI, SCREEN_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS_B], 0
    LEA SI, WRONG_MSG_B
    CALL PRINT_STRING_SI_B
    CALL DELAY_LONG_B
    MOV AL, 001h
    CALL LCD_CMD_B
    LEA DI, SCREEN_BUFFER_B
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS_B], 0
    LEA SI, LOCK_MSG_B
    CALL PRINT_STRING_SI_B
    MOV BYTE PTR [PIN_COUNT_B], 0

CP_END_B:
    POP DI
    POP SI
    POP CX
    POP BX
    POP AX
    RET
CHECK_PIN_B ENDP

; ==========================================================
;  LCD VE YAZDIRMA YARDIMCILARI B
; ==========================================================
PRINT_STRING_SI_B PROC NEAR
    PUSH AX
    PUSH DX
PS_LOOP_B:
    MOV AL, [SI]
    CMP AL, 0
    JE  PS_END_B
    MOV DL, AL
    CALL UPDATE_BUFFER_AND_SCROLL_B
    INC SI
    JMP PS_LOOP_B
PS_END_B:
    CALL LCD_REDRAW_ALL_B
    POP DX
    POP AX
    RET
PRINT_STRING_SI_B ENDP

PRINT_CHAR_DL_B PROC NEAR
    PUSH AX
    PUSH CX
    MOV CL, [CURSOR_POS_B]
    CMP CL, 32
    JNE PCR_NO_SCROLL_B
    CALL UPDATE_BUFFER_AND_SCROLL_B
    CALL LCD_REDRAW_ALL_B
    JMP PCR_END_B
PCR_NO_SCROLL_B:
    CALL UPDATE_BUFFER_AND_SCROLL_B
    MOV AL, [CURSOR_POS_B]
    DEC AL
    CALL SET_HW_CURSOR_B
    MOV AL, DL
    CALL LCD_DATA_B
    MOV AL, [CURSOR_POS_B]
    CMP AL, 32
    JE  PCR_END_B
    CALL SET_HW_CURSOR_B
PCR_END_B:
    POP CX
    POP AX
    RET
PRINT_CHAR_DL_B ENDP

PRINT_NUM_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    CMP AX, 0
    JNE PN_START_B
    MOV DL, '0'
    CALL PRINT_CHAR_DL_B
    JMP PN_END_B
PN_START_B:
    XOR CX, CX
    MOV BX, 10
PN_DIV_B:
    CMP AX, 0
    JE  PN_PRINT_B
    XOR DX, DX
    DIV BX
    PUSH DX
    INC CX
    JMP PN_DIV_B
PN_PRINT_B:
    POP DX
    ADD DL, '0'
    CALL PRINT_CHAR_DL_B
    LOOP PN_PRINT_B
PN_END_B:
    POP DX
    POP CX
    POP BX
    POP AX
    RET
PRINT_NUM_B ENDP

DELAY_SHORT_B PROC NEAR
    PUSH CX
    MOV CX, 50
DSB_L:  NOP
    LOOP DSB_L
    POP CX
    RET
DELAY_SHORT_B ENDP

DELAY_2MS_B PROC NEAR
    PUSH CX
    MOV CX, 2000
D2B_L:  NOP
    LOOP D2B_L
    POP CX
    RET
DELAY_2MS_B ENDP

DELAY_20MS_B PROC NEAR
    PUSH CX
    MOV CX, 20000
D3B_L:  NOP
    LOOP D3B_L
    POP CX
    RET
DELAY_20MS_B ENDP

DELAY_LONG_B PROC NEAR
    PUSH CX
    MOV CX, 50
DLB_OUT:
    CALL DELAY_20MS_B
    LOOP DLB_OUT
    POP CX
    RET
DELAY_LONG_B ENDP

LCD_PULSE_E_B PROC NEAR
    PUSH CX
    PUSH DX
    MOV DX, PORTC_B
    OUT DX, AL
    MOV CL, BYTE PTR [MASK_E_SET_B]
    OR  AL, CL
    OUT DX, AL
    CALL DELAY_SHORT_B
    MOV CL, BYTE PTR [MASK_E_SET_B]
    XOR AL, CL
    OUT DX, AL
    CALL DELAY_SHORT_B
    POP DX
    POP CX
    RET
LCD_PULSE_E_B ENDP

LCD_WRITE_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    MOV DL, AL
    ; Ust nibble
    MOV AL, DL
    AND AL, 0F0h
    MOV CL, 4
    SHR AL, CL
    CMP BH, 0
    JE  HW_NO_RS_B
    OR  AL, BYTE PTR [MASK_RS_SET_B]
HW_NO_RS_B:
    CALL LCD_PULSE_E_B
    ; Alt nibble
    MOV AL, DL
    AND AL, 0Fh
    CMP BH, 0
    JE  LW_NO_RS_B
    OR  AL, BYTE PTR [MASK_RS_SET_B]
LW_NO_RS_B:
    CALL LCD_PULSE_E_B
    POP DX
    POP CX
    POP BX
    POP AX
    RET
LCD_WRITE_B ENDP

LCD_CMD_B PROC NEAR
    PUSH AX
    PUSH BX
    MOV BH, 0
    CALL LCD_WRITE_B
    CALL DELAY_2MS_B
    POP BX
    POP AX
    RET
LCD_CMD_B ENDP

LCD_DATA_B PROC NEAR
    PUSH AX
    PUSH BX
    MOV BH, 1
    CALL LCD_WRITE_B
    CALL DELAY_SHORT_B
    POP BX
    POP AX
    RET
LCD_DATA_B ENDP

LCD_INIT_B PROC NEAR
    PUSH AX
    CALL DELAY_20MS_B
    MOV AL, 033h
    MOV BH, 0
    CALL LCD_WRITE_B
    MOV AL, 032h
    MOV BH, 0
    CALL LCD_WRITE_B
    MOV AL, 028h
    CALL LCD_CMD_B
    MOV AL, 00Ch
    CALL LCD_CMD_B
    MOV AL, 006h
    CALL LCD_CMD_B
    MOV AL, 001h
    CALL LCD_CMD_B
    POP AX
    RET
LCD_INIT_B ENDP

UPDATE_BUFFER_AND_SCROLL_B PROC NEAR
    PUSH AX
    PUSH CX
    PUSH SI
    PUSH DI
    MOV CL, [CURSOR_POS_B]
    CMP CL, 32
    JNE NO_SCROLL_B
    LEA SI, SCREEN_BUFFER_B + 16
    LEA DI, SCREEN_BUFFER_B
    MOV CX, 16
    REP MOVSB
    LEA DI, SCREEN_BUFFER_B + 16
    MOV AL, ' '
    MOV CX, 16
    REP STOSB
    MOV CL, 16
NO_SCROLL_B:
    LEA SI, SCREEN_BUFFER_B
    XOR CH, CH
    ADD SI, CX
    MOV BYTE PTR [SI], DL
    INC CL
    MOV [CURSOR_POS_B], CL
    POP DI
    POP SI
    POP CX
    POP AX
    RET
UPDATE_BUFFER_AND_SCROLL_B ENDP

LCD_REDRAW_ALL_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI
    MOV AL, 02h
    CALL LCD_CMD_B
    LEA SI, SCREEN_BUFFER_B
    MOV CX, 16
L1_LOOP_B:
    MOV AL, [SI]
    CALL LCD_DATA_B
    INC SI
    LOOP L1_LOOP_B
    MOV AL, 0C0h
    CALL LCD_CMD_B
    MOV CX, 16
L2_LOOP_B:
    MOV AL, [SI]
    CALL LCD_DATA_B
    INC SI
    LOOP L2_LOOP_B
    MOV AL, [CURSOR_POS_B]
    CALL SET_HW_CURSOR_B
    POP SI
    POP CX
    POP BX
    POP AX
    RET
LCD_REDRAW_ALL_B ENDP

SET_HW_CURSOR_B PROC NEAR
    PUSH AX
    PUSH BX
    MOV BH, AL
    CMP AL, 16
    JNB CUR_L2_B
CUR_L1_B:
    ADD AL, 80h
    CALL LCD_CMD_B
    JMP CUR_DN_B
CUR_L2_B:
    SUB AL, 16
    ADD AL, 0C0h
    CALL LCD_CMD_B
CUR_DN_B:
    MOV AL, BH
    POP BX
    POP AX
    RET
SET_HW_CURSOR_B ENDP

DUMMY_NMI_B PROC NEAR
    IRET
DUMMY_NMI_B ENDP

CODE ENDS
END START