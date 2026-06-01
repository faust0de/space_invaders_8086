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

STACK SEGMENT PARA STACK           ; Declares the stack segment, paragraph-aligned at 16 bytes
    DB 128 DUP (' ')               ; Reserves 128 bytes for the stack, initialized with spaces
STACK ENDS                         ; Ends the stack segment

; ============================================================
; DATA SEGMENT - All game variables and constants
; ============================================================
DATA SEGMENT PARA 'DATA'           ; Declares the data segment, paragraph-aligned

    ; --- Screen dimensions (CGA Mode 4: 320x200) ---
    WINDOW_WIDTH    DW 0140h       ; Screen width in pixels (0x140 = 320 decimal)
    WINDOW_HEIGHT   DW 00C8h       ; Screen height in pixels (0xC8 = 200 decimal)

    ; --- Game state flags ---
    GAME_ACTIVE     DB 01h         ; Controls the main loop: 1 = game running, 0 = game over
    GAME_WIN        DB 00h         ; End condition flag: 1 = player won, 0 = player lost

    ; --- Time control (technique from Pong tutorial) ---
    ; INT 21h/AH=2Ch returns DL = hundredths of second (0-99)
    ; We compare each frame to detect when the value changes (= new tick)
    TIME_AUX        DB 00h         ; Stores the last 1/100 second value used to control game speed

    ; --- Score display ---
    SCORE           DW 0000h       ; Current numeric score, increased by 10 for each destroyed enemy
    SCORE_STR       DB '00000', 00h ; Five-digit ASCII score string with null terminator
    SCORE_X         DW 0008h       ; Text column where the score is drawn
    SCORE_Y         DW 0002h       ; Text row where the score is drawn

    ; --- End screen messages (null-terminated ASCII strings) ---
    MSG_GAMEOVER    DB 'GAME OVER', 00h            ; Message shown when the player loses
    MSG_WIN         DB 'YOU WIN!', 00h             ; Message shown when all enemies are destroyed
    MSG_SCORE       DB 'SCORE:', 00h               ; Label displayed before the final score
    MSG_RESTART     DB 'R=RESTART  Q=QUIT', 00h    ; Instructions shown on the end screen

    ; --- CGA palette 1 color indices (Mode 04h, palette 1: black/cyan/magenta/white) ---
    COLOR_BLACK     EQU 00h        ; Color index 0 = black, used as the background color
    COLOR_CYAN      EQU 01h        ; Color index 1 = cyan, used for the bunkers
    COLOR_MAGENTA   EQU 02h        ; Color index 2 = magenta, used for enemies and enemy bullets
    COLOR_WHITE     EQU 03h        ; Color index 3 = white, used for the player and player bullets

    ; --- Screen edge margin ---
    WINDOW_BOUNDS   DW 0006h       ; Minimum pixel margin from the left and right screen edges

    ; ========================
    ; PLAYER DATA
    ; ========================
    PLAYER_X        DW 0098h       ; Player horizontal position in pixels (152, near screen center)
    PLAYER_Y        DW 00B0h       ; Player vertical position in pixels (176, near the bottom)
    PLAYER_COLOR    DB 03h         ; Player color = white, CGA color index 3
    PLAYER_VELOCITY DW 0004h       ; Number of pixels the player moves per key press

    ; Player sprite definition (5 columns x 3 rows):
    ; 0 = transparent pixel (not drawn), 1 = solid pixel (drawn in PLAYER_COLOR)
    ; Visual layout:
    ;   Row 0:  . . X . .
    ;   Row 1:  . X X X .
    ;   Row 2:  X X X X X
    PLAYER_SPRITE   DB 0,0,1,0,0   ; Row 0: cannon tip or upper part of the tank
                    DB 0,1,1,1,0   ; Row 1: turret body
                    DB 1,1,1,1,1   ; Row 2: full-width tank base
    SPRITE_WIDTH    DW 0005h       ; Number of columns in the player sprite
    SPRITE_HEIGHT   DW 0003h       ; Number of rows in the player sprite
    SPRITE_SCALE    DW 0004h       ; Scale factor: each sprite pixel becomes a 4x4 screen block

    ; ========================
    ; PLAYER BULLET DATA
    ; ========================
    BULLET_X        DW 0000h       ; Current X position of the player bullet
    BULLET_Y        DW 0000h       ; Current Y position of the player bullet
    BULLET_ACTIVE   DB 00h         ; Bullet state: 0 = inactive, 1 = flying
    BULLET_VELOCITY DW 0006h       ; Number of pixels the player bullet moves upward per game tick
    BULLET_COLOR    DB 03h         ; Player bullet color = white, CGA color index 3

    ; Bullet sprite (3 columns x 4 rows):
    ;   . X .
    ;   . X .
    ;   . X .
    ;   X X X
    BULLET_SPRITE   DB 0,1,0       ; Row 0: thin bullet shaft
                    DB 0,1,0       ; Row 1: thin bullet shaft
                    DB 0,1,0       ; Row 2: thin bullet shaft
                    DB 1,1,1       ; Row 3: bullet base
    BULLET_SPRITE_WIDTH  DW 0003h  ; Number of columns in the bullet sprite
    BULLET_SPRITE_HEIGHT DW 0004h  ; Number of rows in the bullet sprite

    ; ========================
    ; ENEMY BULLET DATA
    ; ========================
    EBULLET_X       DW 0000h       ; Current X position of the enemy bullet
    EBULLET_Y       DW 0000h       ; Current Y position of the enemy bullet
    EBULLET_ACTIVE  DB 00h         ; Enemy bullet state: 0 = inactive, 1 = flying
    EBULLET_VELOCITY DW 0003h      ; Number of pixels the enemy bullet moves downward per game tick
    EBULLET_COLOR   DB 02h         ; Enemy bullet color = magenta, CGA color index 2

    ; ========================
    ; BUNKER DATA
    ; ========================
    ; Bunker sprite shape (7 columns x 4 rows):
    ;   . X X X X X .
    ;   X X X X X X X
    ;   X X X X X X X
    ;   X X . . . X X   <- notch at bottom center (entrance for player)
    BUNKER_SPRITE   DB 0,1,1,1,1,1,0   ; Row 0: rounded upper part of the bunker
                    DB 1,1,1,1,1,1,1   ; Row 1: full-width bunker row
                    DB 1,1,1,1,1,1,1   ; Row 2: full-width bunker row
                    DB 1,1,0,0,0,1,1   ; Row 3: lower row with a central opening
    BUNKER_SPRITE_WIDTH  DW 0007h  ; Number of columns in the bunker sprite
    BUNKER_SPRITE_HEIGHT DW 0004h  ; Number of rows in the bunker sprite
    BUNKER_SCALE         DW 0003h  ; Scale factor: each bunker sprite pixel becomes a 3x3 block
    BUNKER_SCALE_BYTE    DB 03h    ; Same scale value stored as a byte for DIV BL operations

    ; Screen positions of the two bunkers
    BUNKER1_X       DW 0050h       ; X position of the left bunker in pixels (80 decimal)
    BUNKER2_X       DW 00D0h       ; X position of the right bunker in pixels (208 decimal)
    BUNKER_Y        DW 0090h       ; Shared Y position for both bunkers in pixels (144 decimal)

    ; Per-pixel destruction state arrays for each bunker
    ; Each byte maps 1:1 to a sprite pixel: 1 = alive (draw), 0 = destroyed (skip)
    ; 7 columns x 4 rows = 28 bytes per bunker
    BUNKER1_STATE   DB 0,1,1,1,1,1,0   ; Bunker 1 row 0 state: 1 = alive, 0 = destroyed/empty
                    DB 1,1,1,1,1,1,1   ; Bunker 1 row 1 state
                    DB 1,1,1,1,1,1,1   ; Bunker 1 row 2 state
                    DB 1,1,0,0,0,1,1   ; Bunker 1 row 3 state, with central opening

    BUNKER2_STATE   DB 0,1,1,1,1,1,0   ; Bunker 2 row 0 state: 1 = alive, 0 = destroyed/empty
                    DB 1,1,1,1,1,1,1   ; Bunker 2 row 1 state
                    DB 1,1,1,1,1,1,1   ; Bunker 2 row 2 state
                    DB 1,1,0,0,0,1,1   ; Bunker 2 row 3 state, with central opening

    ; ========================
    ; ENEMY (INVADER) DATA
    ; ========================
    ENEMY_ROWS      DW 0003h       ; Number of enemy rows in the grid
    ENEMY_COLS      DW 0006h       ; Number of enemy columns in the grid
    ENEMY_COUNT     DW 0012h       ; Number of living enemies: 3 * 6 = 18 decimal = 0x12

    ; ENEMY_DATA layout: 18 entries x 5 bytes each = 90 bytes total
    ; Each entry: [STATE:1 byte][X:2 bytes][Y:2 bytes]
    ;   STATE: 1 = alive, 0 = dead (destroyed by player bullet)
    ;   X, Y: current screen position of this enemy in pixels
    ; Initialized to all zeros here; INIT_ENEMIES fills correct values at startup
    ENEMY_DATA      DB 90 DUP(00h) ; Reserves 90 bytes for 18 enemies, filled later by INIT_ENEMIES

    ; Enemy sprite shape (5 columns x 3 rows):
    ;   . X . X .
    ;   X X X X X
    ;   X . X . X
    ENEMY_SPRITE    DB 0,1,0,1,0   ; Row 0: enemy antennas
                    DB 1,1,1,1,1   ; Row 1: enemy body
                    DB 1,0,1,0,1   ; Row 2: enemy legs
    ENEMY_SPRITE_W  DW 0005h       ; Number of columns in the enemy sprite
    ENEMY_SPRITE_H  DW 0003h       ; Number of rows in the enemy sprite
    ENEMY_SCALE     DW 0003h       ; Scale factor: each enemy sprite pixel becomes a 3x3 block

    ; Enemy horizontal movement
    ENEMY_VEL_X     DW 0004h       ; Number of pixels each enemy moves horizontally per step
    ENEMY_DIR       DB 01h         ; Current enemy direction: 01h = right, FFh = left
    ENEMY_MOVE_CTR  DW 0000h       ; Tick counter since the last enemy movement step
    ENEMY_MOVE_FREQ DW 0006h       ; Enemy movement frequency: move once every 6 game ticks
    ENEMY_DROP_AMT  DW 0008h       ; Number of pixels enemies move downward when direction changes

    ; Enemy shooting
    ENEMY_SHOOT_CTR  DW 0000h      ; Tick counter since the last enemy shot
    ENEMY_SHOOT_FREQ DW 001Eh      ; Enemy shooting frequency: shoot every 30 ticks (0x1E = 30)

    ; Initial grid layout
    ENEMY_START_X   DW 0020h       ; Initial X position of the leftmost enemy column (32 decimal)
    ENEMY_START_Y   DW 0018h       ; Initial Y position of the top enemy row (24 decimal)
    ENEMY_SPACING_X DW 001Eh       ; Horizontal spacing between enemies in pixels (30 decimal)
    ENEMY_SPACING_Y DW 0012h       ; Vertical spacing between enemies in pixels (18 decimal)

    ; ========================
    ; SOUND DATA
    ; ========================
    ; PC speaker sounds use PIT (Programmable Interval Timer) channel 2.
    ; Audible frequency = 1,193,180 Hz / divisor value.
    SOUND_SHOOT_FREQ  DW 0A00h     ; PIT divisor used for the shooting sound effect
    SOUND_HIT_FREQ    DW 0300h     ; PIT divisor used for the enemy hit sound effect
    SOUND_GAMEOVER_F  DW 0100h     ; PIT divisor used for the game-over sound effect

    ; ========================
    ; MUSIC DATA
    ; ========================
    ; Background melody played one note per MUSIC_TICK_FREQ game ticks (non-blocking).
    ; Each value is a PIT divisor: audible frequency = 1,193,180 / divisor.
    ; Special values: 0000h = rest (silence for one step), 0FFFFh = end marker (loop back).
    ;
    ; Note reference:
    ;   These values are approximate arcade tones generated through PIT divisors.
    ; ========================
    MELODY          DW 0B20h, 0B20h, 0000h, 0B20h, 0000h, 08E0h   ; Background melody phrase 1
                    DW 0B20h, 0000h, 0800h, 0B20h, 0720h, 0000h   ; Background melody phrase 2
                    DW 0660h, 0000h, 0660h, 0000h, 0660h, 0000h   ; Background melody phrase 3
                    DW 08E0h, 0000h, 0000h, 0000h, 08E0h, 0000h   ; Background melody phrase 4
                    DW 0800h, 0000h, 08E0h, 0800h, 0000h, 0720h   ; Background melody phrase 5
                    DW 0FFFFh                                       ; End marker: loop back to the start

    MELODY_IDX      DW 0000h       ; Byte offset inside MELODY for the current note, advanced by 2
    MUSIC_TICK_CTR  DW 0000h       ; Tick counter since the last melody note advance
    MUSIC_TICK_FREQ DW 0006h       ; Advances to the next melody note every 6 game ticks

    ; Descending melody played once on the game over end screen (blocking)
    MELODY_OVER     DW 0660h, 0720h, 0800h, 08E0h, 09F0h, 0B20h   ; Descending game-over melody
                    DW 0D60h, 0000h, 0FFFFh                         ; Final tone, silence, and end marker

    ; Ascending fanfare played once on the win end screen (blocking)
    MELODY_WIN      DW 0B20h, 09F0h, 08E0h, 0800h, 0720h, 0660h   ; Ascending win fanfare melody
                    DW 0660h, 0660h, 0000h, 0FFFFh                  ; Repeated top tone, silence, and end marker

    ; ========================
    ; DRAW TEMPORARY VARIABLES
    ; DRAW_ENEMIES cannot use SP-relative addressing (illegal in 8086 MASM),
    ; so these named variables hold intermediate positions during enemy drawing.
    ; ========================
    DE_ENEMY_X  DW 0000h           ; Temporary base X position of the enemy currently being drawn
    DE_ENEMY_Y  DW 0000h           ; Temporary base Y position of the enemy currently being drawn
    DE_BLOCK_X  DW 0000h           ; Temporary X position of the current scaled enemy block
    DE_BLOCK_Y  DW 0000h           ; Temporary Y position of the current scaled enemy block

DATA ENDS                          ; Ends the data segment
; ============================================================
; CODE SEGMENT - All executable procedures
; ============================================================
CODE SEGMENT PARA 'CODE'           ; Declares the code segment, paragraph-aligned

MAIN PROC FAR                      ; Declares MAIN as a FAR procedure, required for .EXE programs
    ASSUME CS:CODE, DS:DATA, SS:STACK  ; Tells the assembler which segment registers correspond to each segment

    PUSH DS                        ; Saves the original DS value on the stack
    SUB  AX, AX                    ; Clears AX by subtracting it from itself, so AX = 0
    PUSH AX                        ; Pushes 0 onto the stack as a return segment for clean program termination
    MOV  AX, DATA                  ; Loads the segment address of DATA into AX
    MOV  DS, AX                    ; Copies AX into DS so variables in DATA can be accessed correctly

    ; --- Set CGA graphics mode 4 (320x200, 4 colors) ---
    ; Technique from Pong tutorial: INT 10h function 00h sets the video mode.
    MOV AH, 00h                    ; Selects INT 10h function 00h, which sets the video mode
    MOV AL, 04h                    ; Selects video mode 04h: CGA 320x200 with 4 colors
    INT 10h                        ; Calls BIOS video interrupt to apply the selected graphics mode

    ; --- Select CGA palette 1 (black / cyan / magenta / white) ---
    MOV AH, 0Bh                    ; Selects INT 10h function 0Bh, used for color palette configuration
    MOV BH, 01h                    ; BH = 1 means the function will select a CGA palette
    MOV BL, 01h                    ; BL = 1 selects CGA palette 1: cyan, magenta, and white
    INT 10h                        ; Calls BIOS video interrupt to apply the palette selection

    ; --- Initialize enemy grid positions and states ---
    CALL INIT_ENEMIES              ; Calls the procedure that fills ENEMY_DATA with initial enemy states and positions

    ; ============================================================
    ; MAIN GAME LOOP
    ; Technique from Pong tutorial: time-based loop using system clock.
    ; The loop only advances when the 1/100s tick value changes,
    ; giving a consistent frame rate independent of CPU speed.
    ; ============================================================
GAME_LOOP:
    CMP GAME_ACTIVE, 00h           ; Checks if the game is inactive, meaning win or game over
    JE  SHOW_END_SCREEN            ; If GAME_ACTIVE is 0, jump to the end screen

    ; --- Wait for next 1/100s tick (time control from Pong tutorial) ---
    MOV AH, 2Ch                    ; Selects INT 21h function 2Ch, which reads the system time
    INT 21h                        ; Calls DOS interrupt; DL receives hundredths of a second
    CMP DL, TIME_AUX               ; Compares current time tick with the last stored tick
    JE  GAME_LOOP                  ; If the tick has not changed, wait by looping again
    MOV TIME_AUX, DL               ; Stores the new time tick to mark the current frame

    ; --- Clear screen: erase previous frame before drawing new one ---
    CALL CLEAR_SCREEN              ; Clears the screen before drawing the next frame

    ; --- Process keyboard input and move player ---
    CALL MOVE_PLAYER               ; Handles keyboard input for movement and shooting

    ; --- Update positions of all moving objects ---
    CALL MOVE_BULLET               ; Updates the player bullet position if it is active
    CALL MOVE_EBULLET              ; Updates the enemy bullet or creates a new one when needed
    CALL MOVE_ENEMIES              ; Moves the enemy grid horizontally and drops it when it hits a wall

    ; --- Collision detection (all checks each frame) ---
    CALL CHECK_BULLET_BUNKER_COLLISION    ; Checks if the player bullet hits a bunker pixel
    CALL CHECK_BULLET_ENEMY_COLLISION     ; Checks if the player bullet hits an enemy
    CALL CHECK_EBULLET_BUNKER_COLLISION   ; Checks if the enemy bullet hits a bunker pixel
    CALL CHECK_EBULLET_PLAYER_COLLISION   ; Checks if the enemy bullet hits the player
    CALL CHECK_ENEMIES_REACHED_BOTTOM     ; Checks if any enemy has reached the player area

    ; --- Draw all visible game objects ---
    CALL DRAW_BUNKERS              ; Draws both bunkers using their current destruction state
    CALL DRAW_ENEMIES              ; Draws all enemies that are still alive
    CALL DRAW_PLAYER               ; Draws the player tank sprite
    CALL DRAW_BULLET               ; Draws the player bullet if it is active
    CALL DRAW_EBULLET              ; Draws the enemy bullet if it is active

    ; --- Draw score in top-left area ---
    MOV DH, BYTE PTR SCORE_Y       ; Loads the text row where the score will be displayed
    MOV DL, BYTE PTR SCORE_X       ; Loads the text column where the score will be displayed
    CALL DRAW_SCORE                ; Converts the score to ASCII and draws it at DH:DL

    ; --- Advance background music by one step ---
    CALL PLAY_MUSIC_TICK           ; Advances the background melody without stopping the game loop

    JMP GAME_LOOP                  ; Repeats the main game loop while the game remains active

    ; ============================================================
    ; END SCREEN
    ; Reached when GAME_ACTIVE = 0 (win or lose).
    ; Displays result message, plays end melody, waits for R or Q.
    ; ============================================================
SHOW_END_SCREEN:
    CALL STOP_SOUND                ; Stops any sound that may still be playing
    CALL CLEAR_SCREEN              ; Clears the screen before drawing the end screen

    CMP GAME_WIN, 01h              ; Checks if the game ended with a player victory
    JE  SHOW_WIN_MSG               ; If GAME_WIN is 1, jump to the win message

    ; --- Game Over path ---
    MOV DH, 0Ch                    ; Sets the text row for the GAME OVER message
    MOV DL, 0Ah                    ; Sets the text column for the GAME OVER message
    LEA SI, MSG_GAMEOVER           ; Loads the address of the GAME OVER string into SI
    CALL DRAW_STRING               ; Draws the GAME OVER message on screen

    LEA SI, MELODY_OVER            ; Loads the address of the game-over melody into SI
    CALL PLAY_MELODY               ; Plays the full game-over melody in a blocking way
    JMP SHOW_RESTART_PROMPT        ; Skips the win section and jumps to the restart prompt

SHOW_WIN_MSG:
    MOV DH, 0Ch                    ; Sets the text row for the YOU WIN message
    MOV DL, 0Bh                    ; Sets the text column for the YOU WIN message
    LEA SI, MSG_WIN                ; Loads the address of the YOU WIN string into SI
    CALL DRAW_STRING               ; Draws the YOU WIN message on screen

    LEA SI, MELODY_WIN             ; Loads the address of the victory melody into SI
    CALL PLAY_MELODY               ; Plays the full win melody in a blocking way

SHOW_RESTART_PROMPT:
    ; Shows the "SCORE:" label and the score digits on the same centered row
    ; "SCORE:" = 6 characters + space + 5 digits = 12 characters total
    ; Centered in 40 columns: (40 - 12) / 2 = column 14
    MOV DH, 0Eh                    ; Sets text row 14 for the score label
    MOV DL, 0Eh                    ; Sets text column 14 for the score label
    LEA SI, MSG_SCORE              ; Loads the address of the SCORE label into SI
    CALL DRAW_STRING               ; Draws the SCORE label on screen

    MOV DH, 0Eh                    ; Uses the same row as the SCORE label
    MOV DL, 15h                    ; Sets column 21, after "SCORE: "
    CALL DRAW_SCORE                ; Draws the five score digits after the SCORE label

    ; Shows centered restart and quit instructions on row 16
    ; "R=RESTART  Q=QUIT" = 18 characters, so start column = (40 - 18) / 2 = 11
    MOV DH, 10h                    ; Sets text row 16 for the restart/quit instructions
    MOV DL, 0Bh                    ; Sets text column 11 to center the instruction string
    LEA SI, MSG_RESTART            ; Loads the address of the restart/quit message into SI
    CALL DRAW_STRING               ; Draws the restart/quit instructions on screen

WAIT_KEY:
    MOV AH, 00h                    ; Selects INT 16h function 00h, which waits for a key press
    INT 16h                        ; Reads a key from the keyboard; ASCII code is returned in AL

    CMP AL, 72h                    ; Compares AL with lowercase 'r'
    JE  DO_RESTART                 ; If the key is 'r', restart the game
    CMP AL, 52h                    ; Compares AL with uppercase 'R'
    JE  DO_RESTART                 ; If the key is 'R', restart the game
    CMP AL, 71h                    ; Compares AL with lowercase 'q'
    JE  DO_QUIT                    ; If the key is 'q', quit the game
    CMP AL, 51h                    ; Compares AL with uppercase 'Q'
    JE  DO_QUIT                    ; If the key is 'Q', quit the game
    JMP WAIT_KEY                   ; If another key is pressed, keep waiting

DO_RESTART:
    CALL RESET_GAME                ; Restores all game variables to their initial values
    JMP  GAME_LOOP                 ; Returns to the main game loop after resetting

DO_QUIT:
    MOV AX, 4C00h                  ; Selects DOS terminate program function with exit code 0
    INT 21h                        ; Calls DOS interrupt to return control to DOS

    RET                            ; Backup return instruction, normally not reached after INT 21h
MAIN ENDP                          ; Ends the MAIN procedure

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

    CMP EBULLET_ACTIVE, 01h       ; Check if the enemy bullet is currently active
    JE  CEBC_START                ; If it is active, start checking bunker collisions
    JMP CEBC_EXIT                 ; If it is not active, skip the whole procedure

CEBC_START:                       ; Start of enemy-bullet-to-bunker collision checking

    ; ---- Bunker 1 ----
    MOV AX, EBULLET_X             ; Load the enemy bullet X position into AX
    CMP AX, BUNKER1_X             ; Compare bullet X with the left edge of bunker 1
    JL  CEBC_B2                   ; If bullet is left of bunker 1, check bunker 2 instead

    MOV AX, BUNKER_SPRITE_WIDTH   ; Load bunker sprite width in logical pixels
    MUL BUNKER_SCALE              ; Multiply width by scale to get real bunker width in screen pixels
    ADD AX, BUNKER1_X             ; Add bunker 1 X position to calculate bunker 1 right edge
    CMP EBULLET_X, AX             ; Compare bullet X with bunker 1 right edge
    JG  CEBC_B2                   ; If bullet is right of bunker 1, check bunker 2 instead

    MOV AX, EBULLET_Y             ; Load the enemy bullet Y position into AX
    CMP AX, BUNKER_Y              ; Compare bullet Y with the top edge of the bunker
    JL  CEBC_B2                   ; If bullet is above bunker 1, check bunker 2 instead

    MOV AX, BUNKER_SPRITE_HEIGHT  ; Load bunker sprite height in logical pixels
    MUL BUNKER_SCALE              ; Multiply height by scale to get real bunker height in screen pixels
    ADD AX, BUNKER_Y              ; Add bunker Y position to calculate bunker bottom edge
    CMP EBULLET_Y, AX             ; Compare bullet Y with bunker 1 bottom edge
    JG  CEBC_B2                   ; If bullet is below bunker 1, check bunker 2 instead

    ; Hit: compute pixel_col and pixel_row for bunker 1
    MOV AX, EBULLET_X             ; Load enemy bullet X position
    SUB AX, BUNKER1_X             ; Calculate horizontal offset inside bunker 1
    XOR DX, DX                    ; Clear DX before division because DIV uses DX:AX
    MOV BL, BUNKER_SCALE_BYTE     ; Load bunker scale as a byte divisor
    DIV BL                        ; Divide offset by scale; AL = logical pixel column
    XOR AH, AH                    ; Clear remainder so AX contains only the column index
    MOV CX, AX                    ; Store logical pixel column in CX

    MOV AX, EBULLET_Y             ; Load enemy bullet Y position
    SUB AX, BUNKER_Y              ; Calculate vertical offset inside the bunker
    XOR DX, DX                    ; Clear DX before division
    DIV BL                        ; Divide offset by scale; AL = logical pixel row
    XOR AH, AH                    ; Clear remainder so AX contains only the row index

    MOV BX, BUNKER_SPRITE_WIDTH   ; Load bunker width in logical pixels
    MUL BX                        ; AX = pixel_row * bunker_width
    ADD AX, CX                    ; AX = pixel_row * width + pixel_col, the flat array index
    MOV SI, AX                    ; Store the bunker state index in SI

    MOV BX, OFFSET BUNKER1_STATE  ; Load the base address of bunker 1 state array
    ADD BX, SI                    ; Move BX to the exact state byte that was hit
    CMP BYTE PTR [BX], 00h        ; Check if that bunker pixel was already destroyed
    JE  CEBC_EXIT                 ; If it was already destroyed, the bullet passes through
    MOV BYTE PTR [BX], 00h        ; Mark that bunker pixel as destroyed
    MOV EBULLET_ACTIVE, 00h       ; Deactivate the enemy bullet after hitting a valid bunker pixel
    JMP CEBC_EXIT                 ; Exit after handling the collision with bunker 1

CEBC_B2:                          ; Start checking collision against bunker 2

    ; ---- Bunker 2 ----
    MOV AX, EBULLET_X             ; Load the enemy bullet X position into AX
    CMP AX, BUNKER2_X             ; Compare bullet X with the left edge of bunker 2
    JL  CEBC_EXIT                 ; If bullet is left of bunker 2, there is no bunker collision

    MOV AX, BUNKER_SPRITE_WIDTH   ; Load bunker sprite width in logical pixels
    MUL BUNKER_SCALE              ; Multiply width by scale to get real bunker width in screen pixels
    ADD AX, BUNKER2_X             ; Add bunker 2 X position to calculate bunker 2 right edge
    CMP EBULLET_X, AX             ; Compare bullet X with bunker 2 right edge
    JG  CEBC_EXIT                 ; If bullet is right of bunker 2, there is no collision

    MOV AX, EBULLET_Y             ; Load the enemy bullet Y position into AX
    CMP AX, BUNKER_Y              ; Compare bullet Y with the top edge of the bunker
    JL  CEBC_EXIT                 ; If bullet is above bunker 2, there is no collision

    MOV AX, BUNKER_SPRITE_HEIGHT  ; Load bunker sprite height in logical pixels
    MUL BUNKER_SCALE              ; Multiply height by scale to get real bunker height in screen pixels
    ADD AX, BUNKER_Y              ; Add bunker Y position to calculate bunker bottom edge
    CMP EBULLET_Y, AX             ; Compare bullet Y with bunker 2 bottom edge
    JG  CEBC_EXIT                 ; If bullet is below bunker 2, there is no collision

    ; Hit: compute pixel index for bunker 2
    MOV AX, EBULLET_X             ; Load enemy bullet X position
    SUB AX, BUNKER2_X             ; Calculate horizontal offset inside bunker 2
    XOR DX, DX                    ; Clear DX before division because DIV uses DX:AX
    MOV BL, BUNKER_SCALE_BYTE     ; Load bunker scale as a byte divisor
    DIV BL                        ; Divide offset by scale; AL = logical pixel column
    XOR AH, AH                    ; Clear remainder so AX contains only the column index
    MOV CX, AX                    ; Store logical pixel column in CX

    MOV AX, EBULLET_Y             ; Load enemy bullet Y position
    SUB AX, BUNKER_Y              ; Calculate vertical offset inside the bunker
    XOR DX, DX                    ; Clear DX before division
    DIV BL                        ; Divide offset by scale; AL = logical pixel row
    XOR AH, AH                    ; Clear remainder so AX contains only the row index

    MOV BX, BUNKER_SPRITE_WIDTH   ; Load bunker width in logical pixels
    MUL BX                        ; AX = pixel_row * bunker_width
    ADD AX, CX                    ; AX = pixel_row * width + pixel_col, the flat array index
    MOV SI, AX                    ; Store the bunker state index in SI

    MOV BX, OFFSET BUNKER2_STATE  ; Load the base address of bunker 2 state array
    ADD BX, SI                    ; Move BX to the exact state byte that was hit
    CMP BYTE PTR [BX], 00h        ; Check if that bunker pixel was already destroyed
    JE  CEBC_EXIT                 ; If it was already destroyed, the bullet passes through
    MOV BYTE PTR [BX], 00h        ; Mark that bunker pixel as destroyed
    MOV EBULLET_ACTIVE, 00h       ; Deactivate the enemy bullet after hitting a valid bunker pixel

CEBC_EXIT:                        ; Exit label for the procedure
    RET                           ; Return to the caller
CHECK_EBULLET_BUNKER_COLLISION ENDP ; End of enemy-bullet-to-bunker collision procedure

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

CHECK_EBULLET_PLAYER_COLLISION PROC NEAR ; Procedure that checks if the enemy bullet hits the player

    CMP EBULLET_ACTIVE, 01h       ; Check if the enemy bullet is currently active
    JNE CEPC_EXIT                 ; If no enemy bullet is active, skip the whole collision check

    MOV AX, EBULLET_X             ; Load the enemy bullet X position into AX
    CMP AX, PLAYER_X              ; Compare bullet X with the player's left edge
    JL  CEPC_EXIT                 ; If bullet is left of the player, there is no collision

    MOV AX, SPRITE_WIDTH          ; Load the player sprite width in logical pixels
    MUL SPRITE_SCALE              ; AX = SPRITE_WIDTH * SPRITE_SCALE, the real player width in screen pixels
    ADD AX, PLAYER_X              ; AX = player's right edge on the screen
    CMP EBULLET_X, AX             ; Compare bullet X with the player's right edge
    JG  CEPC_EXIT                 ; If bullet is right of the player, there is no collision

    MOV AX, EBULLET_Y             ; Load the enemy bullet Y position into AX
    CMP AX, PLAYER_Y              ; Compare bullet Y with the player's top edge
    JL  CEPC_EXIT                 ; If bullet is above the player, there is no collision

    MOV AX, SPRITE_HEIGHT         ; Load the player sprite height in logical pixels
    MUL SPRITE_SCALE              ; AX = SPRITE_HEIGHT * SPRITE_SCALE, the real player height in screen pixels
    ADD AX, PLAYER_Y              ; AX = player's bottom edge on the screen
    CMP EBULLET_Y, AX             ; Compare bullet Y with the player's bottom edge
    JG  CEPC_EXIT                 ; If bullet is below the player, there is no collision

    ; If execution reaches this point, the enemy bullet is inside the player's bounding box
    MOV GAME_ACTIVE, 00h          ; Stop the main game loop by marking the game as inactive
    MOV GAME_WIN, 00h             ; Mark the result as a loss, not a win
    MOV EBULLET_ACTIVE, 00h       ; Deactivate the enemy bullet after hitting the player

CEPC_EXIT:                        ; Exit label for this collision procedure
    RET                           ; Return to the caller
CHECK_EBULLET_PLAYER_COLLISION ENDP ; End of enemy-bullet-to-player collision procedure



; ============================================================
; CHECK_BULLET_ENEMY_COLLISION
; Checks the player bullet against the collision box of
; each living enemy. Each enemy collision box is:
;   Left   = enemy_X
;   Right  = enemy_X + ENEMY_SPRITE_W * ENEMY_SCALE
;   Top    = enemy_Y
;   Bottom = enemy_Y + ENEMY_SPRITE_H * ENEMY_SCALE
; On hit: destroys the enemy, plays a sound, and adds 10 points.
; If ENEMY_COUNT reaches 0, the player wins.
; ============================================================

CHECK_BULLET_ENEMY_COLLISION PROC NEAR ; Procedure that checks if the player bullet hits any living enemy

    CMP BULLET_ACTIVE, 01h        ; Check if the player bullet is currently active
    JNE CBEC_EXIT                 ; If no player bullet is active, skip all collision checks

    MOV SI, 0                     ; SI = offset into ENEMY_DATA, starting at the first enemy entry

CBEC_LOOP:                        ; Loop through all enemy entries
    CMP SI, 005Ah                 ; Check if all 90 bytes of ENEMY_DATA have been processed
    JGE CBEC_EXIT                 ; If SI >= 90, all 18 enemies were checked, so exit

    MOV AL, BYTE PTR ENEMY_DATA[SI]   ; Load the current enemy state into AL
    CMP AL, 01h                   ; Check if the current enemy is alive
    JNE CBEC_SKIP                 ; If the enemy is not alive, skip to the next enemy

    MOV DI, WORD PTR ENEMY_DATA[SI+1]  ; Load the current enemy X position into DI
    MOV BX, WORD PTR ENEMY_DATA[SI+3]  ; Load the current enemy Y position into BX

    ; Left-edge check: the bullet must be at or to the right of enemy_X
    CMP BULLET_X, DI              ; Compare bullet X with the enemy left edge
    JL  CBEC_SKIP                 ; If bullet is left of the enemy, there is no hit

    ; Right-edge check: bullet_X must be <= enemy_X + scaled enemy width
    PUSH BX                       ; Save enemy Y because BX will be needed after the width calculation
    PUSH SI                       ; Save enemy data index before using calculations that may affect registers
    MOV  AX, ENEMY_SPRITE_W       ; Load enemy sprite width in logical pixels
    MUL  ENEMY_SCALE              ; AX = enemy sprite width * scale, the real enemy width in screen pixels
    ADD  AX, DI                   ; AX = enemy right edge
    CMP  BULLET_X, AX             ; Compare bullet X with the enemy right edge
    POP  SI                       ; Restore enemy data index
    POP  BX                       ; Restore enemy Y position
    JG  CBEC_SKIP                 ; If bullet is right of the enemy, there is no hit

    ; Top-edge check: the bullet must be at or below enemy_Y
    CMP BULLET_Y, BX              ; Compare bullet Y with the enemy top edge
    JL  CBEC_SKIP                 ; If bullet is above the enemy, there is no hit

    ; Bottom-edge check: bullet_Y must be <= enemy_Y + scaled enemy height
    PUSH BX                       ; Save enemy Y before calculating the scaled height
    PUSH SI                       ; Save enemy data index before the calculation
    MOV  AX, ENEMY_SPRITE_H       ; Load enemy sprite height in logical pixels
    MUL  ENEMY_SCALE              ; AX = enemy sprite height * scale, the real enemy height in screen pixels
    ADD  AX, BX                   ; AX = enemy bottom edge
    CMP  BULLET_Y, AX             ; Compare bullet Y with the enemy bottom edge
    POP  SI                       ; Restore enemy data index
    POP  BX                       ; Restore enemy Y position
    JG  CBEC_SKIP                 ; If bullet is below the enemy, there is no hit

    ; ---- HIT CONFIRMED ----
    MOV BYTE PTR ENEMY_DATA[SI], 00h   ; Mark the current enemy as dead by setting its state to 0
    MOV BULLET_ACTIVE, 00h             ; Deactivate the player bullet after the hit

    ; Play hit sound immediately
    MOV BX, SOUND_HIT_FREQ        ; Load the PIT divisor for the hit sound effect
    CALL PLAY_SOUND               ; Turn on the PC speaker using the hit frequency
    CALL STOP_SOUND               ; Stop the speaker to create a short sound effect

    ADD SCORE, 000Ah              ; Add 10 points to the score for destroying one enemy

    DEC ENEMY_COUNT               ; Decrease the number of living enemies by one
    JNZ CBEC_EXIT                 ; If enemies remain alive, exit because the bullet is gone

    ; All enemies destroyed: player wins
    MOV GAME_ACTIVE, 00h          ; Stop the main game loop
    MOV GAME_WIN, 01h             ; Mark the game result as a victory
    JMP CBEC_EXIT                 ; Exit the procedure after setting the win state

CBEC_SKIP:                        ; Label used when the current enemy was not hit
    ADD SI, 0005h                 ; Move to the next enemy entry, since each entry uses 5 bytes
    JMP CBEC_LOOP                 ; Continue checking the next enemy

CBEC_EXIT:                        ; Exit label for this collision procedure
    RET                           ; Return to the caller
CHECK_BULLET_ENEMY_COLLISION ENDP ; End of player-bullet-to-enemy collision procedure


; ============================================================
; DRAW_BUNKERS
; Draws both bunkers pixel by pixel, skipping any pixel
; whose state byte in BUNKER1_STATE / BUNKER2_STATE
; is 0, meaning destroyed. Each alive pixel is drawn as a
; BUNKER_SCALE x BUNKER_SCALE block using COLOR_CYAN.
; ============================================================

DRAW_BUNKERS PROC NEAR             ; Procedure that draws both bunkers on the screen
    PUSH BP                        ; Save BP because it is used as temporary storage for BLOCK_Y

    ; ---- Bunker 1 ----
    MOV SI, 0                      ; SI = flat index into BUNKER1_STATE, from 0 to 27
    MOV BX, 0                      ; BX = current sprite row for bunker 1

B1_ROW:                            ; Start of bunker 1 row loop
    CMP BX, BUNKER_SPRITE_HEIGHT   ; Check if all bunker 1 sprite rows have been processed
    JGE DRAW_B2                    ; If all rows are done, move on to bunker 2

    MOV CX, 0                      ; CX = current sprite column for bunker 1

B1_COL:                            ; Start of bunker 1 column loop
    CMP CX, BUNKER_SPRITE_WIDTH    ; Check if all columns in the current row have been processed
    JGE B1_NEXT_ROW                ; If all columns are done, go to the next row

    ; Read the state of the current bunker pixel
    PUSH BX                        ; Save the current row because BX will be used for addressing
    MOV  BX, OFFSET BUNKER1_STATE  ; Load the base address of bunker 1 state array into BX
    ADD  BX, SI                    ; Move BX to the state byte of the current bunker pixel
    MOV  AL, [BX]                  ; Load the state value: 1 = alive, 0 = destroyed
    POP  BX                        ; Restore the current row counter

    CMP AL, 00h                    ; Check if the current bunker pixel is destroyed
    JE  B1_SKIP                    ; If it is destroyed, skip drawing it

    ; Current pixel is alive: calculate its scaled block position and draw it
    PUSH BX                        ; Save the current sprite row
    PUSH CX                        ; Save the current sprite column
    PUSH SI                        ; Save the current state-array index

    ; BLOCK_X = BUNKER1_X + (column * BUNKER_SCALE)
    MOV AX, CX                     ; AX = current sprite column
    MUL BUNKER_SCALE               ; AX = column * scale, horizontal screen offset
    ADD AX, BUNKER1_X              ; AX = final X position of the scaled block
    MOV DI, AX                     ; DI = BLOCK_X

    ; BLOCK_Y = BUNKER_Y + (row * BUNKER_SCALE)
    MOV AX, BX                     ; AX = current sprite row
    MUL BUNKER_SCALE               ; AX = row * scale, vertical screen offset
    ADD AX, BUNKER_Y               ; AX = final Y position of the scaled block
    MOV BP, AX                     ; BP = BLOCK_Y

    MOV BX, 0                      ; BX = scaled block row counter

B1_BROW:                           ; Start of scaled block row loop for bunker 1
    CMP BX, BUNKER_SCALE           ; Check if all rows of the scaled block were drawn
    JGE B1_BEND                    ; If yes, finish drawing this scaled block

    MOV SI, 0                      ; SI = scaled block column counter

B1_BCOL:                           ; Start of scaled block column loop for bunker 1
    CMP SI, BUNKER_SCALE           ; Check if all columns in this scaled block row were drawn
    JGE B1_BNROW                   ; If yes, move to the next scaled block row

    MOV AX, BP                     ; AX = BLOCK_Y
    ADD AX, BX                     ; AX = BLOCK_Y + block row, final screen Y
    MOV DX, AX                     ; DX = Y coordinate required by INT 10h
    MOV AX, DI                     ; AX = BLOCK_X
    ADD AX, SI                     ; AX = BLOCK_X + block column, final screen X
    MOV CX, AX                     ; CX = X coordinate required by INT 10h

    MOV AH, 0Ch                    ; Select INT 10h function 0Ch, write graphics pixel
    MOV AL, COLOR_CYAN             ; Select cyan as the bunker pixel color
    MOV BH, 00h                    ; Select video page 0
    INT 10h                        ; Draw one pixel at coordinates (CX, DX)

    INC SI                         ; Move to the next column inside the scaled block
    JMP B1_BCOL                    ; Continue drawing columns of the scaled block

B1_BNROW:                          ; Move to the next scaled block row
    INC BX                         ; Increase the scaled block row counter
    JMP B1_BROW                    ; Continue drawing rows of the scaled block

B1_BEND:                           ; End of the current scaled block drawing
    POP SI                         ; Restore the bunker state-array index
    POP CX                         ; Restore the sprite column counter
    POP BX                         ; Restore the sprite row counter

B1_SKIP:                           ; Skip label used when the bunker pixel is destroyed
    INC SI                         ; Advance to the next bunker state byte
    INC CX                         ; Advance to the next sprite column
    JMP B1_COL                     ; Continue checking columns in the current row

B1_NEXT_ROW:                       ; Move to the next bunker 1 sprite row
    INC BX                         ; Increase the sprite row counter
    JMP B1_ROW                     ; Continue processing bunker 1 rows

    ; ---- Bunker 2 (same logic, using BUNKER2_X and BUNKER2_STATE) ----
DRAW_B2:                           ; Start drawing bunker 2
    MOV SI, 0                      ; Reset SI as the flat index into BUNKER2_STATE
    MOV BX, 0                      ; Reset BX as the bunker 2 sprite row counter

B2_ROW:                            ; Start of bunker 2 row loop
    CMP BX, BUNKER_SPRITE_HEIGHT   ; Check if all bunker 2 sprite rows have been processed
    JGE END_BUNKERS                ; If all rows are done, finish the procedure

    MOV CX, 0                      ; CX = current sprite column for bunker 2

B2_COL:                            ; Start of bunker 2 column loop
    CMP CX, BUNKER_SPRITE_WIDTH    ; Check if all columns in the current row have been processed
    JGE B2_NEXT_ROW                ; If all columns are done, go to the next row

    PUSH BX                        ; Save the current row because BX will be used for addressing
    MOV  BX, OFFSET BUNKER2_STATE  ; Load the base address of bunker 2 state array into BX
    ADD  BX, SI                    ; Move BX to the state byte of the current bunker pixel
    MOV  AL, [BX]                  ; Load the state value: 1 = alive, 0 = destroyed
    POP  BX                        ; Restore the current row counter

    CMP AL, 00h                    ; Check if the current bunker pixel is destroyed
    JE  B2_SKIP                    ; If it is destroyed, skip drawing it

    PUSH BX                        ; Save the current sprite row
    PUSH CX                        ; Save the current sprite column
    PUSH SI                        ; Save the current state-array index

    ; BLOCK_X = BUNKER2_X + (column * BUNKER_SCALE)
    MOV AX, CX                     ; AX = current sprite column
    MUL BUNKER_SCALE               ; AX = column * scale, horizontal screen offset
    ADD AX, BUNKER2_X              ; AX = final X position of the scaled block for bunker 2
    MOV DI, AX                     ; DI = BLOCK_X

    ; BLOCK_Y = BUNKER_Y + (row * BUNKER_SCALE)
    MOV AX, BX                     ; AX = current sprite row
    MUL BUNKER_SCALE               ; AX = row * scale, vertical screen offset
    ADD AX, BUNKER_Y               ; AX = final Y position of the scaled block
    MOV BP, AX                     ; BP = BLOCK_Y

    MOV BX, 0                      ; BX = scaled block row counter

B2_BROW:                           ; Start of scaled block row loop for bunker 2
    CMP BX, BUNKER_SCALE           ; Check if all rows of the scaled block were drawn
    JGE B2_BEND                    ; If yes, finish drawing this scaled block

    MOV SI, 0                      ; SI = scaled block column counter

B2_BCOL:                           ; Start of scaled block column loop for bunker 2
    CMP SI, BUNKER_SCALE           ; Check if all columns in this scaled block row were drawn
    JGE B2_BNROW                   ; If yes, move to the next scaled block row

    MOV AX, BP                     ; AX = BLOCK_Y
    ADD AX, BX                     ; AX = BLOCK_Y + block row, final screen Y
    MOV DX, AX                     ; DX = Y coordinate required by INT 10h
    MOV AX, DI                     ; AX = BLOCK_X
    ADD AX, SI                     ; AX = BLOCK_X + block column, final screen X
    MOV CX, AX                     ; CX = X coordinate required by INT 10h

    MOV AH, 0Ch                    ; Select INT 10h function 0Ch, write graphics pixel
    MOV AL, COLOR_CYAN             ; Select cyan as the bunker pixel color
    MOV BH, 00h                    ; Select video page 0
    INT 10h                        ; Draw one pixel at coordinates (CX, DX)

    INC SI                         ; Move to the next column inside the scaled block
    JMP B2_BCOL                    ; Continue drawing columns of the scaled block

B2_BNROW:                          ; Move to the next scaled block row
    INC BX                         ; Increase the scaled block row counter
    JMP B2_BROW                    ; Continue drawing rows of the scaled block

B2_BEND:                           ; End of the current scaled block drawing
    POP SI                         ; Restore the bunker state-array index
    POP CX                         ; Restore the sprite column counter
    POP BX                         ; Restore the sprite row counter

B2_SKIP:                           ; Skip label used when the bunker pixel is destroyed
    INC SI                         ; Advance to the next bunker state byte
    INC CX                         ; Advance to the next sprite column
    JMP B2_COL                     ; Continue checking columns in the current row

B2_NEXT_ROW:                       ; Move to the next bunker 2 sprite row
    INC BX                         ; Increase the sprite row counter
    JMP B2_ROW                     ; Continue processing bunker 2 rows

END_BUNKERS:                       ; End label for drawing both bunkers
    POP BP                         ; Restore BP before returning to the caller
    RET                            ; Return to the caller
DRAW_BUNKERS ENDP                  ; End of DRAW_BUNKERS procedure

; ============================================================
; DRAW_SCORE
; Converts the numeric value of SCORE (0-99990) into a
; 5-digit ASCII string using repeated division by 10
; (technique from the Pong tutorial), then displays it at
; the cursor position provided by the caller in DH (row)
; and DL (column).
; Input: DH = text row, DL = text column
; ============================================================

DRAW_SCORE PROC NEAR               ; Procedure that converts SCORE to ASCII and prints it on screen
    PUSH DX                        ; Save the caller's DH:DL cursor position because DIV overwrites DX

    ; Convert SCORE to ASCII digits using repeated division by 10
    MOV AX, SCORE                  ; Load the current numeric score into AX
    MOV BX, 000Ah                  ; Load 10 into BX, used as the decimal divisor

    XOR DX, DX                     ; Clear DX before division because DIV uses DX:AX
    DIV BX                         ; AX = SCORE / 10, DX = SCORE mod 10, giving the units digit
    ADD DL, 30h                    ; Convert the units digit from number 0-9 to ASCII '0'-'9'
    MOV SCORE_STR+4, DL            ; Store the units digit in the last position of SCORE_STR

    XOR DX, DX                     ; Clear DX before the next division
    DIV BX                         ; AX = previous quotient / 10, DX = tens digit
    ADD DL, 30h                    ; Convert the tens digit to ASCII
    MOV SCORE_STR+3, DL            ; Store the tens digit in position 3 of SCORE_STR

    XOR DX, DX                     ; Clear DX before the next division
    DIV BX                         ; AX = previous quotient / 10, DX = hundreds digit
    ADD DL, 30h                    ; Convert the hundreds digit to ASCII
    MOV SCORE_STR+2, DL            ; Store the hundreds digit in position 2 of SCORE_STR

    XOR DX, DX                     ; Clear DX before the next division
    DIV BX                         ; AX = previous quotient / 10, DX = thousands digit
    ADD DL, 30h                    ; Convert the thousands digit to ASCII
    MOV SCORE_STR+1, DL            ; Store the thousands digit in position 1 of SCORE_STR

    XOR DX, DX                     ; Clear DX before the final division
    DIV BX                         ; AX = previous quotient / 10, DX = ten-thousands digit
    ADD DL, 30h                    ; Convert the ten-thousands digit to ASCII
    MOV SCORE_STR+0, DL            ; Store the ten-thousands digit in position 0 of SCORE_STR

    ; Restore cursor row/column and move the text cursor to that position
    POP DX                         ; Restore DH = row and DL = column passed by the caller
    MOV BH, 00h                    ; Select video page 0
    MOV AH, 02h                    ; Select INT 10h function 02h, set cursor position
    INT 10h                        ; Move the text cursor to row DH and column DL

    LEA SI, SCORE_STR              ; Load the address of the score string into SI

DS_LOOP:                           ; Loop through each character of SCORE_STR
    MOV AL, [SI]                   ; Load the current score character into AL
    CMP AL, 00h                    ; Check if the current character is the null terminator
    JE  DS_DONE                    ; If the null terminator is reached, stop printing

    MOV AH, 0Eh                    ; Select INT 10h function 0Eh, teletype character output
    MOV BH, 00h                    ; Select video page 0
    INT 10h                        ; Print the character in AL and advance the cursor

    INC SI                         ; Move SI to the next character of SCORE_STR
    JMP DS_LOOP                    ; Repeat until the null terminator is found

DS_DONE:                           ; End of score printing loop
    RET                            ; Return to the caller
DRAW_SCORE ENDP                    ; End of DRAW_SCORE procedure

; ============================================================
; DRAW_STRING
; Draws a null-terminated ASCII string stored in DS.
; Input: DH = row, DL = column (text cursor position)
;        SI = offset of the string inside DS
; ============================================================

DRAW_STRING PROC NEAR              ; Procedure that prints a null-terminated string at the cursor position
    MOV BH, 00h                    ; Select video page 0
    MOV AH, 02h                    ; Select INT 10h function 02h, set cursor position
    INT 10h                        ; Move the cursor to the position stored in DH:DL

DSTR_LOOP:                         ; Start of the string-printing loop
    MOV AL, [SI]                   ; Load the next character from the string into AL
    CMP AL, 00h                    ; Check if the current character is the null terminator
    JE  DSTR_DONE                  ; If it is the null terminator, finish printing

    MOV AH, 0Eh                    ; Select INT 10h function 0Eh, teletype character output
    MOV BH, 00h                    ; Select video page 0
    INT 10h                        ; Print the character in AL and advance the cursor

    INC SI                         ; Move SI to the next character in the string
    JMP DSTR_LOOP                  ; Repeat the loop until the null terminator is found

DSTR_DONE:                         ; End label for the string-printing loop
    RET                            ; Return to the caller
DRAW_STRING ENDP                   ; End of DRAW_STRING procedure

; ============================================================
; PLAY_MUSIC_TICK
; Non-blocking background music player.
; It is called once per game tick. Every MUSIC_TICK_FREQ ticks,
; it advances MELODY_IDX by one step (2 bytes) and either:
;   - Programs PIT channel 2 and enables the speaker for an audible note, or
;   - Disables the speaker for a rest / silence.
; When the end marker (0FFFFh) is reached, MELODY_IDX returns to 0.
; ============================================================

PLAY_MUSIC_TICK PROC NEAR          ; Procedure that updates the background music without stopping the game

    INC MUSIC_TICK_CTR             ; Increase the music tick counter by one game tick
    MOV AX, MUSIC_TICK_CTR         ; Load the number of ticks since the last note change into AX
    CMP AX, MUSIC_TICK_FREQ        ; Compare the tick counter with the note-change frequency
    JL  PMT_EXIT                   ; If not enough ticks have passed, keep the current note and exit

    MOV MUSIC_TICK_CTR, 0000h      ; Reset the music tick counter because a note update will happen

    ; Read the PIT divisor of the current note from the MELODY array
    MOV SI, OFFSET MELODY          ; Load the base address of the MELODY array into SI
    ADD SI, MELODY_IDX             ; Move SI to the current note using MELODY_IDX as a byte offset
    MOV BX, WORD PTR [SI]          ; Load the current note divisor into BX

    CMP BX, 0FFFFh                 ; Check if the current value is the melody end marker
    JNE PMT_PLAY                   ; If it is not the end marker, process the current note
    MOV MELODY_IDX, 0000h          ; If it is the end marker, restart the melody from the beginning
    MOV SI, OFFSET MELODY          ; Reload SI with the base address of the MELODY array
    MOV BX, WORD PTR [SI]          ; Load the first note divisor into BX

PMT_PLAY:                          ; Label used to play a note or process a rest
    ADD MELODY_IDX, 0002h          ; Advance MELODY_IDX by 2 bytes because each note is a WORD

    CMP BX, 0000h                  ; Check if the current note is a rest
    JE  PMT_SILENCE                ; If the note is 0000h, silence the speaker

    ; Program PIT channel 2 with the selected frequency divisor
    MOV AL, 0B6h                   ; PIT command byte: channel 2, mode 3 square wave, binary count
    OUT 43h, AL                    ; Send the PIT command to port 43h
    MOV AX, BX                     ; Copy the PIT divisor from BX into AX
    OUT 42h, AL                    ; Send the low byte of the divisor to PIT channel 2 through port 42h
    MOV AL, AH                     ; Move the high byte of the divisor into AL
    OUT 42h, AL                    ; Send the high byte of the divisor to PIT channel 2

    ; Enable the PC speaker through system port 61h
    IN  AL, 61h                    ; Read the current value of port 61h
    OR  AL, 03h                    ; Set bits 0 and 1 to connect PIT channel 2 to the speaker
    OUT 61h, AL                    ; Write the updated value back to port 61h to enable sound
    JMP PMT_EXIT                   ; Exit after starting the note

PMT_SILENCE:                       ; Label used when the current melody value is a rest
    ; Disable the speaker by clearing bits 0 and 1 of port 61h
    IN  AL, 61h                    ; Read the current value of port 61h
    AND AL, 0FCh                   ; Clear bits 0 and 1 to disconnect and silence the speaker
    OUT 61h, AL                    ; Write the updated value back to port 61h

PMT_EXIT:                          ; Exit label for the music tick procedure
    RET                            ; Return to the caller
PLAY_MUSIC_TICK ENDP               ; End of PLAY_MUSIC_TICK procedure

; ============================================================
; PLAY_MELODY
; Blocking melody player, used on the final screen.
; Plays each note from the array pointed to by SI and stops
; when it finds the end marker (0FFFFh).
; Each note is held for a fixed time using a delay loop.
; Input: SI = offset of the melody array (DW values, ending with 0FFFFh)
; ============================================================
PLAY_MELODY PROC NEAR              ; Procedure that plays a complete melody and blocks execution until it finishes

PM_NEXT_NOTE:                      ; Label used to read and process the next melody note
    MOV BX, WORD PTR [SI]          ; Load the next PIT divisor from the melody array into BX
    CMP BX, 0FFFFh                 ; Check if the current value is the end marker
    JE  PM_DONE                    ; If it is the end marker, finish the melody

    ADD SI, 0002h                  ; Move SI to the next note because each note is a WORD of 2 bytes

    CMP BX, 0000h                  ; Check if the current note is a rest / silence
    JE  PM_REST                    ; If it is a rest, silence the speaker for this note duration

    ; Play note: program PIT channel 2 and enable the PC speaker
    MOV AL, 0B6h                   ; PIT command: channel 2, low/high byte access, mode 3, binary mode
    OUT 43h, AL                    ; Send the PIT command byte to port 43h
    MOV AX, BX                     ; Copy the PIT divisor from BX into AX
    OUT 42h, AL                    ; Send the low byte of the divisor to PIT channel 2 through port 42h
    MOV AL, AH                     ; Move the high byte of the divisor into AL
    OUT 42h, AL                    ; Send the high byte of the divisor to PIT channel 2
    IN  AL, 61h                    ; Read the current speaker control value from port 61h
    OR  AL, 03h                    ; Set bits 0 and 1 to enable the speaker output
    OUT 61h, AL                    ; Write the updated value back to port 61h
    JMP PM_DELAY                   ; Go to the delay loop to hold this note

PM_REST:                           ; Label used when the current melody value is a silence/rest
    IN  AL, 61h                    ; Read the current speaker control value from port 61h
    AND AL, 0FCh                   ; Clear bits 0 and 1 to disable the speaker
    OUT 61h, AL                    ; Write the updated value back to port 61h to apply silence

PM_DELAY:                          ; Delay section that controls how long each note/rest lasts
    MOV CX, 8000h                  ; Load CX with the number of delay-loop iterations

PM_DELAY_LOOP:                     ; Start of the active waiting loop
    LOOP PM_DELAY_LOOP             ; Decrease CX and repeat until CX reaches zero

    JMP PM_NEXT_NOTE               ; After the delay, continue with the next melody note

PM_DONE:                           ; End label reached when the melody end marker is found
    IN  AL, 61h                    ; Read the speaker control port to ensure the speaker can be disabled
    AND AL, 0FCh                   ; Clear bits 0 and 1 to turn off the speaker
    OUT 61h, AL                    ; Write the updated value back to port 61h
    RET                            ; Return to the caller after the full melody finishes

PLAY_MELODY ENDP                   ; End of PLAY_MELODY procedure

; ============================================================
; RESET_GAME
; Restores all game state variables to their initial values.
; It is called when the player presses R on the final screen.
; After returning, execution jumps back to GAME_LOOP.
; ============================================================
RESET_GAME PROC NEAR               ; Procedure that resets the game to its initial state

    ; Restore game state flags
    MOV GAME_ACTIVE, 01h          ; Reactivate the main game loop, 1 = running
    MOV GAME_WIN,    00h          ; Clear the win flag, so the game does not start as a victory

    ; Reset score to zero
    MOV SCORE, 0000h              ; Set the numeric score back to 0

    ; Restore player to the initial position near the lower center of the screen
    MOV PLAYER_X, 0098h           ; Restore player X position to 152 pixels
    MOV PLAYER_Y, 00B0h           ; Restore player Y position to 176 pixels

    ; Deactivate player bullet and clear its position
    MOV BULLET_ACTIVE, 00h        ; Mark the player bullet as inactive
    MOV BULLET_X, 0000h           ; Clear the player bullet X position
    MOV BULLET_Y, 0000h           ; Clear the player bullet Y position

    ; Deactivate enemy bullet and clear its position
    MOV EBULLET_ACTIVE, 00h       ; Mark the enemy bullet as inactive
    MOV EBULLET_X, 0000h          ; Clear the enemy bullet X position
    MOV EBULLET_Y, 0000h          ; Clear the enemy bullet Y position

    ; Reset enemy movement and shooting counters
    MOV ENEMY_MOVE_CTR, 0000h     ; Reset the enemy movement tick counter
    MOV ENEMY_SHOOT_CTR, 0000h    ; Reset the enemy shooting tick counter
    MOV ENEMY_DIR, 01h            ; Set enemies to begin moving to the right
    MOV ENEMY_COUNT, 0012h        ; Restore total enemy count to 18 decimal, 0x12

    ; Reset background music playback state
    MOV MELODY_IDX, 0000h         ; Return the melody index to the beginning
    MOV MUSIC_TICK_CTR, 0000h     ; Reset the music note tick counter

    ; Clear TIME_AUX so the first game tick can be processed immediately
    MOV TIME_AUX, 00h             ; Reset the stored time tick value

    ; Restore both bunkers to their original undamaged state
    ; Pattern: 0,1,1,1,1,1,0 / 1,1,1,1,1,1,1 / 1,1,1,1,1,1,1 / 1,1,0,0,0,1,1
    MOV SI, OFFSET BUNKER1_STATE  ; Load SI with the start address of bunker 1 state array
    CALL RG_RESTORE_BUNKER        ; Write the 28-byte original bunker pattern into bunker 1 state
    MOV SI, OFFSET BUNKER2_STATE  ; Load SI with the start address of bunker 2 state array
    CALL RG_RESTORE_BUNKER        ; Write the 28-byte original bunker pattern into bunker 2 state

    ; Reinitialize positions and states of all enemies
    CALL INIT_ENEMIES             ; Refill ENEMY_DATA with initial enemy positions and alive states

    RET                           ; Return to the caller

; ---- Helper subroutine: writes the 28-byte bunker pattern at [SI] ----
RG_RESTORE_BUNKER:                 ; Local helper label used to restore one bunker state array
    MOV BYTE PTR [SI+0],  00h     ; Row 0, column 0: transparent corner
    MOV BYTE PTR [SI+1],  01h     ; Row 0, column 1: alive bunker pixel
    MOV BYTE PTR [SI+2],  01h     ; Row 0, column 2: alive bunker pixel
    MOV BYTE PTR [SI+3],  01h     ; Row 0, column 3: alive bunker pixel
    MOV BYTE PTR [SI+4],  01h     ; Row 0, column 4: alive bunker pixel
    MOV BYTE PTR [SI+5],  01h     ; Row 0, column 5: alive bunker pixel
    MOV BYTE PTR [SI+6],  00h     ; Row 0, column 6: transparent corner
    MOV BYTE PTR [SI+7],  01h     ; Row 1, column 0: alive bunker pixel
    MOV BYTE PTR [SI+8],  01h     ; Row 1, column 1: alive bunker pixel
    MOV BYTE PTR [SI+9],  01h     ; Row 1, column 2: alive bunker pixel
    MOV BYTE PTR [SI+10], 01h     ; Row 1, column 3: alive bunker pixel
    MOV BYTE PTR [SI+11], 01h     ; Row 1, column 4: alive bunker pixel
    MOV BYTE PTR [SI+12], 01h     ; Row 1, column 5: alive bunker pixel
    MOV BYTE PTR [SI+13], 01h     ; Row 1, column 6: alive bunker pixel
    MOV BYTE PTR [SI+14], 01h     ; Row 2, column 0: alive bunker pixel
    MOV BYTE PTR [SI+15], 01h     ; Row 2, column 1: alive bunker pixel
    MOV BYTE PTR [SI+16], 01h     ; Row 2, column 2: alive bunker pixel
    MOV BYTE PTR [SI+17], 01h     ; Row 2, column 3: alive bunker pixel
    MOV BYTE PTR [SI+18], 01h     ; Row 2, column 4: alive bunker pixel
    MOV BYTE PTR [SI+19], 01h     ; Row 2, column 5: alive bunker pixel
    MOV BYTE PTR [SI+20], 01h     ; Row 2, column 6: alive bunker pixel
    MOV BYTE PTR [SI+21], 01h     ; Row 3, column 0: alive bunker pixel
    MOV BYTE PTR [SI+22], 00h     ; Row 3, column 1: start of the central opening
    MOV BYTE PTR [SI+23], 00h     ; Row 3, column 2: middle of the central opening
    MOV BYTE PTR [SI+24], 00h     ; Row 3, column 3: end of the central opening
    MOV BYTE PTR [SI+25], 01h     ; Row 3, column 4: alive bunker pixel
    MOV BYTE PTR [SI+26], 01h     ; Row 3, column 5: alive bunker pixel
    MOV BYTE PTR [SI+27], 01h     ; Row 3, column 6: alive bunker pixel, the 28th bunker state byte
    RET                           ; Return to RESET_GAME after restoring one bunker

RESET_GAME ENDP                    ; End of RESET_GAME procedure

; ============================================================
; PLAY_SOUND
; Turns on the PC speaker using the frequency indicated by BX.
; BX = PIT divisor, where audible frequency = 1,193,180 / BX.
; Plays the sound for a short delay and then returns.
; The caller should call STOP_SOUND afterward if silence is needed.
; ============================================================
PLAY_SOUND PROC NEAR               ; Procedure that starts a short PC speaker sound using the PIT divisor in BX

    ; Step 1: Configure PIT channel 2 for the desired frequency
    ; Command byte 0B6h = binary 10110110:
    ;   Bits 7-6 = 10: select channel 2
    ;   Bits 5-4 = 11: access mode lobyte/hibyte, meaning both bytes are sent
    ;   Bits 3-1 = 011: mode 3, square wave generator
    ;   Bit  0   = 0: binary counting mode, not BCD
    MOV AL, 0B6h                  ; Load the PIT command byte into AL
    OUT 43h, AL                   ; Send the command byte to the PIT command port 43h

    MOV AX, BX                    ; Copy the frequency divisor from BX into AX
    OUT 42h, AL                   ; Send the low byte of the divisor to PIT channel 2 through port 42h
    MOV AL, AH                    ; Move the high byte of the divisor into AL
    OUT 42h, AL                   ; Send the high byte of the divisor to PIT channel 2 through port 42h

    ; Step 2: Enable the speaker through system port 61h
    IN  AL, 61h                   ; Read the current value of system port 61h
    OR  AL, 03h                   ; Set bits 0 and 1 to enable PIT channel 2 output to the speaker
    OUT 61h, AL                   ; Write the updated value back to port 61h to turn on the speaker

    ; Step 3: Active delay so the sound is audible
    MOV CX, 0FFFFh                ; Load CX with 65535 delay-loop iterations

PS_DELAY:                         ; Delay loop label
    LOOP PS_DELAY                 ; Decrement CX and repeat until CX reaches zero

    RET                           ; Return to the caller after the sound delay
PLAY_SOUND ENDP                   ; End of PLAY_SOUND procedure

; ============================================================
; STOP_SOUND
; Silences the PC speaker by clearing bits 0 and 1 of port 61h.
; Bit 0: PIT channel 2 gate control, 0 = disabled
; Bit 1: speaker output enable, 0 = disconnected
; ============================================================
STOP_SOUND PROC NEAR               ; Procedure that turns off the PC speaker
    IN  AL, 61h                   ; Read the current value of system port 61h
    AND AL, 0FCh                  ; Clear bits 0 and 1, since 0FCh = 11111100b
    OUT 61h, AL                   ; Write the updated value back, disabling speaker output
    RET                           ; Return to the caller
STOP_SOUND ENDP                   ; End of STOP_SOUND procedure

; ============================================================
; CLEAR_SCREEN
; Clears the visible screen using the BIOS scroll function
; with 0 lines, which clears the whole selected window.
; It does NOT reset the video mode, avoiding the flickering that
; would happen if INT 10h/AH=00h were called every frame.
; ============================================================
CLEAR_SCREEN PROC NEAR             ; Procedure that clears the screen without changing video mode
    MOV AH, 06h                   ; Select INT 10h function 06h, scroll window up
    MOV AL, 00h                   ; AL = 0 lines to scroll, meaning clear the whole window
    MOV BH, 00h                   ; Fill attribute/color value, 0 = black background
    MOV CX, 0000h                 ; CH:CL = upper-left corner in text coordinates, row 0 column 0
    MOV DX, 184Fh                 ; DH:DL = lower-right corner in text coordinates
                                  ; DH = 18h = 24, the last row in a 25-row text grid
                                  ; DL = 4Fh = 79, the last column in an 80-column text grid
    INT 10h                       ; Execute the BIOS scroll/clear operation
    RET                           ; Return to the caller
CLEAR_SCREEN ENDP                 ; End of CLEAR_SCREEN procedure

CODE ENDS                         ; Ends the code segment
END MAIN                          ; Ends the source file and sets MAIN as the program entry point
