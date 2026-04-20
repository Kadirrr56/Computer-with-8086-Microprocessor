; ==========================================================
;  SISTEM A  -  8086 Ana Birim
;  - 48 tuslu klavye (8x6 matris)
;  - 16x2 LCD
;  - PIN sistemi, Hesap makinesi, Dino oyunu
;  - 8251A USART ile Sistem B'ye / B'den mesaj
;
;  PORT HARITASI (8255A):
;    PORTA  = 0040h  -> Klavye satir girisi
;    PORTB  = 0042h  -> Klavye sutun girisi
;    PORTC  = 0044h  -> LCD veri/kontrol cikisi
;    CTR    = 0046h  -> 8255 kontrol
;
;  8251A PORT HARITASI:
;    USART_DATA    = 0060h  -> 8251A veri kayitci
;    USART_CMD_STA = 0062h  -> 8251A komut/durum kayitci
;
;  KLAVYE KEYMAP (8 satir x 6 sutun = 48 tus):
;    Satir 0: A B C D E F
;    Satir 1: G H I J K L
;    Satir 2: M N O P Q R
;    Satir 3: S T U V W X  (X yerine GONDER)
;    Satir 4: Y Z 0 1 2 3
;    Satir 5: 4 5 6 7 8 9
;    Satir 6: BS ENTER SPC CLR LEFT RIGHT
;    Satir 7: + - * / = GAME
; ==========================================================

CODE    SEGMENT PARA 'CODE'
        ASSUME CS:CODE, DS:DATA, SS:STAK

DATA    SEGMENT PARA 'DATA'

    ; --- KLAVYE OKUMA ---
    LATEST_ROW_DETECTED DB ?
    LATEST_COL_DETECTED DB ?
    PORTAREAD  DB ?
    PORTBREAD  DB ?

    ; --- KEYMAP (8x6 = 48 tus) ---
    ; Satir 3 Col 5 = GONDER (kod: 03h)
    ; Diger ozel tuslar ayni
    KEYMAP DB 'A','B','C','D','E','F'
           DB 'G','H','I','J','K','L'
           DB 'M','N','O','P','Q','R'
           DB 'S','T','U','V','W',03h  ; 03h = GONDER tus kodu
           DB 'Y','Z','0','1','2','3'
           DB '4','5','6','7','8','9'
           DB 08h,0Dh,' ',0Ch,01h,02h  ; BS,ENTER,SPC,CLR,LEFT,RIGHT
           DB '+','-','*','/',3Dh,0Fh  ; +,-,*,/,=,GAME

    ; --- PIN / GUVENLIK ---
    IS_LOCKED   DB 1
    MY_PIN      DB '1','2','3','4'
    PIN_INPUT   DB 4 DUP(0)
    PIN_COUNT   DB 0
    LOCK_MSG    DB 'PIN:', 0
    WRONG_MSG   DB 'WRONG', 0
    GREET_MSG   DB 'HAZIR', 0

    ; --- HESAP MAKINESI ---
    VAL1    DW 0
    CUR_VAL DW 0
    MATH_OP DB 0

    ; --- LCD YARDIMCI MASKELER ---
    MASK_HIGH  DB 0F0h
    MASK_LOW   DB 0Fh
    MASK_E_SET DB 20h
    MASK_RS_SET DB 10h

    ; --- TUS KUYRUGU ---
    Q_SIZE      EQU 16
    KEY_QUEUE   DB Q_SIZE DUP(0)
    Q_HEAD      DB 0
    Q_TAIL      DB 0

    ; --- EKRAN ---
    CURSOR_POS    DB 0
    IS_FIRST_KEY  DB 1
    SCREEN_BUFFER DB 32 DUP(' ')

    ; --- OYUN ---
    IS_GAME_MODE DB 0
    GAME_OVER    DB 0
    DINO_ROW     DB 1
    CACTUS_COL   DB 15
    CACTUS_ROW   DB 1
    GAME_MSG     DB 'GAME OVER', 0

    ; --- 8251A HABERLESME ---
    ; RX tampon: gelen mesaji burada biriktir
    RX_BUFFER   DB 32 DUP(' ')
    RX_COUNT    DB 0
    RX_READY    DB 0       ; 1 = tam mesaj geldi (ETX alindi)

    ; Gonderme icin gecici tampon
    SEND_MSG    DB 'GONDERILIYOR', 0

    ; Durum mesajlari
    SEND_OK_MSG DB 'GONDERILDI', 0
    RX_HDR_MSG  DB 'GELEN:', 0

DATA    ENDS

STAK    SEGMENT PARA STACK 'STACK'
        DW 128 DUP(?)
STAK    ENDS

; ---- I/O Adresleri ----
PORTA       EQU 0040h
PORTB       EQU 0042h
PORTC       EQU 0044h
CONTROL8255 EQU 0046h

; ---- 8259 PIC ----
COMMAND8259 EQU 0020h
DATA8259    EQU 0022h

; ---- 8251A USART ----
USART_DATA  EQU 0060h   ; Veri kayitci (okuma/yazma)
USART_CTRL  EQU 0062h   ; Komut kayitci (yazma) / Durum kayitci (okuma)

; ---- Ozel Tus Kodlari ----
KEY_GONDER  EQU 03h
KEY_BS      EQU 08h
KEY_ENTER   EQU 0Dh
KEY_CLR     EQU 0Ch
KEY_LEFT    EQU 01h
KEY_RIGHT   EQU 02h
KEY_GAME    EQU 0Fh

; ---- 8251A Sabit Degerler ----
; Mode kelimesi: x1 baud, 8bit, no parity, 1 stop -> 01001110b = 4Eh
USART_MODE  EQU 4Eh
; Komut: RTS=1, DTR=1, RxEnable=1, TxEnable=1 -> 00110111b = 37h
USART_CMD   EQU 37h
; Durum biti maskeleri
USART_TxRDY EQU 01h     ; Bit 0: gonderilebilir
USART_RxRDY EQU 02h     ; Bit 1: veri geldi

; ---- Mesaj Cerceveleme ----
STX         EQU 02h     ; Mesaj baslangici (Start of Text)  -- Not: LEFT=01h ile karismaz, 02h=RIGHT ile karismaz; ETX=03h GONDER ile karismaz degil; bu yuzden STX=0FEh kullanacagiz
ETX         EQU 0FFh    ; Mesaj sonu (ozel deger, ASCII disi)
; NOT: STX/ETX icin ASCII disi degerler kullanildi (FE/FF)
; Boylece normal metin karakterleriyle catisma olmaz
STX_VAL     EQU 0FEh
ETX_VAL     EQU 0FFh

; ==========================================================
START PROC
    MOV AX, STAK
    MOV DS, AX
    MOV SP, 256
    ; --- 2. ADIM: DATA SEGMENT KURULUMU ---
    MOV AX, DATA
    MOV DS, AX
    ; 8255 baslat: PA=giris, PB=giris, PC=cikis
    MOV DX, CONTROL8255
    MOV AL, 092h
    OUT DX, AL

    ; LCD baslat
    CALL LCD_INIT

    ; 8251A baslat
    CALL USART_INIT

    ; PIN ekrani
    LEA SI, LOCK_MSG
    CALL PRINT_STRING_SI

    ; 8259 PIC baslat (IRQ0 - klavye kesme)
    MOV AL, 013h
    OUT COMMAND8259, AL
    IN  AL, COMMAND8259
    MOV AL, 08h
    OUT DATA8259, AL
    IN  AL, DATA8259
    MOV AL, 01h
    OUT DATA8259, AL
    IN  AL, DATA8259
    MOV AL, 0FEh        ; Sadece IRQ0 acik
    OUT DATA8259, AL
    STI

    ; Kesme vektoru ayarla
    XOR AX, AX
    MOV ES, AX
    MOV WORD PTR ES:[8],    OFFSET DUMMY_NMI
    MOV WORD PTR ES:[10],   CS
    MOV WORD PTR ES:[8*4],  OFFSET KEY_ISR
    MOV WORD PTR ES:[8*4+2], CS

    MOV AX, DS
    MOV ES, AX

MAIN_LOOP:
    ; 8251A'dan gelen veri var mi? (polling)
    CALL USART_POLL_RX

    ; Oyun modu mu?
    MOV AL, [IS_GAME_MODE]
    CMP AL, 1
    JE  DO_GAME_LOOP

    CALL PROCESS_QUEUE
    JMP MAIN_LOOP

DO_GAME_LOOP:
    CALL GAME_TICK
    JMP MAIN_LOOP
START ENDP

; ==========================================================
;  8251A USART BASLANGIC
; ==========================================================
USART_INIT PROC NEAR
    PUSH AX
    PUSH DX
    PUSH CX

    ; Reset: 3 kez 00h gonder, sonra 40h (internal reset)
    MOV DX, USART_CTRL
    MOV AL, 00h
    OUT DX, AL
    CALL DELAY_2MS
    OUT DX, AL
    CALL DELAY_2MS
    OUT DX, AL
    CALL DELAY_2MS
    MOV AL, 40h         ; Internal reset komutu
    OUT DX, AL
    CALL DELAY_2MS

    ; Mode kelimesi yaz: 8bit, no parity, 1 stop, x1 baud
    MOV AL, USART_MODE
    OUT DX, AL
    CALL DELAY_2MS

    ; Komut kelimesi: TxEN=1, RxEN=1, RTS=1, DTR=1
    MOV AL, USART_CMD
    OUT DX, AL
    CALL DELAY_2MS

    POP CX
    POP DX
    POP AX
    RET
USART_INIT ENDP

; ==========================================================
;  8251A POLLING - ANA DONGU'DEN CAGRILIR
;  RX tampona veri biriktirir, ETX gelince RX_READY=1 yapar
;  ve ekranda gosterir
; ==========================================================
USART_POLL_RX PROC NEAR
    PUSH AX
    PUSH BX
    PUSH DX
    PUSH SI
    PUSH DI

    ; Durum oku
    MOV DX, USART_CTRL
    IN  AL, DX
    TEST AL, USART_RxRDY    ; Bit1: veri geldi mi?
    JZ  UPR_EXIT            ; Yoksa cik

    ; Veriyi al
    MOV DX, USART_DATA
    IN  AL, DX

    ; STX mi? (mesaj baslangici)
    CMP AL, STX_VAL
    JNE UPR_CHECK_ETX
    ; Tamponu temizle, yeni mesaja hazirlan
    LEA DI, RX_BUFFER
    MOV BL, ' '
    MOV CX, 32
UPR_CLR:
    MOV [DI], BL
    INC DI
    LOOP UPR_CLR
    MOV BYTE PTR [RX_COUNT], 0
    MOV BYTE PTR [RX_READY], 0
    JMP UPR_EXIT

UPR_CHECK_ETX:
    CMP AL, ETX_VAL
    JNE UPR_STORE_BYTE
    ; Mesaj tamamlandi - ekranda goster
    MOV BYTE PTR [RX_READY], 1
    CALL SHOW_RX_MESSAGE
    JMP UPR_EXIT

UPR_STORE_BYTE:
    ; Tampona yaz (max 31 karakter)
    MOV BL, [RX_COUNT]
    CMP BL, 31
    JAE UPR_EXIT
    LEA SI, RX_BUFFER
    XOR BH, BH
    ADD SI, BX
    MOV [SI], AL
    INC BYTE PTR [RX_COUNT]

UPR_EXIT:
    POP DI
    POP SI
    POP DX
    POP BX
    POP AX
    RET
USART_POLL_RX ENDP

; ==========================================================
;  GELEN MESAJI EKRANDA GOSTER
;  Ekrana: satir1="GELEN:", satir2=mesaj icerigi
; ==========================================================
SHOW_RX_MESSAGE PROC NEAR
    PUSH AX
    PUSH CX
    PUSH SI
    PUSH DI

    ; Ekrani temizle
    MOV AL, 001h
    CALL LCD_CMD
    LEA DI, SCREEN_BUFFER
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS], 0

    ; Satir 1: "GELEN:" yaz
    LEA SI, RX_HDR_MSG
SRM_HDR:
    MOV AL, [SI]
    CMP AL, 0
    JE  SRM_BODY
    MOV DL, AL
    CALL UPDATE_BUFFER_AND_SCROLL
    INC SI
    JMP SRM_HDR

SRM_BODY:
    ; Satir 2'ye gec: cursor_pos'u 16'ya set et
    MOV BYTE PTR [CURSOR_POS], 16

    ; RX_BUFFER icerigini yaz
    LEA SI, RX_BUFFER
    MOV CL, [RX_COUNT]
    XOR CH, CH
SRM_BODY_LOOP:
    CMP CX, 0
    JE  SRM_DONE
    MOV DL, [SI]
    CMP DL, ' '
    JB  SRM_SKIP
    CALL UPDATE_BUFFER_AND_SCROLL
SRM_SKIP:
    INC SI
    DEC CX
    JMP SRM_BODY_LOOP

SRM_DONE:
    CALL LCD_REDRAW_ALL

    POP DI
    POP SI
    POP CX
    POP AX
    RET
SHOW_RX_MESSAGE ENDP

; ==========================================================
;  GONDER TUSUNA BASILDI - SCREEN_BUFFER ICERIGINI B'YE GONDER
;  Protokol: STX_VAL + veri baytlari + ETX_VAL
; ==========================================================
SEND_SCREEN_TO_B PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    ; STX gonder
    MOV AL, STX_VAL
    CALL USART_SEND_BYTE

    ; SCREEN_BUFFER'in ilk satirini gonder (16 karakter)
    LEA SI, SCREEN_BUFFER
    MOV CX, 16
SSB_LOOP:
    MOV AL, [SI]
    CMP AL, ' '         ; Bosluklari da gonder (tam satir)
    CALL USART_SEND_BYTE
    INC SI
    LOOP SSB_LOOP

    ; ETX gonder
    MOV AL, ETX_VAL
    CALL USART_SEND_BYTE

    ; Ekranda onay goster
    MOV AL, 001h
    CALL LCD_CMD
    PUSH DS
    POP ES
    LEA DI, SCREEN_BUFFER
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS], 0
    LEA SI, SEND_OK_MSG
    CALL PRINT_STRING_SI

    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
SEND_SCREEN_TO_B ENDP

; ==========================================================
;  TEK BAYT GONDER (blocking - TxRDY bekler)
; ==========================================================
USART_SEND_BYTE PROC NEAR
    ; AL = gonderilecek bayt
    PUSH AX
    PUSH DX
    PUSH BX
    MOV BL, AL          ; Bayt'i koru

USB_WAIT:
    MOV DX, USART_CTRL
    IN  AL, DX
    TEST AL, USART_TxRDY
    JZ  USB_WAIT

    MOV AL, BL
    MOV DX, USART_DATA
    OUT DX, AL

    POP BX
    POP DX
    POP AX
    RET
USART_SEND_BYTE ENDP

; ==========================================================
;  OYUN MOTORU
; ==========================================================
GAME_TICK PROC NEAR
    CALL GAME_READ_KEYS
    MOV AL, [IS_GAME_MODE]
    CMP AL, 0
    JE  GT_EXIT
    CALL GAME_UPDATE_PHYSICS
    CALL GAME_DRAW_SCREEN
    CALL DELAY_GAME_SPEED
GT_EXIT:
    RET
GAME_TICK ENDP

GAME_READ_KEYS PROC NEAR
    PUSH AX
    PUSH BX
    PUSH SI
GRK_LOOP:
    MOV AL, [Q_HEAD]
    MOV BL, [Q_TAIL]
    CMP AL, BL
    JE  GRK_END
    LEA SI, KEY_QUEUE
    MOV BL, AL
    XOR BH, BH
    ADD SI, BX
    MOV DL, BYTE PTR [SI]
    INC AL
    CMP AL, Q_SIZE
    JB  GRK_HEAD_OK
    MOV AL, 0
GRK_HEAD_OK:
    MOV [Q_HEAD], AL
    CMP DL, KEY_CLR
    JE  GRK_EXIT_GAME
    CMP DL, KEY_LEFT
    JE  GRK_GO_UP
    CMP DL, KEY_RIGHT
    JE  GRK_GO_DOWN
    JMP GRK_LOOP
GRK_EXIT_GAME:
    MOV BYTE PTR [IS_GAME_MODE], 0
    MOV AL, 001h
    CALL LCD_CMD
    PUSH ES
    PUSH DS
    POP ES
    LEA DI, SCREEN_BUFFER
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    POP ES
    MOV BYTE PTR [CURSOR_POS], 0
    MOV WORD PTR [CUR_VAL], 0
    MOV WORD PTR [VAL1], 0
    MOV BYTE PTR [MATH_OP], 0
    JMP GRK_END
GRK_GO_UP:
    MOV BYTE PTR [DINO_ROW], 0
    JMP GRK_LOOP
GRK_GO_DOWN:
    MOV BYTE PTR [DINO_ROW], 1
    JMP GRK_LOOP
GRK_END:
    POP SI
    POP BX
    POP AX
    RET
GAME_READ_KEYS ENDP

GAME_UPDATE_PHYSICS PROC NEAR
    MOV AL, [GAME_OVER]
    CMP AL, 1
    JE  GUP_END
    MOV AL, [CACTUS_COL]
    DEC AL
    CMP AL, 0FFh
    JNE GUP_SAVE_COL
    IN  AL, 40h
    AND AL, 1
    MOV [CACTUS_ROW], AL
    MOV AL, 15
GUP_SAVE_COL:
    MOV [CACTUS_COL], AL
    CMP AL, 2
    JNE GUP_END
    MOV BL, [DINO_ROW]
    CMP BL, [CACTUS_ROW]
    JNE GUP_END
    MOV BYTE PTR [GAME_OVER], 1
GUP_END:
    RET
GAME_UPDATE_PHYSICS ENDP

GAME_DRAW_SCREEN PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI
    PUSH DI
    LEA DI, SCREEN_BUFFER
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV AL, [GAME_OVER]
    CMP AL, 1
    JE  GDS_DRAW_GAMEOVER
    MOV AL, [CACTUS_ROW]
    MOV BL, 16
    MUL BL
    ADD AL, [CACTUS_COL]
    XOR AH, AH
    LEA SI, SCREEN_BUFFER
    ADD SI, AX
    MOV BYTE PTR [SI], '#'
    MOV AL, [DINO_ROW]
    MOV BL, 16
    MUL BL
    ADD AL, 2
    XOR AH, AH
    LEA SI, SCREEN_BUFFER
    ADD SI, AX
    MOV BYTE PTR [SI], '&'
    JMP GDS_RENDER
GDS_DRAW_GAMEOVER:
    LEA SI, GAME_MSG
    LEA DI, SCREEN_BUFFER + 3
GDS_GO_LOOP:
    MOV AL, [SI]
    CMP AL, 0
    JE  GDS_RENDER
    MOV [DI], AL
    INC SI
    INC DI
    JMP GDS_GO_LOOP
GDS_RENDER:
    CALL LCD_REDRAW_ALL
    POP DI
    POP SI
    POP CX
    POP BX
    POP AX
    RET
GAME_DRAW_SCREEN ENDP

DELAY_GAME_SPEED PROC NEAR
    PUSH CX
    PUSH DX
    MOV DX, 1
DGS_OUTER:
    MOV CX, 10000
DGS_INNER:
    NOP
    LOOP DGS_INNER
    DEC DX
    JNZ DGS_OUTER
    POP DX
    POP CX
    RET
DELAY_GAME_SPEED ENDP

; ==========================================================
;  KLAVYE KESME SERVISI (IRQ0)
; ==========================================================
KEY_ISR PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    MOV DX, PORTA
    IN  AL, DX
    MOV [PORTAREAD], AL

    XOR BX, BX
FIND_ROW:
    TEST AL, 1
    JZ  FOUND_ROW
    INC BL
    SHR AL, 1
    CMP BL, 8
    JB  FIND_ROW
    JMP EXIT_ISR

FOUND_ROW:
    MOV [LATEST_ROW_DETECTED], BL
    MOV DX, PORTB
    IN  AL, DX
    MOV [PORTBREAD], AL
    XOR BX, BX

FIND_COL:
    TEST AL, 1
    JZ  FOUND_COL_OK
    INC BL
    SHR AL, 1
    CMP BL, 6
    JB  FIND_COL
    JMP EXIT_ISR

FOUND_COL_OK:
    MOV [LATEST_COL_DETECTED], BL
    MOV AL, [LATEST_ROW_DETECTED]
    MOV BL, 6
    MUL BL
    ADD AL, [LATEST_COL_DETECTED]
    CMP AL, 47
    JA  EXIT_ISR
    LEA SI, KEYMAP
    MOV BL, AL
    XOR BH, BH
    MOV AL, BYTE PTR [SI + BX]
    CMP AL, 0
    JE  EXIT_ISR

    ; Kuyruga ekle
    MOV DL, [Q_TAIL]
    MOV DH, DL
    INC DL
    CMP DL, Q_SIZE
    JB  NEXT_OK_ISR
    MOV DL, 0
NEXT_OK_ISR:
    CMP DL, [Q_HEAD]
    JE  QUEUE_FULL_ISR
    LEA SI, KEY_QUEUE
    MOV BL, DH
    XOR BH, BH
    ADD SI, BX
    MOV BYTE PTR [SI], AL
    MOV [Q_TAIL], DL

QUEUE_FULL_ISR:
EXIT_ISR:
    MOV AL, 020h
    OUT COMMAND8259, AL
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    IRET
KEY_ISR ENDP

; ==========================================================
;  TUS KUYRUGU ISLEME
; ==========================================================
PROCESS_QUEUE PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

NEXT_KEY:
    MOV AL, [Q_HEAD]
    MOV BL, [Q_TAIL]
    CMP AL, BL
    JE  NO_KEYS

    LEA SI, KEY_QUEUE
    MOV BL, AL
    XOR BH, BH
    ADD SI, BX
    MOV DL, BYTE PTR [SI]

    INC AL
    CMP AL, Q_SIZE
    JB  HEAD_OK
    MOV AL, 0
HEAD_OK:
    MOV [Q_HEAD], AL

    ; --- KILIT KONTROLU ---
    MOV AL, [IS_LOCKED]
    CMP AL, 0
    JE  IS_UNLOCKED

    ; Kilitli: sadece rakam kabul
    CMP DL, '0'
    JB  KEY_PROCESSED
    CMP DL, '9'
    JA  KEY_PROCESSED
    LEA SI, PIN_INPUT
    XOR BH, BH
    MOV BL, [PIN_COUNT]
    ADD SI, BX
    MOV [SI], DL
    INC BYTE PTR [PIN_COUNT]
    MOV DL, '*'
    CALL PRINT_CHAR_DL
    CMP BYTE PTR [PIN_COUNT], 4
    JNE KEY_PROCESSED
    CALL CHECK_PIN
    JMP KEY_PROCESSED

IS_UNLOCKED:
    ; --- ILKTUŞ - START YAZISINI SIL ---
    MOV CL, [IS_FIRST_KEY]
    CMP CL, 0
    JE  NOT_FIRST_KEY
    MOV BYTE PTR [IS_FIRST_KEY], 0
    MOV AL, 001h
    CALL LCD_CMD
    LEA DI, SCREEN_BUFFER
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS], 0

NOT_FIRST_KEY:
    ; --- GONDER TUSU ---
    CMP DL, KEY_GONDER
    JNE NOT_GONDER
    CALL SEND_SCREEN_TO_B
    JMP KEY_PROCESSED
NOT_GONDER:

    ; --- OYUN BASLAT ---
    CMP DL, KEY_GAME
    JNE NOT_GAME_START
    MOV BYTE PTR [IS_GAME_MODE], 1
    MOV BYTE PTR [GAME_OVER], 0
    MOV BYTE PTR [CACTUS_COL], 15
    JMP KEY_PROCESSED
NOT_GAME_START:

    ; --- KONTROL TUSLARI ---
    CMP DL, KEY_BS
    JE  HANDLE_BACKSPACE
    CMP DL, KEY_ENTER
    JE  HANDLE_ENTER
    CMP DL, KEY_CLR
    JE  HANDLE_CLEAR
    CMP DL, KEY_LEFT
    JE  HANDLE_CURSOR_LEFT
    CMP DL, KEY_RIGHT
    JE  HANDLE_CURSOR_RIGHT

    ; --- MATEMATIK OPERATORLERI ---
    CMP DL, '+'
    JE  HANDLE_OP
    CMP DL, '-'
    JE  HANDLE_OP
    CMP DL, '*'
    JE  HANDLE_OP
    CMP DL, '/'
    JE  HANDLE_OP
    CMP DL, '='
    JE  HANDLE_EQUAL

    ; --- RAKAMLAR ---
    CMP DL, '0'
    JB  HANDLE_PRINTABLE
    CMP DL, '9'
    JA  HANDLE_PRINTABLE

HANDLE_DIGIT:
    PUSH AX
    PUSH BX
    PUSH DX
    MOV AX, WORD PTR [CUR_VAL]
    MOV BX, 10
    MUL BX
    MOV BX, AX
    POP DX
    PUSH DX
    SUB DL, '0'
    XOR DH, DH
    ADD BX, DX
    MOV WORD PTR [CUR_VAL], BX
    POP DX
    POP BX
    POP AX
    JMP HANDLE_PRINTABLE

HANDLE_OP:
    MOV AX, WORD PTR [CUR_VAL]
    MOV WORD PTR [VAL1], AX
    MOV WORD PTR [CUR_VAL], 0
    MOV BYTE PTR [MATH_OP], DL
    JMP HANDLE_PRINTABLE

HANDLE_EQUAL:
    CALL PRINT_CHAR_DL
    MOV AX, WORD PTR [VAL1]
    MOV BX, WORD PTR [CUR_VAL]
    MOV CL, BYTE PTR [MATH_OP]
    CMP CL, '+'
    JNE CHK_SUB_A
    ADD AX, BX
    JMP MATH_DONE_A
CHK_SUB_A:
    CMP CL, '-'
    JNE CHK_MUL_A
    CMP AX, BX
    JAE NO_NEG_A
    SUB BX, AX
    MOV AX, BX
    PUSH AX
    MOV DL, '-'
    CALL PRINT_CHAR_DL
    POP AX
    JMP MATH_DONE_A
NO_NEG_A:
    SUB AX, BX
    JMP MATH_DONE_A
CHK_MUL_A:
    CMP CL, '*'
    JNE CHK_DIV_A
    MUL BX
    JMP MATH_DONE_A
CHK_DIV_A:
    CMP CL, '/'
    JNE MATH_DONE_A
    CMP BX, 0
    JE  MATH_DONE_A
    XOR DX, DX
    DIV BX
MATH_DONE_A:
    MOV WORD PTR [CUR_VAL], AX
    MOV WORD PTR [VAL1], 0
    MOV BYTE PTR [MATH_OP], 0
    CALL PRINT_NUM
    JMP KEY_PROCESSED

HANDLE_PRINTABLE:
    CALL PRINT_CHAR_DL
    JMP KEY_PROCESSED

HANDLE_BACKSPACE:
    MOV CL, [CURSOR_POS]
    CMP CL, 0
    JE  KEY_PROCESSED
    DEC CL
    MOV [CURSOR_POS], CL
    LEA SI, SCREEN_BUFFER
    XOR CH, CH
    ADD SI, CX
    MOV BYTE PTR [SI], ' '
    MOV AL, CL
    CALL SET_HW_CURSOR
    MOV AL, ' '
    CALL LCD_DATA
    MOV AL, CL
    CALL SET_HW_CURSOR
    JMP KEY_PROCESSED

HANDLE_ENTER:
    MOV CL, [CURSOR_POS]
    CMP CL, 16
    JAE ENTER_ON_L2
ENTER_ON_L1:
    MOV CH, 16
    JMP ENTER_FILL_LOOP
ENTER_ON_L2:
    MOV CH, 32
ENTER_FILL_LOOP:
    MOV CL, [CURSOR_POS]
    CMP CL, CH
    JE  KEY_PROCESSED
    MOV DL, ' '
    MOV CL, [CURSOR_POS]
    CMP CL, 32
    JNE NO_SCROLL_ENTER
    CALL UPDATE_BUFFER_AND_SCROLL
    CALL LCD_REDRAW_ALL
    JMP ENTER_FILL_LOOP
NO_SCROLL_ENTER:
    CALL UPDATE_BUFFER_AND_SCROLL
    MOV AL, [CURSOR_POS]
    DEC AL
    CALL SET_HW_CURSOR
    MOV AL, DL
    CALL LCD_DATA
    MOV AL, [CURSOR_POS]
    CMP AL, 32
    JE ENTER_FILL_LOOP
    CALL SET_HW_CURSOR
    JMP ENTER_FILL_LOOP

HANDLE_CLEAR:
    MOV AL, 001h
    CALL LCD_CMD
    LEA DI, SCREEN_BUFFER
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS], 0
    MOV WORD PTR [CUR_VAL], 0
    MOV WORD PTR [VAL1], 0
    MOV BYTE PTR [MATH_OP], 0
    JMP KEY_PROCESSED

HANDLE_CURSOR_LEFT:
    MOV CL, [CURSOR_POS]
    CMP CL, 0
    JE  KEY_PROCESSED
    DEC CL
    MOV [CURSOR_POS], CL
    MOV AL, CL
    CALL SET_HW_CURSOR
    JMP KEY_PROCESSED

HANDLE_CURSOR_RIGHT:
    MOV CL, [CURSOR_POS]
    CMP CL, 32
    JE  KEY_PROCESSED
    INC CL
    MOV [CURSOR_POS], CL
    MOV AL, CL
    CALL SET_HW_CURSOR
    JMP KEY_PROCESSED

KEY_PROCESSED:
    JMP NEXT_KEY

NO_KEYS:
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
PROCESS_QUEUE ENDP

; ==========================================================
;  PIN KONTROL
; ==========================================================
CHECK_PIN PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI
    PUSH DI

    LEA SI, MY_PIN
    LEA DI, PIN_INPUT
    MOV CX, 4
    REPE CMPSB
    JNE CP_WRONG_PIN

    MOV BYTE PTR [IS_LOCKED], 0
    MOV AL, 001h
    CALL LCD_CMD
    LEA DI, SCREEN_BUFFER
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS], 0
    LEA SI, GREET_MSG
    CALL PRINT_STRING_SI
    MOV BYTE PTR [IS_FIRST_KEY], 1
    MOV BYTE PTR [PIN_COUNT], 0
    JMP CP_END

CP_WRONG_PIN:
    MOV AL, 001h
    CALL LCD_CMD
    LEA DI, SCREEN_BUFFER
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS], 0
    LEA SI, WRONG_MSG
    CALL PRINT_STRING_SI
    CALL DELAY_LONG
    MOV AL, 001h
    CALL LCD_CMD
    LEA DI, SCREEN_BUFFER
    MOV AL, ' '
    MOV CX, 32
    REP STOSB
    MOV BYTE PTR [CURSOR_POS], 0
    LEA SI, LOCK_MSG
    CALL PRINT_STRING_SI
    MOV BYTE PTR [PIN_COUNT], 0

CP_END:
    POP DI
    POP SI
    POP CX
    POP BX
    POP AX
    RET
CHECK_PIN ENDP

; ==========================================================
;  LCD VE YAZDIRMA YARDIMCILARI
; ==========================================================
PRINT_STRING_SI PROC NEAR
    PUSH AX
    PUSH DX
PS_LOOP:
    MOV AL, [SI]
    CMP AL, 0
    JE  PS_END
    MOV DL, AL
    CALL UPDATE_BUFFER_AND_SCROLL
    INC SI
    JMP PS_LOOP
PS_END:
    CALL LCD_REDRAW_ALL
    POP DX
    POP AX
    RET
PRINT_STRING_SI ENDP

PRINT_CHAR_DL PROC NEAR
    PUSH AX
    PUSH CX
    MOV CL, [CURSOR_POS]
    CMP CL, 32
    JNE PCR_NO_SCROLL
    CALL UPDATE_BUFFER_AND_SCROLL
    CALL LCD_REDRAW_ALL
    JMP PCR_END
PCR_NO_SCROLL:
    CALL UPDATE_BUFFER_AND_SCROLL
    MOV AL, [CURSOR_POS]
    DEC AL
    CALL SET_HW_CURSOR
    MOV AL, DL
    CALL LCD_DATA
    MOV AL, [CURSOR_POS]
    CMP AL, 32
    JE PCR_END
    CALL SET_HW_CURSOR
PCR_END:
    POP CX
    POP AX
    RET
PRINT_CHAR_DL ENDP

PRINT_NUM PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    CMP AX, 0
    JNE PN_START
    MOV DL, '0'
    CALL PRINT_CHAR_DL
    JMP PN_END
PN_START:
    XOR CX, CX
    MOV BX, 10
PN_DIV_LOOP:
    CMP AX, 0
    JE PN_PRINT_LOOP
    XOR DX, DX
    DIV BX
    PUSH DX
    INC CX
    JMP PN_DIV_LOOP
PN_PRINT_LOOP:
    POP DX
    ADD DL, '0'
    CALL PRINT_CHAR_DL
    LOOP PN_PRINT_LOOP
PN_END:
    POP DX
    POP CX
    POP BX
    POP AX
    RET
PRINT_NUM ENDP

; --- Gecikme rutinleri ---
DELAY_SHORT PROC NEAR
    PUSH CX
    MOV CX, 50
DS_LOOP: NOP
    LOOP DS_LOOP
    POP CX
    RET
DELAY_SHORT ENDP

DELAY_2MS PROC NEAR
    PUSH CX
    MOV CX, 2000
D2_LOOP: NOP
    LOOP D2_LOOP
    POP CX
    RET
DELAY_2MS ENDP

DELAY_20MS PROC NEAR
    PUSH CX
    MOV CX, 20000
D3_LOOP: NOP
    LOOP D3_LOOP
    POP CX
    RET
DELAY_20MS ENDP

DELAY_LONG PROC NEAR
    PUSH CX
    MOV CX, 50
DL_OUTER:
    CALL DELAY_20MS
    LOOP DL_OUTER
    POP CX
    RET
DELAY_LONG ENDP

; --- LCD donanim rutinleri ---
LCD_PULSE_E PROC NEAR
    PUSH CX
    PUSH DX
    MOV DX, PORTC
    OUT DX, AL
    MOV CL, BYTE PTR [MASK_E_SET]
    OR  AL, CL
    OUT DX, AL
    CALL DELAY_SHORT
    MOV CL, BYTE PTR [MASK_E_SET]
    XOR AL, CL
    OUT DX, AL
    CALL DELAY_SHORT
    POP DX
    POP CX
    RET
LCD_PULSE_E ENDP

LCD_WRITE PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    MOV DL, AL
    MOV AL, DL
    MOV CL, BYTE PTR [MASK_HIGH]
    AND AL, CL
    MOV CL, 4
    SHR AL, CL
    CMP BH, 0
    JE  HW_NO_RS
    MOV CL, BYTE PTR [MASK_RS_SET]
    OR  AL, CL
HW_NO_RS:
    CALL LCD_PULSE_E
    MOV AL, DL
    MOV CL, BYTE PTR [MASK_LOW]
    AND AL, CL
    CMP BH, 0
    JE  LW_NO_RS
    MOV CL, BYTE PTR [MASK_RS_SET]
    OR  AL, CL
LW_NO_RS:
    CALL LCD_PULSE_E
    POP DX
    POP CX
    POP BX
    POP AX
    RET
LCD_WRITE ENDP

LCD_CMD PROC NEAR
    PUSH AX
    PUSH BX
    MOV BH, 0
    CALL LCD_WRITE
    CALL DELAY_2MS
    POP BX
    POP AX
    RET
LCD_CMD ENDP

LCD_DATA PROC NEAR
    PUSH AX
    PUSH BX
    MOV BH, 1
    CALL LCD_WRITE
    CALL DELAY_SHORT
    POP BX
    POP AX
    RET
LCD_DATA ENDP

LCD_INIT PROC NEAR
    PUSH AX
    CALL DELAY_20MS
    MOV AL, 033h
    MOV BH, 0
    CALL LCD_WRITE
    MOV AL, 032h
    MOV BH, 0
    CALL LCD_WRITE
    MOV AL, 028h
    CALL LCD_CMD
    MOV AL, 00Ch
    CALL LCD_CMD
    MOV AL, 006h
    CALL LCD_CMD
    MOV AL, 001h
    CALL LCD_CMD
    POP AX
    RET
LCD_INIT ENDP

UPDATE_BUFFER_AND_SCROLL PROC NEAR
    PUSH AX
    PUSH CX
    PUSH SI
    PUSH DI
    MOV CL, [CURSOR_POS]
    CMP CL, 32
    JNE NO_SCROLL
    LEA SI, SCREEN_BUFFER + 16
    LEA DI, SCREEN_BUFFER
    MOV CX, 16
    REP MOVSB
    LEA DI, SCREEN_BUFFER + 16
    MOV AL, ' '
    MOV CX, 16
    REP STOSB
    MOV CL, 16
NO_SCROLL:
    LEA SI, SCREEN_BUFFER
    XOR CH, CH
    ADD SI, CX
    MOV BYTE PTR [SI], DL
    INC CL
    MOV [CURSOR_POS], CL
    POP DI
    POP SI
    POP CX
    POP AX
    RET
UPDATE_BUFFER_AND_SCROLL ENDP

LCD_REDRAW_ALL PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI
    MOV AL, 02h
    CALL LCD_CMD
    LEA SI, SCREEN_BUFFER
    MOV CX, 16
L1_LOOP:
    MOV AL, [SI]
    CALL LCD_DATA
    INC SI
    LOOP L1_LOOP
    MOV AL, 0C0h
    CALL LCD_CMD
    MOV CX, 16
L2_LOOP:
    MOV AL, [SI]
    CALL LCD_DATA
    INC SI
    LOOP L2_LOOP
    MOV AL, [CURSOR_POS]
    CALL SET_HW_CURSOR
    POP SI
    POP CX
    POP BX
    POP AX
    RET
LCD_REDRAW_ALL ENDP

SET_HW_CURSOR PROC NEAR
    PUSH AX
    PUSH BX
    MOV BH, AL
    CMP AL, 16
    JNB CUR_ON_L2_B
CUR_ON_L1_B:
    ADD AL, 80h
    CALL LCD_CMD
    JMP CUR_DONE_B
CUR_ON_L2_B:
    SUB AL, 16
    ADD AL, 0C0h
    CALL LCD_CMD
CUR_DONE_B:
    MOV AL, BH
    POP BX
    POP AX
    RET
SET_HW_CURSOR ENDP

DUMMY_NMI PROC NEAR
    IRET
DUMMY_NMI ENDP

CODE ENDS
END START