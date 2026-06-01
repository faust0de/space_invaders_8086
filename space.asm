; ============================================================
; SPACE INVADERS - 8086 Assembly Language
; CGA Graphics Mode 4 (320x200, 4 colors)
; DOSBox + MASM Assembler
; Based on techniques from "8086 Assembly - Pong" (Programming Dimension)
; Controls: A/D = move left/right   SPACE = shoot   R = restart   Q = quit
; ============================================================

; ============================================================
; STACK SEGMENT - Reserved memory for the call stack
; ============================================================
STACK SEGMENT PARA STACK           ; Declara el segmento de pila, alineado a parrafo (16 bytes)
    DB 128 DUP (' ')               ; Reserva 128 bytes para la pila, inicializados con espacios
STACK ENDS                         ; Fin del segmento de pila

; ============================================================
; DATA SEGMENT - All game variables and constants
; ============================================================
DATA SEGMENT PARA 'DATA'           ; Declara el segmento de datos, alineado a parrafo

    ; --- Screen dimensions (CGA Mode 4: 320x200) ---
    WINDOW_WIDTH    DW 0140h       ; Ancho de pantalla en pixels (0x140 = 320 decimal)
    WINDOW_HEIGHT   DW 00C8h       ; Alto de pantalla en pixels (0xC8 = 200 decimal)

    ; --- Game state flags ---
    GAME_ACTIVE     DB 01h         ; Controla el bucle principal: 1 = juego activo, 0 = game over
    GAME_WIN        DB 00h         ; Condicion de fin: 1 = jugador gano, 0 = jugador perdio

    ; --- Time control (technique from Pong tutorial) ---
    ; INT 21h/AH=2Ch returns DL = hundredths of second (0-99)
    ; We compare each frame to detect when the value changes (= new tick)
    TIME_AUX        DB 00h         ; Ultimo valor de 1/100 seg visto; controla la velocidad del bucle

    ; --- Score display ---
    SCORE           DW 0000h       ; Puntaje numerico actual (aumenta +10 por cada enemigo eliminado)
    SCORE_STR       DB '00000', 00h ; Cadena ASCII de 5 digitos para mostrar puntaje + terminador nulo
    SCORE_X         DW 0008h       ; Columna de texto donde se dibuja el puntaje
    SCORE_Y         DW 0002h       ; Fila de texto donde se dibuja el puntaje

    ; --- End screen messages (null-terminated ASCII strings) ---
    MSG_GAMEOVER    DB 'GAME OVER', 00h            ; Mensaje cuando el jugador pierde
    MSG_WIN         DB 'YOU WIN!', 00h             ; Mensaje cuando todos los enemigos son eliminados
    MSG_SCORE       DB 'SCORE:', 00h               ; Etiqueta que aparece antes del puntaje final
    MSG_RESTART     DB 'R=RESTART  Q=QUIT', 00h    ; Instrucciones mostradas en la pantalla final

    ; --- CGA palette 1 color indices (Mode 04h, palette 1: black/cyan/magenta/white) ---
    COLOR_BLACK     EQU 00h        ; Indice 0 = negro (fondo de pantalla)
    COLOR_CYAN      EQU 01h        ; Indice 1 = cian (color de los bunkers)
    COLOR_MAGENTA   EQU 02h        ; Indice 2 = magenta (color de los enemigos)
    COLOR_WHITE     EQU 03h        ; Indice 3 = blanco (jugador y balas)

    ; --- Screen edge margin ---
    WINDOW_BOUNDS   DW 0006h       ; Margen minimo en pixels desde el borde izquierdo/derecho

    ; ========================
    ; PLAYER DATA
    ; ========================
    PLAYER_X        DW 0098h       ; Posicion horizontal del jugador en pixels (152 = centro de pantalla)
    PLAYER_Y        DW 00B0h       ; Posicion vertical del jugador en pixels (176 = cerca del fondo)
    PLAYER_COLOR    DB 03h         ; Color del jugador = blanco (indice CGA 3)
    PLAYER_VELOCITY DW 0004h       ; Pixels que se mueve el jugador por tecla presionada

    ; Player sprite definition (5 columns x 3 rows):
    ; 0 = transparent pixel (not drawn), 1 = solid pixel (drawn in PLAYER_COLOR)
    ; Visual layout:
    ;   Row 0:  . . X . .
    ;   Row 1:  . X X X .
    ;   Row 2:  X X X X X
    PLAYER_SPRITE   DB 0,0,1,0,0   ; Fila 0: punta del canon (parte superior del tanque)
                    DB 0,1,1,1,0   ; Row 1: turret body
                    DB 1,1,1,1,1   ; Fila 2: base del tanque (ancho completo)
    SPRITE_WIDTH    DW 0005h       ; Numero de columnas del sprite del jugador
    SPRITE_HEIGHT   DW 0003h       ; Numero de filas del sprite del jugador
    SPRITE_SCALE    DW 0004h       ; Factor de escala: cada pixel del sprite = bloque 4x4 en pantalla

    ; ========================
    ; PLAYER BULLET DATA
    ; ========================
    BULLET_X        DW 0000h       ; Posicion X actual de la bala del jugador
    BULLET_Y        DW 0000h       ; Posicion Y actual de la bala del jugador
    BULLET_ACTIVE   DB 00h         ; Estado de la bala: 0 = inactiva, 1 = en vuelo
    BULLET_VELOCITY DW 0006h       ; Pixels que sube la bala por tick de juego
    BULLET_COLOR    DB 03h         ; Color de la bala = blanco (indice CGA 3)

    ; Bullet sprite (3 columns x 4 rows):
    ;   . X .
    ;   . X .
    ;   . X .
    ;   X X X
    BULLET_SPRITE   DB 0,1,0       ; Fila 0: eje delgado de la bala
                    DB 0,1,0       ; Fila 1: eje delgado
                    DB 0,1,0       ; Fila 2: eje delgado
                    DB 1,1,1       ; Fila 3: base de la bala
    BULLET_SPRITE_WIDTH  DW 0003h  ; Numero de columnas del sprite de bala
    BULLET_SPRITE_HEIGHT DW 0004h  ; Numero de filas del sprite de bala

    ; ========================
    ; ENEMY BULLET DATA
    ; ========================
    EBULLET_X       DW 0000h       ; Posicion X actual de la bala enemiga
    EBULLET_Y       DW 0000h       ; Posicion Y actual de la bala enemiga
    EBULLET_ACTIVE  DB 00h         ; Estado: 0 = inactiva, 1 = bala enemiga en vuelo
    EBULLET_VELOCITY DW 0003h      ; Pixels que baja la bala enemiga por tick
    EBULLET_COLOR   DB 02h         ; Color de la bala enemiga = magenta (indice CGA 2)

    ; ========================
    ; BUNKER DATA
    ; ========================
    ; Bunker sprite shape (7 columns x 4 rows):
    ;   . X X X X X .
    ;   X X X X X X X
    ;   X X X X X X X
    ;   X X . . . X X   <- notch at bottom center (entrance for player)
    BUNKER_SPRITE   DB 0,1,1,1,1,1,0   ; Fila 0: parte superior redondeada del bunker
                    DB 1,1,1,1,1,1,1   ; Fila 1: ancho completo
                    DB 1,1,1,1,1,1,1   ; Fila 2: ancho completo
                    DB 1,1,0,0,0,1,1   ; Fila 3: base con hueco central para el jugador
    BUNKER_SPRITE_WIDTH  DW 0007h  ; Numero de columnas del sprite del bunker (7 pixels)
    BUNKER_SPRITE_HEIGHT DW 0004h  ; Numero de filas del sprite del bunker (4 pixels)
    BUNKER_SCALE         DW 0003h  ; Factor de escala: cada pixel del sprite = bloque 3x3
    BUNKER_SCALE_BYTE    DB 03h    ; Misma escala pero en BYTE (necesario para la instruccion DIV BL)

    ; Screen positions of the two bunkers
    BUNKER1_X       DW 0050h       ; Posicion X del bunker izquierdo en pixels (80)
    BUNKER2_X       DW 00D0h       ; Posicion X del bunker derecho en pixels (208)
    BUNKER_Y        DW 0090h       ; Ambos bunkers comparten la misma posicion Y (144)

    ; Per-pixel destruction state arrays for each bunker
    ; Each byte maps 1:1 to a sprite pixel: 1 = alive (draw), 0 = destroyed (skip)
    ; 7 columns x 4 rows = 28 bytes per bunker
    BUNKER1_STATE   DB 0,1,1,1,1,1,0   ; Estado fila 0 bunker 1 (1=vivo, 0=destruido)
                    DB 1,1,1,1,1,1,1   ; Estado fila 1
                    DB 1,1,1,1,1,1,1   ; Estado fila 2
                    DB 1,1,0,0,0,1,1   ; Estado fila 3 (hueco central ya destruido)

    BUNKER2_STATE   DB 0,1,1,1,1,1,0   ; Row 0 state
                    DB 1,1,1,1,1,1,1   ; Row 1 state
                    DB 1,1,1,1,1,1,1   ; Row 2 state
                    DB 1,1,0,0,0,1,1   ; Row 3 state

    ; ========================
    ; ENEMY (INVADER) DATA
    ; ========================
    ENEMY_ROWS      DW 0003h       ; Numero de filas de enemigos en la grilla (3)
    ENEMY_COLS      DW 0006h       ; Numero de columnas de enemigos en la grilla (6)
    ENEMY_COUNT     DW 0012h       ; Total de enemigos vivos = 3 * 6 = 18 (0x12)

    ; ENEMY_DATA layout: 18 entries x 5 bytes each = 90 bytes total
    ; Each entry: [STATE:1 byte][X:2 bytes][Y:2 bytes]
    ;   STATE: 1 = alive, 0 = dead (destroyed by player bullet)
    ;   X, Y: current screen position of this enemy in pixels
    ; Initialized to all zeros here; INIT_ENEMIES fills correct values at startup
    ENEMY_DATA      DB 90 DUP(00h) ; 90 bytes para 18 enemigos x 5 bytes; llenado por INIT_ENEMIES

    ; Enemy sprite shape (5 columns x 3 rows):
    ;   . X . X .
    ;   X X X X X
    ;   X . X . X
    ENEMY_SPRITE    DB 0,1,0,1,0   ; Fila 0: antenas del enemigo
                    DB 1,1,1,1,1   ; Fila 1: cuerpo del enemigo
                    DB 1,0,1,0,1   ; Fila 2: patas del enemigo
    ENEMY_SPRITE_W  DW 0005h       ; Numero de columnas del sprite enemigo
    ENEMY_SPRITE_H  DW 0003h       ; Numero de filas del sprite enemigo
    ENEMY_SCALE     DW 0003h       ; Factor de escala: cada pixel del sprite = bloque 3x3

    ; Enemy horizontal movement
    ENEMY_VEL_X     DW 0004h       ; Pixels que se mueve cada enemigo horizontalmente por paso
    ENEMY_DIR       DB 01h         ; Direccion actual: 01h = derecha, FFh = izquierda
    ENEMY_MOVE_CTR  DW 0000h       ; Ticks transcurridos desde el ultimo paso de movimiento
    ENEMY_MOVE_FREQ DW 0006h       ; Un paso de movimiento ocurre cada 8 ticks (menor = mas rapido)
    ENEMY_DROP_AMT  DW 0008h       ; Pixels que bajan los enemigos al invertir direccion

    ; Enemy shooting
    ENEMY_SHOOT_CTR  DW 0000h      ; Ticks transcurridos desde el ultimo disparo enemigo
    ENEMY_SHOOT_FREQ DW 001Eh      ; Los enemigos disparan cada 30 ticks (0x1E = 30)

    ; Initial grid layout
    ENEMY_START_X   DW 0020h       ; Posicion X inicial de la columna izquierda de enemigos (32)
    ENEMY_START_Y   DW 0018h       ; Posicion Y inicial de la fila superior de enemigos (24)
    ENEMY_SPACING_X DW 001Eh       ; Separacion horizontal entre centros de enemigos en pixels (30)
    ENEMY_SPACING_Y DW 0012h       ; Separacion vertical entre centros de enemigos en pixels (18)

    ; ========================
    ; SOUND DATA
    ; ========================
    ; PC speaker sounds use PIT (Programmable Interval Timer) channel 2.
    ; Audible frequency = 1,193,180 Hz / divisor value.
    SOUND_SHOOT_FREQ  DW 0A00h     ; Divisor PIT para sonido de disparo (~292 Hz, clic agudo)
    SOUND_HIT_FREQ    DW 0300h     ; Divisor PIT para sonido de impacto (~977 Hz, pitido medio)
    SOUND_GAMEOVER_F  DW 0100h     ; Divisor PIT para sonido de game over (~2929 Hz, tono agudo)

    ; ========================
    ; MUSIC DATA
    ; Background melody played one note per MUSIC_TICK_FREQ game ticks (non-blocking).
    ; Each value is a PIT divisor: audible frequency = 1,193,180 / divisor.
    ; Special values: 0000h = rest (silence for one step), 0FFFFh = end marker (loop back).
    ;
    ; Note reference:
    ;   0D60h ~ A3 (220 Hz)    0B20h ~ C4 / middle C (261 Hz)    09F0h ~ D4 (294 Hz)
    ;   08E0h ~ E4 (330 Hz)    0800h ~ F#4 (370 Hz)              0720h ~ G#4 (415 Hz)
    ;   0660h ~ A4 (440 Hz)
    ; ========================
    MELODY          DW 0B20h, 0B20h, 0000h, 0B20h, 0000h, 08E0h   ; Phrase 1
                    DW 0B20h, 0000h, 0800h, 0B20h, 0720h, 0000h   ; Phrase 2
                    DW 0660h, 0000h, 0660h, 0000h, 0660h, 0000h   ; Phrase 3
                    DW 08E0h, 0000h, 0000h, 0000h, 08E0h, 0000h   ; Phrase 4
                    DW 0800h, 0000h, 08E0h, 0800h, 0000h, 0720h   ; Phrase 5
                    DW 0FFFFh                                       ; End marker: jump back to start

    MELODY_IDX      DW 0000h       ; Offset en bytes dentro de MELODY para la nota actual (pasos de 2)
    MUSIC_TICK_CTR  DW 0000h       ; Ticks transcurridos desde el ultimo avance de nota
    MUSIC_TICK_FREQ DW 0006h       ; Avanza a la siguiente nota cada 6 ticks de juego

    ; Descending melody played once on the game over end screen (blocking)
    MELODY_OVER     DW 0660h, 0720h, 0800h, 08E0h, 09F0h, 0B20h   ; Descending A4 to C4
                    DW 0D60h, 0000h, 0FFFFh                         ; End on A3 then silence

    ; Ascending fanfare played once on the win end screen (blocking)
    MELODY_WIN      DW 0B20h, 09F0h, 08E0h, 0800h, 0720h, 0660h   ; Ascending C4 to A4
                    DW 0660h, 0660h, 0000h, 0FFFFh                  ; Repeat top note then silence

    ; ========================
    ; DRAW TEMPORARY VARIABLES
    ; DRAW_ENEMIES cannot use SP-relative addressing (illegal in 8086 MASM),
    ; so these named variables hold intermediate positions during enemy drawing.
    ; ========================
    DE_ENEMY_X  DW 0000h           ; Posicion X base del enemigo que se esta dibujando
    DE_ENEMY_Y  DW 0000h           ; Posicion Y base del enemigo que se esta dibujando
    DE_BLOCK_X  DW 0000h           ; X del bloque escalado actual (col * escala + X_enemigo)
    DE_BLOCK_Y  DW 0000h           ; Y del bloque escalado actual (fila * escala + Y_enemigo)

DATA ENDS                          ; Fin del segmento de datos

; ============================================================
; CODE SEGMENT - All executable procedures
; ============================================================
CODE SEGMENT PARA 'CODE'           ; Declare code segment, aligned to paragraph

MAIN PROC FAR                      ; FAR procedure: callable across segments (required for .EXE)
    ASSUME CS:CODE, DS:DATA, SS:STACK  ; Tell assembler which segment register maps to which segment

    PUSH DS                        ; Save original DS on stack (required by DOS .EXE program format)
    SUB  AX, AX                    ; AX = 0 (clear AX; SUB reg,reg is faster than MOV reg,0)
    PUSH AX                        ; Push 0 as return address so RET at end returns cleanly to DOS
    MOV  AX, DATA                  ; AX = segment address of DATA segment
    MOV  DS, AX                    ; DS now points to our DATA segment (required before using variables)

    ; --- Set CGA graphics mode 4 (320x200, 4 colors) ---
    ; Technique from Pong tutorial: INT 10h function 00h sets the video mode.
    MOV AH, 00h                    ; INT 10h function 00h = Set Video Mode
    MOV AL, 04h                    ; Mode 04h = CGA 320x200, 4-color graphics
    INT 10h                        ; Execute BIOS video interrupt to switch to graphics mode

    ; --- Select CGA palette 1 (black / cyan / magenta / white) ---
    MOV AH, 0Bh                    ; INT 10h function 0Bh = Set Color Palette
    MOV BH, 01h                    ; BH=1: select a CGA color palette (not background color)
    MOV BL, 01h                    ; BL=1: choose palette 1 (cyan/magenta/white)
    INT 10h                        ; Execute palette selection

    ; --- Initialize enemy grid positions and states ---
    CALL INIT_ENEMIES              ; Fill ENEMY_DATA array with starting positions

    ; ============================================================
    ; MAIN GAME LOOP
    ; Technique from Pong tutorial: time-based loop using system clock.
    ; The loop only advances when the 1/100s tick value changes,
    ; giving a consistent frame rate independent of CPU speed.
    ; ============================================================
GAME_LOOP:
    CMP GAME_ACTIVE, 00h           ; Is the game over? (GAME_ACTIVE set to 0 on loss or win)
    JE  SHOW_END_SCREEN            ; Yes: jump to end screen

    ; --- Wait for next 1/100s tick (time control from Pong tutorial) ---
    MOV AH, 2Ch                    ; INT 21h function 2Ch = Get System Time
    INT 21h                        ; Returns: CH=hours CL=minutes DH=seconds DL=1/100 seconds
    CMP DL, TIME_AUX               ; Is current 1/100s value the same as last frame?
    JE  GAME_LOOP                  ; Yes: loop again (busy-wait until tick changes)
    MOV TIME_AUX, DL               ; No: save new tick value and proceed with this frame

    ; --- Clear screen: erase previous frame before drawing new one ---
    CALL CLEAR_SCREEN              ; Fill display with black using INT 10h scroll function

    ; --- Process keyboard input and move player ---
    CALL MOVE_PLAYER               ; Read keyboard buffer; move player or fire bullet

    ; --- Update positions of all moving objects ---
    CALL MOVE_BULLET               ; Move player bullet upward one step
    CALL MOVE_EBULLET              ; Move enemy bullet downward; trigger new shot if needed
    CALL MOVE_ENEMIES              ; Move enemy grid left/right; drop when wall is reached

    ; --- Collision detection (all checks each frame) ---
    CALL CHECK_BULLET_BUNKER_COLLISION    ; Player bullet hits bunker -> destroy pixel
    CALL CHECK_BULLET_ENEMY_COLLISION     ; Player bullet hits enemy  -> kill enemy, add score
    CALL CHECK_EBULLET_BUNKER_COLLISION   ; Enemy bullet hits bunker  -> destroy pixel
    CALL CHECK_EBULLET_PLAYER_COLLISION   ; Enemy bullet hits player  -> game over
    CALL CHECK_ENEMIES_REACHED_BOTTOM     ; Enemy reaches player row  -> game over

    ; --- Draw all visible game objects ---
    CALL DRAW_BUNKERS              ; Draw both bunkers (only alive pixels)
    CALL DRAW_ENEMIES              ; Draw all alive enemies
    CALL DRAW_PLAYER               ; Draw the player tank sprite
    CALL DRAW_BULLET               ; Draw player bullet if active
    CALL DRAW_EBULLET              ; Draw enemy bullet if active

    ; --- Draw score in top-left area ---
    MOV DH, BYTE PTR SCORE_Y      ; DH = row for cursor (text row units, from SCORE_Y variable)
    MOV DL, BYTE PTR SCORE_X      ; DL = col for cursor (text col units, from SCORE_X variable)
    CALL DRAW_SCORE                ; Convert SCORE to ASCII and display at (DH, DL)

    ; --- Advance background music by one step ---
    CALL PLAY_MUSIC_TICK           ; Play or silence speaker based on melody position

    JMP GAME_LOOP                  ; Repeat forever until GAME_ACTIVE = 0

    ; ============================================================
    ; END SCREEN
    ; Reached when GAME_ACTIVE = 0 (win or lose).
    ; Displays result message, plays end melody, waits for R or Q.
    ; ============================================================
SHOW_END_SCREEN:
    CALL STOP_SOUND                ; Silence speaker immediately (stop any looping music)
    CALL CLEAR_SCREEN              ; Blank the screen before drawing end screen text

    CMP GAME_WIN, 01h              ; Did the player win?
    JE  SHOW_WIN_MSG               ; Yes: show win message

    ; --- Game Over path ---
    MOV DH, 0Ch                    ; Text row 12 (vertical center of 25-row text grid)
    MOV DL, 0Ah                    ; Text col 10 (roughly centered for "GAME OVER")
    LEA SI, MSG_GAMEOVER           ; SI = address of "GAME OVER" string
    CALL DRAW_STRING               ; Draw the string at (DH, DL)

    LEA SI, MELODY_OVER            ; SI = address of descending game-over melody
    CALL PLAY_MELODY               ; Play entire melody (blocking: waits until done)
    JMP SHOW_RESTART_PROMPT        ; Skip win message, go to prompt

SHOW_WIN_MSG:
    MOV DH, 0Ch                    ; Text row 12
    MOV DL, 0Bh                    ; Text col 11 (roughly centered for "YOU WIN!")
    LEA SI, MSG_WIN                ; SI = address of "YOU WIN!" string
    CALL DRAW_STRING               ; Draw the string at (DH, DL)

    LEA SI, MELODY_WIN             ; SI = address of ascending win fanfare melody
    CALL PLAY_MELODY               ; Play entire melody (blocking)

SHOW_RESTART_PROMPT:
    ; Mostrar etiqueta "SCORE:" y los digitos en la misma fila, centrados
    ; "SCORE:" = 6 chars + espacio + 5 digitos = 12 chars en total
    ; Centrado en 40 columnas: (40 - 12) / 2 = col 14
    MOV DH, 0Eh                    ; Fila de texto 14
    MOV DL, 0Eh                    ; Columna 14: inicio de "SCORE:"
    LEA SI, MSG_SCORE
    CALL DRAW_STRING               ; Dibuja "SCORE:" en (14, 14)

    MOV DH, 0Eh                    ; Misma fila 14
    MOV DL, 15h                    ; Columna 21: justo despues de "SCORE: " (14 + 7)
    CALL DRAW_SCORE                ; Dibuja los 5 digitos del puntaje en (14, 21)

    ; Mostrar instrucciones centradas en fila 16
    ; "R=RESTART  Q=QUIT" = 18 chars -> col inicio = (40-18)/2 = 11
    MOV DH, 10h                    ; Fila de texto 16
    MOV DL, 0Bh                    ; Columna 11: centrado para "R=RESTART  Q=QUIT"
    LEA SI, MSG_RESTART
    CALL DRAW_STRING

WAIT_KEY:
    MOV AH, 00h                    ; INT 16h function 00h = blocking read key from keyboard
    INT 16h                        ; Waits here until a key is pressed; AL = ASCII code

    CMP AL, 72h                    ; Is it 'r' (lowercase, ASCII 0x72)?
    JE  DO_RESTART                 ; Yes: restart game
    CMP AL, 52h                    ; Is it 'R' (uppercase, ASCII 0x52)?
    JE  DO_RESTART                 ; Yes: restart game
    CMP AL, 71h                    ; Is it 'q' (lowercase, ASCII 0x71)?
    JE  DO_QUIT                    ; Yes: exit to DOS
    CMP AL, 51h                    ; Is it 'Q' (uppercase, ASCII 0x51)?
    JE  DO_QUIT                    ; Yes: exit to DOS
    JMP WAIT_KEY                   ; Any other key: ignore and wait again

DO_RESTART:
    CALL RESET_GAME                ; Restore all variables to initial values
    JMP  GAME_LOOP                 ; Re-enter main game loop from the top

DO_QUIT:
    MOV AX, 4C00h                  ; INT 21h function 4Ch = Terminate Program, exit code 0
    INT 21h                        ; Return control to DOS

    RET                            ; Fallback return (should never reach here after INT 21h)
MAIN ENDP                          ; End of MAIN procedure

; ============================================================
; INIT_ENEMIES
; Fills ENEMY_DATA with starting positions for an 3x6 grid.
; Each enemy entry is 5 bytes: [STATE(1)][X(2)][Y(2)]
; STATE is set to 1 (alive).
; X = ENEMY_START_X + (col * ENEMY_SPACING_X)
; Y = ENEMY_START_Y + (row * ENEMY_SPACING_Y)
; ============================================================
INIT_ENEMIES PROC NEAR
    MOV SI, 0                      ; SI = byte offset into ENEMY_DATA (starts at 0)
    MOV BX, 0                      ; BX = current row index (0..ENEMY_ROWS-1)

IE_ROW_LOOP:
    CMP BX, ENEMY_ROWS             ; Have we filled all rows?
    JGE IE_DONE                    ; Yes: exit loop

    MOV CX, 0                      ; CX = current column index (0..ENEMY_COLS-1)

IE_COL_LOOP:
    CMP CX, ENEMY_COLS             ; Have we filled all columns in this row?
    JGE IE_NEXT_ROW                ; Yes: move to next row

    MOV BYTE PTR ENEMY_DATA[SI], 01h  ; STATE = 1 (enemy is alive)
    INC SI                         ; SI now points to the X field (1 byte past STATE)

    ; Calculate X position: X = ENEMY_START_X + (col * ENEMY_SPACING_X)
    PUSH BX                        ; Save BX (row counter) because MUL may clobber DX:AX
    MOV  AX, CX                    ; AX = current column index
    MUL  ENEMY_SPACING_X           ; DX:AX = col * ENEMY_SPACING_X (we only need AX)
    ADD  AX, ENEMY_START_X         ; AX = final X position in pixels
    MOV  WORD PTR ENEMY_DATA[SI], AX   ; Store X into ENEMY_DATA entry
    ADD  SI, 2                     ; SI now points to the Y field (2 bytes past X)

    ; Calculate Y position: Y = ENEMY_START_Y + (row * ENEMY_SPACING_Y)
    MOV  AX, BX                    ; AX = current row index (BX was saved, safe to use)
    MUL  ENEMY_SPACING_Y           ; DX:AX = row * ENEMY_SPACING_Y
    ADD  AX, ENEMY_START_Y         ; AX = final Y position in pixels
    MOV  WORD PTR ENEMY_DATA[SI], AX   ; Store Y into ENEMY_DATA entry
    ADD  SI, 2                     ; SI now points to STATE of next entry (2 bytes past Y)
    POP  BX                        ; Restore row counter

    INC CX                         ; Advance to next column
    JMP IE_COL_LOOP                ; Process next column

IE_NEXT_ROW:
    INC BX                         ; Advance to next row
    JMP IE_ROW_LOOP                ; Process next row

IE_DONE:
    RET                            ; All 18 enemies initialized; return to caller
INIT_ENEMIES ENDP

; ============================================================
; DRAW_PLAYER
; Draws the player sprite onto the CGA framebuffer.
; For each non-zero byte in PLAYER_SPRITE, draws a
; SPRITE_SCALE x SPRITE_SCALE filled block at the
; corresponding screen position.
; ============================================================
DRAW_PLAYER PROC NEAR
    PUSH BP                        ; Save BP: we use it as BLOCK_Y temporary storage

    MOV SI, 0                      ; SI = index into PLAYER_SPRITE byte array
    MOV BX, 0                      ; BX = current sprite row (0..SPRITE_HEIGHT-1)

DP_ROW_LOOP:
    CMP BX, SPRITE_HEIGHT          ; Processed all rows?
    JGE DP_END                     ; Yes: done drawing player

    MOV CX, 0                      ; CX = current sprite column (0..SPRITE_WIDTH-1)

DP_COL_LOOP:
    CMP CX, SPRITE_WIDTH           ; Processed all columns in this row?
    JGE DP_NEXT_ROW                ; Yes: go to next row

    MOV AL, PLAYER_SPRITE[SI]      ; AL = sprite pixel value at [row][col]
    CMP AL, 00h                    ; Is it 0 (transparent)?
    JE  DP_SKIP                    ; Yes: skip drawing this pixel

    ; --- Pixel is solid: draw a SPRITE_SCALE x SPRITE_SCALE block ---
    PUSH BX                        ; Save sprite row (BX will be reused as block row counter)
    PUSH CX                        ; Save sprite column (CX will be reused as X coordinate)
    PUSH SI                        ; Save sprite index (SI will be reused as block col counter)

    ; BLOCK_X = PLAYER_X + (col * SPRITE_SCALE)
    MOV AX, CX                     ; AX = current sprite column
    MUL SPRITE_SCALE               ; AX = col * SPRITE_SCALE (pixel offset from player origin)
    ADD AX, PLAYER_X               ; AX = absolute screen X of this block's left edge
    MOV DI, AX                     ; DI = BLOCK_X (preserved across block drawing loops)

    ; BLOCK_Y = PLAYER_Y + (row * SPRITE_SCALE)
    MOV AX, BX                     ; AX = current sprite row
    MUL SPRITE_SCALE               ; AX = row * SPRITE_SCALE
    ADD AX, PLAYER_Y               ; AX = absolute screen Y of this block's top edge
    MOV BP, AX                     ; BP = BLOCK_Y (preserved across block drawing loops)

    MOV BX, 0                      ; BX = block row counter (0..SPRITE_SCALE-1)

DP_BLOCK_ROW:
    CMP BX, SPRITE_SCALE           ; Drawn all rows of the block?
    JGE DP_BLOCK_END               ; Yes: finish this block

    MOV SI, 0                      ; SI = block column counter (0..SPRITE_SCALE-1)

DP_BLOCK_COL:
    CMP SI, SPRITE_SCALE           ; Drawn all columns in this block row?
    JGE DP_BLOCK_NEXT_ROW          ; Yes: go to next block row

    MOV AX, BP                     ; AX = BLOCK_Y
    ADD AX, BX                     ; AX = BLOCK_Y + block_row = screen Y of this pixel
    MOV DX, AX                     ; DX = Y coordinate for INT 10h

    MOV AX, DI                     ; AX = BLOCK_X
    ADD AX, SI                     ; AX = BLOCK_X + block_col = screen X of this pixel
    MOV CX, AX                     ; CX = X coordinate for INT 10h

    MOV AH, 0Ch                    ; INT 10h function 0Ch = Write Graphics Pixel
    MOV AL, PLAYER_COLOR           ; AL = pixel color (white, CGA index 3)
    MOV BH, 00h                    ; BH = video page 0
    INT 10h                        ; Draw single pixel at (CX, DX)

    INC SI                         ; Next block column
    JMP DP_BLOCK_COL               ; Continue block column loop

DP_BLOCK_NEXT_ROW:
    INC BX                         ; Next block row
    JMP DP_BLOCK_ROW               ; Continue block row loop

DP_BLOCK_END:
    POP SI                         ; Restore sprite array index
    POP CX                         ; Restore sprite column counter
    POP BX                         ; Restore sprite row counter

DP_SKIP:
    INC SI                         ; Advance to next byte in sprite array
    INC CX                         ; Advance to next sprite column
    JMP DP_COL_LOOP                ; Continue sprite column loop

DP_NEXT_ROW:
    INC BX                         ; Advance to next sprite row
    JMP DP_ROW_LOOP                ; Continue sprite row loop

DP_END:
    POP BP                         ; Restore caller's BP
    RET                            ; Return to caller
DRAW_PLAYER ENDP

; ============================================================
; MOVE_PLAYER
; Checks the keyboard buffer and acts on recognized keys:
;   A / a  -> move player left
;   D / d  -> move player right
;   SPACE  -> fire bullet (if none already active)
; Clamps player position so it stays within screen bounds.
; ============================================================
MOVE_PLAYER PROC NEAR
    MOV AH, 01h                    ; INT 16h function 01h = Check keyboard buffer (non-blocking)
    INT 16h                        ; ZF=1 if buffer is empty, ZF=0 if a key is waiting
    JZ  MP_NO_KEY                  ; Buffer empty: nothing to process this frame

    MOV AH, 00h                    ; INT 16h function 00h = Read key from buffer (removes it)
    INT 16h                        ; AL = ASCII code of the key pressed

    CMP AL, 61h                    ; Is it 'a' (lowercase, ASCII 0x61)?
    JE  MP_LEFT                    ; Yes: move left
    CMP AL, 41h                    ; Is it 'A' (uppercase, ASCII 0x41)?
    JE  MP_LEFT                    ; Yes: move left
    CMP AL, 64h                    ; Is it 'd' (lowercase, ASCII 0x64)?
    JE  MP_RIGHT                   ; Yes: move right
    CMP AL, 44h                    ; Is it 'D' (uppercase, ASCII 0x44)?
    JE  MP_RIGHT                   ; Yes: move right
    CMP AL, 20h                    ; Is it SPACE (ASCII 0x20)?
    JE  MP_SHOOT                   ; Yes: try to fire a bullet

MP_NO_KEY:
    JMP MP_EXIT                    ; No recognized key: nothing to do

MP_LEFT:
    MOV AX, PLAYER_VELOCITY        ; AX = movement speed in pixels
    SUB PLAYER_X, AX               ; Move player left by subtracting from X
    MOV AX, WINDOW_BOUNDS          ; AX = left boundary (minimum allowed X)
    CMP PLAYER_X, AX               ; Did we go past the left edge?
    JGE MP_EXIT                    ; No: position is valid, exit
    MOV PLAYER_X, AX               ; Yes: clamp to left boundary
    JMP MP_EXIT

MP_RIGHT:
    MOV AX, PLAYER_VELOCITY        ; AX = movement speed in pixels
    ADD PLAYER_X, AX               ; Move player right by adding to X

    ; Right limit = WINDOW_WIDTH - WINDOW_BOUNDS - (SPRITE_WIDTH * SPRITE_SCALE)
    ; We subtract the sprite width so the player's right edge doesn't go off screen
    MOV AX, SPRITE_WIDTH           ; AX = sprite width in pixels (before scaling)
    MUL SPRITE_SCALE               ; AX = actual pixel width on screen (5 * 4 = 20)
    MOV DI, AX                     ; DI = pixel width of player sprite
    MOV AX, WINDOW_WIDTH           ; AX = total screen width (320)
    SUB AX, WINDOW_BOUNDS          ; AX = 320 - 6 = 314 (right margin)
    SUB AX, DI                     ; AX = 314 - 20 = 294 (maximum allowed PLAYER_X)
    CMP PLAYER_X, AX               ; Did we exceed right boundary?
    JLE MP_EXIT                    ; No: valid position, exit
    MOV PLAYER_X, AX               ; Yes: clamp to right boundary
    JMP MP_EXIT

MP_SHOOT:
    CMP BULLET_ACTIVE, 01h         ; Is a player bullet already in flight?
    JE  MP_EXIT                    ; Yes: cannot fire again until it disappears

    MOV BULLET_ACTIVE, 01h         ; Activate the bullet

    ; Center bullet horizontally over the player:
    ; BULLET_X = PLAYER_X + (SPRITE_WIDTH * SPRITE_SCALE / 2)
    MOV AX, SPRITE_WIDTH           ; AX = sprite column count (5)
    MUL SPRITE_SCALE               ; AX = scaled sprite width in pixels (20)
    SHR AX, 1                      ; AX = half sprite width = center offset (10)
    ADD AX, PLAYER_X               ; AX = PLAYER_X + center offset
    MOV BULLET_X, AX               ; Store bullet starting X

    ; Place bullet just above the player's top edge:
    ; BULLET_Y = PLAYER_Y - BULLET_SPRITE_HEIGHT
    MOV AX, PLAYER_Y               ; AX = player's Y (top edge)
    SUB AX, BULLET_SPRITE_HEIGHT   ; Subtract bullet height so it appears above player
    MOV BULLET_Y, AX               ; Store bullet starting Y

    ; Play shoot sound effect
    MOV BX, SOUND_SHOOT_FREQ       ; BX = PIT divisor for shoot sound frequency
    CALL PLAY_SOUND                ; Turn on speaker with that frequency
    CALL STOP_SOUND                ; Immediately turn off (creates a short click)

MP_EXIT:
    RET                            ; Return to caller
MOVE_PLAYER ENDP

; ============================================================
; DRAW_BULLET
; If the player bullet is active, iterates over BULLET_SPRITE
; and draws each non-zero pixel at (BULLET_X + col, BULLET_Y + row).
; No scaling: bullet is drawn 1 pixel per sprite byte.
; ============================================================
DRAW_BULLET PROC NEAR
    CMP BULLET_ACTIVE, 01h         ; Is the bullet currently in flight?
    JNE DB_EXIT                    ; No: nothing to draw

    MOV SI, 0                      ; SI = index into BULLET_SPRITE byte array
    MOV BX, 0                      ; BX = current sprite row (0..BULLET_SPRITE_HEIGHT-1)

DB_ROW_LOOP:
    CMP BX, BULLET_SPRITE_HEIGHT   ; Processed all sprite rows?
    JGE DB_EXIT                    ; Yes: done

    MOV CX, 0                      ; CX = current sprite column (0..BULLET_SPRITE_WIDTH-1)

DB_COL_LOOP:
    CMP CX, BULLET_SPRITE_WIDTH    ; Processed all columns in this row?
    JGE DB_NEXT_ROW                ; Yes: next row

    MOV AL, BULLET_SPRITE[SI]      ; AL = sprite pixel value (0 = transparent, 1 = draw)
    CMP AL, 00h                    ; Transparent pixel?
    JE  DB_SKIP                    ; Yes: skip this pixel

    PUSH BX                        ; Save row counter (INT 10h may clobber BX via BH)
    PUSH CX                        ; Save col counter (INT 10h uses CX as X coordinate)
    PUSH SI                        ; Save sprite index

    MOV AX, BULLET_Y               ; AX = bullet's Y base position
    ADD AX, BX                     ; AX = Y + row = screen Y of this pixel
    MOV DX, AX                     ; DX = Y for INT 10h

    MOV AX, BULLET_X               ; AX = bullet's X base position
    ADD AX, CX                     ; AX = X + col = screen X of this pixel
    MOV CX, AX                     ; CX = X for INT 10h

    MOV AH, 0Ch                    ; INT 10h function 0Ch = Write Graphics Pixel
    MOV AL, BULLET_COLOR           ; AL = color (white)
    MOV BH, 00h                    ; BH = video page 0
    INT 10h                        ; Plot pixel

    POP SI                         ; Restore sprite index
    POP CX                         ; Restore column counter
    POP BX                         ; Restore row counter

DB_SKIP:
    INC SI                         ; Next byte in sprite array
    INC CX                         ; Next column
    JMP DB_COL_LOOP                ; Continue column loop

DB_NEXT_ROW:
    INC BX                         ; Next row
    JMP DB_ROW_LOOP                ; Continue row loop

DB_EXIT:
    RET
DRAW_BULLET ENDP

; ============================================================
; MOVE_BULLET
; Moves the player bullet upward by BULLET_VELOCITY pixels.
; Deactivates it if it goes above the top of the screen.
; ============================================================
MOVE_BULLET PROC NEAR
    CMP BULLET_ACTIVE, 01h         ; Is the bullet in flight?
    JNE MB_EXIT                    ; No: nothing to move

    MOV AX, BULLET_VELOCITY        ; AX = pixels to move per tick
    SUB BULLET_Y, AX               ; Move bullet up (subtract = decreasing Y = upward)

    CMP BULLET_Y, 0000h            ; Has the bullet gone above Y=0 (top of screen)?
    JL  MB_DISABLE                 ; Yes: deactivate it
    JMP MB_EXIT                    ; No: bullet still on screen

MB_DISABLE:
    MOV BULLET_ACTIVE, 00h         ; Mark bullet as inactive

MB_EXIT:
    RET
MOVE_BULLET ENDP

; ============================================================
; DRAW_EBULLET
; If the enemy bullet is active, draws it as a solid 2x4 block.
; No sprite array: shape is hardcoded as 2 columns x 4 rows.
; ============================================================
DRAW_EBULLET PROC NEAR
    CMP EBULLET_ACTIVE, 01h        ; Is the enemy bullet in flight?
    JNE DEB_EXIT                   ; No: nothing to draw

    MOV BX, 0                      ; BX = current row (0..3)

DEB_ROW:
    CMP BX, 0004h                  ; Drawn all 4 rows?
    JGE DEB_EXIT                   ; Yes: done

    MOV CX, 0                      ; CX = current column (0..1)

DEB_COL:
    CMP CX, 0002h                  ; Drawn both columns?
    JGE DEB_NEXT_ROW               ; Yes: next row

    PUSH BX                        ; Save row counter
    PUSH CX                        ; Save col counter

    MOV AX, EBULLET_Y              ; AX = enemy bullet Y base
    ADD AX, BX                     ; AX = Y + row = screen Y
    MOV DX, AX                     ; DX = Y for INT 10h

    MOV AX, EBULLET_X              ; AX = enemy bullet X base
    ADD AX, CX                     ; AX = X + col = screen X
    MOV CX, AX                     ; CX = X for INT 10h

    MOV AH, 0Ch                    ; INT 10h function 0Ch = Write Graphics Pixel
    MOV AL, EBULLET_COLOR          ; AL = color (magenta)
    MOV BH, 00h                    ; BH = page 0
    INT 10h                        ; Plot pixel

    POP CX                         ; Restore col counter
    POP BX                         ; Restore row counter

    INC CX                         ; Next column
    JMP DEB_COL                    ; Continue column loop

DEB_NEXT_ROW:
    INC BX                         ; Next row
    JMP DEB_ROW                    ; Continue row loop

DEB_EXIT:
    RET
DRAW_EBULLET ENDP

; ============================================================
; MOVE_EBULLET
; If the enemy bullet is active: moves it downward by EBULLET_VELOCITY.
; Deactivates if it reaches the bottom of the screen.
; If the bullet is NOT active: increments ENEMY_SHOOT_CTR and
; calls ENEMY_FIRE when the counter reaches ENEMY_SHOOT_FREQ.
; ============================================================
MOVE_EBULLET PROC NEAR
    CMP EBULLET_ACTIVE, 01h        ; Is there an enemy bullet in flight?
    JNE MEB_TRY_SHOOT              ; No: check if it is time to fire a new one

    MOV AX, EBULLET_VELOCITY       ; AX = pixels to move per tick
    ADD EBULLET_Y, AX              ; Move bullet downward (increasing Y = downward)

    CMP EBULLET_Y, 00C8h           ; Has bullet gone below Y=200 (bottom of screen)?
    JGE MEB_DISABLE                ; Yes: deactivate
    JMP MEB_EXIT                   ; No: still on screen

MEB_DISABLE:
    MOV EBULLET_ACTIVE, 00h        ; Mark enemy bullet as inactive
    JMP MEB_EXIT

MEB_TRY_SHOOT:
    INC ENEMY_SHOOT_CTR            ; Count one more tick since last shot
    MOV AX, ENEMY_SHOOT_CTR        ; AX = current tick count
    CMP AX, ENEMY_SHOOT_FREQ       ; Reached the firing interval?
    JL  MEB_EXIT                   ; No: not yet time to fire

    MOV ENEMY_SHOOT_CTR, 0000h     ; Reset counter for next shot cycle
    CALL ENEMY_FIRE                ; Pick an enemy and spawn a bullet

MEB_EXIT:
    RET
MOVE_EBULLET ENDP

; ============================================================
; ENEMY_FIRE
; Picks the lowest alive enemy in a pseudo-random column and
; spawns an enemy bullet at that enemy's center.
; Uses TIME_AUX mod ENEMY_COLS as a cheap column selector.
; ============================================================
ENEMY_FIRE PROC NEAR
    CMP ENEMY_COUNT, 0000h         ; Are there any enemies left alive?
    JNE EF_START                   ; Yes: proceed
    JMP EF_EXIT                    ; No: nothing to fire from
EF_START:

    ; Pick a column using TIME_AUX as a pseudo-random seed
    MOV AL, TIME_AUX               ; AL = current 1/100s tick value (0..99)
    XOR AH, AH                     ; Clear AH so AX = AL (zero-extend to 16 bits)
    MOV BL, BYTE PTR ENEMY_COLS    ; BL = number of columns (6)
    DIV BL                         ; AH = TIME_AUX mod ENEMY_COLS = chosen column (0..5)
    XOR AL, AL                     ; Clear quotient in AL
    MOV AL, AH                     ; AL = remainder (chosen column)
    XOR AH, AH                     ; Zero-extend to 16 bits
    MOV CX, AX                     ; CX = chosen column index

    ; Search for the lowest alive enemy in that column
    ; "Lowest" = highest Y value = closest to the bottom of the screen
    MOV BX, 0                      ; BX = row counter (start from top row 0)
    MOV DI, 0FFFFh                 ; DI = ENEMY_DATA offset of best candidate (0xFFFF = none yet)
    MOV DX, 0FFFFh                 ; DX = Y of best candidate (0xFFFF = none found yet)

EF_SEARCH:
    CMP BX, ENEMY_ROWS             ; Have we checked all rows?
    JGE EF_FOUND                   ; Yes: use the best candidate found

    ; Compute ENEMY_DATA offset = (row * ENEMY_COLS + col) * 5
    PUSH BX                        ; Save row counter
    PUSH CX                        ; Save column index
    MOV  AX, BX                    ; AX = row
    MUL  ENEMY_COLS                ; AX = row * ENEMY_COLS
    ADD  AX, CX                    ; AX = row * ENEMY_COLS + col = linear grid index
    MOV  SI, 05h                   ; SI = 5 (bytes per enemy entry)
    MUL  SI                        ; AX = linear index * 5 = byte offset into ENEMY_DATA
    MOV  SI, AX                    ; SI = offset of this enemy in ENEMY_DATA

    MOV AL, BYTE PTR ENEMY_DATA[SI]    ; AL = STATE of this enemy (1=alive, 0=dead)
    CMP AL, 01h                    ; Is this enemy alive?
    JNE EF_NEXT_ROW                ; No: skip to next row

    ; Check if this alive enemy is lower than our current best
    MOV AX, WORD PTR ENEMY_DATA[SI+3]  ; AX = Y position of this enemy
    CMP DX, 0FFFFh                 ; Is this the very first alive enemy found?
    JE  EF_FIRST                   ; Yes: automatically the best so far
    CMP AX, DX                     ; Is this enemy lower than current best? (higher Y)
    JLE EF_NEXT_ROW                ; No: current best is still lower (or equal), skip

EF_FIRST:
    MOV DX, AX                     ; Update best Y to this enemy's Y
    MOV DI, SI                     ; Update best offset to this enemy's ENEMY_DATA offset

EF_NEXT_ROW:
    POP CX                         ; Restore column index
    POP BX                         ; Restore row counter
    INC BX                         ; Advance to next row
    JMP EF_SEARCH                  ; Check next row

EF_FOUND:
    CMP DI, 0FFFFh                 ; Was any alive enemy found in this column?
    JE  EF_EXIT                    ; No: column is entirely dead, do not fire

    ; Position bullet at horizontal center of the chosen enemy:
    ; EBULLET_X = enemy_X + (ENEMY_SPRITE_W * ENEMY_SCALE / 2)
    MOV AX, WORD PTR ENEMY_DATA[DI+1]  ; AX = enemy X (read twice for clarity; first read)
    MOV AX, WORD PTR ENEMY_DATA[DI+1]  ; AX = enemy X (second read, same value)
    PUSH AX                            ; Save enemy X on stack
    MOV  AX, ENEMY_SPRITE_W            ; AX = sprite width in pixels (before scaling)
    MUL  ENEMY_SCALE                   ; AX = scaled sprite width
    SHR  AX, 1                         ; AX = half of scaled width = horizontal center offset
    MOV  BX, AX                        ; BX = center offset
    POP  AX                            ; Restore enemy X
    ADD  AX, BX                        ; AX = enemy X + center offset = bullet X
    MOV  EBULLET_X, AX                 ; Store bullet spawn X

    ; Posicionar bala en el borde inferior del enemigo elegido:
    ; EBULLET_Y = enemy_Y + (ENEMY_SPRITE_H * ENEMY_SCALE)
    MOV AX, ENEMY_SPRITE_H            ; AX = altura del sprite en pixels (antes de escalar)
    MUL ENEMY_SCALE                   ; AX = alto real del enemigo en pantalla (H * SCALE)
    ADD AX, WORD PTR ENEMY_DATA[DI+3] ; AX += enemy_Y = borde inferior del enemigo
    MOV EBULLET_Y, AX                 ; Guardar Y de spawn de la bala

    MOV EBULLET_ACTIVE, 01h            ; Activate the enemy bullet

EF_EXIT:
    RET
ENEMY_FIRE ENDP

; ============================================================
; DRAW_ENEMIES
; Iterates over ENEMY_DATA and draws each alive enemy sprite.
; Uses DE_ENEMY_X/Y and DE_BLOCK_X/Y (data segment variables)
; to avoid SP-relative addressing, which is illegal in 8086 MASM.
;
; Register assignments:
;   SI  = outer loop: byte offset into ENEMY_DATA (0, 5, 10 ... 85)
;   BX  = inner loop: sprite row counter / block row counter
;   CX  = inner loop: sprite col counter / block col counter
;          (pushed around INT 10h calls because INT 10h uses CX as X)
; ============================================================
DRAW_ENEMIES PROC NEAR
    PUSH BP                        ; Preserve BP for caller (we do not use it here)

    MOV SI, 0                      ; SI = byte offset into ENEMY_DATA, start at entry 0

DE_LOOP:
    CMP SI, 005Ah                  ; 0x5A = 90 = 18 enemies * 5 bytes: have we visited all?
    JL  DE_ALIVE_CHECK             ; No: check this entry
    JMP DE_DONE                    ; Yes: all enemies processed

DE_ALIVE_CHECK:
    MOV AL, BYTE PTR ENEMY_DATA[SI]    ; AL = STATE of current enemy (1=alive, 0=dead)
    CMP AL, 01h                        ; Is this enemy alive?
    JE  DE_DRAW_THIS                   ; Yes: draw it
    JMP DE_SKIP_ENEMY                  ; No: skip to next entry

DE_DRAW_THIS:
    ; Save enemy's base position into data-segment temp variables
    ; (cannot hold them in registers across the nested loops below)
    MOV AX, WORD PTR ENEMY_DATA[SI+1]  ; AX = this enemy's X position
    MOV DE_ENEMY_X, AX                 ; Store in temp variable for use in inner loops
    MOV AX, WORD PTR ENEMY_DATA[SI+3]  ; AX = this enemy's Y position
    MOV DE_ENEMY_Y, AX                 ; Store in temp variable

    PUSH SI                            ; Save outer loop index (SI reused for sprite indexing)

    MOV BX, 0                          ; BX = sprite row (0..ENEMY_SPRITE_H-1)

DE_ROW:
    CMP BX, ENEMY_SPRITE_H             ; Processed all sprite rows?
    JGE DE_END_ENEMY                   ; Yes: done with this enemy

    MOV CX, 0                          ; CX = sprite column (0..ENEMY_SPRITE_W-1)

DE_COL:
    CMP CX, ENEMY_SPRITE_W             ; Processed all columns in this sprite row?
    JGE DE_NEXT_ROW                    ; Yes: next row

    ; Compute sprite byte index = row * ENEMY_SPRITE_W + col
    ; MUL uses AX, so we must save/restore BX (row) and CX (col)
    PUSH BX                            ; Save sprite row
    PUSH CX                            ; Save sprite column
    MOV  AX, BX                        ; AX = current row
    MUL  ENEMY_SPRITE_W                ; AX = row * 5 (sprite width)
    POP  CX                            ; Restore column (needed for ADD below)
    ADD  AX, CX                        ; AX = row*5 + col = linear sprite index
    MOV  SI, AX                        ; SI = sprite byte index
    MOV  AL, ENEMY_SPRITE[SI]          ; AL = sprite pixel (0=transparent, 1=draw)
    POP  BX                            ; Restore row counter

    CMP AL, 00h                        ; Transparent pixel?
    JE  DE_SKIP_PIX                    ; Yes: skip, do not draw

    ; Compute on-screen block position for this sprite pixel:
    ; BLOCK_X = DE_ENEMY_X + col * ENEMY_SCALE
    MOV AX, CX                         ; AX = column index
    MUL ENEMY_SCALE                    ; AX = col * ENEMY_SCALE (3 pixels per sprite pixel)
    ADD AX, DE_ENEMY_X                 ; AX = enemy base X + column offset
    MOV DE_BLOCK_X, AX                 ; Store result in temp variable

    ; BLOCK_Y = DE_ENEMY_Y + row * ENEMY_SCALE
    MOV AX, BX                         ; AX = row index
    MUL ENEMY_SCALE                    ; AX = row * ENEMY_SCALE
    ADD AX, DE_ENEMY_Y                 ; AX = enemy base Y + row offset
    MOV DE_BLOCK_Y, AX                 ; Store result in temp variable

    ; Draw the ENEMY_SCALE x ENEMY_SCALE filled block for this sprite pixel
    PUSH BX                            ; Save sprite row (BX reused as block row counter)
    PUSH CX                            ; Save sprite col (CX reused as block col / X coord)

    MOV BX, 0                          ; BX = block row counter (0..ENEMY_SCALE-1)

DE_BROW:
    CMP BX, ENEMY_SCALE                ; Drawn all block rows?
    JGE DE_BEND                        ; Yes: done with this block

    MOV CX, 0                          ; CX = block col counter (0..ENEMY_SCALE-1)

DE_BCOL:
    CMP CX, ENEMY_SCALE                ; Drawn all block columns?
    JGE DE_BNROW                       ; Yes: next block row

    ; Screen Y = DE_BLOCK_Y + block_row
    MOV AX, DE_BLOCK_Y                 ; AX = block Y base
    ADD AX, BX                         ; AX = Y + block_row = final screen Y
    MOV DX, AX                         ; DX = Y for INT 10h

    ; Screen X = DE_BLOCK_X + block_col
    MOV AX, DE_BLOCK_X                 ; AX = block X base
    ADD AX, CX                         ; AX = X + block_col = final screen X
    PUSH CX                            ; Save block col counter (INT 10h will use CX as X)
    MOV CX, AX                         ; CX = X for INT 10h

    MOV AH, 0Ch                        ; INT 10h function 0Ch = Write Graphics Pixel
    MOV AL, COLOR_MAGENTA              ; AL = color index 2 (magenta in CGA palette 1)
    MOV BH, 00h                        ; BH = video page 0
    INT 10h                            ; Plot pixel at (CX, DX)

    POP CX                             ; Restore block col counter
    INC CX                             ; Advance block column
    JMP DE_BCOL                        ; Continue block column loop

DE_BNROW:
    INC BX                             ; Advance block row
    JMP DE_BROW                        ; Continue block row loop

DE_BEND:
    POP CX                             ; Restore sprite column counter
    POP BX                             ; Restore sprite row counter

DE_SKIP_PIX:
    INC CX                             ; Advance sprite column
    JMP DE_COL                         ; Continue sprite column loop

DE_NEXT_ROW:
    INC BX                             ; Advance sprite row
    JMP DE_ROW                         ; Continue sprite row loop

DE_END_ENEMY:
    POP SI                             ; Restore outer loop index (ENEMY_DATA offset)

DE_SKIP_ENEMY:
    ADD SI, 0005h                      ; Advance to next enemy entry (5 bytes per entry)
    JMP DE_LOOP                        ; Continue outer enemy loop

DE_DONE:
    POP BP                             ; Restore caller's BP
    RET
DRAW_ENEMIES ENDP

; ============================================================
; MOVE_ENEMIES
; Controls enemy horizontal movement using a tick counter.
; Every ENEMY_MOVE_FREQ ticks:
;   1. Check if any enemy has hit a wall (CHECK_ENEMY_WALL).
;   2. Apply ENEMY_VEL_X to every alive enemy in direction ENEMY_DIR.
; ============================================================
MOVE_ENEMIES PROC NEAR
    INC ENEMY_MOVE_CTR             ; Count one more game tick
    MOV AX, ENEMY_MOVE_CTR        ; AX = current tick count
    CMP AX, ENEMY_MOVE_FREQ       ; Reached movement interval?
    JL  ME_EXIT                   ; No: not time to move yet

    MOV ENEMY_MOVE_CTR, 0000h     ; Yes: reset counter for next interval

    CALL CHECK_ENEMY_WALL         ; Check if any enemy hit a wall; reverse and drop if so

    MOV SI, 0                     ; SI = byte offset into ENEMY_DATA

ME_LOOP:
    CMP SI, 005Ah                 ; Processed all 18 enemies (90 bytes)?
    JGE ME_EXIT                   ; Yes: done

    MOV AL, BYTE PTR ENEMY_DATA[SI]   ; AL = STATE of current enemy
    CMP AL, 01h                   ; Is this enemy alive?
    JNE ME_SKIP                   ; No: skip it

    MOV AL, ENEMY_DIR             ; AL = current direction (01h=right, FFh=left)
    CMP AL, 01h                   ; Moving right?
    JE  ME_MOVE_RIGHT             ; Yes: add velocity

    ; Moving left: subtract velocity from X
    MOV AX, ENEMY_VEL_X           ; AX = horizontal speed in pixels
    SUB WORD PTR ENEMY_DATA[SI+1], AX  ; enemy_X -= velocity (moves left)
    JMP ME_SKIP

ME_MOVE_RIGHT:
    MOV AX, ENEMY_VEL_X           ; AX = horizontal speed in pixels
    ADD WORD PTR ENEMY_DATA[SI+1], AX  ; enemy_X += velocity (moves right)

ME_SKIP:
    ADD SI, 0005h                 ; Advance to next enemy entry
    JMP ME_LOOP                   ; Continue loop

ME_EXIT:
    RET
MOVE_ENEMIES ENDP

; ============================================================
; CHECK_ENEMY_WALL
; Scans all alive enemies for a wall collision.
; If any enemy's right edge >= WINDOW_WIDTH  -> reverse to left.
; If any enemy's left  edge <= WINDOW_BOUNDS -> reverse to right.
; After reversing, all alive enemies drop down by ENEMY_DROP_AMT.
; ============================================================
CHECK_ENEMY_WALL PROC NEAR
    MOV SI, 0                     ; SI = byte offset into ENEMY_DATA
    MOV BX, 0                     ; BX = 0 here (unused; just a clear)

CEW_LOOP:
    CMP SI, 005Ah                 ; Checked all 18 enemies?
    JGE CEW_DONE                  ; Yes: no wall hit found this pass

    MOV AL, BYTE PTR ENEMY_DATA[SI]   ; AL = STATE
    CMP AL, 01h                   ; Is this enemy alive?
    JNE CEW_SKIP                  ; No: skip

    ; Compute right edge = enemy_X + (ENEMY_SPRITE_W * ENEMY_SCALE)
    PUSH SI                       ; Save SI (MUL will clobber DX:AX, not SI, but we push for clarity)
    MOV  AX, ENEMY_SPRITE_W       ; AX = sprite width in pixels (5)
    MUL  ENEMY_SCALE              ; AX = scaled pixel width (5 * 3 = 15)
    MOV  DX, AX                   ; DX = scaled sprite width
    MOV  AX, WORD PTR ENEMY_DATA[SI+1]  ; AX = enemy X (left edge)
    ADD  AX, DX                   ; AX = right edge of this enemy
    POP  SI                       ; Restore SI

    CMP AX, WINDOW_WIDTH          ; Is right edge at or past the right wall?
    JGE CEW_HIT_RIGHT             ; Yes: reverse direction and drop

    ; Check left edge
    MOV AX, WORD PTR ENEMY_DATA[SI+1]  ; AX = enemy X (left edge)
    CMP AX, WINDOW_BOUNDS         ; Is left edge at or past the left wall?
    JLE CEW_HIT_LEFT              ; Yes: reverse direction and drop

CEW_SKIP:
    ADD SI, 0005h                 ; Next enemy entry
    JMP CEW_LOOP                  ; Continue scan

CEW_HIT_RIGHT:
    MOV ENEMY_DIR, 0FFh           ; Set direction to left (FFh used as -1 for comparison)
    JMP CEW_DROP                  ; Drop all enemies

CEW_HIT_LEFT:
    MOV ENEMY_DIR, 01h            ; Set direction to right

CEW_DROP:
    ; Drop all alive enemies downward by ENEMY_DROP_AMT pixels
    MOV SI, 0                     ; Reset SI to start of ENEMY_DATA

CEW_DROP_LOOP:
    CMP SI, 005Ah                 ; Dropped all enemies?
    JGE CEW_DONE                  ; Yes: done

    MOV AL, BYTE PTR ENEMY_DATA[SI]   ; AL = STATE
    CMP AL, 01h                   ; Is this enemy alive?
    JNE CEW_DROP_SKIP             ; No: skip

    MOV AX, ENEMY_DROP_AMT        ; AX = pixels to drop downward
    ADD WORD PTR ENEMY_DATA[SI+3], AX  ; enemy_Y += drop amount (moves down on screen)

CEW_DROP_SKIP:
    ADD SI, 0005h                 ; Next entry
    JMP CEW_DROP_LOOP             ; Continue drop loop

CEW_DONE:
    RET
CHECK_ENEMY_WALL ENDP

; ============================================================
; CHECK_ENEMIES_REACHED_BOTTOM
; If any alive enemy's Y position reaches or passes PLAYER_Y,
; the enemies have invaded the player's row: game over (loss).
; ============================================================
CHECK_ENEMIES_REACHED_BOTTOM PROC NEAR
    MOV SI, 0                     ; SI = byte offset into ENEMY_DATA

CERB_LOOP:
    CMP SI, 005Ah                 ; Checked all enemies?
    JGE CERB_EXIT                 ; Yes: none reached the bottom

    MOV AL, BYTE PTR ENEMY_DATA[SI]   ; AL = STATE
    CMP AL, 01h                   ; Is this enemy alive?
    JNE CERB_SKIP                 ; No: skip

    MOV AX, WORD PTR ENEMY_DATA[SI+3]  ; AX = this enemy's Y position
    CMP AX, PLAYER_Y              ; Has this enemy reached the player's row?
    JGE CERB_GAMEOVER             ; Yes: trigger game over

CERB_SKIP:
    ADD SI, 0005h                 ; Next entry
    JMP CERB_LOOP                 ; Continue loop

CERB_GAMEOVER:
    MOV GAME_ACTIVE, 00h          ; Stop the game loop
    MOV GAME_WIN, 00h             ; Mark as a loss (not a win)

CERB_EXIT:
    RET
CHECK_ENEMIES_REACHED_BOTTOM ENDP

; ============================================================
; CHECK_BULLET_BUNKER_COLLISION
; Tests whether the player bullet overlaps either bunker's
; bounding box. If it does, computes which pixel was hit,
; destroys it in the BUNKER_STATE array, and deactivates bullet.
; Collision box per bunker:
;   Left   = BUNKER_X
;   Right  = BUNKER_X + BUNKER_SPRITE_WIDTH  * BUNKER_SCALE
;   Top    = BUNKER_Y
;   Bottom = BUNKER_Y + BUNKER_SPRITE_HEIGHT * BUNKER_SCALE
; ============================================================
CHECK_BULLET_BUNKER_COLLISION PROC NEAR
    CMP BULLET_ACTIVE, 01h        ; Is the player bullet in flight?
    JE  CBBC_START                ; Yes: proceed to collision test
    JMP CBBC_EXIT                 ; No: skip all checks
CBBC_START:

    ; ---- Test against Bunker 1 ----
    MOV AX, BULLET_X
    CMP AX, BUNKER1_X             ; Is bullet left of bunker 1's left edge?
    JL  CBBC_B2                   ; Yes: no collision with bunker 1

    MOV AX, BUNKER_SPRITE_WIDTH   ; AX = sprite width (7)
    MUL BUNKER_SCALE              ; AX = pixel width on screen (7*3=21)
    ADD AX, BUNKER1_X             ; AX = right edge of bunker 1
    CMP BULLET_X, AX              ; Is bullet right of bunker 1's right edge?
    JG  CBBC_B2                   ; Yes: no collision with bunker 1

    MOV AX, BULLET_Y
    CMP AX, BUNKER_Y              ; Is bullet above bunker 1's top edge?
    JL  CBBC_B2                   ; Yes: no collision

    MOV AX, BUNKER_SPRITE_HEIGHT  ; AX = sprite height (4)
    MUL BUNKER_SCALE              ; AX = pixel height on screen (4*3=12)
    ADD AX, BUNKER_Y              ; AX = bottom edge of bunker 1
    CMP BULLET_Y, AX              ; Is bullet below bunker 1's bottom edge?
    JG  CBBC_B2                   ; Yes: no collision

    ; Bullet is inside bunker 1's bounding box.
    ; Find which sprite pixel was hit:
    ; pixel_col = (BULLET_X - BUNKER1_X) / BUNKER_SCALE
    MOV AX, BULLET_X
    SUB AX, BUNKER1_X             ; AX = horizontal offset inside bunker 1
    XOR DX, DX                    ; Clear DX for 16-bit divide (DIV uses DX:AX)
    MOV BL, BUNKER_SCALE_BYTE     ; BL = 3 (scale factor, in BYTE form for DIV BL)
    DIV BL                        ; AL = pixel_col (quotient), AH = sub-pixel remainder
    XOR AH, AH                    ; Clear remainder so AX = pixel_col only
    MOV CX, AX                    ; CX = pixel_col

    ; pixel_row = (BULLET_Y - BUNKER_Y) / BUNKER_SCALE
    MOV AX, BULLET_Y
    SUB AX, BUNKER_Y              ; AX = vertical offset inside bunker
    XOR DX, DX                    ; Clear DX
    DIV BL                        ; AL = pixel_row
    XOR AH, AH                    ; AX = pixel_row

    ; Flat index = pixel_row * BUNKER_SPRITE_WIDTH + pixel_col
    MOV BX, BUNKER_SPRITE_WIDTH   ; BX = 7 (columns per row)
    MUL BX                        ; AX = pixel_row * 7
    ADD AX, CX                    ; AX = pixel_row * 7 + pixel_col = flat index
    MOV SI, AX                    ; SI = index into BUNKER1_STATE

    MOV BX, OFFSET BUNKER1_STATE  ; BX = base address of BUNKER1_STATE array
    ADD BX, SI                    ; BX = address of the hit pixel's state byte
    CMP BYTE PTR [BX], 00h        ; El pixel ya estaba destruido?
    JE  CBBC_EXIT                 ; Si: la bala pasa por el hueco, no desaparece
    MOV BYTE PTR [BX], 00h        ; No: destruir ese pixel (estado = 0)
    MOV BULLET_ACTIVE, 00h        ; Desactivar la bala del jugador
    JMP CBBC_EXIT                 ; Saltar comprobacion del bunker 2

CBBC_B2:
    ; ---- Test against Bunker 2 (same logic, different X origin) ----
    MOV AX, BULLET_X
    CMP AX, BUNKER2_X             ; Left of bunker 2?
    JL  CBBC_EXIT                 ; Yes: no collision

    MOV AX, BUNKER_SPRITE_WIDTH
    MUL BUNKER_SCALE              ; AX = pixel width (21)
    ADD AX, BUNKER2_X             ; AX = right edge of bunker 2
    CMP BULLET_X, AX              ; Right of bunker 2?
    JG  CBBC_EXIT

    MOV AX, BULLET_Y
    CMP AX, BUNKER_Y              ; Above bunker 2?
    JL  CBBC_EXIT

    MOV AX, BUNKER_SPRITE_HEIGHT
    MUL BUNKER_SCALE              ; AX = pixel height (12)
    ADD AX, BUNKER_Y              ; AX = bottom edge of bunker 2
    CMP BULLET_Y, AX              ; Below bunker 2?
    JG  CBBC_EXIT

    ; Hit bunker 2: compute pixel index using bunker 2's X origin
    MOV AX, BULLET_X
    SUB AX, BUNKER2_X             ; Horizontal offset from bunker 2 left edge
    XOR DX, DX
    MOV BL, BUNKER_SCALE_BYTE     ; BL = 3
    DIV BL                        ; AL = pixel_col
    XOR AH, AH
    MOV CX, AX                    ; CX = pixel_col

    MOV AX, BULLET_Y
    SUB AX, BUNKER_Y              ; Vertical offset from bunker top
    XOR DX, DX
    DIV BL                        ; AL = pixel_row
    XOR AH, AH                    ; AX = pixel_row

    MOV BX, BUNKER_SPRITE_WIDTH
    MUL BX                        ; AX = pixel_row * 7
    ADD AX, CX                    ; AX = flat index
    MOV SI, AX

    MOV BX, OFFSET BUNKER2_STATE  ; BX = base address of BUNKER2_STATE
    ADD BX, SI                    ; BX = address of hit pixel
    CMP BYTE PTR [BX], 00h        ; El pixel ya estaba destruido?
    JE  CBBC_EXIT                 ; Si: la bala pasa por el hueco, no desaparece
    MOV BYTE PTR [BX], 00h        ; No: destruir pixel
    MOV BULLET_ACTIVE, 00h        ; Desactivar bala

CBBC_EXIT:
    RET
CHECK_BULLET_BUNKER_COLLISION ENDP

; ============================================================
; CHECK_EBULLET_BUNKER_COLLISION
; Same logic as CHECK_BULLET_BUNKER_COLLISION but for the
; enemy bullet (EBULLET_X/Y) against both bunkers.
; ============================================================
CHECK_EBULLET_BUNKER_COLLISION PROC NEAR
    CMP EBULLET_ACTIVE, 01h       ; Enemy bullet in flight?
    JE  CEBC_START                ; Yes: check collisions
    JMP CEBC_EXIT                 ; No: skip
CEBC_START:

    ; ---- Bunker 1 ----
    MOV AX, EBULLET_X
    CMP AX, BUNKER1_X             ; Left of bunker 1?
    JL  CEBC_B2                   ; Yes: no hit

    MOV AX, BUNKER_SPRITE_WIDTH
    MUL BUNKER_SCALE
    ADD AX, BUNKER1_X             ; AX = right edge bunker 1
    CMP EBULLET_X, AX             ; Right of bunker 1?
    JG  CEBC_B2

    MOV AX, EBULLET_Y
    CMP AX, BUNKER_Y              ; Above bunker?
    JL  CEBC_B2

    MOV AX, BUNKER_SPRITE_HEIGHT
    MUL BUNKER_SCALE
    ADD AX, BUNKER_Y              ; AX = bottom edge bunker 1
    CMP EBULLET_Y, AX             ; Below bunker?
    JG  CEBC_B2

    ; Hit: compute pixel_col and pixel_row for bunker 1
    MOV AX, EBULLET_X
    SUB AX, BUNKER1_X             ; Horizontal offset
    XOR DX, DX
    MOV BL, BUNKER_SCALE_BYTE
    DIV BL                        ; AL = pixel_col
    XOR AH, AH
    MOV CX, AX

    MOV AX, EBULLET_Y
    SUB AX, BUNKER_Y              ; Vertical offset
    XOR DX, DX
    DIV BL                        ; AL = pixel_row
    XOR AH, AH

    MOV BX, BUNKER_SPRITE_WIDTH
    MUL BX                        ; AX = pixel_row * 7
    ADD AX, CX                    ; AX = flat index
    MOV SI, AX

    MOV BX, OFFSET BUNKER1_STATE
    ADD BX, SI
    CMP BYTE PTR [BX], 00h        ; El pixel ya estaba destruido?
    JE  CEBC_EXIT                 ; Si: la bala pasa por el hueco, no desaparece
    MOV BYTE PTR [BX], 00h        ; No: destruir pixel del bunker 1
    MOV EBULLET_ACTIVE, 00h       ; Desactivar bala enemiga
    JMP CEBC_EXIT

CEBC_B2:
    ; ---- Bunker 2 ----
    MOV AX, EBULLET_X
    CMP AX, BUNKER2_X             ; Left of bunker 2?
    JL  CEBC_EXIT

    MOV AX, BUNKER_SPRITE_WIDTH
    MUL BUNKER_SCALE
    ADD AX, BUNKER2_X             ; AX = right edge bunker 2
    CMP EBULLET_X, AX             ; Right of bunker 2?
    JG  CEBC_EXIT

    MOV AX, EBULLET_Y
    CMP AX, BUNKER_Y              ; Above bunker?
    JL  CEBC_EXIT

    MOV AX, BUNKER_SPRITE_HEIGHT
    MUL BUNKER_SCALE
    ADD AX, BUNKER_Y              ; AX = bottom edge bunker 2
    CMP EBULLET_Y, AX             ; Below bunker?
    JG  CEBC_EXIT

    ; Hit: compute pixel index for bunker 2
    MOV AX, EBULLET_X
    SUB AX, BUNKER2_X
    XOR DX, DX
    MOV BL, BUNKER_SCALE_BYTE
    DIV BL
    XOR AH, AH
    MOV CX, AX

    MOV AX, EBULLET_Y
    SUB AX, BUNKER_Y
    XOR DX, DX
    DIV BL
    XOR AH, AH

    MOV BX, BUNKER_SPRITE_WIDTH
    MUL BX
    ADD AX, CX
    MOV SI, AX

    MOV BX, OFFSET BUNKER2_STATE
    ADD BX, SI
    CMP BYTE PTR [BX], 00h        ; El pixel ya estaba destruido?
    JE  CEBC_EXIT                 ; Si: la bala pasa por el hueco, no desaparece
    MOV BYTE PTR [BX], 00h        ; No: destruir pixel del bunker 2
    MOV EBULLET_ACTIVE, 00h       ; Desactivar bala enemiga

CEBC_EXIT:
    RET
CHECK_EBULLET_BUNKER_COLLISION ENDP

; ============================================================
; CHECK_EBULLET_PLAYER_COLLISION
; Tests the enemy bullet against the player's bounding box.
; Player box:
;   Left   = PLAYER_X
;   Right  = PLAYER_X + SPRITE_WIDTH  * SPRITE_SCALE
;   Top    = PLAYER_Y
;   Bottom = PLAYER_Y + SPRITE_HEIGHT * SPRITE_SCALE
; If hit: GAME_ACTIVE = 0, GAME_WIN = 0 (loss).
; ============================================================
CHECK_EBULLET_PLAYER_COLLISION PROC NEAR
    CMP EBULLET_ACTIVE, 01h       ; Hay bala enemiga en vuelo?
    JNE CEPC_EXIT                 ; No: saltar toda la comprobacion

    MOV AX, EBULLET_X
    CMP AX, PLAYER_X              ; Bala a la izquierda del borde izquierdo del jugador?
    JL  CEPC_EXIT                 ; Si: no hay colision

    MOV AX, SPRITE_WIDTH
    MUL SPRITE_SCALE              ; AX = ancho real del jugador en pixels (SPRITE_WIDTH * SPRITE_SCALE)
    ADD AX, PLAYER_X              ; AX = borde derecho del jugador
    CMP EBULLET_X, AX             ; Bala a la derecha del borde derecho del jugador?
    JG  CEPC_EXIT                 ; Si: no hay colision

    MOV AX, EBULLET_Y
    CMP AX, PLAYER_Y              ; Bala por encima del borde superior del jugador?
    JL  CEPC_EXIT                 ; Si: no hay colision

    MOV AX, SPRITE_HEIGHT
    MUL SPRITE_SCALE              ; AX = alto real del jugador en pixels
    ADD AX, PLAYER_Y              ; AX = borde inferior del jugador
    CMP EBULLET_Y, AX             ; Bala por debajo del borde inferior?
    JG  CEPC_EXIT                 ; Si: no hay colision

    ; Impacto: la bala enemiga golpeo al jugador
    MOV GAME_ACTIVE, 00h          ; Detiene el bucle principal
    MOV GAME_WIN, 00h             ; Marca como derrota
    MOV EBULLET_ACTIVE, 00h       ; Desactiva la bala enemiga

CEPC_EXIT:
    RET
CHECK_EBULLET_PLAYER_COLLISION ENDP

; ============================================================
; CHECK_BULLET_ENEMY_COLLISION
; Comprueba la bala del jugador contra la caja de colision de
; cada enemigo vivo. Caja de cada enemigo:
;   Izquierda = enemy_X
;   Derecha   = enemy_X + ENEMY_SPRITE_W * ENEMY_SCALE
;   Arriba    = enemy_Y
;   Abajo     = enemy_Y + ENEMY_SPRITE_H * ENEMY_SCALE
; Al impactar: elimina al enemigo, reproduce sonido, suma 10 pts.
; Si ENEMY_COUNT llega a 0: el jugador gana.
; ============================================================
CHECK_BULLET_ENEMY_COLLISION PROC NEAR
    CMP BULLET_ACTIVE, 01h        ; Hay bala del jugador en vuelo?
    JNE CBEC_EXIT                 ; No: saltar todas las comprobaciones

    MOV SI, 0                     ; SI = offset en ENEMY_DATA (0,5,10...85)

CBEC_LOOP:
    CMP SI, 005Ah                 ; Se revisaron los 18 enemigos (90 bytes)?
    JGE CBEC_EXIT                 ; Si: terminar

    MOV AL, BYTE PTR ENEMY_DATA[SI]   ; AL = estado del enemigo actual
    CMP AL, 01h                   ; Esta vivo?
    JNE CBEC_SKIP                 ; No: saltar al siguiente

    MOV DI, WORD PTR ENEMY_DATA[SI+1]  ; DI = posicion X del enemigo
    MOV BX, WORD PTR ENEMY_DATA[SI+3]  ; BX = posicion Y del enemigo

    ; Comprobacion borde izquierdo: bala debe estar a la derecha de enemy_X
    CMP BULLET_X, DI
    JL  CBEC_SKIP                 ; Bala a la izquierda del enemigo: no hay impacto

    ; Comprobacion borde derecho: bala <= enemy_X + ancho_real
    PUSH BX                       ; Salvar Y del enemigo (MUL puede alterar DX:AX)
    PUSH SI                       ; Salvar indice del enemigo
    MOV  AX, ENEMY_SPRITE_W
    MUL  ENEMY_SCALE              ; AX = ancho real del enemigo en pixels
    ADD  AX, DI                   ; AX = borde derecho del enemigo
    CMP  BULLET_X, AX             ; Bala a la derecha del borde derecho?
    POP  SI
    POP  BX
    JG  CBEC_SKIP                 ; Si: no hay impacto

    ; Comprobacion borde superior: bala debe estar por debajo de enemy_Y
    CMP BULLET_Y, BX
    JL  CBEC_SKIP                 ; Bala por encima del enemigo: no hay impacto

    ; Comprobacion borde inferior: bala <= enemy_Y + alto_real
    PUSH BX
    PUSH SI
    MOV  AX, ENEMY_SPRITE_H
    MUL  ENEMY_SCALE              ; AX = alto real del enemigo en pixels
    ADD  AX, BX                   ; AX = borde inferior del enemigo
    CMP  BULLET_Y, AX             ; Bala por debajo del borde inferior?
    POP  SI
    POP  BX
    JG  CBEC_SKIP                 ; Si: no hay impacto

    ; ---- IMPACTO ----
    MOV BYTE PTR ENEMY_DATA[SI], 00h   ; Eliminar enemigo: poner estado en 0 (muerto)
    MOV BULLET_ACTIVE, 00h             ; Desactivar la bala del jugador

    ; Reproducir sonido de impacto inmediatamente
    MOV BX, SOUND_HIT_FREQ        ; BX = divisor PIT para frecuencia de impacto
    CALL PLAY_SOUND               ; Encender altavoz con esa frecuencia
    CALL STOP_SOUND               ; Apagar altavoz (pitido corto)

    ADD SCORE, 000Ah              ; Sumar 10 puntos al puntaje (0x0A = 10)

    DEC ENEMY_COUNT               ; Un enemigo menos vivo
    JNZ CBEC_EXIT                 ; Quedan enemigos: salir (bala ya no existe)

    ; Todos los enemigos eliminados: el jugador gana
    MOV GAME_ACTIVE, 00h          ; Detener bucle principal
    MOV GAME_WIN, 01h             ; Marcar como victoria
    JMP CBEC_EXIT

CBEC_SKIP:
    ADD SI, 0005h                 ; Avanzar al siguiente enemigo (5 bytes por entrada)
    JMP CBEC_LOOP                 ; Continuar el bucle

CBEC_EXIT:
    RET
CHECK_BULLET_ENEMY_COLLISION ENDP

; ============================================================
; DRAW_BUNKERS
; Dibuja los dos bunkers pixel a pixel, omitiendo cualquier
; pixel cuyo byte de estado en BUNKER1_STATE / BUNKER2_STATE
; sea 0 (destruido). Cada pixel vivo se dibuja como un bloque
; BUNKER_SCALE x BUNKER_SCALE en COLOR_CYAN.
; ============================================================
DRAW_BUNKERS PROC NEAR
    PUSH BP                        ; Preservar BP (se usa como BLOCK_Y dentro del proc)

    ; ---- Bunker 1 ----
    MOV SI, 0                      ; SI = indice plano en BUNKER1_STATE (0..27)
    MOV BX, 0                      ; BX = fila del sprite (0..BUNKER_SPRITE_HEIGHT-1)

B1_ROW:
    CMP BX, BUNKER_SPRITE_HEIGHT   ; Se procesaron todas las filas del bunker 1?
    JGE DRAW_B2                    ; Si: pasar al bunker 2

    MOV CX, 0                      ; CX = columna del sprite (0..BUNKER_SPRITE_WIDTH-1)

B1_COL:
    CMP CX, BUNKER_SPRITE_WIDTH    ; Se procesaron todas las columnas de esta fila?
    JGE B1_NEXT_ROW                ; Si: siguiente fila

    ; Leer el estado de este pixel
    PUSH BX                        ; Salvar fila (BX se reusara como registro de direccion)
    MOV  BX, OFFSET BUNKER1_STATE  ; BX = direccion base del array de estado
    ADD  BX, SI                    ; BX = direccion del byte de estado de este pixel
    MOV  AL, [BX]                  ; AL = estado (1 = vivo, 0 = destruido)
    POP  BX                        ; Restaurar contador de fila

    CMP AL, 00h                    ; Pixel destruido?
    JE  B1_SKIP                    ; Si: no dibujarlo

    ; Pixel vivo: calcular posicion del bloque en pantalla y dibujarlo
    PUSH BX                        ; Salvar fila del sprite
    PUSH CX                        ; Salvar columna del sprite
    PUSH SI                        ; Salvar indice del array de estado

    ; BLOCK_X = BUNKER1_X + (columna * BUNKER_SCALE)
    MOV AX, CX                     ; AX = indice de columna
    MUL BUNKER_SCALE               ; AX = columna * 3 = desplazamiento X en pixels
    ADD AX, BUNKER1_X              ; AX = X absoluto del bloque en pantalla
    MOV DI, AX                     ; DI = BLOCK_X

    ; BLOCK_Y = BUNKER_Y + (fila * BUNKER_SCALE)
    MOV AX, BX                     ; AX = indice de fila
    MUL BUNKER_SCALE               ; AX = fila * 3 = desplazamiento Y en pixels
    ADD AX, BUNKER_Y               ; AX = Y absoluto del bloque en pantalla
    MOV BP, AX                     ; BP = BLOCK_Y

    MOV BX, 0                      ; BX = contador de fila del bloque (0..BUNKER_SCALE-1)

B1_BROW:
    CMP BX, BUNKER_SCALE           ; Se dibujaron todas las filas del bloque?
    JGE B1_BEND                    ; Si: terminar el bloque

    MOV SI, 0                      ; SI = contador de columna del bloque (0..BUNKER_SCALE-1)

B1_BCOL:
    CMP SI, BUNKER_SCALE           ; Se dibujaron todas las columnas de esta fila del bloque?
    JGE B1_BNROW                   ; Si: siguiente fila del bloque

    MOV AX, BP
    ADD AX, BX                     ; AX = BLOCK_Y + fila_bloque = Y final en pantalla
    MOV DX, AX                     ; DX = Y para INT 10h
    MOV AX, DI
    ADD AX, SI                     ; AX = BLOCK_X + columna_bloque = X final en pantalla
    MOV CX, AX                     ; CX = X para INT 10h

    MOV AH, 0Ch                    ; Funcion INT 10h: escribir pixel grafico
    MOV AL, COLOR_CYAN             ; Color = cian (indice 1)
    MOV BH, 00h                    ; Pagina de video 0
    INT 10h                        ; Dibujar pixel en (CX, DX)

    INC SI                         ; Siguiente columna del bloque
    JMP B1_BCOL

B1_BNROW:
    INC BX                         ; Siguiente fila del bloque
    JMP B1_BROW

B1_BEND:
    POP SI                         ; Restaurar indice del array de estado
    POP CX                         ; Restaurar columna del sprite
    POP BX                         ; Restaurar fila del sprite

B1_SKIP:
    INC SI                         ; Avanzar al siguiente pixel del array de estado
    INC CX                         ; Avanzar a la siguiente columna del sprite
    JMP B1_COL

B1_NEXT_ROW:
    INC BX                         ; Siguiente fila del sprite
    JMP B1_ROW

    ; ---- Bunker 2 (logica identica, usa BUNKER2_X y BUNKER2_STATE) ----
DRAW_B2:
    MOV SI, 0                      ; Reiniciar indice de estado para bunker 2
    MOV BX, 0                      ; Reiniciar contador de fila

B2_ROW:
    CMP BX, BUNKER_SPRITE_HEIGHT
    JGE END_BUNKERS

    MOV CX, 0

B2_COL:
    CMP CX, BUNKER_SPRITE_WIDTH
    JGE B2_NEXT_ROW

    PUSH BX
    MOV  BX, OFFSET BUNKER2_STATE  ; Direccion base del array de estado del bunker 2
    ADD  BX, SI
    MOV  AL, [BX]                  ; AL = estado del pixel (1=vivo, 0=destruido)
    POP  BX

    CMP AL, 00h
    JE  B2_SKIP

    PUSH BX
    PUSH CX
    PUSH SI

    ; BLOCK_X = BUNKER2_X + (columna * BUNKER_SCALE)
    MOV AX, CX
    MUL BUNKER_SCALE
    ADD AX, BUNKER2_X              ; AX = X del bloque del bunker 2
    MOV DI, AX

    ; BLOCK_Y = BUNKER_Y + (fila * BUNKER_SCALE)
    MOV AX, BX
    MUL BUNKER_SCALE
    ADD AX, BUNKER_Y
    MOV BP, AX

    MOV BX, 0

B2_BROW:
    CMP BX, BUNKER_SCALE
    JGE B2_BEND

    MOV SI, 0

B2_BCOL:
    CMP SI, BUNKER_SCALE
    JGE B2_BNROW

    MOV AX, BP
    ADD AX, BX
    MOV DX, AX                     ; DX = Y en pantalla
    MOV AX, DI
    ADD AX, SI
    MOV CX, AX                     ; CX = X en pantalla

    MOV AH, 0Ch
    MOV AL, COLOR_CYAN             ; Color cian para el bunker 2
    MOV BH, 00h
    INT 10h                        ; Dibujar pixel

    INC SI
    JMP B2_BCOL

B2_BNROW:
    INC BX
    JMP B2_BROW

B2_BEND:
    POP SI
    POP CX
    POP BX

B2_SKIP:
    INC SI
    INC CX
    JMP B2_COL

B2_NEXT_ROW:
    INC BX
    JMP B2_ROW

END_BUNKERS:
    POP BP                         ; Restaurar BP del llamador
    RET
DRAW_BUNKERS ENDP

; ============================================================
; DRAW_SCORE
; Convierte el valor numerico de SCORE (0-99990) en una cadena
; ASCII de 5 digitos usando division repetida por 10 (tecnica
; del tutorial Pong), luego la muestra en la posicion de cursor
; indicada por el llamador en DH (fila) y DL (columna).
; Entrada: DH = fila de texto, DL = columna de texto
; ============================================================
DRAW_SCORE PROC NEAR
    PUSH DX                        ; Salvar DH:DL del llamador (DIV sobreescribe DX)

    ; Convertir SCORE a digitos ASCII mediante divisiones sucesivas por 10
    MOV AX, SCORE                  ; AX = valor actual del puntaje
    MOV BX, 000Ah                  ; BX = 10 (divisor decimal)

    XOR DX, DX                     ; Limpiar DX antes de dividir (DIV usa DX:AX)
    DIV BX                         ; AX = puntaje/10, DX = puntaje mod 10 (digito de unidades)
    ADD DL, 30h                    ; Convertir digito 0-9 a ASCII '0'-'9' (sumar 0x30)
    MOV SCORE_STR+4, DL            ; Guardar digito de unidades en posicion 4 de SCORE_STR

    XOR DX, DX
    DIV BX                         ; DX = digito de decenas
    ADD DL, 30h
    MOV SCORE_STR+3, DL            ; Guardar digito de decenas en posicion 3

    XOR DX, DX
    DIV BX                         ; DX = digito de centenas
    ADD DL, 30h
    MOV SCORE_STR+2, DL            ; Guardar digito de centenas en posicion 2

    XOR DX, DX
    DIV BX                         ; DX = digito de miles
    ADD DL, 30h
    MOV SCORE_STR+1, DL            ; Guardar digito de miles en posicion 1

    XOR DX, DX
    DIV BX                         ; DX = digito de decenas de miles
    ADD DL, 30h
    MOV SCORE_STR+0, DL            ; Guardar digito de decenas de miles en posicion 0

    ; Restaurar fila/columna y mover el cursor de texto a esa posicion
    POP DX                         ; DH = fila, DL = columna (restaurado antes de la conversion)
    MOV BH, 00h                    ; Pagina de video 0
    MOV AH, 02h                    ; Funcion INT 10h 02h = Posicionar cursor
    INT 10h                        ; Mover cursor a (DH, DL)

    LEA SI, SCORE_STR              ; SI = direccion de la cadena ASCII del puntaje

DS_LOOP:
    MOV AL, [SI]                   ; AL = siguiente caracter de la cadena
    CMP AL, 00h                    ; Es el terminador nulo?
    JE  DS_DONE                    ; Si: terminar la impresion

    MOV AH, 0Eh                    ; Funcion INT 10h 0Eh = Salida de teletipo (imprime y avanza cursor)
    MOV BH, 00h                    ; Pagina 0
    INT 10h                        ; Imprimir caracter en AL

    INC SI                         ; Avanzar al siguiente caracter
    JMP DS_LOOP

DS_DONE:
    RET
DRAW_SCORE ENDP

; ============================================================
; DRAW_STRING
; Dibuja una cadena ASCII terminada en nulo almacenada en DS.
; Entrada: DH = fila, DL = columna (posicion del cursor de texto)
;          SI = offset de la cadena dentro de DS
; ============================================================
DRAW_STRING PROC NEAR
    MOV BH, 00h                    ; Pagina de video 0
    MOV AH, 02h                    ; Funcion INT 10h: Posicionar cursor
    INT 10h                        ; Mover cursor a (DH, DL)

DSTR_LOOP:
    MOV AL, [SI]                   ; AL = siguiente caracter de la cadena
    CMP AL, 00h                    ; Terminador nulo alcanzado?
    JE  DSTR_DONE                  ; Si: terminar

    MOV AH, 0Eh                    ; Funcion INT 10h: Salida de teletipo
    MOV BH, 00h                    ; Pagina 0
    INT 10h                        ; Imprimir caracter y avanzar cursor

    INC SI                         ; Avanzar puntero de cadena
    JMP DSTR_LOOP

DSTR_DONE:
    RET
DRAW_STRING ENDP

; ============================================================
; PLAY_MUSIC_TICK
; Reproductor de musica de fondo no bloqueante.
; Se llama una vez por tick de juego. Cada MUSIC_TICK_FREQ ticks
; avanza MELODY_IDX un paso (2 bytes) y:
;   - Programa el canal 2 del PIT y activa el altavoz (nota audible), o
;   - Desactiva el altavoz (silencio / pausa).
; Al llegar al marcador de fin (0FFFFh), MELODY_IDX vuelve a 0.
; ============================================================
PLAY_MUSIC_TICK PROC NEAR
    INC MUSIC_TICK_CTR             ; Contar un tick mas de juego
    MOV AX, MUSIC_TICK_CTR        ; AX = ticks desde el ultimo cambio de nota
    CMP AX, MUSIC_TICK_FREQ       ; Se llego al intervalo de cambio de nota?
    JL  PMT_EXIT                  ; No: mantener la nota actual y salir

    MOV MUSIC_TICK_CTR, 0000h     ; Si: reiniciar contador de ticks

    ; Leer el divisor PIT de la nota actual del array MELODY
    MOV SI, OFFSET MELODY         ; SI = direccion base del array MELODY
    ADD SI, MELODY_IDX            ; SI = direccion de la nota actual
    MOV BX, WORD PTR [SI]         ; BX = divisor PIT de la nota actual

    CMP BX, 0FFFFh                ; Es el marcador de fin de melodia?
    JNE PMT_PLAY                  ; No: reproducir/silenciar esta nota
    MOV MELODY_IDX, 0000h         ; Si: volver al inicio de la melodia
    MOV SI, OFFSET MELODY         ; Recargar SI apuntando a la primera nota
    MOV BX, WORD PTR [SI]         ; BX = divisor de la primera nota

PMT_PLAY:
    ADD MELODY_IDX, 0002h         ; Avanzar indice 2 bytes (una WORD = una nota)

    CMP BX, 0000h                 ; Es una pausa (silencio)?
    JE  PMT_SILENCE               ; Si: desactivar altavoz

    ; Programar el canal 2 del PIT con la frecuencia elegida
    MOV AL, 0B6h                  ; Byte de comando PIT: canal 2, modo 3 (onda cuadrada), binario
    OUT 43h, AL                   ; Escribir comando al registro de comando del PIT (puerto 0x43)
    MOV AX, BX                    ; AX = divisor de frecuencia
    OUT 42h, AL                   ; Enviar byte bajo del divisor al canal 2 del PIT (puerto 0x42)
    MOV AL, AH                    ; AL = byte alto del divisor
    OUT 42h, AL                   ; Enviar byte alto al canal 2

    ; Activar altavoz via Puerto B del sistema (puerto 0x61)
    IN  AL, 61h                   ; Leer valor actual del puerto 0x61
    OR  AL, 03h                   ; Poner bit 0 (gate del PIT2) y bit 1 (habilitar salida del altavoz)
    OUT 61h, AL                   ; Escribir de vuelta: altavoz conectado al PIT canal 2
    JMP PMT_EXIT

PMT_SILENCE:
    ; Desactivar altavoz: limpiar bits 0 y 1 del puerto 0x61
    IN  AL, 61h                   ; Leer puerto 0x61
    AND AL, 0FCh                  ; Limpiar bits 0 y 1 (0xFC = 11111100 en binario)
    OUT 61h, AL                   ; Escribir de vuelta: altavoz silenciado

PMT_EXIT:
    RET
PLAY_MUSIC_TICK ENDP

; ============================================================
; PLAY_MELODY
; Reproductor de melodia bloqueante, usado en la pantalla final.
; Reproduce cada nota del array apuntado por SI, deteniendose
; al encontrar el marcador de fin (0FFFFh).
; Cada nota se mantiene un tiempo fijo mediante un bucle de espera.
; Entrada: SI = offset del array de melodia (DW, termina con 0FFFFh)
; ============================================================
PLAY_MELODY PROC NEAR

PM_NEXT_NOTE:
    MOV BX, WORD PTR [SI]         ; BX = divisor PIT de la siguiente nota
    CMP BX, 0FFFFh                ; Marcador de fin?
    JE  PM_DONE                   ; Si: melodia terminada

    ADD SI, 0002h                 ; Avanzar SI a la siguiente nota (2 bytes por entrada)

    CMP BX, 0000h                 ; Es una pausa (silencio)?
    JE  PM_REST                   ; Si: apagar altavoz durante esta nota

    ; Reproducir nota: programar PIT canal 2 y activar altavoz
    MOV AL, 0B6h                  ; Comando PIT: canal 2, lobyte/hibyte, modo 3, binario
    OUT 43h, AL                   ; Escribir comando al PIT
    MOV AX, BX                    ; AX = divisor
    OUT 42h, AL                   ; Enviar byte bajo al canal 2
    MOV AL, AH
    OUT 42h, AL                   ; Enviar byte alto al canal 2
    IN  AL, 61h                   ; Leer puerto de control del altavoz
    OR  AL, 03h                   ; Activar altavoz (bits 0 y 1)
    OUT 61h, AL                   ; Aplicar activacion
    JMP PM_DELAY                  ; Ir a esperar la duracion de la nota

PM_REST:
    IN  AL, 61h                   ; Leer puerto de control del altavoz
    AND AL, 0FCh                  ; Desactivar altavoz (limpiar bits 0 y 1)
    OUT 61h, AL                   ; Aplicar silencio

PM_DELAY:
    MOV CX, 8000h                 ; CX = cantidad de iteraciones de espera (~1/6 segundo en DOSBox)
PM_DELAY_LOOP:
    LOOP PM_DELAY_LOOP             ; Decrementar CX y repetir hasta llegar a cero (espera activa)

    JMP PM_NEXT_NOTE               ; Pasar a la siguiente nota

PM_DONE:
    IN  AL, 61h                   ; Asegurar que el altavoz quede apagado al terminar la melodia
    AND AL, 0FCh
    OUT 61h, AL
    RET
PLAY_MELODY ENDP

; ============================================================
; RESET_GAME
; Restaura todas las variables de estado del juego a sus valores
; iniciales. Se llama cuando el jugador presiona R en la pantalla
; final. Al retornar, la ejecucion salta de vuelta a GAME_LOOP.
; ============================================================
RESET_GAME PROC NEAR

    ; Restaurar banderas de estado del juego
    MOV GAME_ACTIVE, 01h          ; Reactivar el bucle principal (1 = corriendo)
    MOV GAME_WIN,    00h          ; Limpiar bandera de victoria

    ; Reiniciar puntaje a cero
    MOV SCORE, 0000h

    ; Restaurar jugador a su posicion inicial (centro inferior de la pantalla)
    MOV PLAYER_X, 0098h           ; X = 152 pixels (centro horizontal)
    MOV PLAYER_Y, 00B0h           ; Y = 176 pixels (cerca del fondo)

    ; Desactivar bala del jugador y limpiar su posicion
    MOV BULLET_ACTIVE, 00h        ; Sin bala en vuelo
    MOV BULLET_X, 0000h           ; Limpiar X de la bala
    MOV BULLET_Y, 0000h           ; Limpiar Y de la bala

    ; Desactivar bala enemiga y limpiar su posicion
    MOV EBULLET_ACTIVE, 00h       ; Sin bala enemiga en vuelo
    MOV EBULLET_X, 0000h          ; Limpiar X de la bala enemiga
    MOV EBULLET_Y, 0000h          ; Limpiar Y de la bala enemiga

    ; Reiniciar contadores de movimiento y disparo de enemigos
    MOV ENEMY_MOVE_CTR, 0000h     ; Reiniciar contador de ticks de movimiento
    MOV ENEMY_SHOOT_CTR, 0000h    ; Reiniciar contador de ticks de disparo
    MOV ENEMY_DIR, 01h            ; Los enemigos comienzan moviendose a la derecha
    MOV ENEMY_COUNT, 0012h        ; Restaurar conteo total de enemigos (18 = 0x12)

    ; Reiniciar estado de reproduccion de musica
    MOV MELODY_IDX, 0000h         ; Volver al inicio de la melodia
    MOV MUSIC_TICK_CTR, 0000h     ; Reiniciar contador de ticks de nota

    ; Limpiar TIME_AUX para que el primer tick del bucle se procese inmediatamente
    MOV TIME_AUX, 00h

    ; Restaurar ambos bunkers a su estado original sin danos
    ; (patron: 0,1,1,1,1,1,0 / 1,1,1,1,1,1,1 / 1,1,1,1,1,1,1 / 1,1,0,0,0,1,1)
    MOV SI, OFFSET BUNKER1_STATE  ; SI = inicio del array de estado del bunker 1
    CALL RG_RESTORE_BUNKER        ; Escribir patron de 28 bytes en [SI]
    MOV SI, OFFSET BUNKER2_STATE  ; SI = inicio del array de estado del bunker 2
    CALL RG_RESTORE_BUNKER        ; Escribir patron de 28 bytes en [SI]

    ; Reinicializar posiciones y estados de todos los enemigos
    CALL INIT_ENEMIES

    RET

; ---- Subrutina auxiliar: escribe el patron de 28 bytes del bunker en [SI] ----
RG_RESTORE_BUNKER:
    MOV BYTE PTR [SI+0],  00h     ; Fila 0, col 0: esquina transparente
    MOV BYTE PTR [SI+1],  01h     ; Fila 0, col 1
    MOV BYTE PTR [SI+2],  01h     ; Fila 0, col 2
    MOV BYTE PTR [SI+3],  01h     ; Fila 0, col 3
    MOV BYTE PTR [SI+4],  01h     ; Fila 0, col 4
    MOV BYTE PTR [SI+5],  01h     ; Fila 0, col 5
    MOV BYTE PTR [SI+6],  00h     ; Fila 0, col 6: esquina transparente
    MOV BYTE PTR [SI+7],  01h     ; Fila 1, col 0
    MOV BYTE PTR [SI+8],  01h     ; Fila 1, col 1
    MOV BYTE PTR [SI+9],  01h     ; Fila 1, col 2
    MOV BYTE PTR [SI+10], 01h     ; Fila 1, col 3
    MOV BYTE PTR [SI+11], 01h     ; Fila 1, col 4
    MOV BYTE PTR [SI+12], 01h     ; Fila 1, col 5
    MOV BYTE PTR [SI+13], 01h     ; Fila 1, col 6
    MOV BYTE PTR [SI+14], 01h     ; Fila 2, col 0
    MOV BYTE PTR [SI+15], 01h     ; Fila 2, col 1
    MOV BYTE PTR [SI+16], 01h     ; Fila 2, col 2
    MOV BYTE PTR [SI+17], 01h     ; Fila 2, col 3
    MOV BYTE PTR [SI+18], 01h     ; Fila 2, col 4
    MOV BYTE PTR [SI+19], 01h     ; Fila 2, col 5
    MOV BYTE PTR [SI+20], 01h     ; Fila 2, col 6
    MOV BYTE PTR [SI+21], 01h     ; Fila 3, col 0
    MOV BYTE PTR [SI+22], 00h     ; Fila 3, col 1: inicio del hueco central
    MOV BYTE PTR [SI+23], 00h     ; Fila 3, col 2: centro del hueco
    MOV BYTE PTR [SI+24], 00h     ; Fila 3, col 3: fin del hueco central
    MOV BYTE PTR [SI+25], 01h     ; Fila 3, col 4
    MOV BYTE PTR [SI+26], 01h     ; Fila 3, col 5
    MOV BYTE PTR [SI+27], 01h     ; Fila 3, col 6  <- faltaba este byte (28vo pixel)
    RET

RESET_GAME ENDP

; ============================================================
; PLAY_SOUND
; Enciende el altavoz del PC a la frecuencia indicada por BX.
; BX = divisor del PIT (frecuencia audible = 1.193.180 / BX).
; Reproduce durante un breve retardo y luego retorna.
; El llamador debe invocar STOP_SOUND despues si lo desea.
; ============================================================
PLAY_SOUND PROC NEAR
    ; Paso 1: Configurar el canal 2 del PIT para la frecuencia deseada
    ; Byte de comando 0B6h = binario 10110110:
    ;   Bits 7-6 = 10: seleccionar canal 2
    ;   Bits 5-4 = 11: modo de acceso lobyte/hibyte (enviar ambos bytes)
    ;   Bits 3-1 = 011: modo 3 (generador de onda cuadrada)
    ;   Bit  0   = 0:  conteo binario (no BCD)
    MOV AL, 0B6h                  ; Byte de comando del PIT
    OUT 43h, AL                   ; Escribir al registro de comando del PIT (puerto 0x43)

    MOV AX, BX                    ; AX = divisor de frecuencia pasado por el llamador
    OUT 42h, AL                   ; Enviar byte bajo del divisor al canal 2 del PIT (puerto 0x42)
    MOV AL, AH                    ; AL = byte alto
    OUT 42h, AL                   ; Enviar byte alto del divisor

    ; Paso 2: Activar el altavoz via Puerto B del sistema (puerto 0x61)
    IN  AL, 61h                   ; Leer valor actual del puerto 0x61
    OR  AL, 03h                   ; Poner bit 0 (gate PIT2) y bit 1 (habilitar salida del altavoz)
    OUT 61h, AL                   ; Escribir de vuelta: altavoz conectado al PIT canal 2

    ; Paso 3: Espera activa para que el sonido sea audible
    MOV CX, 0FFFFh                ; CX = cantidad de iteraciones (65535)
PS_DELAY:
    LOOP PS_DELAY                 ; Decrementar CX y repetir hasta llegar a cero

    RET
PLAY_SOUND ENDP

; ============================================================
; STOP_SOUND
; Silencia el altavoz limpiando los bits 0 y 1 del puerto 0x61.
; Bit 0: gate del canal 2 del PIT (0 = deshabilitado)
; Bit 1: habilitacion de salida del altavoz (0 = desconectado)
; ============================================================
STOP_SOUND PROC NEAR
    IN  AL, 61h                   ; Leer Puerto B del sistema
    AND AL, 0FCh                  ; Limpiar bits 0 y 1 (0xFC = 1111 1100 en binario)
    OUT 61h, AL                   ; Escribir de vuelta: salida del altavoz deshabilitada
    RET
STOP_SOUND ENDP

; ============================================================
; CLEAR_SCREEN
; Borra la pantalla visible usando la funcion de desplazamiento
; del BIOS con 0 lineas (lo que limpia toda la ventana).
; NO reinicia el modo de video (evita el parpadeo que ocurriria
; si se llamara INT 10h/AH=00h cada frame como se hacia antes).
; ============================================================
CLEAR_SCREEN PROC NEAR
    MOV AH, 06h                   ; Funcion INT 10h 06h = Desplazar ventana hacia arriba
    MOV AL, 00h                   ; AL = 0 lineas a desplazar = limpiar toda la ventana
    MOV BH, 00h                   ; Atributo de relleno: color 0 (fondo negro)
    MOV CX, 0000h                 ; CH:CL = esquina superior izquierda (fila 0, col 0)
    MOV DX, 184Fh                ; DH:DL = esquina inferior derecha en coordenadas de TEXTO
                                 ; DH=18h=24 (fila 24, ultima fila de texto en modo 25 filas)
                                 ; DL=4Fh=79 (columna 79, ultima columna en modo 80 columnas)
    INT 10h                       ; Ejecutar desplazamiento/limpieza
    RET
CLEAR_SCREEN ENDP

CODE ENDS                         ; Fin del segmento de codigo
END MAIN                          ; Fin del archivo fuente; punto de entrada del programa = MAIN